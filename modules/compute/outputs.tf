output "server_vm_id" {
  value = azurerm_windows_virtual_machine.server.id
}

output "client_vm_id" {
  value = azurerm_windows_virtual_machine.client.id
}

output "server_private_ip" {
  value = azurerm_network_interface.server.private_ip_address
}

output "client_private_ip" {
  value = azurerm_network_interface.client.private_ip_address
}

output "dc02_private_ip" {
  value = var.enable_second_dc ? azurerm_network_interface.dc02[0].private_ip_address : null
}
