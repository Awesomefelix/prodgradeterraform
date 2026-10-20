output "storage_account_id" {
  value = azurerm_storage_account.sa.id
}

output "storage_account_name" {
  value = azurerm_storage_account.sa.name
}

output "blob_container_name" {
  value = azurerm_storage_container.blob_container.name
}
