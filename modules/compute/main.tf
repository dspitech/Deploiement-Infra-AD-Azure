# =============================================================================
# Module compute : SRV-AD01 (contrôleur de domaine) + PC-CLIENT01 (poste client)
# Toute la configuration Windows/AD est automatisée via Custom Script Extension
# + une tâche planifiée qui survit au redémarrage post-promotion AD DS.
# =============================================================================

locals {
  departments_csv = join(",", var.departments)

  # NB : on encode la configuration en Base64 plutôt que de passer des
  # arguments CLI un a un. Le Custom Script Extension execute commandToExecute
  # via cmd.exe : les guillemets simples ne sont pas fiables (mot de passe
  # genere avec caracteres speciaux, quotes imbriquees...). Le Base64 ne
  # contient jamais d'espace ni de guillemet, ce qui elimine tout risque
  # d'echappement incorrect.
  server_bootstrap_config = {
    DomainName     = var.ad_domain_name
    NetbiosName    = var.ad_netbios_name
    SafeModePassword = var.admin_password
    AdminUsername  = var.admin_username
    AdminPassword  = var.admin_password
    DepartmentsCsv = local.departments_csv
    EnableDhcp     = var.enable_dhcp
    DhcpScopeStart = var.dhcp_scope_start
    DhcpScopeEnd   = var.dhcp_scope_end
    DhcpGateway    = var.dhcp_default_gateway
    ServerIp       = var.server_private_ip
  }
  server_bootstrap_config_b64 = base64encode(jsonencode(local.server_bootstrap_config))

  # Scripts nécessaires côté serveur (téléchargés par la 1ère extension)
  server_script_files = [
    "common.psm1",
    "01-install-ad.ps1",
    "Bootstrap-Server.ps1",
    "02-configure-dns.ps1",
    "03-configure-dhcp.ps1",
    "04-create-ous.ps1",
    "05-create-groups.ps1",
    "06-create-users.ps1",
    "07-create-shares.ps1",
    "08-configure-permissions.ps1",
    "09-create-gpos.ps1",
    "10-configure-fsrm.ps1",
    "11-configure-shadowcopies-print.ps1",
    "12-configure-applocker.ps1",
    "13-configure-laps.ps1",
    "14-configure-audit-delegation.ps1",
    "15-configure-backup.ps1",
    "16-configure-monitoring.ps1",
    "17-run-security-checks.ps1",
    "users.csv",
  ]

  client_script_files = [
    "common.psm1",
    "client-hardening.ps1",
  ]

  dc02_config = {
    DomainName       = var.ad_domain_name
    NetbiosName      = var.ad_netbios_name
    AdminUsername    = var.admin_username
    AdminPassword    = var.admin_password
    SafeModePassword = var.admin_password
    PrimaryDcIp      = var.server_private_ip
  }
  dc02_config_b64 = base64encode(jsonencode(local.dc02_config))
  dc02_script_files = ["common.psm1", "01b-install-dc02.ps1"]
}

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
# SRV-AD01 : contrôleur de domaine
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

# Disque dédié aux sauvegardes Windows Server Backup (section 12 des demandes
# complémentaires). Doit être distinct du volume sauvegardé (D:).
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
  name                = var.server_vm_name
  computer_name       = var.server_vm_name
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  network_interface_ids = [azurerm_network_interface.server.id]
  tags                = var.tags

  # Trusted Launch (vTPM + Secure Boot) : prerequis pour BitLocker avec
  # protecteur TPM sur une VM Azure (Gen2). Necessite azurerm >= 3.30 et une
  # image compatible Gen2 (c'est le cas de 2022-datacenter-g2 utilisee ici).
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
# (usage prévu : recuperation de secrets par des scripts d'administration
# futurs, sans jamais exposer de mot de passe en clair sur la ligne de
# commande). Le téléchargement initial des scripts continue d'utiliser la clé
# de stockage classique via protected_settings, plus simple et deja chiffrée
# côté Azure ; le basculement complet vers un téléchargement authentifié par
# identité managée est possible mais dépend de la version de l'extension -
# a valider avec la documentation Azure a jour avant activation en production.
resource "azurerm_key_vault_access_policy" "server_identity" {
  key_vault_id = var.key_vault_id
  tenant_id    = azurerm_windows_virtual_machine.server.identity[0].tenant_id
  object_id    = azurerm_windows_virtual_machine.server.identity[0].principal_id

  secret_permissions = ["Get", "List"]
}

