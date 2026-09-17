variable "name" {
  description = "Environment name prefix (e.g. dev-template) - used for the Application name"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/qa/prod) - selects the deploy/<env>/aws source path"
  type        = string
}

variable "region" {
  description = "AWS region of the cluster (passed to aws eks get-token)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS API endpoint"
  type        = string
}

variable "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate"
  type        = string
}

variable "git_repo_url" {
  description = "HTTPS URL of the manifests repo (this repo)"
  type        = string
  default     = "https://github.com/michaeltg17/Template.Deployment.git"
}

variable "git_repo_token" {
  description = "GitHub PAT (contents:read on this repo only) ArgoCD uses to clone the repo"
  type        = string
  sensitive   = true
}

variable "argocd_chart_version" {
  description = "argo-cd helm chart version (pinned; verified present in the argo-helm index)"
  type        = string
  default     = "10.9.1"
}
