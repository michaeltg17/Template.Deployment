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

output "tf_plan_principal_id" {
  description = "tf-plan managed identity object id (bound read-only in the cluster by the argocd module)"
  value       = azurerm_user_assigned_identity.tf_plan.principal_id
}

output "tf_apply_principal_id" {
  description = "tf-apply managed identity object id (bound cluster-admin in the cluster by the argocd module)"
  value       = azurerm_user_assigned_identity.tf_apply.principal_id
}

output "tf_plan_client_id" {
  description = "tf-plan managed identity client id (set as AZURE_TF_PLAN_CLIENT_ID_<ENV> in the CI workflow)"
  value       = azurerm_user_assigned_identity.tf_plan.client_id
}

output "tf_apply_client_id" {
  description = "tf-apply managed identity client id (set as AZURE_TF_APPLY_CLIENT_ID_<ENV> in the CI workflow)"
  value       = azurerm_user_assigned_identity.tf_apply.client_id
}
