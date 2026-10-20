variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "environment" { type = string }
variable "prefix" { type = string }
variable "backend_subnet_id" { type = string }
variable "backend_identity_id" { type = string }

variable "backend_identity_principal_id" {
  type        = string
  description = "Principal ID (Object ID) of the backend user-assigned identity for role assignments"
}

variable "key_vault_id" {
  description = "The ID of the Key Vault to assign read access to the backend identity"
  type        = string
}

variable "app_secrets_kv_uris" {
  description = "Map of application secrets mapping to their Key Vault Secret URIs"
  type        = map(string)
}

# ---------------------------------------------------------------------------
# Private registry access
# ---------------------------------------------------------------------------
variable "vnet_id" {
  type        = string
  description = "VNet to link the private ACR DNS zone to"
}

variable "private_endpoint_subnet_id" {
  type        = string
  description = "Subnet that hosts the ACR private endpoint"
}

variable "acr_private_link_enabled" {
  type        = bool
  description = "Upgrade the registry to Premium and pull images over a private endpoint"
  default     = false
}

variable "acr_allowed_ip_ranges" {
  type        = list(string)
  description = "CIDR ranges allowed to reach the registry's public endpoint (to push images). Only used with private link; empty means public access is disabled"
  default     = []
}

# ---------------------------------------------------------------------------
# Container apps (all pull from the same registry)
# ---------------------------------------------------------------------------
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
  description = "Container apps to deploy, keyed by app name"
}
