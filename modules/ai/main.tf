resource "azurerm_cognitive_account" "openai" {
  name                          = "cog-${var.prefix}-ai-${var.environment}"
  location                      = "eastus" # Hardcoded to East US for model availability
  resource_group_name           = var.resource_group_name
  kind                          = "OpenAI"
  sku_name                      = "S0"
  local_auth_enabled            = false
  public_network_access_enabled = true
}

# One deployment per entry in var.deployments (for example gpt-5 and gpt-4o side by side).
# Each model has its own quota, so capacity is requested per deployment.
resource "azurerm_cognitive_deployment" "models" {
  for_each             = var.deployments
  name                 = each.key
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = each.value.model_name
    version = each.value.model_version
  }

  sku {
    name     = each.value.sku
    capacity = each.value.capacity
  }
}

# Keeps an existing single "gpt-5" deployment instead of replacing it
moved {
  from = azurerm_cognitive_deployment.gpt
  to   = azurerm_cognitive_deployment.models["gpt-5"]
}

resource "azurerm_role_assignment" "backend_ai" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = var.backend_identity_principal_id
}

# ---------------------------------------------------------
# SECRETS: Sync AI endpoint and deployment names to Key Vault
# ---------------------------------------------------------
resource "azurerm_key_vault_secret" "ai_endpoint" {
  name         = "AI-ENDPOINT"
  value        = azurerm_cognitive_account.openai.endpoint
  key_vault_id = var.key_vault_id
}

# One secret per deployment, e.g. deployment "gpt-4o" -> secret AI-DEPLOYMENT-GPT-4O.
# Applications read the name from the matching environment variable.
resource "azurerm_key_vault_secret" "ai_deployment" {
  for_each     = local.secret_names
  name         = each.value
  value        = azurerm_cognitive_deployment.models[each.key].name
  key_vault_id = var.key_vault_id
}
