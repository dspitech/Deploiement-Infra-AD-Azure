variable "project_name" { type = string }
variable "environment" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }
variable "resource_group_name" { type = string }

variable "admin_password" {
  type      = string
  sensitive = true
}
variable "storage_account_key" {
  type      = string
  sensitive = true
}

variable "authorized_object_ids" {
  description = "Object IDs (utilisateurs/SP humains) autorises a lire les secrets, ex: l'operateur qui lance terraform apply."
  type        = list(string)
  default     = []
}