resource "azurerm_role_assignment" "server_storage_reader" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_windows_virtual_machine.server.identity[0].principal_id
}

# Étape 1 : installation du rôle AD DS + promotion en contrôleur de domaine.
# Ce script redémarre automatiquement le serveur (Install-ADDSForest -Restart)
# et enregistre une tâche planifiée "ESTIAM-Bootstrap" qui reprend l'exécution
# au démarrage suivant pour dérouler DNS, DHCP, OU, groupes, utilisateurs,
# partages, permissions et GPO (voir Bootstrap-Server.ps1 / stage machine).
resource "azurerm_virtual_machine_extension" "server_bootstrap" {
  name                       = "bootstrap-ad"
  virtual_machine_id         = azurerm_windows_virtual_machine.server.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  depends_on                 = [azurerm_virtual_machine_data_disk_attachment.server_data, azurerm_virtual_machine_data_disk_attachment.server_backup]

  settings = jsonencode({
    fileUris = [for f in local.server_script_files : "${var.scripts_blob_base_url}/${f}"]
  })

  protected_settings = jsonencode({
    storageAccountName = var.storage_account_name
    storageAccountKey  = var.storage_account_key
    commandToExecute = "powershell -NoProfile -ExecutionPolicy Unrestricted -File 01-install-ad.ps1 -ConfigBase64 ${local.server_bootstrap_config_b64}"
  })

  tags = var.tags
}

# L'extension ci-dessus ne rend la main qu'après le PREMIER redémarrage
# déclenché par Install-ADDSForest ; la suite (DNS/DHCP/OU/users/GPO) continue
# en tâche de fond via la tâche planifiée. On attend ensuite un délai de
# sécurité avant de joindre le client au domaine.
resource "time_sleep" "wait_for_ad_ready" {
  depends_on      = [azurerm_virtual_machine_extension.server_bootstrap]
  create_duration = "50m" # pipeline etendu (DNS, DHCP, OU, groupes, utilisateurs, partages,
  # permissions, GPO, FSRM, AppLocker, LAPS, audit, backup, monitoring...) : 16 scripts
  # sequentiels apres le redemarrage post-promotion. 35 min s'est revele insuffisant
  # (la jonction du client a echoue car l'OU cible n'existait pas encore) -> marge
  # augmentee. Si l'echec revient, RDP/Bastion sur SRV-AD01 et verifier la progression
  # dans le journal du script planifie "ESTIAM-Bootstrap" (Planificateur de taches +
  # transcript PowerShell) avant d'augmenter encore ce delai.
}

# -----------------------------------------------------------------------------
# PC-CLIENT01 : poste de travail joint au domaine
# -----------------------------------------------------------------------------

resource "azurerm_network_interface" "client" {
  name                = "nic-${var.client_vm_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # DNS pointé sur SRV-AD01 (+ DC02 en secours si le second DC est actif) :
  # indispensable pour résoudre le domaine AD avant la jonction (section 5).
  dns_servers = var.enable_second_dc ? [var.server_private_ip, var.dc02_private_ip] : [var.server_private_ip]

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.main_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.client_private_ip
  }
}

