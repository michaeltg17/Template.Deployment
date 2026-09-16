module "vpc" {
  source = "../../modules/vpc"

  name                 = local.name
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  tags = local.tags
}

module "eks" {
  source = "../../modules/eks"

  name                  = local.name
  region                = var.aws_region
  environment           = var.environment
  project_name          = var.project_name
  kubernetes_version    = var.kubernetes_version
  vpc_id                = module.vpc.vpc_id
  vpc_cidr              = module.vpc.vpc_cidr
  private_subnet_ids    = module.vpc.private_subnet_ids
  worker_instance_types = var.worker_instance_types
  worker_disk_size_gb   = var.worker_disk_size_gb
  worker_min_size       = var.worker_min_size
  worker_max_size       = var.worker_max_size
  worker_desired_size   = var.worker_desired_size
  github_repo           = "michaeltg17/Template.Deployment"
  # Prod: pin the CD (deploy) identity to the main/dev branches only.
  cd_oidc_sub = var.cd_oidc_sub

  tags = local.tags
}

module "rds" {
  source = "../../modules/rds"

  name                       = "${local.name}-db"
  engine_version             = var.db_engine_version
  instance_class             = var.db_instance_class
  master_password            = var.db_master_password
  app_username               = var.db_app_username
  app_password               = var.db_app_password
  multi_az                   = var.db_multi_az
  apply_immediately          = var.db_apply_immediately
  backup_retention_period    = var.db_backup_retention_period
  deletion_protection        = var.db_deletion_protection
  skip_final_snapshot        = var.db_skip_final_snapshot
  final_snapshot_identifier  = var.db_final_snapshot_identifier
  vpc_id                     = module.vpc.vpc_id
  private_subnet_ids         = module.vpc.private_subnet_ids
  vpc_cidr                   = module.vpc.vpc_cidr
  allowed_security_group_ids = [module.eks.node_security_group_id]

  tags = local.tags
}

# Application secrets (DB login + image API key) in Secrets Manager and the
# image API URL in SSM, plus the External Secrets Operator IRSA role. The pods
# read the secrets at runtime via ESO (aws/k8s ExternalSecret manifests); the
# CD workflow reads the SSM parameter + RDS describe and never sees the
# password or key.
module "secrets" {
  source = "../../modules/secrets"

  name                    = local.name
  environment             = var.environment
  project_name            = var.project_name
  db_master_username      = module.rds.master_username
  db_master_password      = var.db_master_password
  db_app_username         = var.db_app_username
  db_app_password         = var.db_app_password
  image_api_key           = var.image_api_key
  image_api_url           = var.image_api_url
  cluster_oidc_issuer     = module.eks.cluster_oidc_issuer
  cluster_oidc_issuer_arn = module.eks.cluster_oidc_provider_arn

  tags = local.tags
}

# Kubernetes API access uses EKS access entries (not the legacy aws-auth
# ConfigMap). The eks module sets the cluster to API auth mode and creates an
# access entry for the CD role (group "admins"); EKS auto-creates the node-role
# entry for the managed node group. Cluster-admin for the CD role is granted by
# the ClusterRoleBinding in aws/k8s/cd-admin.yaml (applied by deploy.sh).
