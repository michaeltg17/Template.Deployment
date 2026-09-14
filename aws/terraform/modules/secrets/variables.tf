variable "name" {
  description = "Resource name prefix (e.g. template-dev). Secrets are named <name>-db, <name>-db-master, <name>-image-api"
  type        = string
}

variable "environment" {
  description = "Environment name (dev/qa/prod). Used for the SSM parameter path template/<env>/image-api-url"
  type        = string
}

variable "db_master_username" {
  description = "RDS master username"
  type        = string
}

variable "db_master_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "app_username" {
  description = "Dedicated app login (prod); empty = the app connects as the master user (dev/qa)"
  type        = string
  default     = ""
}

variable "app_password" {
  description = "Dedicated app login password (only used when app_username is set)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "image_api_key" {
  description = "Image API key for this environment"
  type        = string
  sensitive   = true
}

variable "image_api_url" {
  description = "Image API base URL for this environment (non-secret, stored in SSM Parameter Store)"
  type        = string
}

variable "cluster_oidc_issuer" {
  description = "EKS cluster OIDC issuer URL (e.g. https://oidc.eks.<region>.amazonaws.com/id/...). Used to build the ESO IRSA role's trust condition"
  type        = string
}

variable "cluster_oidc_issuer_arn" {
  description = "ARN of the EKS cluster OIDC provider (the Federated principal the ESO IRSA role trusts)"
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource in this module"
  type        = map(string)
  default     = {}
}
