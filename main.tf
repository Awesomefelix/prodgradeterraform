resource "random_password" "database_admin" {
  count            = var.administrator_password == null ? 1 : 0
  length           = 24
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!@#$%^&*()-_=+[]{}"
}

locals {
  resolved_prefix             = var.prefix
  resolved_environment        = var.environment
  resolved_vnet_address_space = var.vnet_address_space
  resolved_admin_password     = var.administrator_password != null ? var.administrator_password : random_password.database_admin[0].result
  rg_name                     = "rg-${local.resolved_prefix}-${local.resolved_environment}"

  # Key Vault secret URIs written by the database, ai, redis and storage modules.
  # They are pointers only (not secret values).
  kv_secret_uris = {
    for n in concat(
      [
        "DB-HOST",
        "DB-CONNECTION-STRING",
        "AI-ENDPOINT",
        "REDIS-HOST",
        "REDIS-PORT",
        "REDIS-PRIMARY-KEY",
        "STORAGE-CONNECTION-STRING",
      ],
      module.ai.deployment_secret_names, # AI-DEPLOYMENT-<NAME>, one per deployment
    ) : n => "${module.security.key_vault_uri}secrets/${n}"
  }
}

resource "azurerm_resource_group" "main" {
  name     = local.rg_name
  location = var.location
}

# 1. Networking Module
module "networking" {
  source              = "./modules/networking"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  environment         = local.resolved_environment
  prefix              = local.resolved_prefix
  vnet_address_space  = local.resolved_vnet_address_space
}

# 2. Security & Managed Identity Module (Creates Key Vault)
module "security" {
  source              = "./modules/security"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  environment         = local.resolved_environment
  prefix              = local.resolved_prefix
}

# 3. Secure Blob Storage Module
module "storage" {
  source                        = "./modules/storage"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  environment                   = local.resolved_environment
  prefix                        = local.resolved_prefix
  vnet_id                       = module.networking.vnet_id
  private_endpoint_subnet_id    = module.networking.private_endpoint_subnet_id
  backend_identity_principal_id = module.security.backend_identity_principal_id
  key_vault_id                  = module.security.key_vault_id
}

# 4. PostgreSQL Database Module (private endpoint for VNet workloads; public access switchable)
module "database" {
  source              = "./modules/database"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  environment         = local.resolved_environment
  prefix              = local.resolved_prefix
  vnet_id             = module.networking.vnet_id
  db_sku              = var.db_sku
  key_vault_id        = module.security.key_vault_id

  # Credentials and office firewall rule (the rule only applies while public access is on)
  administrator_password = local.resolved_admin_password
  office_ip              = var.office_ip

  # Private connectivity: Container Apps reach the database through this private endpoint
  private_endpoint_subnet_id = module.networking.private_endpoint_subnet_id
  private_endpoint_enabled   = var.db_private_endpoint_enabled
  public_access_enabled      = var.db_public_access_enabled

  # Storage auto-grow + runtime SKU scaling (see module "scaling")
  db_storage_mb       = var.db_storage_mb
  autoscaling_enabled = var.db_scaling.enabled
}

# 5. Azure OpenAI Module (one deployment per entry in var.ai_deployments)
module "ai" {
  source                        = "./modules/ai"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  environment                   = local.resolved_environment
  prefix                        = local.resolved_prefix
  backend_identity_principal_id = module.security.backend_identity_principal_id
  key_vault_id                  = module.security.key_vault_id

  # Model deployments (for example gpt-5 and gpt-4o side by side)
  deployments = var.ai_deployments
}

# 6. Container Apps Backend Module
module "backend" {
  source                        = "./modules/backend"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  environment                   = local.resolved_environment
  prefix                        = local.resolved_prefix
  backend_subnet_id             = module.networking.backend_subnet_id
  backend_identity_id           = module.security.backend_identity_id
  backend_identity_principal_id = module.security.backend_identity_principal_id

  # Private registry access
  vnet_id                    = module.networking.vnet_id
  private_endpoint_subnet_id = module.networking.private_endpoint_subnet_id
  acr_private_link_enabled   = var.acr_private_link_enabled
  acr_allowed_ip_ranges      = var.acr_allowed_ip_ranges

  # api-container, worker-container, ...
  container_apps = var.container_apps

  # Inject the Key Vault ID from the security module output
  key_vault_id = module.security.key_vault_id

  # Auto-generated URIs plus any extras from tfvars (e.g. secrets from var.app_secrets)
  app_secrets_kv_uris = merge(local.kv_secret_uris, var.app_secrets_kv_uris)

  # The Container App resolves these secrets at creation, so they must exist first
  depends_on = [
    module.database,
    module.ai,
    module.redis,
    module.storage,
    azurerm_key_vault_secret.app_secrets,
  ]
}

# 7. App Service Frontend Module
module "frontend" {
  source               = "./modules/frontend"
  resource_group_name  = azurerm_resource_group.main.name
  location             = azurerm_resource_group.main.location
  environment          = local.resolved_environment
  prefix               = local.resolved_prefix
  frontend_subnet_id   = module.networking.frontend_subnet_id
  frontend_identity_id = module.security.frontend_identity_id
  webapp_sku           = var.webapp_sku

  # The runbook changes the plan tier at runtime, so Terraform must not revert it
  sku_managed_externally = var.webapp_scaling.enabled && length(var.webapp_scaling.sku_ladder) > 0
}

# 8. Redis Cache Module
module "redis" {
  source              = "./modules/redis"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  environment         = local.resolved_environment
  prefix              = local.resolved_prefix
  redis_sku           = var.redis_sku
  redis_capacity      = var.redis_capacity
  key_vault_id        = module.security.key_vault_id
}

# -----------------------------------------------------------------------------
# DYNAMIC DEVELOPER SECRETS ENGINE
# Loops over key-value pairs defined in var.app_secrets and writes to Key Vault
# -----------------------------------------------------------------------------
resource "azurerm_key_vault_secret" "app_secrets" {
  for_each     = nonsensitive(var.app_secrets)
  name         = each.key
  value        = each.value
  key_vault_id = module.security.key_vault_id
}

# -----------------------------------------------------------------------------
# 9. Event-driven scaling (database tier + App Service tier / instances)
# Everything inside is a no-op unless db_scaling / webapp_scaling are enabled.
# -----------------------------------------------------------------------------
module "scaling" {
  source              = "./modules/scaling"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  environment         = local.resolved_environment
  prefix              = local.resolved_prefix

  postgres_server_id = module.database.server_id
  db_sku             = var.db_sku
  db_scaling         = var.db_scaling

  service_plan_id  = module.frontend.service_plan_id
  service_plan_sku = var.webapp_sku
  webapp_scaling   = var.webapp_scaling
}
