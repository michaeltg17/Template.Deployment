[![ci](https://github.com/michaeltg17/Template.Deployment/actions/workflows/ci.yml/badge.svg)](https://github.com/michaeltg17/Template.Deployment/actions/workflows/ci.yml)
# Template.Deployment

Deployment of the Template project to **AWS** (EKS + ALB + RDS) and **Azure** (AKS + App Gateway/AGIC + PostgreSQL Flexible), managed end to end with Terraform and Kubernetes manifests. The two clouds are deliberately symmetric; the app itself (the k8s workloads) lives once in `common/k8s/`, with each cloud adding only its Terraform, bootstrap, and a thin ingress overlay.

Full diagram and description of the architecture here: [ARCH.md](https://github.com/michaeltg17/Template.Deployment/blob/main/ARCH.md)

API: [Template.Api](https://github.com/michaeltg17/Template.Api)

Deployment: [Template.Deployment](https://github.com/michaeltg17/Template.Deployment)

Built with the help of local AI using https://github.com/michaeltg17/best-model-dual-3090 and [OpenCode](https://github.com/anomalyco/opencode).
