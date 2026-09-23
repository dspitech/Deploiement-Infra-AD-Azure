<div align="center">

# ESTIAM - Infrastructure Active Directory sur Azure

**Terraform déploie les ressources Azure et les VM - la configuration Windows / AD est faite ensuite par vous, service par service, avec les scripts PowerShell du dossier `scripts/`.**

| | |
|---|---|
| **Version** | 2.0.0 - voir [`CHANGELOG.md`](./CHANGELOG.md) |
| **Portée** | `SRV-AD01` (futur DC) + `PC-CLIENT01` (+ `DC02` optionnelle), domaine `estiam.local` |
| **Région cible** | `norwayeast` |

</div>

---

## Principe

1. **Terraform** crée uniquement : Resource Group, VNet/Subnets, NSG, Azure Bastion, Key Vault, les VM Windows (serveur + client, DC02 en option) et leurs disques de données. **Il n'exécute plus aucun script dans les VM.**
2. **Vous** vous connectez ensuite aux VM (Bastion) et lancez les scripts, un dossier par service, dans l'ordre.

<img width="1024" height="559" alt="image" src="https://github.com/user-attachments/assets/b1fd5658-ef68-49c9-ace8-fbae3f581c2d" />

---

## Structure du dépôt

```
├── bootstrap-backend/        Backend Terraform distant (à exécuter une seule fois)
├── main.tf, variables.tf, outputs.tf, providers.tf, versions.tf, backend.tf
├── terraform.tfvars.example, backend.hcl.example
├── modules/
│   ├── network/              Resource Group, VNet, Subnets
│   ├── security/             NSG, Azure Bastion
│   ├── keyvault/             Key Vault (mot de passe admin)
│   └── compute/              VM, NIC, disques, identités managées
│
└── scripts/                  UN DOSSIER PAR SERVICE, à exécuter à la main
    ├── 00-common/            common.psm1 + config.json (domaine, IP, DHCP, services)
    ├── 01-active-directory/  01-install-ad.ps1            (SRV-AD01, redémarre)
    ├── 02-second-dc/         02-install-dc02.ps1          (optionnel, sur DC02)
    ├── 03-dns/               03-configure-dns.ps1
    ├── 04-dhcp/              04-configure-dhcp.ps1
    ├── 05-organizational-units/  05-create-ous.ps1
    ├── 06-groups/            06-create-groups.ps1
    ├── 07-users/             07-create-users.ps1 + users.csv
    ├── 08-file-shares/       08-create-shares.ps1
    ├── 09-ntfs-permissions/  09-configure-permissions.ps1
    ├── 10-gpo/               10-create-gpos.ps1
    ├── 11-fsrm/              11-configure-fsrm.ps1
    ├── 12-shadow-copies/     12-configure-shadowcopies.ps1
    ├── 13-print-server/      13-configure-print-server.ps1
    ├── 14-applocker/         14-configure-applocker.ps1
    ├── 15-laps/              15-configure-laps.ps1
    ├── 16-audit-delegation/  16-configure-audit-delegation.ps1
    ├── 17-backup/            17-configure-backup.ps1
    ├── 18-monitoring/        18-configure-monitoring.ps1
    ├── 19-security-checks/   19-run-security-checks.ps1
    ├── 20-client-pc/         01-join-domain.ps1, 02-client-hardening.ps1  (sur PC-CLIENT01)
    └── Run-All.ps1           (facultatif) enchaîne les étapes 03 à 19
```

---

## Prérequis

| Outil / accès | Détail |
|---|---|
| Terraform | >= 1.6.0 |
| Azure CLI | `az login` (ou Service Principal) |
| Abonnement Azure | quota suffisant pour 2 VM `Standard_B2s` (3 avec DC02) |
| Rôle Azure | *Contributor* sur l'abonnement / resource group |

---

## Partie 1 - Déployer l'infrastructure Azure (Terraform)

```bash
# (une seule fois) backend d'état distant
git clone https://github.com/dspitech/Deploiement-Infra-AD-Azure.git
cd /Deploiement-Infra-AD-Azure/bootstrap-backend && terraform init && terraform apply -auto-approve
terraform output backend_hcl_content      # à reporter dans backend.hcl
cd ..
cp backend.hcl.example backend.hcl        # puis éditer

# déploiement
terraform init -backend-config backend.hcl
cp terraform.tfvars.example terraform.tfvars
export TF_VAR_admin_password="Un-Mot-De-Passe-Fort-2026!"   # sinon généré automatiquement
terraform plan && terraform apply -auto-approve

terraform output -raw admin_password      # mot de passe généré (si non fourni)
```

