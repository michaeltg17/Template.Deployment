output "resource_group_name" {
  description = "State resource group name (must match environments/*/versions.tf backend)"
  value       = azurerm_resource_group.state.name
}

output "storage_account_name" {
  description = "State storage account name (must match environments/*/versions.tf backend)"
  value       = azurerm_storage_account.state.name
}

output "container_name" {
  description = "State container name (must match environments/*/versions.tf backend)"
  value       = azurerm_storage_container.state.name
}
