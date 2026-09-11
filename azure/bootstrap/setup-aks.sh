#!/usr/bin/env bash
# One-time bootstrap for an AKS environment (run AFTER `terraform apply`):
#   1. point kubectl at the cluster (az aks get-credentials)
#   2. wait for the worker nodes to be Ready
#   3. install AGIC (Application Gateway Ingress Controller) - it builds the
#      App Gateway routing from azure/k8s/ingress.yaml when the app is deployed
#
# Usage (from the repo root, Git Bash / Linux / macOS):
#   bash azure/bootstrap/setup-aks.sh [env]     # default: dev
#
# Reads cluster details from azure/terraform/environments/<env> outputs.
# Override with CLUSTER_NAME / LOCATION / RESOURCE_GROUP / APPGATEWAY_NAME if needed.

set -euo pipefail

ENV_NAME="${1:-dev}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TF_DIR="$REPO_ROOT/azure/terraform/environments/$ENV_NAME"

[ -d "$TF_DIR" ] || { echo "ERROR: missing $TF_DIR"; exit 1; }
command -v az >/dev/null 2>&1 || { echo "ERROR: az CLI not found in PATH"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found in PATH"; exit 1; }
az account show --query name -o tsv >/dev/null 2>&1 || { echo "ERROR: not logged in to Azure (run: az login)"; exit 1; }

tfout() { terraform -chdir="$TF_DIR" output -raw "$1"; }

CLUSTER_NAME="${CLUSTER_NAME:-$(tfout aks_name)}"
LOCATION="${LOCATION:-$(tfout location)}"
RESOURCE_GROUP="${RESOURCE_GROUP:-$(tfout resource_group_name)}"
APPGATEWAY_NAME="${APPGATEWAY_NAME:-$(tfout appgateway_name)}"
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

# Create the AGIC service principal via the az CLI (recent azurerm versions
# removed azurerm_application/azurerm_service_principal from Terraform). It
# configures the App Gateway from the Ingress; its credentials become
# armAuth.secretJSON for the helm install. Contributor on the RG is deliberately
# broad (dev); scope to App Gateway Contributor + Reader for production.
RG_ID="$(az group show -n "$RESOURCE_GROUP" --query id -o tsv)"
echo "==> creating the AGIC service principal (${CLUSTER_NAME}-agic)"
AGIC_SP_JSON="$(az ad sp create-for-rbac --name "${CLUSTER_NAME}-agic" --role Contributor --scopes "$RG_ID" --sdk-auth)"
AGIC_SP_SECRET_JSON="$(printf '%s' "$AGIC_SP_JSON" | base64 | tr -d '\n')"

HELM_VERSION="3.16.4"
# Pin the AGIC chart for reproducible bootstraps.
AGIC_CHART="oci://mcr.microsoft.com/azure-application-gateway/charts/ingress-azure"
AGIC_CHART_VERSION="1.8.1"

echo "==> updating kubeconfig (alias: ${CLUSTER_NAME})"
az aks get-credentials -n "$CLUSTER_NAME" -g "$RESOURCE_GROUP" --overwrite
kubectl config use-context "azure://${RESOURCE_GROUP}/${CLUSTER_NAME}" >/dev/null 2>&1 || true

echo "==> waiting for worker nodes to be Ready"
kubectl wait --for=condition=Ready node --all --timeout=900s

install_helm() {
  command -v helm >/dev/null 2>&1 && return 0
  echo "==> installing helm v${HELM_VERSION}"
  local tmp
  tmp="$(mktemp -d)"
  case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
    msys* | cygwin* | mingw* | windows*)
      # The windows zip nests the binary under windows-amd64/ (older releases
      # used helm/), so extract everything with junk paths and locate it.
      curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-windows-amd64.zip" -o "$tmp/helm.zip"
      unzip -q -j "$tmp/helm.zip" -d "$tmp"
      ;;
    *)
      curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" | tar -xzf - -C "$tmp"
      ;;
  esac
  chmod +x "$tmp"/* 2>/dev/null || true
  # The tarball/zip keep the binary in a subdir (linux-amd64/, windows-amd64/);
  # find it rather than assuming a flat layout.
  HELM_BIN="$(find "$tmp" -type f \( -name 'helm' -o -name 'helm.exe' \) -print -quit)"
  [ -n "$HELM_BIN" ] || { echo "ERROR: helm binary not found after download"; exit 1; }
  HELM_DIR="$(dirname "$HELM_BIN")"
  export PATH="$HELM_DIR:$PATH"
  helm version --short
}

install_helm

# Write the AGIC values to a file (not --set) so the base64 secretJSON, which
# can contain + / =, is never re-parsed as a helm key path.
AGIC_VALUES="$(mktemp)"
trap 'rm -f "$AGIC_VALUES"' EXIT
cat > "$AGIC_VALUES" <<EOF
verbosityLevel: 5
# The chart defaults rbac.enabled=false, which leaves the AGIC service account
# without permission to read the watched namespace -> AGIC crashloops with
# ErrorNoSuchNamespace. Enable it so the chart creates the ClusterRoleBinding.
rbac:
  enabled: true
appgw:
  name: ${APPGATEWAY_NAME}
  resourceGroup: ${RESOURCE_GROUP}
  subscriptionId: ${SUBSCRIPTION_ID}
kubernetes:
  watchNamespace: app
armAuth:
  type: servicePrincipal
  secretJSON: ${AGIC_SP_SECRET_JSON}
EOF

# AGIC crashloops (ErrorNoSuchNamespace) if the namespace it watches does not
# exist yet. deploy.sh creates it too, but ensure it here so AGIC is healthy
# from the start (idempotent).
echo "==> ensuring the watched namespace (app) exists"
kubectl create namespace app --dry-run=client -o yaml | kubectl apply -f -

echo "==> installing AGIC (chart v${AGIC_CHART_VERSION})"
helm upgrade --install agic-controller "$AGIC_CHART" \
  --version "$AGIC_CHART_VERSION" \
  --namespace ingress-azure --create-namespace \
  -f "$AGIC_VALUES"

echo "==> waiting for the AGIC pod to be Ready"
kubectl -n ingress-azure wait --for=condition=ready pod --all --timeout=300s

echo ""
echo "============================================================"
echo "  Cluster:    ${CLUSTER_NAME} (${LOCATION})"
echo "  KubeCtx:    azure://${RESOURCE_GROUP}/${CLUSTER_NAME}"
echo "  AppGateway: ${APPGATEWAY_NAME}"
echo "  AGIC:       ready (it builds the gateway from azure/k8s/ingress.yaml)"
echo ""
echo "  Next:       cd common/k8s && ./deploy.sh ${ENV_NAME} azure"
echo "============================================================"
