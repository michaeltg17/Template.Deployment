locals {
  tags                 = var.tags
  github_oidc_issuer   = "https://token.actions.githubusercontent.com"
  resource_group_scope = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
}

# Public API server (kubectl/CD reach it directly) + Azure CNI node-subnet
# model (pods share the node subnet IPs). Version is left to AKS's default
# (latest supported for the region).
resource "azurerm_kubernetes_cluster" "this" {
  name                    = var.name
  location                = var.location
  resource_group_name     = var.resource_group_name
  dns_prefix              = "${var.name}-dns"
  private_cluster_enabled = false

  # System-assigned managed identity for the cluster's managed resources.
  identity {
    type = "SystemAssigned"
  }

  # CNI node-subnet model: pods share the node subnet IPs. (Network config lives
  # in the network_profile block in this provider version.) The VNet is
  # 10.0.0.0/16, so the default service CIDR (10.0.0.0/16) would overlap; use a
  # separate range for ClusterIPs.
  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.100.0.0/16"
    dns_service_ip = "10.100.0.10"
  }

  # System node pool: 1 small node (cheapest). The default_node_pool block is
  # implicitly the system pool (no `mode` argument in this provider version);
  # the user pool is a separate resource below.
  default_node_pool {
    name            = "system"
    node_count      = 1
    vm_size         = var.node_vm_size
    vnet_subnet_id  = var.vnet_subnet_id
    os_disk_size_gb = 30
    max_pods        = 30
  }

  tags = merge(local.tags, { Name = var.name })

  # Azure sets computed upgrade_settings defaults (node_soak_duration_in_minutes,
  # etc.) on the system pool that Terraform does not declare, causing perpetual
  # plan drift. Ignore the block's computed drift (Terraform still creates it).
  lifecycle {
    ignore_changes = [default_node_pool]
  }
}

# User node pool: the app's pods land here.
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  node_count            = var.node_count
  vm_size               = var.node_vm_size
  mode                  = "User"
  vnet_subnet_id        = var.vnet_subnet_id
  os_disk_size_gb       = 30
  max_pods              = 30

  tags = merge(local.tags, { Name = "${var.name}-user" })

  # Azure sets computed upgrade_settings defaults that Terraform does not declare,
  # causing perpetual plan drift. Ignore them (Terraform still creates the pool).
  lifecycle {
    ignore_changes = [upgrade_settings]
  }
}

# --- CD identity: a user-assigned managed identity federated to GitHub OIDC
# (no stored secret). Recent azurerm removed azurerm_application /
# azurerm_service_principal, so the identity is a user-assigned identity plus a
# federated credential on it. The CD workflow uses its client id with
# `azure/login` (federated, no secret). ---
data "azurerm_client_config" "current" {}

resource "azurerm_user_assigned_identity" "cd" {
  name                = "${var.name}-cd"
  location            = var.location
  resource_group_name = var.resource_group_name

  tags = merge(local.tags, { Name = "${var.name}-cd" })
}

# One federated credential per branch the workflow may run on. The subject is
# the GitHub OIDC claim the workflow presents (repo + branch ref).
resource "azurerm_federated_identity_credential" "cd" {
  for_each = toset(var.cd_branches)

  name                      = "${var.name}-cd-${each.value}"
  user_assigned_identity_id = azurerm_user_assigned_identity.cd.id
  issuer                    = local.github_oidc_issuer
  subject                   = "repo:${var.github_repo}:ref:refs/heads/${each.value}"
  audience                  = ["api://AzureADTokenExchange"]
}

# CD needs to read the resource group (PG endpoint, etc.) and get kubectl
# credentials on the cluster.
resource "azurerm_role_assignment" "cd_reader" {
  scope                = local.resource_group_scope
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.cd.principal_id
}

resource "azurerm_role_assignment" "cd_aks" {
  scope = azurerm_kubernetes_cluster.this.id
  # Grants the CD identity `Microsoft.ContainerService/managedClusters/accessProfiles/*`
  # (via the AKS Contributor role) so the deploy workflow can run
  # `az aks get-credentials` and fetch the kubeconfig.
  role_definition_name = "Azure Kubernetes Service Contributor Role"
  principal_id         = azurerm_user_assigned_identity.cd.principal_id
}
