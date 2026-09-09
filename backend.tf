# =============================================================================
# Backend distant : etat Terraform stocke dans Azure Storage, avec
# verrouillage automatique (bail sur le blob) pour eviter les applies
# concurrents. Les valeurs concretes (nom du compte de stockage, etc.)
# viennent de bootstrap-backend/ et sont fournies via -backend-config.
#
# Utilisation :
#   cd bootstrap-backend && terraform init && terraform apply
#   # noter les valeurs de sortie, les reporter dans backend.hcl
#   cd .. && cp backend.hcl.example backend.hcl   # puis editer
#   terraform init -backend-config=backend.hcl
# =============================================================================

terraform {
  backend "azurerm" {
    # Rempli via -backend-config=backend.hcl (voir backend.hcl.example).
    # Ne JAMAIS committer backend.hcl (contient un nom de compte de stockage
    # propre a votre abonnement) - deja exclu par .gitignore.
  }
}
