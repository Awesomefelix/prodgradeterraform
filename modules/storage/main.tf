resource "azurerm_storage_account" "sa" {
  name                     = "st${var.prefix}${var.environment}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Enterprise Standard: Deny all public network access
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
}

resource "azurerm_storage_container" "blob_container" {
  name                  = "app-data"
  storage_account_id    = azurerm_storage_account.sa.id
  container_access_type = "private"
}

# ---------------------------------------------------------
# Private Endpoint & DNS Zone for Blob Storage
# ---------------------------------------------------------
resource "azurerm_private_dns_zone" "blob_zone" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob_vnet_link" {
  name                  = "vnet-link-blob"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.blob_zone.name
  virtual_network_id    = var.vnet_id
}

resource "azurerm_private_endpoint" "blob_pe" {
  name                = "pe-blob-${var.prefix}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-blob"
    private_connection_resource_id = azurerm_storage_account.sa.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "blob-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob_zone.id]
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.blob_vnet_link]
}

# ---------------------------------------------------------
# RBAC: Grant Backend Access to Storage
# ---------------------------------------------------------
resource "azurerm_role_assignment" "backend_blob_contributor" {
  scope                = azurerm_storage_account.sa.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.backend_identity_principal_id
}

# ---------------------------------------------------------
# SECRETS: Sync Storage Connection String to Key Vault
# ---------------------------------------------------------
resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "STORAGE-CONNECTION-STRING"
  value        = azurerm_storage_account.sa.primary_connection_string
  key_vault_id = var.key_vault_id
}
