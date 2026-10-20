data "azurerm_client_config" "current" {}

# -----------------------------------------------------------------------------
# PostgreSQL Flexible Server.
#
# Two variants of the same server, chosen by var.autoscaling_enabled:
#   db         - SKU and storage are fully controlled by Terraform.
#   db_scaled  - storage auto-grows and the SKU is changed at runtime by the scaling
#                runbook, so Terraform ignores sku_name / storage_mb to avoid undoing it.
#
# Switching an EXISTING server between the two needs a state move first:
#   terraform state mv 'module.database.azurerm_postgresql_flexible_server.db[0]' \
#                      'module.database.azurerm_postgresql_flexible_server.db_scaled[0]'
#
# Network access: the server is NOT VNet-injected. VNet workloads connect through the
# private endpoint below; public access is controlled by var.public_access_enabled.
# -----------------------------------------------------------------------------
resource "azurerm_postgresql_flexible_server" "db" {
  count               = var.autoscaling_enabled ? 0 : 1
  name                = "psql-${var.prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = var.db_sku
  storage_mb          = var.db_storage_mb
  version             = "16"

  public_network_access_enabled = var.public_access_enabled

  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password

  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = true # Enable password auth for local Dev tools
    tenant_id                     = data.azurerm_client_config.current.tenant_id
  }

  lifecycle {
    ignore_changes = [zone]

    precondition {
      condition     = var.public_access_enabled || var.private_endpoint_enabled
      error_message = "Public access can only be disabled when private_endpoint_enabled is true, otherwise nothing could reach the server."
    }
  }
}

resource "azurerm_postgresql_flexible_server" "db_scaled" {
  count               = var.autoscaling_enabled ? 1 : 0
  name                = "psql-${var.prefix}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = var.db_sku
  storage_mb          = var.db_storage_mb
  auto_grow_enabled   = true # storage grows automatically (it can never shrink)
  version             = "16"

  public_network_access_enabled = var.public_access_enabled

  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password

  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = true
    tenant_id                     = data.azurerm_client_config.current.tenant_id
  }

  lifecycle {
    # sku_name: changed by the scaling runbook. storage_mb: grown by auto-grow.
    # tags: the runbook records its last action and cooldown time there.
    ignore_changes = [zone, sku_name, storage_mb, tags]

    precondition {
      condition     = var.public_access_enabled || var.private_endpoint_enabled
      error_message = "Public access can only be disabled when private_endpoint_enabled is true, otherwise nothing could reach the server."
    }
  }
}

moved {
  from = azurerm_postgresql_flexible_server.db
  to   = azurerm_postgresql_flexible_server.db[0]
}

locals {
  server = one(concat(azurerm_postgresql_flexible_server.db, azurerm_postgresql_flexible_server.db_scaled))
}

# -----------------------------------------------------------------------------
# Private endpoint: gives the server a private IP inside the VNet.
# The privatelink zone is linked to the VNet, so the normal server name
# (psql-<prefix>-<env>.postgres.database.azure.com) resolves to that private IP
# for the Container Apps and anything else inside the VNet.
# -----------------------------------------------------------------------------
resource "azurerm_private_dns_zone" "postgres" {
  count               = var.private_endpoint_enabled ? 1 : 0
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  count                 = var.private_endpoint_enabled ? 1 : 0
  name                  = "psql-vnet-link-${var.environment}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.postgres[0].name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
}

resource "azurerm_private_endpoint" "postgres" {
  count               = var.private_endpoint_enabled ? 1 : 0
  name                = "pe-psql-${var.prefix}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-psql-${var.environment}"
    private_connection_resource_id = local.server.id
    subresource_names              = ["postgresqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "psql-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.postgres[0].id]
  }
}

# Firewall rule for the office Wi-Fi public IP. It only applies while public access is on
# (Azure stops enforcing firewall rules once public access is disabled).
resource "azurerm_postgresql_flexible_server_firewall_rule" "office_wifi" {
  count            = var.public_access_enabled ? 1 : 0
  name             = "allow-office-wifi"
  server_id        = local.server.id
  start_ip_address = var.office_ip
  end_ip_address   = var.office_ip
}

moved {
  from = azurerm_postgresql_flexible_server_firewall_rule.office_wifi
  to   = azurerm_postgresql_flexible_server_firewall_rule.office_wifi[0]
}

# ---------------------------------------------------------
# SECRETS: Key Vault Synchronization
# ---------------------------------------------------------

resource "azurerm_key_vault_secret" "db_host" {
  name         = "DB-HOST"
  value        = local.server.fqdn
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "db_connection_string" {
  name         = "DB-CONNECTION-STRING"
  value        = "postgresql://${var.administrator_login}:${urlencode(var.administrator_password)}@${local.server.fqdn}:5432/postgres?sslmode=require"
  key_vault_id = var.key_vault_id
}
