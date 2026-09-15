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

echo
echo "[1/5] Terraform format check"
terraform fmt -check -recursive .
echo "OK: terraform fmt"

echo
echo "[2/5] Terraform validate (aws dev/qa/prod + azure)"
tfvalidate "aws/terraform/environments/dev"
tfvalidate "aws/terraform/environments/qa"
tfvalidate "aws/terraform/environments/prod"
tfvalidate "azure/terraform/environments/dev"
echo "OK: terraform validate"

echo
echo "[3/5] Shellcheck"
shellcheck --severity=warning \
  aws/bootstrap/*.sh \
  azure/bootstrap/*.sh \
  common/k8s/deploy.sh \
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
