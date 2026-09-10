locals {
  tags = {
    Project     = "template"
    Environment = "shared"
    ManagedBy   = "terraform"
  }
}

# Remote state for every azure/terraform environment. One key per env lives
# under the container (dev/terraform.tfstate, ...) and each env's
# versions.tf points at it.
#
# The storage account name must be globally unique, lowercase, and 3-24 chars
# (no hyphens). Change it here AND in environments/dev/versions.tf together.
resource "azurerm_resource_group" "state" {
  name     = "template-az-state"
  location = "eastus"
  tags     = local.tags
}

resource "azurerm_storage_account" "state" {
  name                     = "michaeltg17azstate"
  resource_group_name      = azurerm_resource_group.state.name
  location                 = azurerm_resource_group.state.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  tags = local.tags
}

resource "azurerm_storage_container" "state" {
  name                  = "terraform"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}
