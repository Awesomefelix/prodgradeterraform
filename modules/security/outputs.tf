output "key_vault_id" {
  value = azurerm_key_vault.kv.id
  # Wait for the deployer's Secrets Officer role so secret writes don't race RBAC
  depends_on = [azurerm_role_assignment.devops_kv_admin]
}

output "key_vault_uri" {
  value = azurerm_key_vault.kv.vault_uri
}

output "frontend_identity_id" {
  value      = azurerm_user_assigned_identity.frontend_identity.id
  depends_on = [azurerm_role_assignment.frontend_kv_reader]
}

output "backend_identity_id" {
  value      = azurerm_user_assigned_identity.backend_identity.id
  depends_on = [azurerm_role_assignment.backend_kv_reader]
}

output "backend_identity_principal_id" {
  value = azurerm_user_assigned_identity.backend_identity.principal_id
}
