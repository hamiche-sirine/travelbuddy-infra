output "acr_login_server" {
  description = "Adresse du registre pour pousser les images"
  value       = azurerm_container_registry.main.login_server
}

output "backend_url" {
  description = "URL publique du backend"
  value       = "https://${azurerm_container_app.backend.ingress[0].fqdn}"
}

output "frontend_url" {
  description = "URL publique du frontend"
  value       = "https://${azurerm_container_app.frontend.ingress[0].fqdn}"
}