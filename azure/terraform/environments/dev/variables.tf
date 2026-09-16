variable "location" {
  description = "Azure region for all resources in this environment"
  type        = string
  default     = "eastus"
}

variable "project_name" {
  description = "Resource name suffix and Project tag"
  type        = string
  default     = "template"
}

variable "environment" {
  description = "Environment name (prefix of every resource name)"
  type        = string
  default     = "dev"
}

variable "db_admin_password" {
  description = "PostgreSQL Flexible Server admin password. MUST equal DB_PASSWORD in common/k8s/environments/<env>.secrets.env and the DB_PASSWORD_<ENV> GitHub secret"
  type        = string
  sensitive   = true
}

variable "node_vm_size" {
  description = "VM size for the AKS user node pool. Pick one your subscription allows in the chosen region (e.g. Standard_D2s_v7)."
  type        = string
  default     = "Standard_D2s_v7"
}
