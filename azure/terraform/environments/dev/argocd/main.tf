# ArgoCD (GitOps) state. Reads the cluster + tf principal ids from the main env
# state (../) via terraform_remote_state, then installs ArgoCD + the
# Application that syncs deploy/<env>/azure/ into the cluster.
#
# Separate state (not the main env state) because the module's data source reads
# the cluster's kube_config, which does not exist during the first apply of the
# main state. This state is planned/applied after the main state.

locals {
  # Env-first resource name prefix (<env>-<project>), matching the main state.
  name = "dev-template"
}

data "terraform_remote_state" "main" {
  backend = "azurerm"
  config = {
    resource_group_name  = "template-az-state"
    storage_account_name = "michaeltg17azstate"
    container_name       = "terraform"
    key                  = "dev/terraform.tfstate"
    use_azuread_auth     = true
  }
}

module "argocd" {
  source = "../../../modules/argocd"

  name                  = local.name
  environment           = "dev"
  location              = data.terraform_remote_state.main.location
  resource_group_name   = data.terraform_remote_state.main.resource_group_name
  cluster_name          = data.terraform_remote_state.main.aks_name
  tf_plan_principal_id  = data.terraform_remote_state.main.tf_plan_principal_id
  tf_apply_principal_id = data.terraform_remote_state.main.tf_apply_principal_id
  git_repo_token        = var.argocd_repo_token
}