resource "azurerm_windows_virtual_machine" "client" {
  name                   = var.client_vm_name
  computer_name          = var.client_vm_name
  location               = var.location
  resource_group_name    = var.resource_group_name
  size                   = var.vm_size
  admin_username         = var.admin_username
  admin_password         = var.admin_password
  network_interface_ids  = [azurerm_network_interface.client.id]
  tags                   = var.tags
  depends_on             = [azurerm_marketplace_agreement.client_os]

  # Trusted Launch (vTPM + Secure Boot), prerequis BitLocker avec protecteur TPM.
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

resource "azurerm_role_assignment" "client_storage_reader" {
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_windows_virtual_machine.client.identity[0].principal_id
}

# Jonction automatique au domaine (extension native Azure, plus fiable qu'un
# script manuel : gère nativement le redémarrage post-jonction).
resource "azurerm_virtual_machine_extension" "client_domain_join" {
  name                       = "domain-join"
  virtual_machine_id         = azurerm_windows_virtual_machine.client.id
  publisher                  = "Microsoft.Compute"
  type                       = "JsonADDomainExtension"
  type_handler_version       = "1.3"
  auto_upgrade_minor_version = true
  depends_on                 = [time_sleep.wait_for_ad_ready]

  settings = jsonencode({
    Name    = var.ad_domain_name
    OUPath  = "OU=Workstations,OU=Computers,OU=ESTIAM,${join(",", [for dc in split(".", var.ad_domain_name) : "DC=${dc}"])}"
    User    = "${var.ad_netbios_name}\\${var.admin_username}"
    Restart = true
    Options = 3
  })

  protected_settings = jsonencode({
    Password = var.admin_password
  })

  tags = var.tags
}

# Durcissement local du poste (fallback complémentaire aux GPO, section 15-21)
resource "azurerm_virtual_machine_extension" "client_hardening" {
  name                       = "security-hardening"
  virtual_machine_id         = azurerm_windows_virtual_machine.client.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  depends_on                 = [azurerm_virtual_machine_extension.client_domain_join]

  settings = jsonencode({
    fileUris = [for f in local.client_script_files : "${var.scripts_blob_base_url}/${f}"]
  })

  protected_settings = jsonencode({
    storageAccountName = var.storage_account_name
    storageAccountKey  = var.storage_account_key
    commandToExecute   = "powershell -NoProfile -ExecutionPolicy Unrestricted -File client-hardening.ps1 -NetbiosName '${var.ad_netbios_name}'"
  })

  tags = var.tags
}

# =============================================================================
# DC02 : second contrôleur de domaine (haute disponibilité AD, section
# "évolution possible" du cahier des charges - élimine le point de
# défaillance unique que représente SRV-AD01 seul).
# =============================================================================

resource "azurerm_network_interface" "dc02" {
  count               = var.enable_second_dc ? 1 : 0
  name                = "nic-${var.dc02_vm_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  dns_servers = [var.server_private_ip] # pointe vers SRV-AD01 pour trouver le domaine a rejoindre

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.main_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.dc02_private_ip
  }
}

resource "azurerm_windows_virtual_machine" "dc02" {
  count                  = var.enable_second_dc ? 1 : 0
  name                   = var.dc02_vm_name
  computer_name          = var.dc02_vm_name
  location               = var.location
  resource_group_name    = var.resource_group_name
  size                   = var.vm_size
  admin_username         = var.admin_username
  admin_password         = var.admin_password
  network_interface_ids  = [azurerm_network_interface.dc02[0].id]
  tags                   = var.tags

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

resource "azurerm_role_assignment" "dc02_storage_reader" {
  count                = var.enable_second_dc ? 1 : 0
  scope                = var.storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_windows_virtual_machine.dc02[0].identity[0].principal_id
}

# Promotion en second DC : ne demarre qu'une fois SRV-AD01 pleinement pret
# (meme garde-fou que la jonction du client), pour etre certain que le
# domaine et le DNS sont fonctionnels avant de tenter la promotion.
resource "azurerm_virtual_machine_extension" "dc02_bootstrap" {
  count                      = var.enable_second_dc ? 1 : 0
  name                       = "bootstrap-dc02"
  virtual_machine_id         = azurerm_windows_virtual_machine.dc02[0].id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  depends_on                 = [time_sleep.wait_for_ad_ready]

  settings = jsonencode({
    fileUris = [for f in local.dc02_script_files : "${var.scripts_blob_base_url}/${f}"]
  })

  protected_settings = jsonencode({
    storageAccountName = var.storage_account_name
    storageAccountKey  = var.storage_account_key
    commandToExecute   = "powershell -NoProfile -ExecutionPolicy Unrestricted -File 01b-install-dc02.ps1 -ConfigBase64 ${local.dc02_config_b64}"
  })

  tags = var.tags
}
