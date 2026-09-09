output "storage_account_name" {
  value = azurerm_storage_account.scripts.name
}

output "storage_account_id" {
  value = azurerm_storage_account.scripts.id
}

output "container_name" {
  value = azurerm_storage_container.scripts.name
}

output "primary_access_key" {
  value     = azurerm_storage_account.scripts.primary_access_key
  sensitive = true
}

output "blob_base_url" {
  value = "${azurerm_storage_account.scripts.primary_blob_endpoint}${azurerm_storage_container.scripts.name}"
}
