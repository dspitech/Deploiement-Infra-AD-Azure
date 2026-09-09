# Changelog

Toutes les évolutions notables de ce projet sont documentées ici.
Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/).

## [1.2.0] - Résilience et sécurité renforcée

### Ajouté
- **Backend Terraform distant** (`bootstrap-backend/`) : état stocké dans
  Azure Storage, versionné et verrouillé.
- **Module `keyvault`** : centralise le mot de passe admin et la clé du
  compte de stockage.
- **Identité managée** sur les 3 VM, avec accès en lecture au Key Vault et
  rôle `Storage Blob Data Reader`.
- **BitLocker** (Trusted Launch : vTPM + Secure Boot) sur les 3 VM, clé de
  récupération sauvegardée dans Active Directory (GPO `GPO-ESTIAM-BitLocker`).
- **DC02** : second contrôleur de domaine pour la haute disponibilité de
  l'annuaire (`01b-install-dc02.ps1`).

## [1.1.0] - Fonctionnalités avancées

### Ajouté
- Comptes d'administration séparés (`adm-*`), comptes de service (`svc-*`),
  comptes temporaires avec expiration, `HomeDirectory` natif AD.
- **FSRM** : quotas (2 Go/utilisateur), filtrage des fichiers exécutables.
- **Shadow Copies** (2 clichés/jour) et serveur d'impression de démonstration.
- **AppLocker** : blocage de l'exécution depuis `%TEMP%`/`Downloads`.
- **Windows LAPS** : rotation automatique du mot de passe admin local.
- Politique d'audit AD, délégation Helpdesk (`dsacls`), désactivation
  automatique des comptes inactifs.
- **Windows Server Backup** : sauvegarde quotidienne vers un disque dédié.
- **Dashboard de supervision** HTML/CSS/JS auto-hébergé (IIS).
- Script de tests de sécurité automatisés (~25 vérifications).

## [1.0.0] - Version initiale

### Ajouté
- Modules Terraform : `network`, `security`, `storage`, `compute`.
- Déploiement automatisé d'un contrôleur de domaine (`estiam.local`) et
  d'un poste client joint au domaine, sans étape manuelle.
- Scripts PowerShell auto-orchestrés (installation AD DS, DNS, DHCP, OU,
  groupes, utilisateurs, partages, permissions NTFS, GPO de base).
- Azure Bastion pour l'administration sans exposition RDP publique.