Le déploiement ne prend que quelques minutes (création des VM uniquement).
Aucune IP publique n'est exposée sur les VM : connexion via **Azure Bastion**
(portail Azure → Resource Group → VM → *Connect* → *Bastion*) avec le compte `estiamadmin`.

---

## Partie 2 - Configurer Windows (scripts, à la main)

### 2.1 Vérifier `scripts/00-common/config.json`

C'est la **seule** configuration des scripts (elle remplace les variables Terraform de l'ancienne version) :

```json
{
  "DomainName": "estiam.local",   "NetbiosName": "ESTIAM",
  "ServerIp": "10.10.10.10",      "Departments": ["Direction","IT","RH","Finance","Marketing","Administration"],
  "EnableDhcp": true, "DhcpScopeStart": "10.10.10.100", "DhcpScopeEnd": "10.10.10.200", "DhcpGateway": "10.10.10.1"
}
```

> `ServerIp` doit correspondre à `server_private_ip` de Terraform (défaut `10.10.10.10`).

### 2.2 Copier les scripts sur les VM

Le dossier `scripts/` doit se trouver sur `SRV-AD01` (et sur `PC-CLIENT01` pour le dossier client). Trois options :

- **Depuis GitHub** (le plus simple ; dépôt public et modifications poussées). Sur la VM, en PowerShell administrateur :
  ```powershell
  Invoke-WebRequest https://github.com/dspitech/Deploiement-Infra-AD-Azure/archive/refs/heads/main.zip -OutFile C:\estiam.zip
  Expand-Archive C:\estiam.zip C:\ -Force
  cd C:\Deploiement-Infra-AD-Azure-main\scripts
  ```
- **Copier/coller** : Bastion (SKU Basic) permet le presse-papiers texte, pas le transfert de fichiers. Recréer les fichiers avec `notepad`, ou passer Bastion en SKU Standard pour le transfert de fichiers.
- Autre : disque/partage de votre choix.

Si PowerShell bloque les scripts : `Set-ExecutionPolicy -Scope Process Bypass`.

### 2.3 Ordre d'exécution sur `SRV-AD01` (PowerShell en administrateur)

```powershell
# 1) Promotion en contrôleur de domaine : le serveur REDÉMARRE tout seul
.\01-active-directory\01-install-ad.ps1

# 2) Attendre 5-10 min après le redémarrage, se reconnecter en ESTIAM\estiamadmin, puis :
.\Run-All.ps1                 # enchaîne les étapes 03 à 19
#   ou, une par une, dans l'ordre :
.\03-dns\03-configure-dns.ps1
.\04-dhcp\04-configure-dhcp.ps1
# ... etc. (voir tableau ci-dessous)

# En cas d'erreur, corriger puis reprendre où l'on s'était arrêté :
.\Run-All.ps1 -From 10
```

Chaque script est **idempotent** (rejouable sans effet de bord) et attend qu'Active Directory soit disponible avant d'agir. Les journaux sont dans `C:\ESTIAM\Logs\estiam-bootstrap.log`.

### 2.4 Sur `DC02` (optionnel, si `enable_second_dc = true`)

Une fois `SRV-AD01` opérationnel : `.\02-second-dc\02-install-dc02.ps1` (demande le compte de domaine et le mot de passe DSRM ; redémarre à la fin).

### 2.5 Sur `PC-CLIENT01`

```powershell
# Après l'étape 05 (OU Workstations créée) sur le serveur :
.\20-client-pc\01-join-domain.ps1        # demande ESTIAM\estiamadmin, redémarre le poste

# Après redémarrage, connecté en administrateur du domaine, et une fois l'étape 10 (GPO) jouée :
.\20-client-pc\02-client-hardening.ps1   # gpupdate, AppLocker, Defender, BitLocker
```

---

## Détail des scripts

