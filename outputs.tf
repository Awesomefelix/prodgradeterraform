output "acr_login_server" {
  value       = module.backend.acr_login_server
  description = "Registry the container apps pull from (push images here)"
}

output "container_app_fqdns" {
  value       = module.backend.container_app_fqdns
  description = "Public FQDN per container app (null for apps without ingress)"
}

output "postgres_server_name" {
  value       = module.database.server_name
  sensitive   = true
  description = "PostgreSQL server name (marked sensitive because it is derived from a sensitive deployment context)"
}

output "frontend_hostname" {
  value = module.frontend.default_hostname
}

output "scaling_webhook_expiry" {
  value       = module.scaling.webhook_expiry_time
  description = "Rotate the scaling webhooks before this date (null when scaling is off)"
}
