# Two variants of the same plan, chosen by var.sku_managed_externally:
#   plan         - SKU fully controlled by Terraform.
#   plan_scaled  - the SKU is changed at runtime by the scaling runbook, so Terraform
#                  ignores sku_name. (Instance count is handled by Azure autoscale.)
#
# Switching an EXISTING plan between the two needs a state move first:
#   terraform state mv 'module.frontend.azurerm_service_plan.plan[0]' \
#                      'module.frontend.azurerm_service_plan.plan_scaled[0]'
resource "azurerm_service_plan" "plan" {
  count               = var.sku_managed_externally ? 0 : 1
  name                = "asp-${var.prefix}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = var.webapp_sku
}

resource "azurerm_service_plan" "plan_scaled" {
  count               = var.sku_managed_externally ? 1 : 0
  name                = "asp-${var.prefix}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = var.webapp_sku

  lifecycle {
    # sku_name: changed by the scaling runbook. tags: it records its cooldown there.
    ignore_changes = [sku_name, tags]
  }
}

moved {
  from = azurerm_service_plan.plan
  to   = azurerm_service_plan.plan[0]
}

locals {
  plan = one(concat(azurerm_service_plan.plan, azurerm_service_plan.plan_scaled))
}

resource "azurerm_linux_web_app" "web" {
  name                = "app-${var.prefix}-frontend-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = local.plan.id

  # Connect Web App to the VNet so it can securely reach the Container App backend
  virtual_network_subnet_id = var.frontend_subnet_id

  identity {
    type         = "UserAssigned"
    identity_ids = [var.frontend_identity_id]
  }

  site_config {
    # Free/Shared tiers cannot use Always On; every other tier should.
    always_on = !contains(["F1", "D1"], var.webapp_sku)
    application_stack {
      node_version = "20-lts"
    }
  }
}
