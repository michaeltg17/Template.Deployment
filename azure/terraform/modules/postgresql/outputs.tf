output "name" {
  description = "PostgreSQL Flexible Server name"
  value       = azurerm_postgresql_flexible_server.this.name
}

output "fqdn" {
  description = "Server FQDN (the private endpoint the app connects to; put in <env>.env as RDS_ENDPOINT)"
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "db_user" {
  description = "Server administrator login (put in <env>.env as DB_USER - just the login; the FQDN goes in RDS_ENDPOINT)"
  value       = azurerm_postgresql_flexible_server.this.administrator_login
}

output "admin_login" {
  description = "Server administrator login (same as db_user)"
  value       = azurerm_postgresql_flexible_server.this.administrator_login
}
