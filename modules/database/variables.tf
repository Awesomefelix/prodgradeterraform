variable "resource_group_name" {
  type        = string
  description = "The name of the resource group"
}

variable "location" {
  type        = string
  description = "The Azure region where resources will be deployed"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g. dev, staging, prod)"
}

variable "prefix" {
  type        = string
  description = "Prefix for all resource names"
}

variable "vnet_id" {
  type        = string
  description = "The ID of the Virtual Network (the private DNS zone is linked to it)"
}

variable "private_endpoint_subnet_id" {
  type        = string
  description = "Subnet that hosts the database private endpoint"
}

variable "db_sku" {
  type        = string
  description = "SKU for the PostgreSQL Flexible Server"
}

# REQUIRED: Accepts the Key Vault ID from the root main.tf
variable "key_vault_id" {
  type        = string
  description = "The ID of the Key Vault where secrets will be stored"
}

# ---------------------------------------------------------
# Credentials
# ---------------------------------------------------------

variable "administrator_login" {
  type        = string
  description = "Database administrator username for password authentication"
  default     = "psqladmin"
}

variable "administrator_password" {
  type        = string
  description = "Database administrator password"
  sensitive   = true
}

# ---------------------------------------------------------
# Network access
# ---------------------------------------------------------

variable "private_endpoint_enabled" {
  type        = bool
  description = "Create a private endpoint (and private DNS) so VNet workloads reach the server over a private IP"
  default     = false
}

variable "public_access_enabled" {
  type        = bool
  description = "Keep the server's public endpoint on. Set false once everything connects privately (requires private_endpoint_enabled)"
  default     = true
}

variable "office_ip" {
  type        = string
  description = "Developer public IP address for office/home Wi-Fi firewall access (only used while public access is on)"
  default     = "135.129.124.220"
}

# ---------------------------------------------------------
# Sizing
# ---------------------------------------------------------

variable "db_storage_mb" {
  type        = number
  description = "Initial storage in MB (32768 = 32 GB). With auto-grow this is only the starting size"
  default     = 32768
}

variable "autoscaling_enabled" {
  type        = bool
  description = "Enable storage auto-grow and let the scaling runbook change the SKU (Terraform then ignores sku_name and storage_mb)"
  default     = false
}
