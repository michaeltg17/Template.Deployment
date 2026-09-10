resource "azurerm_resource_group" "this" {
  name     = "${local.name}-rg"
  location = var.location
  tags     = local.tags
}

# 10.0.0.0/16 split into three delegated subnets (App Gateway /24, AKS nodes
# /24, PostgreSQL /24). Private PG + AGIC both require the subnet delegation,
# so it lives in the vnet module.
module "vnet" {
  source = "../../modules/vnet"

  name                = local.name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  vnet_cidr           = "10.0.0.0/16"
  tags                = local.tags
}

# AKS + node pools + the GitHub-OIDC CD identity + the AGIC managed identity.
module "aks" {
  source = "../../modules/aks"

  name                = local.name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  vnet_subnet_id      = module.vnet.nodes_subnet_id
  node_vm_size        = var.node_vm_size
  tags                = local.tags
}

# Private PostgreSQL Flexible Server (smallest SKU) in the delegated subnet.
module "postgresql" {
  source = "../../modules/postgresql"

  name                = "${local.name}-pg"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  vnet_id             = module.vnet.vnet_id
  delegated_subnet_id = module.vnet.pg_subnet_id
  admin_password      = var.db_admin_password
  tags                = local.tags
}

# Public App Gateway (Standard_v2). AGIC rewrites its routing from the Ingress.
module "appgateway" {
  source = "../../modules/appgateway"

  name                = "${local.name}-agw"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  public_subnet_id    = module.vnet.appgw_subnet_id
  tags                = local.tags
}
