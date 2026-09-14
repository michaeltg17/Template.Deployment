output "db_secret_arn" {
  description = "ARN of the <name>-db secret (the app login). Granted to the ESO IRSA role"
  value       = aws_secretsmanager_secret.db.arn
}

output "db_master_secret_arn" {
  description = "ARN of the <name>-db-master secret (RDS master login). Granted to the CD role so bootstrap/provision-db-user.sh can read it"
  value       = aws_secretsmanager_secret.db_master.arn
}

output "image_api_secret_arn" {
  description = "ARN of the <name>-image-api secret. Granted to the ESO IRSA role"
  value       = aws_secretsmanager_secret.image_api.arn
}

output "db_secret_name" {
  description = "Name of the <name>-db secret (referenced by the aws/k8s ExternalSecret)"
  value       = aws_secretsmanager_secret.db.name
}

output "image_api_secret_name" {
  description = "Name of the <name>-image-api secret (referenced by the aws/k8s ExternalSecret)"
  value       = aws_secretsmanager_secret.image_api.name
}

output "image_api_url_parameter_name" {
  description = "SSM parameter name holding the image API URL (read by the CD workflow)"
  value       = aws_ssm_parameter.image_api_url.name
}

output "eso_role_arn" {
  description = "IRSA role for External Secrets Operator (bootstrap/setup-eks.sh annotates the ESO service account with it)"
  value       = aws_iam_role.eso.arn
}
