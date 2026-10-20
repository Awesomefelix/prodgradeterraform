resource "azurerm_managed_redis" "redis" {
  name                = "redis-${var.prefix}-${var.environment}-832"
  location            = "eastus" # Hardcoded to East US to bypass North Europe capacity limits
  resource_group_name = var.resource_group_name
  sku_name            = var.redis_sku

  default_database {
    clustering_policy                  = "EnterpriseCluster"
    eviction_policy                    = "NoEviction"
    access_keys_authentication_enabled = true
  }

  tags = {
    environment = var.environment
  }
}

# Sync Redis Hostname to Key Vault
resource "azurerm_key_vault_secret" "redis_host" {
  name         = "REDIS-HOST"
  value        = azurerm_managed_redis.redis.hostname
  key_vault_id = var.key_vault_id
}

# Sync Redis Port to Key Vault
resource "azurerm_key_vault_secret" "redis_port" {
  name         = "REDIS-PORT"
  value        = tostring(azurerm_managed_redis.redis.default_database[0].port)
  key_vault_id = var.key_vault_id
}

# Sync Redis Primary Access Key to Key Vault
resource "azurerm_key_vault_secret" "redis_key" {
  name         = "REDIS-PRIMARY-KEY"
  value        = azurerm_managed_redis.redis.default_database[0].primary_access_key
  key_vault_id = var.key_vault_id
}

output "redis_hostname" {
  value = azurerm_managed_redis.redis.hostname
}
