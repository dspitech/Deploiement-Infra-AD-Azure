output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "location" {
  value = azurerm_resource_group.this.location
}

output "vnet_id" {
  value = azurerm_virtual_network.this.id
}

output "vnet_name" {
  value = azurerm_virtual_network.this.name
}

output "main_subnet_id" {
  value = azurerm_subnet.main.id
}

output "bastion_subnet_id" {
  value = var.enable_bastion ? azurerm_subnet.bastion[0].id : null
}
