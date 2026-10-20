variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "environment" { type = string }
variable "prefix" { type = string }

variable "redis_sku" {
  type        = string
  default     = "Balanced_B0"
  description = "Managed Redis SKU name"
}

variable "redis_capacity" {
  type        = number
  default     = 0
  description = "Legacy variable placeholder for module compatibility"
}

variable "key_vault_id" {
  type        = string
  description = "The ID of the Key Vault where Redis secrets will be stored"
}
