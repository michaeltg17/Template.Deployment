# AGENTS.md

## Context

- `ARCH.md` documents the full architecture and workflows for **both clouds**:
  AWS (Terraform + EKS + ALB controller + RDS) and Azure (Terraform + AKS +
  App Gateway/AGIC + PostgreSQL Flexible), plus the shared `common/k8s`
  deploy/CD and teardown. Read it before working on deployment, teardown,
  CI/CD, or anything that crosses the Terraform / k8s / cloud boundary.
- Layout: `common/` (cloud-agnostic k8s + CI), `aws/`, `azure/`. Each cloud has
  `terraform/` (modules + environments + bootstrap), `bootstrap/` (shell), and
  `k8s/` (ingress overlay). The app's k8s workloads live only in `common/k8s/`.
- `common/k8s/deploy.sh <env> <cloud>` renders common + `<cloud>/k8s` and
  applies in order. CI (`.github/workflows/ci.yml` -> `common/ci-docker.sh`)
  validates **both** clouds' Terraform + every shell script + every manifest.
- azurerm is pinned to `~> 4.0` (resolves to 4.81.0). In that version: there is
  **no** `azurerm_application`/`azurerm_service_principal` (the AGIC service
  principal is created by `azure/bootstrap/setup-aks.sh` via the az CLI); the AKS
  cluster uses `network_profile` + `identity` blocks and `default_node_pool` has
  no `mode`; the App Gateway `sku` block needs both `name` and `tier`; the
  private DNS vnet link uses `private_dns_zone_name` + `resource_group_name`.
- The Azure CD identity is a **user-assigned managed identity** + federated
  credential (created by Terraform); `cd-azure.yml` uses its client id with
  `azure/login` (federated, `id-token: write`).

## Branching model

- **All work happens on the `dev` branch.** Commit directly to `dev`; do **not** create feature/topic branches that open a PR straight to `main`.
- `main` only ever changes via a merged **`dev` → `main`** PR. There is exactly one PR in flight at a time, from `dev` to `main`.
- So the loop is: commit on `dev` → push `dev` → open (or update) the `dev` → `main` PR → merge.

## PR Workflow (dev → main)

When creating or updating the `dev` → `main` PR:

1. **Always run `git fetch origin main` first** — This is critical. The local `main` branch is often outdated and will show stale committed changes as part of the diff if not refreshed.
2. Compare `origin/main..dev` to identify only the actual new changes.
3. Check if a PR already exists (use `github_list_pull_requests`).
4. If none exists, create one with an accurate title and description summarizing the changes.
5. If one exists, update its title and description to reflect the actual current diff.
