# =============================================================================
# Module keyvault : centralise les secrets du projet (mot de passe admin,
# cle du compte de stockage) pour audit/rotation, plutot que de les laisser
# uniquement dans l'etat Terraform.
# =============================================================================

data "azurerm_client_config" "current" {}

resource "random_string" "kv_suffix" {
  length  = 4
  special = false
  upper   = false
}

resource "azurerm_key_vault" "this" {
  name                       = substr("kv-${var.project_name}-${random_string.kv_suffix.result}", 0, 24)
  location                   = var.location
  resource_group_name       = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = true
  soft_delete_retention_days = 90
  enable_rbac_authorization  = false
  tags                       = var.tags

  # Delais releves : la lecture des "certificate contacts" par le provider
  # (appel automatique fait par azurerm apres creation/refresh) a echoue avec
  # "context deadline exceeded" lors d'un apply charge (plusieurs VM + extensions
  # en parallele). Timeouts plus larges pour eviter un echec sur simple lenteur
  # reseau/API plutot qu'une vraie erreur de configuration.
  timeouts {
    create = "15m"
    read   = "15m"
    update = "15m"
    delete = "15m"
  }
}

# Acces complet pour l'identite qui execute Terraform (necessaire pour ecrire
# les secrets ci-dessous)
resource "azurerm_key_vault_access_policy" "terraform_operator" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
}

# Acces en lecture pour les operateurs humains designes (ex: equipe IT)
resource "azurerm_key_vault_access_policy" "authorized_readers" {
  for_each     = toset(var.authorized_object_ids)
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = each.value

  secret_permissions = ["Get", "List"]
}

resource "azurerm_key_vault_secret" "admin_password" {
  name         = "estiam-admin-password"
  value        = var.admin_password
  key_vault_id = azurerm_key_vault.this.id
  content_type = "Mot de passe administrateur local + domaine (genere par Terraform)"

  depends_on = [azurerm_key_vault_access_policy.terraform_operator]
}

resource "azurerm_key_vault_secret" "storage_account_key" {
  name         = "estiam-scripts-storage-key"
  value        = var.storage_account_key
  key_vault_id = azurerm_key_vault.this.id
  content_type = "Cle du compte de stockage hebergeant les scripts PowerShell"

  depends_on = [azurerm_key_vault_access_policy.terraform_operator]
}
