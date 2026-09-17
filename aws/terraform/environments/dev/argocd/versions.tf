terraform {
  required_version = ">= 1.5"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
  }

  # Remote state: a second key per environment (argocd) in the shared bucket.
  # Separate from the main env state so this state can read the cluster after
  # it exists (see main.tf).
  backend "s3" {
    bucket       = "michaeltg17-template-terraform-state"
    key          = "dev/argocd/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
