variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "environment" { type = string }
variable "prefix" { type = string }
variable "frontend_subnet_id" { type = string }
variable "frontend_identity_id" { type = string }
variable "webapp_sku" { type = string }

variable "sku_managed_externally" {
  type        = bool
  description = "True when the scaling runbook changes the plan SKU at runtime (Terraform then ignores sku_name)"
  default     = false
}
