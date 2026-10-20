variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "environment" { type = string }
variable "prefix" { type = string }

variable "backend_identity_principal_id" {
  type        = string
  description = "The Principal GUID of the backend managed identity"
}

# REQUIRED: Accepts the Key Vault ID from the root main.tf
variable "key_vault_id" {
  type        = string
  description = "The ID of the Key Vault where secrets will be stored"
}

# ---------------------------------------------------------
# Model deployments (any number, all on the same account)
# ---------------------------------------------------------
variable "deployments" {
  type = map(object({
    model_name    = string
    model_version = string
    sku           = optional(string, "GlobalStandard")
    capacity      = optional(number, 10)
  }))
  description = "Deployments to create, keyed by deployment name (the name applications call)"
}
