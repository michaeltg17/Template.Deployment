terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # Pinned to the 4.x line (5.x renamed the Entra ID + federated-identity
      # resources this module uses). Bump deliberately.
      version = "~> 4.0"
    }
  }

  # Remote state: one key per env in the shared storage account (created +
  # managed by azure/terraform/bootstrap). Azure AD auth (no account key
  # needed) - the account/rg must match the bootstrap.
  backend "azurerm" {
    resource_group_name  = "template-az-state"
    storage_account_name = "michaeltg17azstate"
    container_name       = "terraform"
    key                  = "dev/terraform.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
}
