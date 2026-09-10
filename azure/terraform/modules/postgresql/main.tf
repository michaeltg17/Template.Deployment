locals {
  tags = var.tags
}

# Private DNS zone (must end with .postgres.database.azure.com). The server's
# FQDN is resolved to its VNet private IP through this zone, so the app reaches
# the DB privately by name - no public endpoint at all.
resource "azurerm_private_dns_zone" "this" {
  name                = "${var.name}-pdz.postgres.database.azure.com"
  resource_group_name = var.resource_group_name

  tags = merge(local.tags, { Name = "${var.name}-pdz" })
}

# Link the private zone to the VNet so every subnet in the VNet can resolve the
# server's FQDN to its private IP.
resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  name                  = "${var.name}-pdz-vnetlink"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this.name
  virtual_network_id    = var.vnet_id
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name

  version    = var.pg_version
  sku_name   = var.sku_name
  storage_mb = var.storage_mb
  zone       = 1

  administrator_login    = var.admin_login
  administrator_password = var.admin_password

  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = azurerm_private_dns_zone.this.id
  public_network_access_enabled = false

  backup_retention_days = 7

  tags = merge(local.tags, { Name = var.name })

  depends_on = [azurerm_private_dns_zone_virtual_network_link.this]
}
