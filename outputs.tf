output "resource_group_name" {
  description = "Nom du groupe de ressources Azure créé."
  value       = module.network.resource_group_name
}

output "server_private_ip" {
  description = "Adresse IP privée de SRV-AD01 (contrôleur de domaine / DNS)."
  value       = module.compute.server_private_ip
}

output "client_private_ip" {
  description = "Adresse IP privée de PC-CLIENT01."
  value       = module.compute.client_private_ip
}

output "dc02_private_ip" {
  description = "Adresse IP privée de DC02 (second contrôleur de domaine), si activé."
  value       = module.compute.dc02_private_ip
}

output "key_vault_name" {
  description = "Nom du Key Vault contenant le mot de passe admin et la clé du compte de stockage."
  value       = module.keyvault.key_vault_name
}

output "domain_name" {
  value = var.ad_domain_name
}

output "admin_username" {
  value = var.admin_username
}

output "admin_password" {
  description = "Mot de passe administrateur (généré automatiquement si non fourni). Sensible. Également stocké dans le Key Vault ESTIAM (secret 'estiam-admin-password') pour consultation ultérieure sans repasser par l'état Terraform."
  value       = local.admin_password_effective
  sensitive   = true
}

output "bastion_enabled" {
  value = var.enable_bastion
}

output "how_to_connect" {
  description = "Rappel de connexion (aucune IP publique n'est exposée sur les VM)."
  value = var.enable_bastion ? "Connexion via Azure Bastion depuis le portail Azure (Resource Group ${module.network.resource_group_name})." : "Connexion RDP directe autorisée uniquement depuis : ${join(", ", var.allowed_admin_source_ips)}"
}
