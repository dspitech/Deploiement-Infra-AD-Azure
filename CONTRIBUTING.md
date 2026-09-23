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
| Scripts d'étape serveur | `scripts/<NN>-<service>/<NN>-<action>.ps1`, numérotés dans l'ordre d'exécution | `11-fsrm/11-configure-fsrm.ps1` |
| GPO | `GPO-ESTIAM-<OBJET>` | `GPO-ESTIAM-USB-Restriction` |

## Ajouter un nouveau script de service

1. Créer un dossier `scripts/<NN>-<service>/` (numéroté après le dernier
   existant) contenant `<NN>-<action>.ps1`.
2. Reprendre l'en-tête des scripts existants : `#Requires -RunAsAdministrator`,
   `param([string]$ConfigPath)`, import de `..\00-common\common.psm1`, puis
   `$Config = Get-EstiamConfig -Path $ConfigPath`.
3. Rendre le script **idempotent** : vérifier l'existence d'une ressource
   avant de la créer (voir les scripts existants pour le pattern).
4. Rester en **ASCII** (pas d'accents) dans les `.ps1` pour rester compatible
   Windows PowerShell 5.1.
5. Ajouter l'étape à la liste `$steps` de `scripts/Run-All.ps1`.
6. Documenter l'étape dans le README et mettre à jour `CHANGELOG.md`.

## Modifier une ressource Terraform existante

1. Identifier le bon module (`modules/network`, `modules/security`,
   `modules/keyvault`, `modules/compute`) plutôt que de
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
