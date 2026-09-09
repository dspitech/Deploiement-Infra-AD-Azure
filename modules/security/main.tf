# =============================================================================
# Module security : NSG + Azure Bastion (section 28-29 du cahier des charges)
# =============================================================================

resource "azurerm_network_security_group" "main" {
  name                = "nsg-${var.project_name}-${var.environment}-main"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Trafic interne au VNet (AD DS, DNS, DHCP, SMB, GPO...) toujours autorisé
  # par les règles par défaut AzureVNetInBound / AllowVnetInBound.

  # RDP direct depuis Internet : refusé par défaut. N'est ouvert que si
  # enable_bastion = false ET que des IP publiques sont explicitement listées.
  dynamic "security_rule" {
    for_each = (!var.enable_bastion && length(var.allowed_admin_source_ips) > 0) ? [1] : []
    content {
      name                       = "Allow-RDP-Admin"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "3389"
      source_address_prefixes    = var.allowed_admin_source_ips
      destination_address_prefix = "*"
    }
  }

  # Blocage explicite de tout accès entrant direct depuis Internet
  security_rule {
    name                       = "Deny-Internet-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = var.main_subnet_id
  network_security_group_id = azurerm_network_security_group.main.id
}

# -----------------------------------------------------------------------------
# Azure Bastion : administration sécurisée sans exposer RDP (section 29)
# -----------------------------------------------------------------------------

resource "azurerm_public_ip" "bastion" {
  count               = var.enable_bastion ? 1 : 0
  name                = "pip-${var.project_name}-bastion"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_bastion_host" "this" {
  count               = var.enable_bastion ? 1 : 0
  name                = "bastion-${var.project_name}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Basic"
  tags                = var.tags

  ip_configuration {
    name                 = "bastion-ipconfig"
    subnet_id            = var.bastion_subnet_id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
}
