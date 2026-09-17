variable "name" {
  description = "Environment name prefix (e.g. dev-template) - used for the Application name"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/qa/prod) - selects the deploy/<env>/azure source path"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group of the AKS cluster"
  type        = string
}

variable "cluster_name" {
  description = "AKS cluster name"
  type        = string
}

variable "tf_plan_principal_id" {
  description = "Object id of the tf-plan managed identity (bound read-only in the cluster)"
  type        = string
}

variable "tf_apply_principal_id" {
  description = "Object id of the tf-apply managed identity (bound cluster-admin in the cluster)"
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
