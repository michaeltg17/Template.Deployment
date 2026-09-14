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
  db_master_username      = module.rds.master_username
  db_master_password      = var.db_master_password
  app_username            = var.db_app_username
  app_password            = var.db_app_password
  image_api_key           = var.image_api_key
  image_api_url           = var.image_api_url
  cluster_oidc_issuer     = module.eks.cluster_oidc_issuer
  cluster_oidc_issuer_arn = module.eks.cluster_oidc_provider_arn

  tags = local.tags
}

# Note: the aws-auth ConfigMap (node role -> system:node) is applied by
# bootstrap/setup-eks.sh with kubectl, not here. The kubernetes provider
# cannot plan kubernetes_manifest before the cluster exists (its
# cluster_ca_certificate is unknown at plan time).
