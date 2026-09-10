terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # One-time bootstrap with local state (like the AWS S3 bootstrap). The envs
  # (environments/<env>) point at the storage account created here as their
  # remote backend - run `terraform init && terraform apply` here first.
}

provider "azurerm" {
  features {}
}
