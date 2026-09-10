#!/usr/bin/env bash
# Full teardown for an AKS environment (reverse of
# `terraform apply` -> bootstrap/setup-aks.sh -> common/k8s/deploy.sh):
#   1. delete the app namespace (AGIC drops the Ingress routing)
#   2. uninstall AGIC (so it stops re-applying config during the destroy)
#   3. terraform destroy (deletes the RG: cluster, App Gateway, PG, VNet, state)
#   4. verify nothing is left
#
# Unlike the AWS ALB (which the controller creates outside the TF state), the
# App Gateway IS in the Terraform state, so `terraform destroy` removes it.
#
# Self-healing: if the cluster is already gone (e.g. `terraform destroy` was
# run directly), skip the k8s cleanup and go straight to terraform destroy.
#
# Usage (from the repo root, Git Bash / Linux / macOS):
#   bash azure/bootstrap/teardown.sh [env]     # default: dev

set -euo pipefail

ENV_NAME="${1:-dev}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TF_DIR="$REPO_ROOT/azure/terraform/environments/$ENV_NAME"

[ -d "$TF_DIR" ] || { echo "ERROR: missing $TF_DIR"; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "ERROR: terraform not found in PATH"; exit 1; }

tfout() { terraform -chdir="$TF_DIR" output -raw "$1"; }

CLUSTER_NAME="${CLUSTER_NAME:-$(tfout aks_name)}"
RESOURCE_GROUP="${RESOURCE_GROUP:-$(tfout resource_group_name)}"

cluster_reachable() {
  command -v az >/dev/null 2>&1 && \
    command -v kubectl >/dev/null 2>&1 && \
    az aks show -n "$CLUSTER_NAME" -g "$RESOURCE_GROUP" >/dev/null 2>&1
}

if cluster_reachable; then
  echo "==> deleting the app namespace (AGIC drops the Ingress routing)"
  if kubectl get ns app >/dev/null 2>&1; then
    kubectl delete ns app --timeout=300s
  fi

  if command -v helm >/dev/null 2>&1 && \
     helm list -n ingress-azure -q 2>/dev/null | grep -q '^agic-controller$'; then
    echo "==> uninstalling AGIC"
    helm uninstall agic-controller -n ingress-azure
  fi
else
  echo "==> cluster '${CLUSTER_NAME:-<unknown>}' is not reachable; skipping k8s cleanup"
fi

echo "==> terraform destroy"
terraform -chdir="$TF_DIR" destroy -auto-approve

echo "==> verifying nothing is left"
leftover=0
if command -v az >/dev/null 2>&1 && az group show -n "$RESOURCE_GROUP" >/dev/null 2>&1; then
  echo "  LEFTOVER: resource group $RESOURCE_GROUP"
  leftover=1
fi
if [ "$leftover" -eq 0 ]; then
  echo "OK: nothing left (resource group gone)"
else
  echo "ERROR: leftovers remain - see above"
  exit 1
fi
