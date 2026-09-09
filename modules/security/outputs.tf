output "nsg_id" {
  value = azurerm_network_security_group.main.id
}

output "bastion_host_id" {
  value = var.enable_bastion ? azurerm_bastion_host.this[0].id : null
}