| # | Dossier / script | Machine | Ce qu'il fait |
|---|---|---|---|
| 01 | `01-active-directory` | SRV-AD01 | Installe AD DS + DNS, promeut le serveur (foret `estiam.local`), **redémarre** |
| 02 | `02-second-dc` | DC02 | Promeut DC02 en second contrôleur (optionnel) |
| 03 | `03-dns` | SRV-AD01 | Zone inversée, forwarder Azure, client DNS local, règle ping |
| 04 | `04-dhcp` | SRV-AD01 | Rôle DHCP, autorisation dans AD, étendue et options |
| 05 | `05-organizational-units` | SRV-AD01 | Arborescence des OU |
| 06 | `06-groups` | SRV-AD01 | Groupes de sécurité (`GG-ESTIAM-*`, `GG-FS-*`, Helpdesk) |
| 07 | `07-users` | SRV-AD01 | Utilisateurs (`users.csv`), comptes `adm-*`, compte `svc-backup` |
| 08 | `08-file-shares` | SRV-AD01 | Initialise le disque D:, partages SMB, dossiers personnels |
| 09 | `09-ntfs-permissions` | SRV-AD01 | Matrice de permissions NTFS |
| 10 | `10-gpo` | SRV-AD01 | GPO (sécurité, USB, terminal, WU, Defender, BitLocker, admins locaux), script de connexion |
| 11 | `11-fsrm` | SRV-AD01 | Quotas 2 Go, filtrage des exécutables |
| 12 | `12-shadow-copies` | SRV-AD01 | Clichés instantanés sur D: |
| 13 | `13-print-server` | SRV-AD01 | Serveur d'impression de démonstration |
| 14 | `14-applocker` | SRV-AD01 | Politique AppLocker (GPO) |
| 15 | `15-laps` | SRV-AD01 | Windows LAPS |
| 16 | `16-audit-delegation` | SRV-AD01 | Audit AD, délégation Helpdesk, désactivation des comptes inactifs |
| 17 | `17-backup` | SRV-AD01 | Initialise E:, Windows Server Backup quotidien |
| 18 | `18-monitoring` | SRV-AD01 | Dashboard IIS `http://10.10.10.10/estiam/` + collecteur |
| 19 | `19-security-checks` | SRV-AD01 | ~25 vérifications PASS/FAIL |
| 20 | `20-client-pc` | PC-CLIENT01 | Jonction au domaine, durcissement, BitLocker |

**Dépendances à respecter :** 05 avant 06/07 ; 06 avant 07 ; 08 avant 09, 11, 12, 17 ; 10 avant 13 ; la jonction du client (20/01) nécessite l'étape 05.

---

## Références rapides

- **Variables Terraform** (`variables.tf`) : `location`, `vm_size`, `admin_username`, `admin_password`, `enable_bastion`, `allowed_admin_source_ips`, `enable_second_dc`, `enable_bitlocker`, `key_vault_authorized_object_ids`, noms/IP des VM.
- **Identifiants** : mots de passe générés pour les utilisateurs dans `C:\ESTIAM\generated-credentials.csv` (accès restreint) sur `SRV-AD01` ; mot de passe admin dans le Key Vault (`estiam-admin-password`).
- **Validation** : `nslookup estiam.local`, `Get-ADUser -Filter *`, `Get-SmbShare`, rapport `C:\ESTIAM\security-check-report.json`. Sur `PC-CLIENT01`, connexion avec `ESTIAM\jdupont` puis `gpresult /r`.
- **Incidents** : voir [`RUNBOOK.md`](./RUNBOOK.md).

## Limitations connues

- **DHCP dans Azure** : le réseau virtuel Azure ne relaie pas les broadcasts DHCP ; le rôle DHCP s'installe et se configure, mais les VM Azure continuent de recevoir leur adresse de la plateforme (IP statiques ici). L'étape 04 est donc surtout démonstrative.
- **Windows LAPS** nécessite une mise à jour Windows Server 2022 récente ; sinon l'étape 15 le signale et s'arrête proprement (à rejouer après Windows Update).
- **BitLocker** exige le vTPM Trusted Launch (`enable_bitlocker = true`) ; sans TPM, un protecteur par mot de passe de récupération est utilisé.
- La restauration de sauvegarde reste une **procédure manuelle** (voir Runbook).

## Démanteler

```bash
terraform destroy
cd bootstrap-backend && terraform destroy   # si le backend n'est plus nécessaire
```

## Contribution et licence

Voir [`CONTRIBUTING.md`](./CONTRIBUTING.md). Projet pédagogique ESTIAM : réutilisation libre à des fins d'apprentissage, sans garantie pour un usage en production.
