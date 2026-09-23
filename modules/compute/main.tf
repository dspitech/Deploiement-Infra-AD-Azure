# =============================================================================
# Module compute : SRV-AD01 (futur contrôleur de domaine), PC-CLIENT01 (poste
# client) et, en option, DC02.
#
# Terraform ne fait QUE créer les machines et leurs ressources Azure (NIC,
# disques, identités managées). L'installation et la configuration de Windows
# (AD DS, DNS, DHCP, GPO...) se font ensuite À LA MAIN avec les scripts du
# dossier scripts/ (un dossier par service).
# =============================================================================

# -----------------------------------------------------------------------------
# Acceptation des termes Marketplace pour l'image du poste client (une fois)
# -----------------------------------------------------------------------------
resource "azurerm_marketplace_agreement" "client_os" {
  count     = var.accept_client_marketplace_terms ? 1 : 0
  publisher = "MicrosoftWindowsDesktop"
  offer     = var.client_os_offer
  plan      = var.client_os_sku
}

# -----------------------------------------------------------------------------
# SRV-AD01 : futur contrôleur de domaine
# -----------------------------------------------------------------------------

resource "azurerm_network_interface" "server" {
  name                = "nic-${var.server_vm_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.main_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.server_private_ip
  }
}

# Disque de données (D:) : partages de fichiers. Initialisé par
# scripts/08-file-shares.
resource "azurerm_managed_disk" "server_data" {
  name                 = "disk-${var.server_vm_name}-data"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = 32
  tags                 = var.tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "server_data" {
  managed_disk_id    = azurerm_managed_disk.server_data.id
  virtual_machine_id = azurerm_windows_virtual_machine.server.id
  lun                = 0
  caching            = "ReadWrite"
}

# Disque dédié aux sauvegardes Windows Server Backup (E:). Doit être distinct
# du volume sauvegardé (D:). Initialisé par scripts/17-backup.
resource "azurerm_managed_disk" "server_backup" {
  name                 = "disk-${var.server_vm_name}-backup"
  location             = var.location
  resource_group_name  = var.resource_group_name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = 64
  tags                 = var.tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "server_backup" {
  managed_disk_id    = azurerm_managed_disk.server_backup.id
  virtual_machine_id = azurerm_windows_virtual_machine.server.id
  lun                = 1
  caching            = "None" # recommandé pour les volumes de sauvegarde
}

resource "azurerm_windows_virtual_machine" "server" {
  name                  = var.server_vm_name
  computer_name         = var.server_vm_name
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.server.id]
  tags                  = var.tags

  # Trusted Launch (vTPM + Secure Boot) : prérequis pour BitLocker avec
  # protecteur TPM sur une VM Azure (Gen2). Nécessite azurerm >= 3.30 et une
  # image compatible Gen2 (c'est le cas de 2022-datacenter-g2 utilisée ici).
  vtpm_enabled        = var.enable_bitlocker
  secure_boot_enabled = var.enable_bitlocker

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }

  boot_diagnostics {
    storage_account_uri = null # utilise le stockage managé par défaut
  }
}

# Accès en lecture aux secrets du Key Vault via l'identité managée de la VM
# (usage prévu : récupération de secrets par des scripts d'administration,
# sans jamais exposer de mot de passe en clair sur la ligne de commande).
resource "azurerm_key_vault_access_policy" "server_identity" {
  key_vault_id = var.key_vault_id
  tenant_id    = azurerm_windows_virtual_machine.server.identity[0].tenant_id
  object_id    = azurerm_windows_virtual_machine.server.identity[0].principal_id

  secret_permissions = ["Get", "List"]
}

# -----------------------------------------------------------------------------
# PC-CLIENT01 : poste de travail (à joindre au domaine avec
# scripts/20-client-pc/01-join-domain.ps1 une fois AD en place)
# -----------------------------------------------------------------------------

resource "azurerm_network_interface" "client" {
  name                = "nic-${var.client_vm_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # DNS pointé sur SRV-AD01 (+ DC02 en secours si le second DC est actif) :
  # indispensable pour résoudre le domaine AD au moment de la jonction.
  dns_servers = var.enable_second_dc ? [var.server_private_ip, var.dc02_private_ip] : [var.server_private_ip]

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.main_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.client_private_ip
  }
}

resource "azurerm_windows_virtual_machine" "client" {
  name                  = var.client_vm_name
  computer_name         = var.client_vm_name
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.client.id]
  tags                  = var.tags
  depends_on            = [azurerm_marketplace_agreement.client_os]

  # Trusted Launch (vTPM + Secure Boot), prérequis BitLocker avec protecteur TPM.
  vtpm_enabled        = var.enable_bitlocker
  secure_boot_enabled = var.enable_bitlocker

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = var.client_os_offer
    sku       = var.client_os_sku
    version   = "latest"
  }

  boot_diagnostics {
    storage_account_uri = null
  }
}

resource "azurerm_key_vault_access_policy" "client_identity" {
  key_vault_id = var.key_vault_id
  tenant_id    = azurerm_windows_virtual_machine.client.identity[0].tenant_id
  object_id    = azurerm_windows_virtual_machine.client.identity[0].principal_id

  secret_permissions = ["Get", "List"]
}

# =============================================================================
# DC02 (optionnel) : second contrôleur de domaine (haute disponibilité AD).
# Seule la VM est créée ici ; la promotion se fait avec
# scripts/02-second-dc/02-install-dc02.ps1 une fois SRV-AD01 opérationnel.
# =============================================================================

resource "azurerm_network_interface" "dc02" {
  count               = var.enable_second_dc ? 1 : 0
  name                = "nic-${var.dc02_vm_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  dns_servers = [var.server_private_ip] # pointe vers SRV-AD01 pour trouver le domaine à rejoindre

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.main_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.dc02_private_ip
  }
}

resource "azurerm_windows_virtual_machine" "dc02" {
  count                 = var.enable_second_dc ? 1 : 0
  name                  = var.dc02_vm_name
  computer_name         = var.dc02_vm_name
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.dc02[0].id]
  tags                  = var.tags

  vtpm_enabled        = var.enable_bitlocker
  secure_boot_enabled = var.enable_bitlocker

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }

  boot_diagnostics {
    storage_account_uri = null
  }
}
