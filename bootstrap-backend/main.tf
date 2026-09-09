# =============================================================================
# Bootstrap du backend Terraform distant (etat partage + verrouillage)
#
# A executer UNE SEULE FOIS, avant terraform init du projet principal.
# Cette configuration utilise volontairement un etat LOCAL (chicken-and-egg :
# on ne peut pas stocker l'etat qui decrit le stockage de l'etat lui-meme).
# Une fois applique, notez les valeurs de sortie et reportez-les dans
# ../backend.hcl pour initialiser le projet principal.
# =============================================================================

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "location" {
  type    = string
  default = "norwayeast"
}

variable "project_name" {
  type    = string
  default = "estiam"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-${var.project_name}-tfstate"
  location = var.location
  tags = {
    projet = "ESTIAM"
    usage  = "terraform-backend"
  }
}

resource "azurerm_storage_account" "tfstate" {
  name                     = substr("st${var.project_name}tfstate${random_string.suffix.result}", 0, 24)
  resource_group_name      = azurerm_resource_group.tfstate.name
  location                 = azurerm_resource_group.tfstate.location
  account_tier             = "Standard"
  account_replication_type = "ZRS" # zone-redondant : resiste a la perte d'une zone
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true # retrouver un etat precedent en cas d'erreur
  }

  tags = {
    projet = "ESTIAM"
    usage  = "terraform-backend"
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}

output "resource_group_name" {
  value = azurerm_resource_group.tfstate.name
}

output "storage_account_name" {
  value = azurerm_storage_account.tfstate.name
}

output "container_name" {
  value = azurerm_storage_container.tfstate.name
}

output "backend_hcl_content" {
  value = <<-EOT
    resource_group_name  = "${azurerm_resource_group.tfstate.name}"
    storage_account_name = "${azurerm_storage_account.tfstate.name}"
    container_name        = "${azurerm_storage_container.tfstate.name}"
    key                   = "estiam.tfstate"
  EOT
}
