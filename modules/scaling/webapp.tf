# -----------------------------------------------------------------------------
# App Service: two independent mechanisms.
#   1. Autoscale     - native, changes the INSTANCE COUNT (scale out / in).
#   2. Tier scaling  - alert + runbook, changes the plan SKU (scale up / down).
# Autoscale reacts first (lower thresholds); tier scaling only fires on sustained load
# that more instances did not fix.
# -----------------------------------------------------------------------------

locals {
  enable_web_autoscale = var.webapp_scaling.enabled && var.webapp_scaling.autoscale_enabled
}

resource "azurerm_monitor_autoscale_setting" "web" {
  count               = local.enable_web_autoscale ? 1 : 0
  name                = "autoscale-${var.prefix}-web-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = var.service_plan_id

  lifecycle {
    precondition {
      condition     = can(regex("^(S|P)", var.service_plan_sku))
      error_message = "App Service autoscale needs a Standard (S) or Premium (P) plan. Basic and Free cannot autoscale."
    }
  }

  profile {
    name = "cpu-and-memory"

    capacity {
      default = var.webapp_scaling.min_instances
      minimum = var.webapp_scaling.min_instances
      maximum = var.webapp_scaling.max_instances
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = var.service_plan_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.webapp_scaling.scale_out_cpu_percent
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = var.service_plan_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 80
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = var.service_plan_id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT15M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.webapp_scaling.scale_in_cpu_percent
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
}

resource "azurerm_monitor_metric_alert" "web_cpu_high" {
  count               = local.enable_web_tier ? 1 : 0
  name                = "alert-web-cpu-high-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [var.service_plan_id]
  description         = "Sustained high CPU even after scale-out: step the plan up one tier"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT30M"

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.webapp_scaling.scale_up_cpu_percent
  }

  action {
    action_group_id = azurerm_monitor_action_group.scale["web-up"].id
  }
}

resource "azurerm_monitor_metric_alert" "web_memory_high" {
  count               = local.enable_web_tier ? 1 : 0
  name                = "alert-web-memory-high-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [var.service_plan_id]
  description         = "Sustained high memory: step the plan up one tier"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT30M"

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "MemoryPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 90
  }

  action {
    action_group_id = azurerm_monitor_action_group.scale["web-up"].id
  }
}

resource "azurerm_monitor_metric_alert" "web_cpu_low" {
  count               = local.enable_web_tier ? 1 : 0
  name                = "alert-web-cpu-low-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [var.service_plan_id]
  description         = "Sustained low CPU: step the plan down one tier"
  severity            = 3
  frequency           = "PT1H"
  window_size         = "PT12H"

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.webapp_scaling.scale_down_cpu_percent
  }

  action {
    action_group_id = azurerm_monitor_action_group.scale["web-down"].id
  }
}
