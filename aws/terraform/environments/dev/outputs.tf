output "region" {
  description = "AWS region"
  value       = var.aws_region
}

output "vpc_id" {
  description = "VPC id (used by bootstrap/setup-eks.sh)"
  value       = module.vpc.vpc_id
}

output "cluster_name" {
  description = "EKS cluster name (aws eks update-kubeconfig --name <this>)"
  value       = module.eks.cluster_name
}

# Surfaced for the argocd state (./argocd), which reads the cluster via
# terraform_remote_state to configure its helm/kubernetes providers.
output "cluster_endpoint" {
  description = "EKS API endpoint (argocd state)"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate (argocd state)"
  value       = module.eks.cluster_certificate_authority_data
}

output "kubectl_setup" {
  description = "One-liner to point kubectl at the cluster"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --alias ${module.eks.cluster_name}"
}

output "rds_endpoint" {
  description = "RDS private endpoint (put in k8s/environments/<env>.env as RDS_ENDPOINT)"
  value       = module.rds.address
}

output "db_user" {
  description = "The login the app connects as (app user when set, else master). Put in k8s/environments/<env>.env as DB_USER"
  value       = module.rds.username
}

output "cd_role_arn" {
  description = "GitHub Actions role ARN for the CD (deploy) workflow (set as the AWS_ROLE_ARN_<ENV> repo variable)"
  value       = module.eks.cd_role_arn
}

output "plan_role_arn" {
  description = "GitHub Actions role ARN for the read-only terraform plan CI job (set as the AWS_PLAN_ROLE_ARN_<ENV> repo variable)"
  value       = module.eks.plan_role_arn
}

output "apply_role_arn" {
  description = "GitHub Actions role ARN for the terraform apply CI job (set as the AWS_APPLY_ROLE_ARN_<ENV> repo variable)"
  value       = module.eks.apply_role_arn
}

output "alb_controller_role_arn" {
  description = "IRSA role for the load balancer controller (bootstrap/setup-eks.sh reads it)"
  value       = module.eks.alb_controller_role_arn
}

output "eso_role_arn" {
  description = "IRSA role for External Secrets Operator (bootstrap/setup-eks.sh annotates the ESO service account with it)"
  value       = module.secrets.eso_role_arn
}

output "db_secret_name" {
  description = "Secrets Manager name of the app-login secret (referenced by aws/k8s/external-secret.yaml)"
  value       = module.secrets.db_secret_name
}

output "image_api_secret_name" {
  description = "Secrets Manager name of the image-API-key secret (referenced by aws/k8s/external-secret.yaml)"
  value       = module.secrets.image_api_secret_name
}

output "destroy_command" {
  description = "Destroys everything this config created"
  value       = "terraform destroy (run from this directory)"
}
