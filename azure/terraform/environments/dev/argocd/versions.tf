terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # Pinned to the 4.x line (5.x renamed the Entra ID + federated-identity
      # resources the aks module uses). Bump deliberately.
      version = "~> 4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
  }

  # Remote state: a second key per environment (argocd) in the shared storage
  # account. Separate from the main env state so this state can read the
  # cluster after it exists (see main.tf). Azure AD auth (no account key).
  backend "azurerm" {
    resource_group_name  = "template-az-state"
    storage_account_name = "michaeltg17azstate"
    container_name       = "terraform"
    key                  = "dev/argocd/terraform.tfstate"
    use_azuread_auth     = true
  }
}
