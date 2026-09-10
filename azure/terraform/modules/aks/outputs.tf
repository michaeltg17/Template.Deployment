output "cluster_name" {
  description = "AKS cluster name (az aks get-credentials -n <this>)"
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_id" {
  description = "AKS cluster id"
  value       = azurerm_kubernetes_cluster.this.id
}

output "cd_client_id" {
  description = "CD managed identity client id (set as AZURE_CLIENT_ID in the CD workflow)"
  value       = azurerm_user_assigned_identity.cd.client_id
}

output "cd_tenant_id" {
  description = "Tenant id (set as AZURE_TENANT_ID in the CD workflow)"
  value       = data.azurerm_client_config.current.tenant_id
}
