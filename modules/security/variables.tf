variable "project_name" { type = string }
variable "environment" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }
variable "resource_group_name" { type = string }
variable "main_subnet_id" { type = string }
variable "bastion_subnet_id" {
  type    = string
  default = null
}
variable "enable_bastion" { type = bool }
variable "allowed_admin_source_ips" { type = list(string) }
