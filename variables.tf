# =============================================================================
# Variables globales du projet ESTIAM
# =============================================================================

variable "project_name" {
  description = "Préfixe utilisé pour nommer toutes les ressources Azure."
  type        = string
  default     = "estiam"
}

variable "environment" {
  description = "Nom de l'environnement (lab, dev, prod...)."
  type        = string
  default     = "lab"
}

variable "location" {
  description = "Région Azure de déploiement."
  type        = string
  default     = "norwayeast"
}

variable "tags" {
  description = "Tags appliqués à toutes les ressources."
  type        = map(string)
  default = {
    projet      = "ESTIAM"
    gere_par    = "terraform"
    criticite   = "lab"
  }
}

# -----------------------------------------------------------------------------
# Réseau
# -----------------------------------------------------------------------------

variable "vnet_address_space" {
  description = "Plage d'adressage du VNet."
  type        = list(string)
  default     = ["10.10.0.0/16"]
}

variable "subnet_prefix" {
  description = "Plage d'adressage du subnet principal (Subnet-ESTIAM)."
  type        = string
  default     = "10.10.10.0/24"
}

variable "bastion_subnet_prefix" {
  description = "Plage d'adressage du subnet Azure Bastion (doit s'appeler AzureBastionSubnet et faire /26 minimum)."
  type        = string
  default     = "10.10.20.0/26"
}

variable "server_private_ip" {
  description = "Adresse IP privée statique du contrôleur de domaine SRV-AD01."
  type        = string
  default     = "10.10.10.10"
}

variable "client_private_ip" {
  description = "Adresse IP privée statique du poste PC-CLIENT01."
  type        = string
  default     = "10.10.10.20"
}

variable "allowed_admin_source_ips" {
  description = <<-EOT
    Liste des plages IP publiques autorisées à administrer l'infrastructure
    (RDP direct) si Azure Bastion est désactivé. Laisser vide + enable_bastion=true
    pour ne JAMAIS exposer RDP sur Internet (recommandé, conforme section 29 du cahier des charges).
  EOT
  type    = list(string)
  default = []
}

variable "enable_bastion" {
  description = "Déploie Azure Bastion pour l'administration distante sécurisée (recommandé, cf section 29)."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Machines virtuelles
# -----------------------------------------------------------------------------

variable "vm_size" {
  description = "Taille des machines virtuelles."
  type        = string
  default     = "Standard_B2s"
}

variable "admin_username" {
  description = "Nom du compte administrateur local ET du compte Administrateur de domaine créé par Install-ADDSForest."
  type        = string
  default     = "estiamadmin"
}

variable "admin_password" {
  description = <<-EOT
    Mot de passe administrateur (local + DSRM + domaine).
    Ne PAS renseigner en dur ici ni dans un fichier versionné :
    - passer par une variable d'environnement TF_VAR_admin_password
    - ou par Azure Key Vault / un pipeline CI/CD avec secret protégé
    Si laissé vide, un mot de passe aléatoire fort est généré automatiquement
    par Terraform (resource random_password) et exposé en sortie sensible.
  EOT
  type      = string
  default   = ""
  sensitive = true
}

variable "server_vm_name" {
  type    = string
  default = "SRV-AD01"
}

variable "client_vm_name" {
  type    = string
  default = "PC-CLIENT01"
}

variable "client_os_offer" {
  description = "Offre Marketplace du poste client (image Windows 10/11 Entreprise)."
  type        = string
  default     = "windows-11"
}

variable "client_os_sku" {
  description = "SKU de l'image du poste client."
  type        = string
  default     = "win11-23h2-ent"
}

variable "accept_client_marketplace_terms" {
  description = "Accepte automatiquement les termes Marketplace de l'image client Windows 11 Entreprise (nécessaire une seule fois par abonnement)."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Active Directory
# -----------------------------------------------------------------------------

variable "ad_domain_name" {
  description = "Nom de domaine Active Directory (FQDN)."
  type        = string
  default     = "estiam.local"
}

variable "ad_netbios_name" {
  description = "Nom NetBIOS du domaine."
  type        = string
  default     = "ESTIAM"
}

variable "departments" {
  description = "Liste des services/OU métier de l'entreprise."
  type        = list(string)
  default     = ["Direction", "IT", "RH", "Finance", "Marketing", "Administration"]
}

# -----------------------------------------------------------------------------
# DHCP
# -----------------------------------------------------------------------------

variable "enable_dhcp" {
  description = "Active le rôle DHCP sur SRV-AD01 (section 6 du cahier des charges)."
  type        = bool
  default     = true
}

variable "dhcp_scope_start" {
  type    = string
  default = "10.10.10.100"
}

variable "dhcp_scope_end" {
  type    = string
  default = "10.10.10.200"
}

variable "dhcp_default_gateway" {
  type    = string
  default = "10.10.10.1"
}

# -----------------------------------------------------------------------------
# Résilience / sécurité avancée
# -----------------------------------------------------------------------------

variable "enable_second_dc" {
  description = "Déploie un second contrôleur de domaine (DC02) pour éliminer le point de défaillance unique. Désactivé par défaut : un seul DC (SRV-AD01) suffit pour le lab et évite de dépasser le quota de coeurs standardBSFamily de l'abonnement."
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

variable "enable_bitlocker" {
  description = "Active BitLocker (Trusted Launch : vTPM + Secure Boot) sur les VM, avec sauvegarde des clés de récupération dans Active Directory."
  type        = bool
  default     = true
}

variable "key_vault_authorized_object_ids" {
  description = "Object IDs Azure AD (utilisateurs/groupes) autorisés à lire les secrets du Key Vault ESTIAM (ex: équipe IT). Laisser vide si seul l'opérateur Terraform doit y accéder."
  type        = list(string)
  default     = []
}
