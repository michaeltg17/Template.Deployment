variable "name" {
  description = "Name prefix for the virtual network and subnets"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to create the network in"
  type        = string
}

variable "vnet_cidr" {
  description = "VNet address space"
  type        = string
  default     = "10.0.0.0/16"
}

variable "appgw_subnet_cidr" {
  description = "App Gateway subnet (public, dedicated + delegated)"
  type        = string
  default     = "10.0.0.0/24"
}

variable "nodes_subnet_cidr" {
  description = "AKS node subnet (private; nodes + pods via the CNI node-subnet model)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "pg_subnet_cidr" {
  description = "PostgreSQL subnet (private)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "tags" {
  description = "Tags applied to every resource in this module"
  type        = map(string)
  default     = {}
}
