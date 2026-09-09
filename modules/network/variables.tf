variable "project_name" { type = string }
variable "environment" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }
variable "vnet_address_space" { type = list(string) }
variable "subnet_prefix" { type = string }
variable "bastion_subnet_prefix" { type = string }
variable "enable_bastion" { type = bool }
