# =============================================================================
# Module storage : héberge les scripts PowerShell (Custom Script Extension)
# =============================================================================

resource "random_string" "sa_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_account" "scripts" {
  name                     = substr("st${var.project_name}${random_string.sa_suffix.result}", 0, 24)
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  # Accès public désactivé : les VM téléchargent les scripts via la clé de
  # compte de stockage transmise dans les "protected_settings" de la Custom
  # Script Extension (jamais exposée dans le portail ni les logs Terraform).
  allow_nested_items_to_be_public = false
  tags                             = var.tags
}

resource "azurerm_storage_container" "scripts" {
  name                  = "scripts"
  storage_account_name = azurerm_storage_account.scripts.name
  container_access_type = "private"
}

# Upload automatique de tous les scripts du dossier ./scripts
resource "azurerm_storage_blob" "scripts" {
  for_each               = fileset(var.scripts_dir, "**")
  name                   = each.value
  storage_account_name  = azurerm_storage_account.scripts.name
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "Block"
  source                 = "${var.scripts_dir}/${each.value}"
  content_md5            = filemd5("${var.scripts_dir}/${each.value}")
}

# La clé du compte de stockage est utilisée par l'agent Azure VM Agent
# (Custom Script Extension) pour s'authentifier et télécharger les blobs
# privés via "protected_settings" -> jamais exposée dans les logs ni le portail.
