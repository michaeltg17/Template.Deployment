variable "name" {
  description = "AKS cluster name"
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

variable "vnet_subnet_id" {
  description = "AKS node subnet id (nodes + pods, CNI node-subnet model)"
  type        = string
}

variable "node_vm_size" {
  description = "Node pool VM size (Standard_B2s_v2 = cheapest)"
  type        = string
  default     = "Standard_B2s_v2"
}

variable "node_count" {
  description = "Number of user nodes (1 = cheapest)"
  type        = number
  default     = 1
}

variable "github_repo" {
  description = "GitHub repo owner/name (for the CD federated identity)"
  type        = string
  default     = "michaeltg17/Template.Deployment"
}

variable "cd_branches" {
  description = "Branches the CD workflow may run on (each gets a federated identity credential)"
  type        = list(string)
  default     = ["dev", "main"]
}

variable "tags" {
  description = "Tags applied to every resource in this module"
  type        = map(string)
  default     = {}
}
