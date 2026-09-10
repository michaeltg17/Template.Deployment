variable "name" {
  description = "App Gateway name"
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

variable "public_subnet_id" {
  description = "Dedicated (delegated to Microsoft.Network/applicationGateways) App Gateway subnet"
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource in this module"
  type        = map(string)
  default     = {}
}
