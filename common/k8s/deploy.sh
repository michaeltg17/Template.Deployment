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
#   environments/<env>.secrets.env    (DB_PASSWORD, IMAGE_API_KEY - NOT committed)
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
[ -f "$SECRETS_FILE" ] || { echo "ERROR: missing $SECRETS_FILE (copy .secrets.env.example and fill in values)" >&2; exit 1; }

# Strip \r so CRLF (Windows) env files cannot smuggle a carriage return into
# a value, which would corrupt the rendered YAML.
# shellcheck disable=SC1090
source <(tr -d '\r' < "$ENV_FILE")
# shellcheck disable=SC1090
source <(tr -d '\r' < "$SECRETS_FILE")

: "${API_URL:?set API_URL in $ENV_FILE}"
: "${IMAGE_API_URL:?set IMAGE_API_URL in $ENV_FILE}"
: "${RDS_ENDPOINT:?set RDS_ENDPOINT in $ENV_FILE (terraform output)}"
: "${DB_USER:?set DB_USER in $ENV_FILE (terraform output)}"
: "${API_IMAGE_TAG:?set API_IMAGE_TAG in $ENV_FILE}"
: "${REACT_IMAGE_TAG:?set REACT_IMAGE_TAG in $ENV_FILE}"
: "${MIGRATIONS_IMAGE_TAG:?set MIGRATIONS_IMAGE_TAG in $ENV_FILE}"
: "${DB_PASSWORD:?set DB_PASSWORD in $SECRETS_FILE}"
: "${IMAGE_API_KEY:?set IMAGE_API_KEY in $SECRETS_FILE}"

STAGE="$(mktemp -d)"
RENDER="$(mktemp -d)"
trap 'rm -rf "$STAGE" "$RENDER"' EXIT

# base + overlay: stage the shared manifests, then layer the cloud overlay on
# top (a same-named file in <cloud>/k8s overrides the base).
cp "$K8S_BASE"/*.yaml "$STAGE"/
cp "$K8S_CLOUD"/*.yaml "$STAGE"/

# Render the placeholders in every staged manifest.
for f in "$STAGE"/*.yaml; do
  sed \
    -e "s|__API_URL__|${API_URL}|g" \
    -e "s|__IMAGE_API_URL__|${IMAGE_API_URL}|g" \
    -e "s|__RDS_ENDPOINT__|${RDS_ENDPOINT}|g" \
    -e "s|__DB_USER__|${DB_USER}|g" \
    -e "s|__API_IMAGE_TAG__|${API_IMAGE_TAG}|g" \
    -e "s|__REACT_IMAGE_TAG__|${REACT_IMAGE_TAG}|g" \
    -e "s|__MIGRATIONS_IMAGE_TAG__|${MIGRATIONS_IMAGE_TAG}|g" \
    -e "s|__DB_PASSWORD__|${DB_PASSWORD}|g" \
    -e "s|__IMAGE_API_KEY__|${IMAGE_API_KEY}|g" \
    "$f" > "$RENDER/$(basename "$f")"
done

apply() {
  # --validate=false: server-side OpenAPI validation can transiently fail to
  # download the schema from the cluster API server; manifests are already
  # checked by kubeconform in CI, so skip the redundant server-side validation.
  kubectl apply --validate=false -f "$RENDER/$1"
  echo "  applied $1"
}

echo "==> [$CLOUD] namespace"
apply namespace.yaml

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
  kubectl -n app annotate service api alb.ingress.kubernetes.io/healthcheck-path=/health/ready --overwrite
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
