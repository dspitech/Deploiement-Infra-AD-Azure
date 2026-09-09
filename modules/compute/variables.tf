variable "project_name" { type = string }
variable "environment" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }
variable "resource_group_name" { type = string }
variable "main_subnet_id" { type = string }

variable "vm_size" { type = string }
variable "admin_username" { type = string }
variable "admin_password" {
  type      = string
  sensitive = true
}

variable "server_vm_name" { type = string }
variable "client_vm_name" { type = string }
variable "server_private_ip" { type = string }
variable "client_private_ip" { type = string }

variable "client_os_offer" { type = string }
variable "client_os_sku" { type = string }
variable "accept_client_marketplace_terms" { type = bool }

variable "ad_domain_name" { type = string }
variable "ad_netbios_name" { type = string }
variable "departments" { type = list(string) }

variable "enable_dhcp" { type = bool }
variable "dhcp_scope_start" { type = string }
variable "dhcp_scope_end" { type = string }
variable "dhcp_default_gateway" { type = string }

variable "storage_account_name" { type = string }
variable "storage_account_id" { type = string }
variable "storage_account_key" {
  type      = string
  sensitive = true
}
variable "scripts_blob_base_url" { type = string }

variable "key_vault_id" {
  description = "ID du Key Vault ESTIAM (pour donner aux VM un acces en lecture a leurs propres secrets via identite managee)."
  type        = string
}

variable "enable_bitlocker" {
  description = "Active le chiffrement BitLocker (Trusted Launch : vTPM + Secure Boot) sur les VM."
  type        = bool
  default     = true
}

variable "enable_second_dc" {
  description = "Deploie un second controleur de domaine (DC02) pour la haute disponibilite AD."
  type        = bool
  default     = true
}
variable "dc02_vm_name" {
  type    = string
  default = "DC02"
}
variable "dc02_private_ip" {
  type    = string
  default = "10.10.10.11"
}
