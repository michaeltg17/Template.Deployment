variable "argocd_repo_token" {
  description = "GitHub PAT (contents:read on this repo only) ArgoCD uses to clone the rendered manifests. Never in the repo itself"
  type        = string
  sensitive   = true
}
