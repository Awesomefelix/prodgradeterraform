output "automation_account_name" {
  value       = one(azurerm_automation_account.scaling[*].name)
  description = "Automation account that runs the scaling runbook (null when scaling is off)"
}

output "webhook_expiry_time" {
  value       = local.enable_runbook ? var.webhook_expiry_time : null
  description = "Rotate the scaling webhooks before this date"
}
