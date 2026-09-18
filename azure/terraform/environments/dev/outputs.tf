output "location" {
  description = "Azure region of this environment"
  value       = var.location
}

output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.this.name
}

# --- cluster ---
output "aks_name" {
  description = "AKS cluster name"
  value       = module.aks.cluster_name
}

output "kubectl_setup" {
  description = "Command to load the cluster credentials"
  value       = "az aks get-credentials -n ${module.aks.cluster_name} -g ${azurerm_resource_group.this.name}"
}

# --- database ---
output "postgresql_endpoint" {
  description = "PostgreSQL Flexible Server private FQDN"
  value       = module.postgresql.fqdn
}

output "db_user" {
  description = "PostgreSQL admin login (already the <admin>@<fqdn> form)"
  value       = module.postgresql.db_user
}

output "db_password" {
  description = "PostgreSQL admin password"
  value       = var.db_admin_password
  sensitive   = true
}

# --- CI/CD (GitHub OIDC) ---
output "cd_client_id" {
  description = "CD service principal client id (set as AZURE_CLIENT_ID in the CD workflow)"
  value       = module.aks.cd_client_id
}

output "cd_tenant_id" {
  description = "Tenant id (set as AZURE_TENANT_ID in the CD workflow)"
  value       = module.aks.cd_tenant_id
}

output "tf_plan_client_id" {
  description = "tf-plan managed identity client id (set as AZURE_TF_PLAN_CLIENT_ID_<ENV> in the CI workflow)"
  value       = module.aks.tf_plan_client_id
}

output "tf_apply_client_id" {
  description = "tf-apply managed identity client id (set as AZURE_TF_APPLY_CLIENT_ID_<ENV> in the CI workflow)"
  value       = module.aks.tf_apply_client_id
}

# Surfaced for the argocd state (./argocd), which binds these managed
# identities (by object id) as the tf-plan / tf-apply k8s users in the cluster.
output "tf_plan_principal_id" {
  description = "tf-plan managed identity object id (argocd state)"
  value       = module.aks.tf_plan_principal_id
}

output "tf_apply_principal_id" {
  description = "tf-apply managed identity object id (argocd state)"
  value       = module.aks.tf_apply_principal_id
}

# --- ingress ---
output "appgateway_id" {
  description = "App Gateway id (the AppGatewayIngress CR points at it)"
  value       = module.appgateway.application_gateway_id
}

output "appgateway_name" {
  description = "App Gateway name (armAuth/appgw.name for the AGIC helm install)"
  value       = module.appgateway.name
}

output "appgateway_fqdn" {
  description = "Public app URL (the App Gateway DNS name)"
  value       = module.appgateway.fqdn
}
