# Contribuer à ce projet

Ce dépôt suit quelques conventions simples pour rester lisible et sûr à
faire évoluer, même dans un cadre pédagogique.

## Avant toute modification

1. **Lire le README** et le `RUNBOOK.md` associés à la zone que vous
   touchez (réseau, sécurité, comptes, sauvegarde...).
2. **Travailler sur une branche dédiée** (`feature/xxx`, `fix/xxx`) plutôt
   que directement sur la branche principale, même en solo - cela facilite
   la relecture et le retour arrière.
3. Vérifier qu'aucun secret (mot de passe, clé, token) n'est ajouté en dur
   dans le code : tout doit passer par `TF_VAR_*`, Key Vault, ou un fichier
   exclu par `.gitignore` (`terraform.tfvars`, `backend.hcl`).

## Conventions de nommage (à respecter dans tout nouvel ajout)

| Élément | Convention | Exemple |
|---|---|---|
| Serveurs | `SRV-<ROLE><NUM>` ou `DC<NUM>` | `SRV-AD01`, `DC02` |
| Postes clients | `PC-CLIENT<NUM>` | `PC-CLIENT01` |
| Comptes utilisateurs | `<initiale><nom>` | `jdupont` |
| Comptes d'administration | `adm-<compte utilisateur>` | `adm-tbernard` |
| Comptes de service | `svc-<usage>` | `svc-backup` |
| Groupes métier | `GG-ESTIAM-<SERVICE>` | `GG-ESTIAM-IT` |
| Groupes ressources | `GG-FS-<RESSOURCE>-<DROIT>` | `GG-FS-FINANCE-RW` |
| Scripts d'étape serveur | `<NN>-<action>.ps1`, numérotés dans l'ordre d'exécution | `10-configure-fsrm.ps1` |
| GPO | `GPO-ESTIAM-<OBJET>` | `GPO-ESTIAM-USB-Restriction` |

## Ajouter une nouvelle étape d'automatisation serveur

1. Créer le script dans `scripts/`, numéroté après la dernière étape
   existante (`18-...ps1`, etc.), avec le même en-tête `param([Parameter(Mandatory=$true)]$Config)`
   et `Import-Module "$here\common.psm1"`.
2. Rendre le script **idempotent** : vérifier l'existence d'une ressource
   avant de la créer (voir les scripts existants pour le pattern).
3. Ajouter le script à la liste `server_script_files` dans
   `modules/compute/main.tf` (sinon il ne sera pas téléchargé sur la VM).
4. Ajouter l'étape à la liste `$steps` dans `scripts/Bootstrap-Server.ps1`.
5. Documenter la nouvelle étape dans le tableau du README
   (« Détail des étapes d'automatisation serveur »).
6. Mettre à jour `CHANGELOG.md`.

## Modifier une ressource Terraform existante

1. Identifier le bon module (`modules/network`, `modules/security`,
   `modules/storage`, `modules/keyvault`, `modules/compute`) plutôt que de
   dupliquer une ressource dans `main.tf` racine.
2. Exposer toute nouvelle valeur nécessaire ailleurs via `outputs.tf` du
   module, jamais via des références croisées directes entre modules.
3. Lancer `terraform fmt -recursive` avant de committer.
4. Lancer `terraform validate` (et idéalement `tfsec`/`checkov` si
   disponibles) avant tout `apply` sur un environnement partagé.

## Checklist avant un `terraform apply` en environnement partagé

- [ ] `terraform fmt -recursive` exécuté sans modification
- [ ] `terraform validate` sans erreur
- [ ] `terraform plan` relu intégralement (aucune destruction non voulue)
- [ ] Aucun secret en dur dans le diff
- [ ] `CHANGELOG.md` mis à jour si la modification est notable
- [ ] Documentation (README/RUNBOOK) mise à jour si le comportement change

## Style des scripts PowerShell

- Toujours écrire dans `Write-EstiamLog` (fonction commune, `common.psm1`)
  plutôt que `Write-Host`, pour que les journaux restent centralisés dans
  `C:\ESTIAM\Logs\estiam-bootstrap.log`.
- Encadrer les opérations risquées (réseau, AD, registre) de `try/catch`
  avec un message explicite en cas d'échec.
- Préférer les cmdlets natifs (`ActiveDirectory`, `GroupPolicy`,
  `DhcpServer`...) à des appels `Invoke-Expression` ou `cmd /c` bruts.
