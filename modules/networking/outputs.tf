output "vnet_id" {
  value       = azurerm_virtual_network.vnet.id
  description = "The ID of the Virtual Network"
}

output "frontend_subnet_id" {
  value       = azurerm_subnet.frontend.id
  description = "The ID of the Frontend Subnet"
}

output "backend_subnet_id" {
  value       = azurerm_subnet.backend.id
  description = "The ID of the Backend Subnet (Container Apps environment)"
}

output "private_endpoint_subnet_id" {
  value       = azurerm_subnet.private_endpoints.id
  description = "The ID of the Private Endpoint Subnet"
}
