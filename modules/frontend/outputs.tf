output "service_plan_id" {
  value = local.plan.id
}

output "service_plan_name" {
  value = local.plan.name
}

output "default_hostname" {
  value = azurerm_linux_web_app.web.default_hostname
}
