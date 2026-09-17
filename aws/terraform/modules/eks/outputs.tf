output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "EKS API endpoint (private)"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Cluster API security group id"
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "Worker node security group id"
  value       = aws_security_group.node.id
}

output "node_group_arn" {
  description = "Managed node group ARN"
  value       = aws_eks_node_group.this.arn
}

output "node_role_arn" {
  description = "Worker node IAM role ARN"
  value       = aws_iam_role.node.arn
}

output "cd_role_arn" {
  description = "GitHub Actions OIDC role ARN for the CD (deploy) workflow (set as AWS_ROLE_ARN_<env> repo secret)"
  value       = aws_iam_role.cd.arn
}

output "plan_role_arn" {
  description = "GitHub Actions OIDC role ARN for the read-only `terraform plan` CI job (any ref)"
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "GitHub Actions OIDC role ARN for the `terraform apply` CI job (main ref + workflow_dispatch only)"
  value       = aws_iam_role.apply.arn
}

output "alb_controller_role_arn" {
  description = "IRSA role for the load balancer controller (used by bootstrap/setup-eks.sh)"
  value       = aws_iam_role.alb_controller.arn
}

output "cluster_oidc_issuer" {
  description = "EKS cluster OIDC issuer URL (the secrets module uses it to build the ESO IRSA trust condition)"
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "cluster_oidc_provider_arn" {
  description = "ARN of the EKS cluster OIDC provider (the secrets module's ESO IRSA role trusts it)"
  value       = aws_iam_openid_connect_provider.eks.arn
}
