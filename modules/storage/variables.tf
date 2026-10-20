variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "environment" { type = string }
variable "prefix" { type = string }
variable "vnet_id" { type = string }
variable "private_endpoint_subnet_id" { type = string }

variable "backend_identity_principal_id" {
  type        = string
  description = "The Principal GUID of the backend managed identity"
}

# REQUIRED: Accepts the Key Vault ID from the root main.tf
variable "key_vault_id" {
  type        = string
  description = "The ID of the Key Vault where secrets will be stored"
}
