output "id" {
  description = "DB instance identifier"
  value       = aws_db_instance.this.id
}

output "arn" {
  description = "DB instance ARN"
  value       = aws_db_instance.this.arn
}

output "address" {
  description = "Private endpoint address (put in k8s/environments/<env>.env as RDS_ENDPOINT)"
  value       = aws_db_instance.this.address
}

output "port" {
  description = "DB port"
  value       = aws_db_instance.this.port
}

output "username" {
  description = "The login the app connects as (the dedicated app user when app_username is set, otherwise the master user). Put in k8s/environments/<env>.env as DB_USER and store in the <env>-db secret"
  value       = var.app_username != "" ? var.app_username : aws_db_instance.this.username
}

output "master_username" {
  description = "Master username (always the RDS master login; bootstrap/provision-db-user.sh uses it to create the app user)"
  value       = aws_db_instance.this.username
}
