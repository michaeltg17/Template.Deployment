#!/usr/bin/env bash
# Deploys the app stack to the current kubectl context for a given cloud.
#
#   ./deploy.sh <env> <cloud>        e.g. ./deploy.sh dev aws   |   ./deploy.sh dev azure
#
# Base manifests live in common/k8s (this dir). Cloud-specific overlays live in
# <cloud>/k8s and are layered on top: a same-named file there overrides the base.
# <cloud>/k8s/ingress.yaml is the required overlay (ALB for aws, App Gateway for
# azure). The load-balancer health check differs per cloud:
#   - aws:   the ALB defaults its target-group probe to /, and the API has no /
#            route (404), so we annotate the api Service with
#            alb.ingress.kubernetes.io/healthcheck-path=/health/ready.
#   - azure: AGIC derives the App Gateway probe from the pod's httpGet readiness
#            probe (already /health/ready in api.yaml), so nothing extra is needed.
#
# Reads:
#   environments/<env>.env             (API_URL, IMAGE_API_URL, RDS_ENDPOINT, DB_USER, image tags)
#   environments/<env>.secrets.env    (DB_PASSWORD, IMAGE_API_KEY - NOT committed; AZURE ONLY)
#
# AWS: the DB password + image API key live in AWS Secrets Manager and are
# synced into the cluster by External Secrets Operator (aws/k8s). deploy.sh
# reads the secret names + region from terraform outputs, renders the ESO
# manifests, applies them, and waits for ESO to populate the in-cluster
# Secrets. The secrets file is NOT read on AWS.
#
# Requires: kubectl pointed at the cluster. The database is created by terraform
# (RDS on aws, PostgreSQL Flexible on azure) - there is no in-cluster PG.

set -euo pipefail

ENV_NAME="${1:-dev}"
CLOUD="${2:-}"
case "$CLOUD" in
  aws | azure) ;;
  *) echo "ERROR: cloud must be 'aws' or 'azure' (got: '${CLOUD:-<empty>}')" >&2; exit 1 ;;
esac

K8S_BASE="$(cd "$(dirname "$0")" && pwd)"        # common/k8s
REPO_ROOT="$(cd "$K8S_BASE/../.." && pwd)"       # repo root
K8S_CLOUD="$REPO_ROOT/$CLOUD/k8s"
ENV_FILE="$K8S_BASE/environments/$ENV_NAME.env"
SECRETS_FILE="$K8S_BASE/environments/$ENV_NAME.secrets.env"

[ -d "$K8S_CLOUD" ] || { echo "ERROR: missing $K8S_CLOUD" >&2; exit 1; }
[ -f "$K8S_CLOUD/ingress.yaml" ] || { echo "ERROR: missing $K8S_CLOUD/ingress.yaml" >&2; exit 1; }
[ -f "$ENV_FILE" ] || { echo "ERROR: missing $ENV_FILE (copy $ENV_NAME.env.example to $ENV_FILE and fill in values)" >&2; exit 1; }

# On AWS the secrets live in AWS Secrets Manager (ESO syncs them); the secrets
# file is only required on the non-AWS (azure) path.
if [ "$CLOUD" != "aws" ]; then
  [ -f "$SECRETS_FILE" ] || { echo "ERROR: missing $SECRETS_FILE (copy .secrets.env.example and fill in values)" >&2; exit 1; }
fi

# Strip \r so CRLF (Windows) env files cannot smuggle a carriage return into
# a value, which would corrupt the rendered YAML.
# shellcheck disable=SC1090
source <(tr -d '\r' < "$ENV_FILE")
if [ "$CLOUD" != "aws" ]; then
  # shellcheck disable=SC1090
  source <(tr -d '\r' < "$SECRETS_FILE")
fi

: "${API_URL:?set API_URL in $ENV_FILE}"
: "${IMAGE_API_URL:?set IMAGE_API_URL in $ENV_FILE}"
: "${RDS_ENDPOINT:?set RDS_ENDPOINT in $ENV_FILE (terraform output)}"
: "${API_IMAGE_TAG:?set API_IMAGE_TAG in $ENV_FILE}"
: "${REACT_IMAGE_TAG:?set REACT_IMAGE_TAG in $ENV_FILE}"
: "${MIGRATIONS_IMAGE_TAG:?set MIGRATIONS_IMAGE_TAG in $ENV_FILE}"
if [ "$CLOUD" != "aws" ]; then
  : "${DB_USER:?set DB_USER in $ENV_FILE (terraform output)}"
  : "${DB_PASSWORD:?set DB_PASSWORD in $SECRETS_FILE}"
  : "${IMAGE_API_KEY:?set IMAGE_API_KEY in $SECRETS_FILE}"
fi

