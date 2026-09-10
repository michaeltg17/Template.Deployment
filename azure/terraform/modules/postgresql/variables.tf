variable "name" {
  description = "PostgreSQL Flexible Server name (lowercase, 3-45 chars, no hyphens-only)"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group"
  type        = string
}

variable "vnet_id" {
  description = "VNet to link the server's private DNS zone to"
  type        = string
}

variable "delegated_subnet_id" {
  description = "Private subnet (delegated to Microsoft.DBforPostgreSQL/flexibleServers) the server is injected into"
  type        = string
}

variable "admin_login" {
  description = "Server administrator login"
  type        = string
  default     = "template_admin"
}

variable "admin_password" {
  description = "Server administrator password. MUST equal DB_PASSWORD in common/k8s/environments/<env>.secrets.env and the DB_PASSWORD_<ENV> GitHub secret"
  type        = string
  sensitive   = true
}

variable "pg_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "16"
}

variable "sku_name" {
  description = "Compute SKU (B_Standard_B1ms = cheapest)"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "storage_mb" {
  description = "Storage size in MB (min 32768)"
  type        = number
  default     = 32768
}

variable "storage_tier" {
  description = "Storage performance tier (P4 for 32768 MB)"
  type        = string
  default     = "P4"
}

variable "tags" {
  description = "Tags applied to every resource in this module"
  type        = map(string)
  default     = {}
}
