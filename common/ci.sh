#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

echo "========================================="
echo "  Running CI (multi-cloud)"
echo "========================================="

# init (no backend) + validate one terraform root. Runs in a subshell so the
# rm/init don't leak, and each root is validated independently.
tfvalidate() {
  (
    cd "$1"
    rm -rf .terraform
    terraform init -backend=false -input=false
    terraform validate
  )
}

# init (no backend) only - for roots that read another state via
# data.terraform_remote_state. `terraform validate` cannot resolve the remote
# state's output attributes (the state is not read at validate time), so init
# is the deepest no-credential check available: it verifies the module source
# resolves, the providers are valid, and the backend config is well-formed. The
# full validation happens in the credentialed terraform-plan CI job.
tfinit() {
  (
    cd "$1"
    rm -rf .terraform
    terraform init -backend=false -input=false
  )
}

echo
echo "[1/5] Terraform format check"
terraform fmt -check -recursive .
echo "OK: terraform fmt"

echo
echo "[2/5] Terraform validate (main states) + init (argocd states)"
tfvalidate "aws/terraform/environments/dev"
tfvalidate "aws/terraform/environments/qa"
tfvalidate "aws/terraform/environments/prod"
tfvalidate "azure/terraform/environments/dev"
# ArgoCD lives in a separate state per env (reads the cluster from the main
# state via terraform_remote_state) - init only, see tfinit.
tfinit "aws/terraform/environments/dev/argocd"
tfinit "aws/terraform/environments/qa/argocd"
tfinit "aws/terraform/environments/prod/argocd"
tfinit "azure/terraform/environments/dev/argocd"
echo "OK: terraform validate + init"

echo
echo "[3/5] Shellcheck"
shellcheck --severity=warning \
  aws/bootstrap/*.sh \
  azure/bootstrap/*.sh \
  common/k8s/deploy.sh \
  common/k8s/render.sh \
  common/tools-docker.sh \
  common/ci.sh \
  common/ci-docker.sh
echo "OK: shellcheck"

echo
echo "[4/5] Parse YAML (k8s manifests + workflows)"
python3 - <<'PY'
import yaml, glob
files = sorted(
    glob.glob("common/k8s/*.yaml")
    + glob.glob("aws/k8s/*.yaml")
    + glob.glob("azure/k8s/*.yaml")
    + glob.glob(".github/workflows/*.yml")
)
for f in files:
    docs = list(yaml.safe_load_all(open(f, encoding="utf-8")))
    print("OK:", f, len(docs), "docs")
print("parsed", len(files), "files")
PY
echo "OK: yaml parse"

echo
echo "[5/5] Validate k8s manifests (kubeconform)"
kubeconform -strict -summary -ignore-missing-schemas \
  common/k8s/*.yaml \
  aws/k8s/*.yaml \
  azure/k8s/*.yaml

echo
echo "========================================="
echo "  All CI checks passed!"
echo "========================================="
