#!/usr/bin/env bash
# Create the dedicated application DB login (prod) in the RDS instance.
#
# The private RDS endpoint is not reachable from the terraform runner, so the
# role is created here - after `terraform apply` + bootstrap/setup-eks.sh - by
# running a one-shot psql job on the cluster (it can reach the private DB).
#
# It reads, from Secrets Manager (names from the terraform outputs):
#   <env>-template-db-master  -> the master login (used to connect and run DDL)
#   <env>-template-db         -> the app login to create (username + password)
# and the RDS endpoint via `aws rds describe-db-instances`.
#
# Idempotent: re-running is a no-op (the role is created only if absent, else
# its password is reset; the grants are re-applied).
#
# Usage (from the repo root, Git Bash / Linux / macOS):
#   bash aws/bootstrap/provision-db-user.sh [env]     # default: dev
#
# Only needed when the env uses a dedicated app user (prod). dev/qa connect as
# the master user and skip this step.

set -euo pipefail

ENV_NAME="${1:-dev}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TF_DIR="$REPO_ROOT/aws/terraform/environments/$ENV_NAME"

[ -d "$TF_DIR" ] || { echo "ERROR: missing $TF_DIR"; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI not found in PATH"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found in PATH"; exit 1; }

tfout() { terraform -chdir="$TF_DIR" output -raw "$1"; }

CLUSTER_NAME="${CLUSTER_NAME:-$(tfout cluster_name)}"
AWS_REGION="${AWS_REGION:-$(tfout region)}"
# The RDS identifier is the cluster name + "-db" (the env root wires the rds
# module as "${local.name}-db", and the eks cluster is named "${local.name}").
RDS_IDENTIFIER="${RDS_IDENTIFIER:-${CLUSTER_NAME}-db}"
DB_SECRET_NAME="${DB_SECRET_NAME:-$(tfout db_secret_name)}"
MASTER_SECRET_NAME="${MASTER_SECRET_NAME:-${DB_SECRET_NAME}-master}"

secret_json() { aws secretsmanager get-secret-value --secret-id "$1" --region "$AWS_REGION" --query SecretString --output text; }
json_field() { printf '%s' "$1" | python3 -c 'import sys,json; print(json.load(sys.stdin)["'$2'"])'; }

echo "==> reading master + app credentials from Secrets Manager"
MASTER_JSON="$(secret_json "$MASTER_SECRET_NAME")"
APP_JSON="$(secret_json "$DB_SECRET_NAME")"
MASTER_USER="$(json_field "$MASTER_JSON" username)"
MASTER_PASS="$(json_field "$MASTER_JSON" password)"
APP_USER="$(json_field "$APP_JSON" username)"
APP_PASS="$(json_field "$APP_JSON" password)"

echo "==> resolving the RDS endpoint for ${RDS_IDENTIFIER}"
RDS_ENDPOINT="$(aws rds describe-db-instances --db-instance-identifier "$RDS_IDENTIFIER" --region "$AWS_REGION" --query 'DBInstances[0].Endpoint.Address' --output text)"
[ -n "$RDS_ENDPOINT" ] && [ "$RDS_ENDPOINT" != "None" ] || { echo "ERROR: RDS instance ${RDS_IDENTIFIER} not found (terraform not applied?)"; exit 1; }

echo "==> creating app login ${APP_USER} on ${RDS_ENDPOINT} (via a psql job on ${CLUSTER_NAME})"
# The job connects as the master user to create the app role + grants, then
# reconnects as the app user to prove it authenticates. All credentials come
# from a temporary k8s Secret that is deleted at the end.
kubectl -n app create secret generic provision-db-creds \
  --from-literal=host="$RDS_ENDPOINT" \
  --from-literal=port=5432 \
  --from-literal=masteruser="$MASTER_USER" \
  --from-literal=masterpass="$MASTER_PASS" \
  --from-literal=appuser="$APP_USER" \
  --from-literal=apppass="$APP_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n app delete job provision-db-user --ignore-not-found >/dev/null 2>&1 || true
kubectl -n app apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: provision-db-user
  namespace: app
  labels:
    app: provision-db-user
spec:
  backoffLimit: 3
  ttlSecondsAfterFinished: 600
  template:
    metadata:
      labels:
        app: provision-db-user
    spec:
      restartPolicy: Never
      containers:
        - name: psql
          image: postgres:18.6
          env:
            - name: HOST
              valueFrom: { secretKeyRef: { name: provision-db-creds, key: host } }
            - name: PORT
              valueFrom: { secretKeyRef: { name: provision-db-creds, key: port } }
            - name: MASTERUSER
              valueFrom: { secretKeyRef: { name: provision-db-creds, key: masteruser } }
            - name: MASTERPASS
              valueFrom: { secretKeyRef: { name: provision-db-creds, key: masterpass } }
            - name: APPUSER
              valueFrom: { secretKeyRef: { name: provision-db-creds, key: appuser } }
            - name: APPPASS
              valueFrom: { secretKeyRef: { name: provision-db-creds, key: apppass } }
          command:
            - bash
            - -c
            - |
              set -euo pipefail
              CONN="host=$HOST port=$PORT dbname=template_db sslmode=require"
              echo "connecting as master user to provision app login $APPUSER"
              PGPASSWORD="$MASTERPASS" psql "$CONN user=$MASTERUSER" -v appuser="$APPUSER" -v apppass="$APPPASS" <<'SQL'
              DO $$
              BEGIN
                IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = current_setting('appuser')) THEN
                  EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', current_setting('appuser'), current_setting('apppass'));
                ELSE
                  EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', current_setting('appuser'), current_setting('apppass'));
                END IF;
              END
              $$;
              GRANT ALL PRIVILEGES ON DATABASE template_db TO current_setting('appuser')::regrole;
              SQL
              PGPASSWORD="$MASTERPASS" psql "$CONN user=$MASTERUSER" \
                -c "GRANT ALL ON SCHEMA public TO \"${APPUSER}\";"
              echo "verifying the app login can authenticate"
              PGPASSWORD="$APPPASS" psql "$CONN user=$APPUSER" -c "SELECT current_user AS app_login_ok;"
EOF

echo "==> waiting for the provision job to complete"
if ! kubectl -n app wait --for=condition=complete job/provision-db-user --timeout=180s; then
  echo "ERROR: provision-db-user job failed. Last logs:" >&2
  kubectl -n app logs job/provision-db-user --tail=50 || true
  kubectl -n app delete secret provision-db-creds >/dev/null 2>&1 || true
  exit 1
fi

# Clean up the temporary creds secret + job.
kubectl -n app delete job provision-db-user --ignore-not-found >/dev/null 2>&1 || true
kubectl -n app delete secret provision-db-creds >/dev/null 2>&1 || true

echo ""
echo "============================================================"
echo "  App login ${APP_USER} is provisioned on ${RDS_ENDPOINT}"
echo "  The ${DB_SECRET_NAME} secret already holds its credentials"
echo "============================================================"
