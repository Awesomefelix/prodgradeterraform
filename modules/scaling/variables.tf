variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "environment" { type = string }
variable "prefix" { type = string }

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------
variable "postgres_server_id" {
  type        = string
  description = "Resource ID of the PostgreSQL Flexible Server to scale (empty when database scaling is off)"
  default     = ""
}

variable "db_sku" {
  type        = string
  description = "Initial database SKU. Must be on the ladder when database scaling is enabled"
  default     = ""
}

variable "service_plan_id" {
  type        = string
  description = "Resource ID of the App Service plan to scale (empty when web scaling is off)"
  default     = ""
}

variable "service_plan_sku" {
  type        = string
  description = "Initial App Service plan SKU"
  default     = ""
}

# ---------------------------------------------------------------------------
# Behaviour
# ---------------------------------------------------------------------------
variable "db_scaling" {
  type = object({
    enabled                = optional(bool, false)
    sku_ladder             = optional(list(string), [])
    scale_up_cpu_percent   = optional(number, 80)
    scale_down_cpu_percent = optional(number, 20)
    cpu_credits_low        = optional(number, 50)
    cooldown_up_minutes    = optional(number, 30)
    cooldown_down_minutes  = optional(number, 360)
  })
  default = {}
}

variable "webapp_scaling" {
  type = object({
    enabled                = optional(bool, false)
    sku_ladder             = optional(list(string), [])
    autoscale_enabled      = optional(bool, true)
    min_instances          = optional(number, 2)
    max_instances          = optional(number, 6)
    scale_out_cpu_percent  = optional(number, 70)
    scale_in_cpu_percent   = optional(number, 30)
    scale_up_cpu_percent   = optional(number, 85)
    scale_down_cpu_percent = optional(number, 20)
    cooldown_up_minutes    = optional(number, 60)
    cooldown_down_minutes  = optional(number, 720)
  })
  default = {}
}

variable "webhook_expiry_time" {
  type        = string
  description = "Expiry of the Automation webhooks (RFC 3339). Azure allows at most 10 years. Rotate before this date"
  default     = "2036-10-01T00:00:00Z"
}
