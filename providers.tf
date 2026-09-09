provider "azurerm" {
  features {
    virtual_machine {
      delete_os_disk_on_deletion = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  # Authentification : utiliser un Service Principal (recommandé en CI/CD)
  # via les variables d'environnement standard :
  #   ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_SUBSCRIPTION_ID, ARM_TENANT_ID
  # ou `az login` en local.
}
