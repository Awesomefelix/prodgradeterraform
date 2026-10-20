variable "environment" {
  type        = string
  description = "The deployment environment (e.g., dev, staging, prod)."
  default     = "prod"
}

variable "prefix" {
  type        = string
  description = "Project prefix for resource naming."
  default     = "proactive"
}

variable "location" {
  type        = string
  description = "Azure region to deploy resources"
  default     = "northeurope"
}

variable "vnet_address_space" {
  type        = list(string)
  description = "Address space for the Virtual Network."
  default     = ["10.0.0.0/16"]
}

variable "webapp_sku" {
  type        = string
  description = "App Service Plan SKU for frontend"
  default     = "B1"
}

variable "db_sku" {
  type        = string
  description = "PostgreSQL Flexible Server SKU"
  default     = "B_Standard_B1ms"
}

variable "redis_sku" {
  type        = string
  description = "Redis Cache SKU family and size"
  default     = "Balanced_B0"
}

variable "redis_capacity" {
  type        = number
  description = "Redis Cache capacity rating"
  default     = 0
}

# -----------------------------------------------------------------------------
# Dynamic Developer / App Secrets
# -----------------------------------------------------------------------------
variable "app_secrets" {
  type        = map(string)
  description = "Dynamic key-value pairs for application secrets synced directly to Azure Key Vault"
  default     = {}
  sensitive   = true
}

variable "app_secrets_kv_uris" {
  type        = map(string)
  description = "Extra Key Vault secret URIs to expose to the backend (merged with the auto-generated ones)"
  default     = {}
}

# -----------------------------------------------------------------------------
# Database Public Access & Admin Credentials
# -----------------------------------------------------------------------------
variable "administrator_password" {
  type        = string
  description = "Database administrator password. If omitted, a random strong password is generated."
  sensitive   = true
  default     = null
}

variable "office_ip" {
  type        = string
  description = "Office Wi-Fi public IP for the database firewall rule (only used while db_public_access_enabled is true)"
  default     = "135.129.124.220"
}

# -----------------------------------------------------------------------------
# Container apps and private container registry
# -----------------------------------------------------------------------------
variable "container_apps" {
  type = map(object({
    ingress_enabled          = optional(bool, false)
    external_ingress         = optional(bool, true)
    target_port              = optional(number, 3000)
    image                    = optional(string, "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest")
    cpu                      = optional(number, 0.5)
    memory                   = optional(string, "1Gi")
    min_replicas             = optional(number, 1)
    max_replicas             = optional(number, 3)
    http_concurrent_requests = optional(number, 50)
  }))
  description = "Container apps to deploy, keyed by name. All pull from the same registry"
  default = {
    "api-container"    = { ingress_enabled = true }
    "worker-container" = {}
  }
}

variable "acr_private_link_enabled" {
  type        = bool
  description = "Use a Premium registry and pull images over a private endpoint"
  default     = false
}

variable "acr_allowed_ip_ranges" {
  type        = list(string)
  description = "CIDR ranges allowed to push to the registry's public endpoint when private link is on (empty = public access fully disabled)"
  default     = []
}

# -----------------------------------------------------------------------------
# Database sizing and event-driven scaling
# -----------------------------------------------------------------------------
variable "db_storage_mb" {
  type        = number
  description = "Initial database storage in MB (32768 = 32 GB). Auto-grow takes over when db_scaling is enabled"
  default     = 32768
}

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
  description = "Database auto-grow plus alert-driven SKU scaling. sku_ladder is ordered smallest to largest and must contain db_sku"
  default     = {}
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
  description = "App Service instance autoscale plus alert-driven tier scaling. sku_ladder must contain webapp_sku; leave it empty for instance autoscale only"
  default     = {}
}

# -----------------------------------------------------------------------------
# Database network access
# -----------------------------------------------------------------------------
variable "db_private_endpoint_enabled" {
  type        = bool
  description = "Create a private endpoint (plus private DNS) so VNet workloads such as the container apps reach the database over a private IP"
  default     = false
}

variable "db_public_access_enabled" {
  type        = bool
  description = "Keep the database's public endpoint on. Set to false once everything connects privately (requires db_private_endpoint_enabled)"
  default     = true
}

# -----------------------------------------------------------------------------
# Azure OpenAI deployments
# -----------------------------------------------------------------------------
variable "ai_deployments" {
  type = map(object({
    model_name    = string
    model_version = string
    sku           = optional(string, "GlobalStandard")
    capacity      = optional(number, 10)
  }))
  description = "Model deployments on the OpenAI account, keyed by deployment name. Each gets an AI-DEPLOYMENT-<NAME> secret. Verify each model and version is available to your subscription in East US before applying"
  default = {
    "gpt-5" = {
      model_name    = "gpt-5"
      model_version = "2025-08-07"
    }
    "gpt-4o" = {
      model_name    = "gpt-4o"
      model_version = "2024-11-20"
    }
  }
}
