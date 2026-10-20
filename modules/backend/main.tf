locals {
  acr_private = var.acr_private_link_enabled
  acr_public  = !local.acr_private || length(var.acr_allowed_ip_ranges) > 0
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-${var.prefix}-backend-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "env" {
  name                           = "cae-${var.prefix}-${var.environment}"
  location                       = var.location
  resource_group_name            = var.resource_group_name
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.law.id
  infrastructure_subnet_id       = var.backend_subnet_id
  internal_load_balancer_enabled = false # Enabled public ingress
}

# -----------------------------------------------------------------------------
# Azure Container Registry shared by every container app.
# Private endpoints require the Premium tier, so Premium is used only when
# acr_private_link_enabled is true; otherwise it stays Basic.
# -----------------------------------------------------------------------------
resource "azurerm_container_registry" "acr" {
  name                          = "cr${replace(var.prefix, "-", "")}${var.environment}" # Must be alphanumeric
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = local.acr_private ? "Premium" : "Basic"
  admin_enabled                 = !local.acr_private # identity-based pulls only when private
  public_network_access_enabled = local.acr_public
}

resource "azurerm_private_dns_zone" "acr" {
  count               = local.acr_private ? 1 : 0
  name                = "privatelink.azurecr.io"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  count                 = local.acr_private ? 1 : 0
  name                  = "acr-vnet-link-${var.environment}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.acr[0].name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
}

resource "azurerm_private_endpoint" "acr" {
  count               = local.acr_private ? 1 : 0
  name                = "pe-acr-${var.prefix}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-acr-${var.environment}"
    private_connection_resource_id = azurerm_container_registry.acr.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "acr-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr[0].id]
  }
}

# Grant the backend managed identity permission to pull from ACR.
# NOTE: principal_id MUST receive the Principal ID (GUID), NOT the Resource ID.
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = var.backend_identity_principal_id
}

# -----------------------------------------------------------------------------
# Container apps: api-container (public ingress) and worker-container (no ingress).
# All apps share the identity, the registry and the Key Vault-backed secrets.
# -----------------------------------------------------------------------------
resource "azurerm_container_app" "apps" {
  for_each                     = var.container_apps
  name                         = each.key
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [var.backend_identity_id]
  }

  # Pull from the (private) registry with the managed identity
  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = var.backend_identity_id
  }

  # Map the secrets to Key Vault URIs using the managed identity
  dynamic "secret" {
    for_each = var.app_secrets_kv_uris
    content {
      name                = lower(secret.key)
      key_vault_secret_id = secret.value
      identity            = var.backend_identity_id
    }
  }

  template {
    min_replicas = each.value.min_replicas
    max_replicas = each.value.max_replicas

    container {
      name   = each.key
      image  = each.value.image
      cpu    = each.value.cpu
      memory = each.value.memory

      # Expose every secret as an environment variable
      dynamic "env" {
        for_each = var.app_secrets_kv_uris
        content {
          name        = env.key
          secret_name = lower(env.key)
        }
      }
    }

    # Scale replicas on request volume (only apps that receive traffic)
    dynamic "http_scale_rule" {
      for_each = each.value.ingress_enabled ? [1] : []
      content {
        name                = "http-concurrency"
        concurrent_requests = tostring(each.value.http_concurrent_requests)
      }
    }
  }

  dynamic "ingress" {
    for_each = each.value.ingress_enabled ? [1] : []
    content {
      allow_insecure_connections = false
      external_enabled           = each.value.external_ingress
      target_port                = each.value.target_port

      traffic_weight {
        percentage      = 100
        latest_revision = true
      }
    }
  }

  # CI/CD deploys new image tags; Terraform must not roll them back
  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [
    azurerm_role_assignment.acr_pull,
    azurerm_private_endpoint.acr,
    azurerm_private_dns_zone_virtual_network_link.acr,
  ]
}
