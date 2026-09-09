<div align="center">

# ESTIAM - Infrastructure Active Directory automatisée sur Azure

**Provisioning Terraform + configuration PowerShell entièrement automatisés - zéro étape manuelle dans Windows.**

| | |
|---|---|
| **Statut** |  Stable - prêt pour déploiement lab/démonstration |
| **Version** | 1.2.0 - voir [`CHANGELOG.md`](./CHANGELOG.md) |
| **Portée** | 3 VM Azure (2 contrôleurs de domaine + 1 poste client), domaine `estiam.local` |
| **Région cible** | `norwayeast` |
| **Licence** | Usage pédagogique ESTIAM - voir [Licence](#licence) |
| **Mainteneur** | Projet étudiant ESTIAM (Administration Systèmes, Réseaux & DevOps) |

</div>

---

## Résumé exécutif

Ce dépôt déploie et configure, **sans aucune intervention manuelle**, une
infrastructure Active Directory d'entreprise complète sur Microsoft Azure :
annuaire redondant (2 contrôleurs de domaine), réseau segmenté et sans
exposition publique, poste client durci (GPO, AppLocker, BitLocker, LAPS),
serveur de fichiers avec quotas et sauvegarde, supervision temps réel, et
gestion centralisée des secrets. L'ensemble est pilotable par une seule
commande (`terraform apply`) et repose sur des pratiques d'Infrastructure
as Code standard (modules Terraform, état distant versionné, secrets hors
du code).

---

## Sommaire

1. [Architecture](#architecture)
2. [Coût estimé](#coût-estimé)
3. [Compatibilité](#compatibilité)
4. [Structure du dépôt](#structure-du-dépôt)
5. [Prérequis](#prérequis)
6. [Démarrage rapide](#démarrage-rapide)
7. [Séquencement du déploiement](#séquencement-du-déploiement)
8. [Détail des étapes d'automatisation serveur](#détail-des-étapes-dautomatisation-serveur)
9. [Référence des variables](#référence-des-variables)
10. [Objectifs de continuité (RTO/RPO)](#objectifs-de-continuité-rtorpo)
11. [Sécurité et gouvernance](#sécurité-et-gouvernance)
12. [Identifiants générés](#identifiants-générés)
13. [Dashboard de supervision](#dashboard-de-supervision)
14. [Tests et validation](#tests-et-validation)
15. [Runbook incidents](#runbook-incidents)
16. [Limitations connues et simplifications assumées](#limitations-connues-et-simplifications-assumées)
17. [Dépannage](#dépannage)
18. [Glossaire](#glossaire)
19. [Évolutions possibles](#évolutions-possibles)
20. [Contribution](#contribution)
21. [Licence](#licence)

---

## Architecture

<img width="1024" height="559" alt="image" src="https://github.com/user-attachments/assets/b1fd5658-ef68-49c9-ace8-fbae3f581c2d" />


**Principes de conception :**

- **Zero Trust réseau** - aucune VM n'a d'IP publique ; tout accès
  d'administration transite par Azure Bastion.
- **Secrets externalisés** - mot de passe admin et clé de stockage dans
  Key Vault, jamais en dur dans le code ; état Terraform dans un backend
  distant chiffré, jamais en local.
- **Idempotence** - chaque script de configuration peut être rejoué sans
  effet de bord, permettant une reprise automatique après incident.
- **Moindre privilège** - comptes utilisateur / admin / service séparés,
  délégation Helpdesk limitée, identités managées par VM plutôt que
  credentials partagés.

---

## Coût estimé

Estimation indicative (tarifs pay-as-you-go `norwayeast`, hors remises
négociées, à titre pédagogique - **toujours vérifier avec la
[calculatrice Azure](https://azure.microsoft.com/pricing/calculator/)
avant tout engagement budgétaire**) :

| Ressource | Quantité | Coût mensuel approximatif |
|---|---|---|
| VM `Standard_B2s` (2 vCPU, 4 Go) | 3 (SRV-AD01, DC02, PC-CLIENT01) | ~90 € |
| Disques managés `StandardSSD_LRS` | ~250 Go cumulés | ~20 € |
| Azure Bastion (SKU Basic) | 1 | ~130 € |
| Storage Account (scripts + état Terraform) | 2 comptes, usage faible | < 2 € |
| Key Vault | 1, usage faible | < 1 € |
| **Total indicatif** | | **≈ 240 €/mois** |

> Azure Bastion (SKU Basic) est le poste le plus coûteux du lab. Pour un
> usage ponctuel, envisagez de le désactiver (`enable_bastion = false`
> + `allowed_admin_source_ips`) et de le réactiver uniquement lors des
> sessions d'administration, ou d'arrêter (`az vm deallocate`) les VM en
> dehors des périodes de démonstration - Azure ne facture alors plus le
> calcul, seulement le stockage.

---

## Compatibilité

| Composant | Version testée / requise |
|---|---|
| Terraform | >= 1.6.0 |
| Provider `hashicorp/azurerm` | ~> 3.90 (Trusted Launch nécessite >= 3.30) |
| Provider `hashicorp/random` | ~> 3.6 |
| Provider `hashicorp/time` | ~> 0.11 |
| Contrôleurs de domaine | Windows Server 2022 Datacenter (image `2022-datacenter-g2`, Gen2) |
| Poste client | Windows 11 Entreprise (image `win11-23h2-ent`) |
| Windows LAPS natif | Nécessite les dernières mises à jour cumulatives Windows Server 2022 |

---

## Structure du dépôt

```
estiam-ad-infra/
├── bootstrap-backend/          Terraform minimal pour créer le backend distant
│   └── main.tf                 (état local, à exécuter UNE SEULE FOIS)
│
├── main.tf                     Assemblage des modules
├── variables.tf                Toutes les variables du projet
├── outputs.tf                  Sorties (IP, mots de passe, Key Vault...)
├── providers.tf / versions.tf  Configuration des providers Terraform
├── backend.tf                  Déclaration du backend distant azurerm
├── backend.hcl.example         Exemple de configuration du backend
├── terraform.tfvars.example    Exemple de variables (location, vm_size...)
│
├── modules/
│   ├── network/                Resource Group, VNet, Subnets
│   ├── security/                NSG, Azure Bastion
│   ├── storage/                 Storage Account privé (héberge les scripts PowerShell)
│   ├── keyvault/                Key Vault (secrets centralisés)
│   └── compute/                 VMs, disques, identités managées, extensions
│
├── scripts/                     Scripts PowerShell exécutés automatiquement
│   ├── common.psm1              Fonctions partagées (logs, stage machine...)
│   ├── 01-install-ad.ps1        Promotion de SRV-AD01 en DC1
│   ├── 01b-install-dc02.ps1     Promotion de DC02 en DC2 (réplique)
│   ├── Bootstrap-Server.ps1     Orchestrateur post-redémarrage (étapes 2 à 17)
│   ├── 02 … 17-*.ps1            Étapes de configuration (voir tableau détaillé)
│   ├── client-hardening.ps1     Durcissement + BitLocker sur PC-CLIENT01
│   └── users.csv                Base des utilisateurs à créer
│
├── RUNBOOK.md                   Procédures de récupération / incidents
├── CHANGELOG.md                 Historique des versions
├── CONTRIBUTING.md              Conventions de contribution
└── README.md                    Ce document
```

---

## Prérequis

| Outil / accès | Détail |
|---|---|
| Terraform | >= 1.6.0 |
| Azure CLI | pour `az login`, ou un Service Principal pour l'automatisation CI/CD |
| Abonnement Azure | avec quota suffisant pour 3 VM `Standard_B2s` |
| **Rôle Azure** | *Contributor* **+ *User Access Administrator*** (ou *Owner*) sur l'abonnement/resource group - nécessaire pour que Terraform puisse créer les attributions de rôle RBAC des identités managées |
| PowerShell / Bash | pour lancer les commandes `terraform` |

---

## Démarrage rapide

### Étape 0 - Backend Terraform distant (une seule fois)

L'état Terraform est stocké dans Azure Storage plutôt qu'en local, avec
versionnement des blobs (retour arrière possible) et verrouillage
automatique (empêche deux `apply` concurrents) :

```bash
cd bootstrap-backend
terraform init
terraform apply -auto-approve
terraform output backend_hcl_content
cd ..
cp backend.hcl.example backend.hcl
# Coller les valeurs de la sortie ci-dessus dans backend.hcl
```

### Étape 1 - Déploiement principal

```bash
terraform init -backend-config backend.hcl
cp terraform.tfvars.example terraform.tfvars   # adapter si besoin

export ARM_SUBSCRIPTION_ID="..."
export ARM_TENANT_ID="..."
export ARM_CLIENT_ID="..."       # si Service Principal
export ARM_CLIENT_SECRET="..."
export TF_VAR_admin_password="Un-Mot-De-Passe-Fort-2026!"  # sinon généré automatiquement

terraform plan && terraform apply -auto-approve
```

`location = "norwayeast"` et `vm_size = "Standard_B2s"` sont déjà les
valeurs par défaut dans `variables.tf` et `terraform.tfvars.example`.

**Durée estimée : 45 à 55 minutes** entre `terraform apply` et un
environnement pleinement opérationnel (promotion des deux contrôleurs de
domaine, redémarrages, attente de convergence, jonction du client,
durcissement, chiffrement BitLocker). Aucune intervention n'est requise
pendant ce délai.

### Vérifier le déploiement

```bash
terraform output
terraform output -raw admin_password   # affiche le mot de passe généré
```

Connectez-vous ensuite via **Azure Bastion** (portail Azure → Resource
Group → SRV-AD01 → Bastion) avec le compte `estiamadmin`.

### Démanteler l'environnement

```bash
terraform destroy
# Puis, si le backend distant n'est plus nécessaire :
cd bootstrap-backend && terraform destroy
```

---

## Séquencement du déploiement

```
Terraform
   │
   ├─► Réseau (VNet, Subnet, NSG, Bastion)
   ├─► Key Vault (secrets)
   ├─► Storage Account privé + upload des scripts PowerShell
   │
   ├─► SRV-AD01 (VM + identité managée + disques D:/E:)
   │      └─► CSE "01-install-ad.ps1"
   │             ├─ Installe AD DS
   │             ├─ Enregistre une tâche planifiée (survit au reboot)
   │             ├─ Install-ADDSForest ──► redémarrage automatique
   │             │
   │             └─► [après reboot] Bootstrap-Server.ps1 (tâche planifiée)
   │                    └─ Attend qu'AD soit prêt, puis déroule
   │                       les étapes 2 à 17 (voir tableau ci-dessous)
   │                       de façon idempotente, puis se désinscrit
   │
   ├─► time_sleep (35 min de sécurité)
   │
   ├─► DC02 (VM + identité managée)
   │      └─► CSE "01b-install-dc02.ps1"
   │             └─ Install-ADDSDomainController (réplique le domaine)
   │
   └─► PC-CLIENT01 (VM + identité managée)
          ├─► Extension JsonADDomainExtension (jonction au domaine)
          └─► CSE "client-hardening.ps1"
                 ├─ gpupdate /force
                 ├─ Démarre le service AppLocker
                 ├─ Active BitLocker (+ sauvegarde clé dans AD)
                 └─ Vérifications locales complémentaires
```

Tout est enchaîné automatiquement : le seul délai est le temps naturel de
démarrage/redémarrage des VM et de réplication Active Directory.

---

## Détail des étapes d'automatisation serveur

Exécutées dans l'ordre par `Bootstrap-Server.ps1`, chacune **idempotente**
(peut être relancée sans effet de bord en cas d'échec partiel) :

| # | Script | Ce qu'il fait |
|---|---|---|
| 1 | `01-install-ad.ps1` | Installe AD DS, promeut SRV-AD01 en 1er contrôleur de domaine (`estiam.local`) |
| 2 | `02-configure-dns.ps1` | Zone inversée, forwarders, client DNS local |
| 3 | `03-configure-dhcp.ps1` | Étendue DHCP, autorisation dans AD, options (passerelle, DNS, suffixe) |
| 4 | `04-create-ous.ps1` | Arborescence des unités d'organisation (Users, Groups, Computers, Servers, ServiceAccounts, AdminAccounts) |
| 5 | `05-create-groups.ps1` | Groupes de sécurité métier (`GG-ESTIAM-*`), ressources (`GG-FS-*-RW`), Helpdesk |
| 6 | `06-create-users.ps1` | Utilisateurs (CSV), comptes admin séparés (`adm-*`), compte de service (`svc-backup`), comptes temporaires |
| 7 | `07-create-shares.ps1` | Initialise le disque D:, partages SMB, dossiers personnels |
| 8 | `08-configure-permissions.ps1` | Matrice de permissions NTFS par groupe |
| 9 | `09-create-gpos.ps1` | GPO : sécurité, USB, terminal, Windows Update, Defender/Firewall, BitLocker, groupes restreints locaux |
| 10 | `10-configure-fsrm.ps1` | Quotas (2 Go/utilisateur), filtrage des exécutables sur les partages |
| 11 | `11-configure-shadowcopies-print.ps1` | Shadow Copies (2×/jour), serveur d'impression de démonstration |
| 12 | `12-configure-applocker.ps1` | Politique AppLocker (bloque l'exécution depuis Temp/Downloads) |
| 13 | `13-configure-laps.ps1` | Windows LAPS (mot de passe admin local unique, rotation 30 jours) |
| 14 | `14-configure-audit-delegation.ps1` | Politique d'audit, délégation Helpdesk (`dsacls`), désactivation des comptes inactifs |
| 15 | `15-configure-backup.ps1` | Windows Server Backup (disque E: dédié, quotidienne, D:\ + System State) |
| 16 | `16-configure-monitoring.ps1` | Dashboard HTML/CSS/JS (IIS) + collecteur de métriques |
| 17 | `17-run-security-checks.ps1` | ~25 vérifications automatisées, rapport PASS/FAIL |

En parallèle (déclenchés indépendamment par Terraform) :

| Composant | Script | Rôle |
|---|---|---|
| DC02 | `01b-install-dc02.ps1` | Réplique le domaine (2ᵉ contrôleur, haute disponibilité) |
| PC-CLIENT01 | `client-hardening.ps1` | Jonction, GPO immédiates, AppLocker, BitLocker |

---

## Référence des variables

Toutes définies dans `variables.tf`, valeurs par défaut déjà alignées sur
la demande initiale (`location = "norwayeast"`, `vm_size = "Standard_B2s"`).
Les plus utiles à ajuster :

| Variable | Défaut | Description |
|---|---|---|
| `location` | `norwayeast` | Région Azure |
| `vm_size` | `Standard_B2s` | Taille des 3 VM |
| `admin_username` | `estiamadmin` | Compte administrateur local + domaine |
| `admin_password` | *(vide → généré)* | Fournir via `TF_VAR_admin_password`, jamais en dur |
| `ad_domain_name` / `ad_netbios_name` | `estiam.local` / `ESTIAM` | Domaine Active Directory |
| `departments` | Direction, IT, RH, Finance, Marketing, Administration | Structure des OU/groupes |
| `enable_bastion` | `true` | Azure Bastion vs RDP direct restreint |
| `allowed_admin_source_ips` | `[]` | IP autorisées en RDP direct si Bastion désactivé |
| `enable_dhcp` | `true` | Active le rôle DHCP sur SRV-AD01 |
| `enable_second_dc` | `true` | Déploie DC02 (haute disponibilité) |
| `enable_bitlocker` | `true` | Trusted Launch (vTPM/Secure Boot) + chiffrement BitLocker |
| `key_vault_authorized_object_ids` | `[]` | Object IDs Azure AD humains autorisés à lire les secrets |

---

## Objectifs de continuité (RTO/RPO)

| Scénario | RPO cible (perte de données max.) | RTO cible (temps de restauration) | Mécanisme |
|---|---|---|---|
| Suppression accidentelle d'un fichier | ≤ 6 h | Quelques minutes | Shadow Copies (2 clichés/jour) |
| Perte du volume de partages (D:) | 24 h | 1 à 2 h | Windows Server Backup (quotidienne, disque E: dédié) |
| Panne du contrôleur de domaine principal | 0 (réplication temps quasi réel) | Quelques minutes (bascule sur DC02) | 2ᵉ contrôleur de domaine |
| Corruption Active Directory | 24 h | 2 à 4 h | Restauration System State + `dcdiag`/`repadmin` (voir Runbook) |
| Perte totale de la région Azure | N/A | N/A - hors périmètre actuel | Nécessiterait une réplication multi-région (non implémentée, voir Évolutions) |

> Ces objectifs sont indicatifs pour un contexte pédagogique. Un
> environnement de production nécessiterait une sauvegarde hors site
> (Azure Backup / Recovery Services Vault) pour se prémunir d'une perte de
> la VM ou du disque de sauvegarde lui-même.

---

## Sécurité et gouvernance

| Domaine | Mesures |
|---|---|
| **Identités** | Compte utilisateur / compte admin (`adm-*`) / compte de service (`svc-*`) strictement séparés ; comptes temporaires avec expiration ; désactivation auto des comptes inactifs (90 j) |
| **Mots de passe** | Politique de domaine (12 caractères, complexité, historique 10, verrouillage 5 tentatives) ; Windows LAPS pour l'admin local ; secrets centralisés dans Key Vault |
| **Accès réseau** | Aucune IP publique sur les VM ; Azure Bastion ; NSG avec refus explicite du trafic Internet entrant |
| **Poste client** | GPO : terminal/PowerShell restreints (sauf IT), USB bloqué, Autorun désactivé, SmartScreen actif, Panneau de configuration bloqué ; AppLocker (bloque Temp/Downloads) ; BitLocker (clé sauvegardée dans AD) ; aucun utilisateur standard n'est administrateur local |
| **Fichiers** | Permissions NTFS par groupe (moindre privilège) ; quotas FSRM ; filtrage des types de fichiers exécutables ; Shadow Copies |
| **Audit** | Politique d'audit (connexions, gestion des comptes, GPO, accès DS) publiée via GPO |
| **Délégation** | Groupe Helpdesk limité au reset mot de passe / déverrouillage, sans droits d'administration complets |
| **Continuité** | 2ᵉ contrôleur de domaine, sauvegarde quotidienne sur disque dédié, Shadow Copies |
| **Identités machine** | Chaque VM a une identité managée (accès Key Vault + Storage en lecture, principe du moindre privilège) |
| **IaC** | Backend Terraform distant versionné et verrouillé ; secrets jamais en dur dans le code |

---

## Identifiants générés

- Tous les mots de passe générés automatiquement (utilisateurs, comptes
  admin séparés, compte de service) sont stockés dans
  `C:\ESTIAM\generated-credentials.csv` sur `SRV-AD01`, avec un accès NTFS
  restreint aux administrateurs.
- Le mot de passe administrateur (local + domaine) est également disponible
  dans le **Key Vault ESTIAM**, secret `estiam-admin-password`.
- Le mot de passe administrateur local de chaque poste client est géré par
  **Windows LAPS** (lecture réservée au groupe `GG-ESTIAM-IT`).

Récupérez les identifiants une fois via Azure Bastion, puis supprimez ou
archivez le fichier CSV selon votre politique de sécurité.

---

## Dashboard de supervision

Un tableau de bord HTML/CSS/JS auto-hébergé (IIS, aucune dépendance
externe) est disponible sur :

```
http://10.10.10.10/estiam/
```

Rafraîchi toutes les 5 secondes, il affiche : CPU, RAM, espace disque,
statut des services (AD DS, DNS, DHCP, IIS, AppLocker), statistiques
Active Directory (utilisateurs, groupes, OU, comptes désactivés),
connexions échouées de la dernière heure, et le résultat des tests de
sécurité automatisés (étape 17).

---

## Tests et validation

Une fois le déploiement terminé, se connecter via Azure Bastion et
vérifier :

```powershell
nslookup estiam.local
repadmin /replsummary                 # réplication DC1 ↔ DC2
Get-ADUser -Filter * | Select Name,Enabled
Get-SmbShare
Get-BitLockerVolume
Get-Content C:\ESTIAM\security-check-report.json | ConvertFrom-Json
```

Sur `PC-CLIENT01`, se connecter avec `ESTIAM\jdupont` et vérifier :

- l'accès à `\\SRV-AD01\Direction` mais pas à `\\SRV-AD01\Finance` ;
- la restriction du terminal (`cmd`/`powershell` bloqués) ;
- le blocage d'une clé USB ;
- `gpresult /r` pour confirmer l'application des GPO.

---

## Runbook incidents

Voir [`RUNBOOK.md`](./RUNBOOK.md) pour les procédures détaillées :

- récupération d'un fichier supprimé (Shadow Copies / sauvegarde) ;
- restauration du System State après incident serveur ;
- déverrouillage / réinitialisation de mot de passe via le groupe Helpdesk ;
- vérification de santé globale de l'infrastructure ;
- procédure de test de restauration périodique (recommandé trimestriel).

---

## Limitations connues et simplifications assumées

Pour rester réaliste dans un contexte de lab étudiant, certains points
avancés sont implémentés avec des techniques volontairement robustes
plutôt que via des mécanismes plus fragiles à scripter de façon fiable :

- **Lecteurs réseau** : script de connexion NETLOGON + attribut
  `scriptPath`/`HomeDirectory` natif AD, plutôt que des Group Policy
  Preferences (Drive Maps) dont le format XML brut est plus difficile à
  générer sans l'interface GPMC.
- **Restriction de PowerShell** : stratégie "Ne pas exécuter les
  applications Windows spécifiées" (registre), complétée par AppLocker
  pour le blocage Temp/Downloads.
- **Groupe Administrateurs local des postes** : géré via un fichier
  `GptTmpl.inf` (Restricted Groups), technique standard à vérifier une
  fois via `gpresult /r`.
- **Windows LAPS** nécessite une mise à jour Windows Server 2022
  relativement récente pour le module natif ; si absent, l'étape 13 le
  signale dans les logs et s'arrête proprement (à rejouer après Windows
  Update).
- **Politique d'audit** appliquée via le même mécanisme `GptTmpl.inf` que
  les groupes restreints, plutôt que via l'interface graphique.
- **Délégation Helpdesk** appliquée via `dsacls.exe` ; vérifiez les droits
  obtenus après déploiement.
- **Test de restauration de sauvegarde** : une sauvegarde de validation
  est lancée automatiquement, mais un test de restauration complet reste
  une **procédure manuelle documentée** (voir Runbook) - restaurer en
  aveugle n'est jamais une bonne pratique, même automatisée.
- **Téléchargement des scripts par identité managée** : l'infrastructure
  (identité + rôle `Storage Blob Data Reader`) est en place, mais le
  téléchargement effectif par les Custom Script Extensions utilise encore
  la clé de compte de stockage (mécanisme éprouvé, déjà chiffré côté
  Azure). Le support du téléchargement de blobs par identité managée dans
  les CSE dépend de la version de l'extension - à vérifier dans la
  documentation Azure à jour avant de basculer dessus en production.
- **BitLocker / Trusted Launch** nécessite `azurerm` >= 3.30 et une image
  Gen2 (déjà le cas). Si le TPM n'est pas détecté, un protecteur par mot
  de passe de récupération est utilisé en secours (chiffrement actif, mais
  sans déverrouillage transparent au démarrage).
- **DC02** partage la même fenêtre d'attente (35 min) que la jonction du
  client, par simplicité ; sa promotion pourrait démarrer plus tôt en
  pratique.

---

## Dépannage

| Symptôme | Piste |
|---|---|
| L'extension `bootstrap-ad` reste "en cours" très longtemps | Normal : elle ne termine qu'après le premier redémarrage. Vérifier ensuite `C:\ESTIAM\Logs\estiam-bootstrap.log` via Bastion. |
| Le client ne rejoint pas le domaine | Vérifier que `time_sleep` (35 min) est bien écoulé et que le DNS du client résout `estiam.local` (`nslookup`). |
| Une étape échoue et bloque la suite | La tâche planifiée `ESTIAM-Bootstrap-Continue` réessaiera au prochain redémarrage. Consulter le log pour l'erreur exacte. |
| `terraform apply` échoue sur une attribution de rôle | Vérifier le rôle *User Access Administrator* / *Owner* de l'identité Terraform (voir Prérequis). |
| Windows LAPS ne s'active pas | Vérifier `Get-Module -ListAvailable LAPS` - nécessite une mise à jour Windows Server récente. |
| BitLocker ne chiffre pas | Vérifier `Get-Tpm` - le vTPM Trusted Launch doit être actif (`vtpm_enabled = true`). |

---

## Glossaire

| Terme | Définition |
|---|---|
| **AD DS** | Active Directory Domain Services - service d'annuaire Windows |
| **CSE** | Custom Script Extension - extension Azure exécutant un script au démarrage d'une VM |
| **DC** | Domain Controller - contrôleur de domaine |
| **FSRM** | File Server Resource Manager - quotas et filtrage de fichiers sur un serveur de fichiers |
| **GPO** | Group Policy Object - stratégie de groupe Active Directory |
| **Idempotent** | Se dit d'une opération qui produit le même résultat qu'elle soit exécutée une ou plusieurs fois |
| **IaC** | Infrastructure as Code - gestion de l'infrastructure par du code versionné |
| **LAPS** | Local Administrator Password Solution - rotation automatique des mots de passe admin locaux |
| **NSG** | Network Security Group - pare-feu réseau Azure |
| **RPO** | Recovery Point Objective - perte de données maximale tolérée |
| **RTO** | Recovery Time Objective - délai maximal de restauration toléré |
| **Trusted Launch** | Fonctionnalité Azure combinant vTPM et Secure Boot pour sécuriser le démarrage d'une VM |
| **vTPM** | Virtual Trusted Platform Module - module de sécurité matériel virtualisé, requis par BitLocker |

---

## Évolutions possibles

Liste complète des pistes envisagées (identité/MFA, DFS-R, Azure Backup,
WSUS, Sentinel, Azure Policy, CI/CD, JEA, AD CS...) disponible sur demande
- certaines nécessitent une évolution d'architecture plus large
(Entra Connect, second site, PKI interne) qui dépasse le périmètre initial
de ce lab étudiant.

---

## Contribution

Voir [`CONTRIBUTING.md`](./CONTRIBUTING.md) pour les conventions de
nommage, la structure attendue d'une modification, et la checklist de
relecture avant tout `terraform apply` en environnement partagé.

---

## Licence

Projet réalisé dans un cadre pédagogique (ESTIAM). Réutilisation et
adaptation libres à des fins d'apprentissage ; aucune garantie n'est
fournie quant à une utilisation en environnement de production sans
revue de sécurité préalable.
