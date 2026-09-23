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

variable "key_vault_id" {
  description = "ID du Key Vault ESTIAM (accès en lecture aux secrets pour l'identité managée des VM)."
  type        = string
}

variable "enable_bitlocker" {
  description = "Active Trusted Launch (vTPM + Secure Boot) sur les VM, prérequis de BitLocker avec protecteur TPM."
  type        = bool
  default     = true
}

variable "enable_second_dc" {
  description = "Déploie la VM DC02 (second contrôleur de domaine, à promouvoir avec scripts/02-second-dc)."
  type        = bool
  default     = false
}
variable "dc02_vm_name" {
  type    = string
  default = "DC02"
}
variable "dc02_private_ip" {
  type    = string
  default = "10.10.10.11"
}