# AWS: the DB login (username + password) lives in the env's Secrets Manager
# secret and is injected into the connection string by External Secrets
# Operator (the dedicated app login on prod, the master login on dev/qa). The
# __DB_USER__ placeholder only appears in secrets.yaml, which is skipped on the
# AWS path, so DB_USER is left empty here. We DO need the secret names + region
# from terraform outputs to render the ESO manifests.
DB_USER="${DB_USER:-}"
if [ "$CLOUD" = "aws" ]; then
  # The secret names are deterministic (template-<env>-db / -image-api) and the
  # region is fixed, so CI can pass them as env vars without `terraform init`.
  # Locally they fall back to the terraform outputs.
  TF_DIR="$REPO_ROOT/aws/terraform/environments/$ENV_NAME"
  if [ -z "${AWS_REGION:-}" ] || [ -z "${DB_SECRET_NAME:-}" ] || [ -z "${IMAGE_API_SECRET_NAME:-}" ]; then
    [ -d "$TF_DIR" ] || { echo "ERROR: missing $TF_DIR (set AWS_REGION/DB_SECRET_NAME/IMAGE_API_SECRET_NAME, or run from a terraform env)" >&2; exit 1; }
    command -v terraform >/dev/null 2>&1 || { echo "ERROR: terraform not found in PATH (needed for the ESO secret names)" >&2; exit 1; }
    [ -z "${AWS_REGION:-}" ] && AWS_REGION="$(terraform -chdir="$TF_DIR" output -raw region)"
    [ -z "${DB_SECRET_NAME:-}" ] && DB_SECRET_NAME="$(terraform -chdir="$TF_DIR" output -raw db_secret_name)"
    [ -z "${IMAGE_API_SECRET_NAME:-}" ] && IMAGE_API_SECRET_NAME="$(terraform -chdir="$TF_DIR" output -raw image_api_secret_name)"
  fi
  : "${AWS_REGION:?no AWS_REGION (set it or run from a terraform env)}"
  : "${DB_SECRET_NAME:?no DB_SECRET_NAME (set it or run from a terraform env)}"
  : "${IMAGE_API_SECRET_NAME:?no IMAGE_API_SECRET_NAME (set it or run from a terraform env)}"
fi

STAGE="$(mktemp -d)"
RENDER="$(mktemp -d)"
trap 'rm -rf "$STAGE" "$RENDER"' EXIT

