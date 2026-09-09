variable "project_name" { type = string }
variable "environment" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }
variable "resource_group_name" { type = string }
variable "scripts_dir" {
  description = "Chemin local du dossier contenant les scripts PowerShell à uploader."
  type        = string
}
