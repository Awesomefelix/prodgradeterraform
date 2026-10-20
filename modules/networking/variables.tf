variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
}

variable "prefix" {
  type        = string
  description = "Naming prefix"
}

variable "vnet_address_space" {
  type        = list(string)
  description = "CIDR block for the VNet (use a /16)"
}
