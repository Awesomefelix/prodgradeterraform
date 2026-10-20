# -----------------------------------------------------------------------------
# PostgreSQL alerts. Storage is handled natively by auto-grow (database module).
# -----------------------------------------------------------------------------

resource "azurerm_monitor_metric_alert" "db_cpu_high" {
  count               = local.enable_db ? 1 : 0
  name                = "alert-db-cpu-high-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [var.postgres_server_id]
  description         = "Sustained high CPU: step the database up one SKU"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.db_scaling.scale_up_cpu_percent
  }

  action {
    action_group_id = azurerm_monitor_action_group.scale["db-up"].id
  }
}

# Burstable SKUs only. When the CPU credit bank runs low the server is throttled to its
# baseline, so move to a larger SKU (bigger credit bank, or General Purpose with no credits).
resource "azurerm_monitor_metric_alert" "db_credits_low" {
  count               = local.enable_db ? 1 : 0
  name                = "alert-db-cpu-credits-low-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [var.postgres_server_id]
  description         = "CPU credits nearly exhausted: step the database up one SKU"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "cpu_credits_remaining"
    aggregation      = "Minimum"
    operator         = "LessThan"
    threshold        = var.db_scaling.cpu_credits_low
  }

  action {
    action_group_id = azurerm_monitor_action_group.scale["db-up"].id
  }
}

resource "azurerm_monitor_metric_alert" "db_cpu_low" {
  count               = local.enable_db ? 1 : 0
  name                = "alert-db-cpu-low-${var.environment}"
  resource_group_name = var.resource_group_name
  scopes              = [var.postgres_server_id]
  description         = "Sustained low CPU: step the database down one SKU"
  severity            = 3
  frequency           = "PT1H"
  window_size         = "PT6H"

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = var.db_scaling.scale_down_cpu_percent
  }

  action {
    action_group_id = azurerm_monitor_action_group.scale["db-down"].id
  }
}
