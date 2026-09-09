# =============================================================================
# ESTIAM - Infrastructure Active Directory automatisée (Azure + Terraform)
# =============================================================================

resource "random_password" "admin" {
  count            = var.admin_password == "" ? 1 : 0
  length           = 20
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!@#%^&*-_="
}

locals {
  admin_password_effective = var.admin_password != "" ? var.admin_password : random_password.admin[0].result
}

module "network" {
  source = "./modules/network"

  project_name           = var.project_name
  environment            = var.environment
  location               = var.location
  tags                   = var.tags
  vnet_address_space     = var.vnet_address_space
  subnet_prefix          = var.subnet_prefix
  bastion_subnet_prefix  = var.bastion_subnet_prefix
  enable_bastion         = var.enable_bastion
}

module "security" {
  source = "./modules/security"

  project_name              = var.project_name
  environment               = var.environment
  location                  = var.location
  tags                      = var.tags
  resource_group_name       = module.network.resource_group_name
  main_subnet_id            = module.network.main_subnet_id
  bastion_subnet_id         = module.network.bastion_subnet_id
  enable_bastion            = var.enable_bastion
  allowed_admin_source_ips  = var.allowed_admin_source_ips
}

module "storage" {
  source = "./modules/storage"

  project_name         = var.project_name
  environment          = var.environment
  location             = var.location
  tags                 = var.tags
  resource_group_name  = module.network.resource_group_name
  scripts_dir          = "${path.module}/scripts"
}

module "keyvault" {
  source = "./modules/keyvault"

  project_name          = var.project_name
  environment           = var.environment
  location              = var.location
  tags                  = var.tags
  resource_group_name   = module.network.resource_group_name
  admin_password        = local.admin_password_effective
  storage_account_key   = module.storage.primary_access_key
  authorized_object_ids = var.key_vault_authorized_object_ids
}

module "compute" {
  source = "./modules/compute"

  project_name         = var.project_name
  environment          = var.environment
  location             = var.location
  tags                 = var.tags
  resource_group_name  = module.network.resource_group_name
  main_subnet_id       = module.network.main_subnet_id

  vm_size         = var.vm_size
  admin_username  = var.admin_username
  admin_password  = local.admin_password_effective

  server_vm_name    = var.server_vm_name
  client_vm_name    = var.client_vm_name
  server_private_ip = var.server_private_ip
  client_private_ip = var.client_private_ip

  client_os_offer                 = var.client_os_offer
  client_os_sku                   = var.client_os_sku
  accept_client_marketplace_terms = var.accept_client_marketplace_terms

  ad_domain_name  = var.ad_domain_name
  ad_netbios_name = var.ad_netbios_name
  departments     = var.departments

  enable_dhcp           = var.enable_dhcp
  dhcp_scope_start      = var.dhcp_scope_start
  dhcp_scope_end        = var.dhcp_scope_end
  dhcp_default_gateway  = var.dhcp_default_gateway

  storage_account_name   = module.storage.storage_account_name
  storage_account_id     = module.storage.storage_account_id
  storage_account_key    = module.storage.primary_access_key
  scripts_blob_base_url  = module.storage.blob_base_url

  key_vault_id     = module.keyvault.key_vault_id
  enable_bitlocker = var.enable_bitlocker
  enable_second_dc = var.enable_second_dc
  dc02_vm_name     = var.dc02_vm_name
  dc02_private_ip  = var.dc02_private_ip

  depends_on = [module.security]
}
