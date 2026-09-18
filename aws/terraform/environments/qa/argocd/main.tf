# ArgoCD (GitOps) state. Reads the cluster from the main env state (../) via
# terraform_remote_state, then installs ArgoCD + the Application that syncs
# deploy/<env>/aws/ into the cluster.
#
# Separate state (not the main env state) because the helm/kubernetes providers
# need a live cluster API endpoint, which does not exist during the first apply
# of the main state. This state is planned/applied after the main state.

locals {
  # Env-first resource name prefix (<env>-<project>), matching the main state.
  name = "qa-template"
}

data "terraform_remote_state" "main" {
  backend = "s3"
  config = {
    bucket       = "michaeltg17-template-terraform-state"
    key          = "qa/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

module "argocd" {
  source = "../../../modules/argocd"

  name                   = local.name
  environment            = "qa"
  region                 = data.terraform_remote_state.main.region
  cluster_name           = data.terraform_remote_state.main.cluster_name
  cluster_endpoint       = data.terraform_remote_state.main.cluster_endpoint
  cluster_ca_certificate = data.terraform_remote_state.main.cluster_certificate_authority_data
  git_repo_token         = var.argocd_repo_token
}
