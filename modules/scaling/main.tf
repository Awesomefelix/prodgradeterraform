# -----------------------------------------------------------------------------
# Event-driven SKU scaling.
#
#   Azure Monitor metric alert -> Action Group -> Automation webhook -> runbook
#   -> ARM call that moves the resource ONE step along a SKU ladder.
#
# Azure has no native "autoscale to a different tier" for PostgreSQL Flexible
# Server or for the App Service plan tier, so this module provides it.
# -----------------------------------------------------------------------------

locals {
  enable_db       = var.db_scaling.enabled
  enable_web_tier = var.webapp_scaling.enabled && length(var.webapp_scaling.sku_ladder) > 0
  enable_runbook  = local.enable_db || local.enable_web_tier

  # One entry per scaling action. Only enabled entries are created.
  all_actions = {
    "db-up" = {
      enabled     = local.enable_db
      target_type = "Postgres"
      direction   = "Up"
      resource_id = var.postgres_server_id
      ladder      = var.db_scaling.sku_ladder
      cooldown    = var.db_scaling.cooldown_up_minutes
    }
    "db-down" = {
      enabled     = local.enable_db
      target_type = "Postgres"
      direction   = "Down"
      resource_id = var.postgres_server_id
      ladder      = var.db_scaling.sku_ladder
      cooldown    = var.db_scaling.cooldown_down_minutes
    }
    "web-up" = {
      enabled     = local.enable_web_tier
      target_type = "AppServicePlan"
      direction   = "Up"
      resource_id = var.service_plan_id
      ladder      = var.webapp_scaling.sku_ladder
      cooldown    = var.webapp_scaling.cooldown_up_minutes
    }
    "web-down" = {
      enabled     = local.enable_web_tier
      target_type = "AppServicePlan"
      direction   = "Down"
      resource_id = var.service_plan_id
      ladder      = var.webapp_scaling.sku_ladder
      cooldown    = var.webapp_scaling.cooldown_down_minutes
    }
  }

  actions = { for k, v in local.all_actions : k => v if v.enabled }
}

# Fail early if the starting SKU is not on its ladder: the runbook would skip every scale.
resource "terraform_data" "validate" {
  lifecycle {
    precondition {
      condition     = !local.enable_db || contains(var.db_scaling.sku_ladder, var.db_sku)
      error_message = "db_sku must be one of db_scaling.sku_ladder."
    }
    precondition {
      condition     = !local.enable_web_tier || contains(var.webapp_scaling.sku_ladder, var.service_plan_sku)
      error_message = "webapp_sku must be one of webapp_scaling.sku_ladder."
    }
    precondition {
      condition     = !local.enable_db || length(var.db_scaling.sku_ladder) >= 2
      error_message = "db_scaling.sku_ladder needs at least two entries."
    }
  }
}

resource "azurerm_automation_account" "scaling" {
  count               = local.enable_runbook ? 1 : 0
  name                = "aa-${var.prefix}-scaling-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Basic"

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_automation_runbook" "scale_sku" {
  count                   = local.enable_runbook ? 1 : 0
  name                    = "Scale-Sku"
  location                = var.location
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.scaling[0].name
  runbook_type            = "PowerShell"
  log_verbose             = true
  log_progress            = true
  description             = "Moves a PostgreSQL server or App Service plan one step along a SKU ladder"
  content                 = file("${path.module}/scripts/Scale-Sku.ps1")
}

resource "azurerm_automation_webhook" "scale" {
  for_each                = local.actions
  name                    = "wh-${each.key}"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.scaling[0].name
  runbook_name            = azurerm_automation_runbook.scale_sku[0].name
  expiry_time             = var.webhook_expiry_time
  enabled                 = true

  parameters = {
    TargetType      = each.value.target_type
    Direction       = each.value.direction
    ResourceId      = each.value.resource_id
    SkuLadderJson   = jsonencode(each.value.ladder)
    CooldownMinutes = tostring(each.value.cooldown)
  }
}

resource "azurerm_monitor_action_group" "scale" {
  for_each            = local.actions
  name                = "ag-${each.key}-${var.environment}"
  resource_group_name = var.resource_group_name
  short_name          = substr(replace("sc${each.key}", "-", ""), 0, 12)

  automation_runbook_receiver {
    name                    = "scale"
    automation_account_id   = azurerm_automation_account.scaling[0].id
    runbook_name            = azurerm_automation_runbook.scale_sku[0].name
    webhook_resource_id     = azurerm_automation_webhook.scale[each.key].id
    is_global_runbook       = false
    service_uri             = azurerm_automation_webhook.scale[each.key].uri
    use_common_alert_schema = true
  }
}

# The runbook's identity may only touch the two resources it scales.
resource "azurerm_role_assignment" "scaler_db" {
  count                = local.enable_db ? 1 : 0
  scope                = var.postgres_server_id
  role_definition_name = "Contributor"
  principal_id         = azurerm_automation_account.scaling[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "scaler_web" {
  count                = local.enable_web_tier ? 1 : 0
  scope                = var.service_plan_id
  role_definition_name = "Contributor"
  principal_id         = azurerm_automation_account.scaling[0].identity[0].principal_id
}