# base + overlay: stage the shared manifests, then layer the cloud overlay on
# top (a same-named file in <cloud>/k8s overrides the base).
cp "$K8S_BASE"/*.yaml "$STAGE"/
cp "$K8S_CLOUD"/*.yaml "$STAGE"/

# On the non-aws path the secret placeholders must be set (they are sourced
# from the secrets file above); on aws they are unused (ESO owns the secrets).
DB_PASSWORD="${DB_PASSWORD:-}"
IMAGE_API_KEY="${IMAGE_API_KEY:-}"
AWS_REGION="${AWS_REGION:-}"
DB_SECRET_NAME="${DB_SECRET_NAME:-}"
IMAGE_API_SECRET_NAME="${IMAGE_API_SECRET_NAME:-}"

# Render the placeholders in every staged manifest, then drop any doc that is
# guarded by `skip-if: <cloud>=<value>` matching the current cloud (used to
# keep the baked azure Secrets out of the aws path, where ESO owns them).
render_one() {
  local src="$1" dst="$2"
  sed \
    -e "s|__CLOUD__|${CLOUD}|g" \
    -e "s|__API_URL__|${API_URL}|g" \
    -e "s|__IMAGE_API_URL__|${IMAGE_API_URL}|g" \
    -e "s|__RDS_ENDPOINT__|${RDS_ENDPOINT}|g" \
    -e "s|__DB_USER__|${DB_USER}|g" \
    -e "s|__API_IMAGE_TAG__|${API_IMAGE_TAG}|g" \
    -e "s|__REACT_IMAGE_TAG__|${REACT_IMAGE_TAG}|g" \
    -e "s|__MIGRATIONS_IMAGE_TAG__|${MIGRATIONS_IMAGE_TAG}|g" \
    -e "s|__DB_PASSWORD__|${DB_PASSWORD}|g" \
    -e "s|__IMAGE_API_KEY__|${IMAGE_API_KEY}|g" \
    -e "s|__AWS_REGION__|${AWS_REGION}|g" \
    -e "s|__DB_SECRET_NAME__|${DB_SECRET_NAME}|g" \
    -e "s|__IMAGE_API_SECRET_NAME__|${IMAGE_API_SECRET_NAME}|g" \
    "$src" > "$dst"
}

for f in "$STAGE"/*.yaml; do
  render_one "$f" "$RENDER/$(basename "$f").tmp"
  # Drop docs whose skip-if annotation matches the current cloud.
  python3 - "$RENDER/$(basename "$f").tmp" "$CLOUD" > "$RENDER/$(basename "$f")" <<'PY'
import sys, yaml
src, cloud = sys.argv[1], sys.argv[2]
out = []
for doc in yaml.safe_load_all(open(src, encoding="utf-8")):
    if not doc:
        continue
    skip = (doc.get("metadata") or {}).get("annotations", {}).get("skip-if", "")
    if skip and skip == f"{cloud}":
        continue
    out.append(doc)
yaml.safe_dump_all(out, sys.stdout, default_flow_style=False, sort_keys=False)
PY
  rm -f "$RENDER/$(basename "$f").tmp"
done

apply() {
  # Skip files that rendered to zero docs (e.g. secrets.yaml on aws, where the
  # baked Secrets are ESO-owned and skipped via the skip-if annotation).
  if ! python3 -c 'import sys,yaml; sys.exit(0 if any(d for d in yaml.safe_load_all(open(sys.argv[1],encoding="utf-8"))) else 1)' "$RENDER/$1" 2>/dev/null; then
    echo "  skipped $1 (no objects for this cloud)"
    return 0
  fi
  # --validate=false: server-side OpenAPI validation can transiently fail to
  # download the schema from the cluster API server; manifests are already
  # checked by kubeconform in CI, so skip the redundant server-side validation.
  kubectl apply --validate=false -f "$RENDER/$1"
  echo "  applied $1"
}

echo "==> [$CLOUD] namespace"
apply namespace.yaml

if [ "$CLOUD" = "aws" ]; then
  echo "==> [aws] external-secrets store + ExternalSecrets (ESO syncs the secrets from AWS Secrets Manager)"
  apply secretstore.yaml
  apply external-secret.yaml
  echo "    waiting for ESO to populate the in-cluster Secrets (api-config, app-secrets)"
  for _ in $(seq 1 30); do
    if kubectl -n app get secret api-config >/dev/null 2>&1 \
       && kubectl -n app get secret app-secrets >/dev/null 2>&1 \
       && [ -n "$(kubectl -n app get secret api-config -o jsonpath='{.data.postgresql-connection-string}' 2>/dev/null)" ]; then
      break
    fi
    sleep 6
  done
  kubectl -n app get secret api-config >/dev/null 2>&1 || { echo "ERROR: ESO did not create the api-config Secret (check the external-secrets pods in ns external-secrets)" >&2; exit 1; }
  kubectl -n app get secret app-secrets >/dev/null 2>&1 || { echo "ERROR: ESO did not create the app-secrets Secret (check the external-secrets pods in ns external-secrets)" >&2; exit 1; }
fi

echo "==> [$CLOUD] secrets"
apply secrets.yaml

echo "==> [$CLOUD] migrations (runs against the DB at ${RDS_ENDPOINT})"
apply migrations-job.yaml
if ! kubectl -n app wait --for=condition=complete job/migrations --timeout=300s; then
  echo "ERROR: migrations job failed. Last logs:" >&2
  kubectl -n app logs job/migrations --tail=50 || true
  exit 1
fi

echo "==> [$CLOUD] api"
apply api.yaml
# The ALB (aws) defaults its target-group health probe to /, but the API has no
# / route (404), so point it at /health/ready. AGIC (azure) already derives its
# App Gateway probe from the pod's httpGet readiness probe, so this is aws-only.
if [ "$CLOUD" = "aws" ]; then
  # MSYS_NO_PATHCONV=1 stops Git Bash from rewriting the leading-slash path
  # (/health/ready) into a Windows path (C:/Program Files/Git/health/ready).
  MSYS_NO_PATHCONV=1 kubectl -n app annotate service api alb.ingress.kubernetes.io/healthcheck-path=/health/ready --overwrite
fi
kubectl -n app wait --for=condition=ready pod -l app=api --timeout=180s || true

echo "==> [$CLOUD] react"
apply react.yaml
kubectl -n app wait --for=condition=ready pod -l app=react --timeout=180s || true

echo "==> [$CLOUD] ingress (the cloud controller creates the public LB from this)"
apply ingress.yaml

# The controller publishes the LB DNS name on the Ingress status.
LB_DNS=""
for _ in $(seq 1 30); do
  LB_DNS="$(kubectl -n app get ingress app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  [ -n "$LB_DNS" ] && break
  sleep 6
done

echo ""
echo "============================================================"
echo "  App:      http://${LB_DNS:-<LB DNS not published yet>}/"
echo "  API:      http://${LB_DNS:-<LB DNS not published yet>}/api/  (via LB)"
echo "============================================================"
echo ""
echo "Quick check:"
echo "  curl -s http://${LB_DNS}/api/ | head"
echo "  kubectl -n app get pods,svc,ingress"
