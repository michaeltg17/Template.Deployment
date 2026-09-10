output "application_gateway_id" {
  description = "App Gateway id (AGIC is configured against this in bootstrap/setup-aks.sh)"
  value       = azurerm_application_gateway.this.id
}

output "name" {
  description = "App Gateway name (armAuth/appgw.name for the AGIC helm install)"
  value       = azurerm_application_gateway.this.name
}

output "fqdn" {
  description = "App Gateway public DNS name (the public app URL)"
  value       = azurerm_public_ip.this.fqdn
}

output "ip_address" {
  description = "App Gateway public IP"
  value       = azurerm_public_ip.this.ip_address
}
