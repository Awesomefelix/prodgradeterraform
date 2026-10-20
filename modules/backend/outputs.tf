output "acr_login_server" {
  value       = azurerm_container_registry.acr.login_server
  description = "Registry that both container apps pull from"
}

output "acr_name" {
  value = azurerm_container_registry.acr.name
}

output "container_app_fqdns" {
  value       = { for k, a in azurerm_container_app.apps : k => try(a.ingress[0].fqdn, null) }
  description = "Public FQDN per container app (null for apps without ingress)"
}
