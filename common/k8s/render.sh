#!/usr/bin/env bash
# Renders the app stack manifests for a given env + cloud to an output
# directory. This is the GitOps path: the CD workflow runs this, commits the
# rendered manifests to deploy/<env>/<cloud>/, and ArgoCD syncs that directory
# into the cluster. No kubectl, no apply - render only.
#
#   ./render.sh <env> <cloud> <out-dir>
#   e.g. ./render.sh dev aws deploy/dev/aws
#
# The rendering is identical to deploy.sh (same placeholders, same skip-if
# filtering); only the apply step is dropped.
#
# Reads:
#   environments/<env>.env             (API_URL, IMAGE_API_URL, RDS_ENDPOINT, DB_USER, image tags)
#   environments/<env>.secrets.env    (DB_PASSWORD, IMAGE_API_KEY - AZURE ONLY)
#
# AWS: the DB password + image API key live in AWS Secrets Manager and are
# synced into the cluster by External Secrets Operator. The ESO secret names +
# region are passed as env vars (or read from terraform outputs locally) and
# rendered into the ESO manifests. The secrets file is NOT read on AWS.

set -euo pipefail

ENV_NAME="${1:-dev}"
CLOUD="${2:-}"
OUT_DIR="${3:-}"
case "$CLOUD" in
  aws | azure) ;;
  *) echo "ERROR: cloud must be 'aws' or 'azure' (got: '${CLOUD:-<empty>}')" >&2; exit 1 ;;
esac
[ -n "$OUT_DIR" ] || { echo "ERROR: out-dir required (e.g. deploy/$ENV_NAME/$CLOUD)" >&2; exit 1; }

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
# Operator. The __DB_USER__ placeholder only appears in secrets.yaml, which is
# skipped on the AWS path, so DB_USER is left empty here. We DO need the secret
# names + region from terraform outputs to render the ESO manifests.
DB_USER="${DB_USER:-}"
if [ "$CLOUD" = "aws" ]; then
  # The secret names are deterministic (<env>-template-db / -image-api) and the
  # region is fixed, so CD can pass them as env vars without `terraform init`.
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

# On the non-aws path the secret placeholders must be set (they are sourced
# from the secrets file above); on aws they are unused (ESO owns the secrets).
DB_PASSWORD="${DB_PASSWORD:-}"
IMAGE_API_KEY="${IMAGE_API_KEY:-}"
AWS_REGION="${AWS_REGION:-}"
DB_SECRET_NAME="${DB_SECRET_NAME:-}"
IMAGE_API_SECRET_NAME="${IMAGE_API_SECRET_NAME:-}"

# Render into a fresh stage + output dir. base + overlay: stage the shared
# manifests, then layer the cloud overlay on top (a same-named file in
# <cloud>/k8s overrides the base).
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$K8S_BASE"/*.yaml "$STAGE"/
cp "$K8S_CLOUD"/*.yaml "$STAGE"/

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# Render the placeholders in every staged manifest, then drop any doc that is
# guarded by `skip-if: <cloud>` matching the current cloud (used to keep the
# baked azure Secrets out of the aws path, where ESO owns them). A file that
# renders to zero docs is dropped (e.g. secrets.yaml on aws), so the output
# dir only contains objects this cloud actually applies.
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
  base="$(basename "$f")"
  render_one "$f" "$STAGE/$base.tmp"
  # Drop docs whose skip-if annotation matches the current cloud, and drop the
  # file entirely if it renders to zero docs.
  python3 - "$STAGE/$base.tmp" "$CLOUD" > "$OUT_DIR/$base" <<'PY'
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
  rm -f "$STAGE/$base.tmp"
  # Drop files that rendered to zero docs.
  if ! python3 -c 'import sys,yaml; sys.exit(0 if any(d for d in yaml.safe_load_all(open(sys.argv[1],encoding="utf-8"))) else 1)' "$OUT_DIR/$base" 2>/dev/null; then
    rm -f "$OUT_DIR/$base"
    echo "  dropped $base (no objects for this cloud)"
  fi
done

echo "Rendered $CLOUD/$ENV_NAME manifests to $OUT_DIR:"
ls -1 "$OUT_DIR"
