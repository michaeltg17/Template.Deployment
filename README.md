[![ci](https://github.com/michaeltg17/Template.Deployment/actions/workflows/ci.yml/badge.svg)](https://github.com/michaeltg17/Template.Deployment/actions/workflows/ci.yml)
# Template.Deployment

Deployment of the Template project to **AWS** (EKS + ALB + RDS) and **Azure** (AKS + App Gateway/AGIC + PostgreSQL Flexible), managed end to end with Terraform and Kubernetes manifests. The two clouds are deliberately symmetric; the app itself (the k8s workloads) lives once in `common/k8s/`, with each cloud adding only its Terraform, bootstrap, and a thin ingress overlay.

Full diagram and description of the architecture here: [ARCH.md](https://github.com/michaeltg17/Template.Deployment/blob/main/ARCH.md)

API: [Template.Api](https://github.com/michaeltg17/Template.Api)

UI: [Template.React](https://github.com/michaeltg17/Template.React)

Built with the help of local AI using https://github.com/michaeltg17/best-model-dual-3090 and [OpenCode](https://github.com/anomalyco/opencode).

## Quickstart

Everything in this repo (bootstrap, deploy, teardown, CI) runs from shell scripts that expect a Linux userland. The supported, host-agnostic way to get that userland is the **pinned tooling container** - no WSL, no per-tool installs, identical on Windows / macOS / Linux:

```sh
# one-time: builds the tools image (terraform, kubectl, helm, aws, az, python3)
bash common/tools-docker.sh                 # drops you into an interactive shell in the container
```

Run any repo script through it (your `~/.aws` and `~/.kube` are bind-mounted in, so credentials stay on the host):

```sh
bash common/tools-docker.sh -c "bash aws/bootstrap/setup-eks.sh dev"
bash common/tools-docker.sh -c "bash common/k8s/deploy.sh dev aws"
bash common/tools-docker.sh -c "bash common/ci.sh"        # or: bash common/ci-docker.sh
```

> **Windows note:** run these from **Git Bash** (or any bash). PowerShell mangles the bash scripts. If you prefer to install the tools natively instead of using the container, see the per-cloud **Prerequisites** in [ARCH.md](ARCH.md) for the exact versions (terraform 1.15.8, kubectl v1.36.3, helm v3.22.0, awscli 2.34.0).

The full walkthrough (bootstrap -> provision -> cluster bootstrap -> deploy -> validate, for both clouds) is in [ARCH.md](ARCH.md#aws).

## How deployment works (GitOps)

Infrastructure is Terraform; the app's k8s workloads are delivered **GitOps-style**:

- **Terraform** provisions each cloud (EKS/AKS, DB, ingress, and **ArgoCD** itself). Each env's ArgoCD lives in its own Terraform state (`<env>/argocd/`) so it can install after the cluster exists.
- **CD** (`Deploy (AWS)` / `Deploy (Azure)` in Actions) renders the cloud-agnostic manifests in `common/k8s/` + the `<cloud>/k8s/` overlay with `common/k8s/render.sh` and **commits** them to `deploy/<env>/<cloud>/` on `main`.
- **ArgoCD** (in-cluster) watches `deploy/<env>/<cloud>/` on `main` and syncs the change into the cluster. The migrations Job runs first (`PreSync` hook) and is deleted on success.
- **Terraform in CI**: `terraform plan` runs read-only on every PR (the `terraform-plan` job in `ci.yml`); `terraform apply` runs from `main` (`apply-infra.yml`) - auto for `dev`/`qa`, button-gated for `prod`. Both use GitHub OIDC (no stored long-lived credentials).

