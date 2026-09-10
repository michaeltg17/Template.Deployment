output "vnet_id" {
  description = "VNet id"
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "VNet name"
  value       = azurerm_virtual_network.this.name
}

output "vnet_cidr" {
  description = "VNet address space"
  value       = var.vnet_cidr
}

output "appgw_subnet_id" {
  description = "App Gateway (delegated) subnet id"
  value       = azurerm_subnet.appgw.id
}

output "nodes_subnet_id" {
  description = "AKS node subnet id"
  value       = azurerm_subnet.nodes.id
}

output "nodes_subnet_cidr" {
  description = "AKS node subnet CIDR"
  value       = var.nodes_subnet_cidr
}

output "pg_subnet_id" {
  description = "PostgreSQL subnet id"
  value       = azurerm_subnet.pg.id
}
