<#
.SYNOPSIS
    Etape 1 : installe le role AD DS + DNS et promeut SRV-AD01 en premier
    controleur de domaine de la nouvelle foret (ex : estiam.local).

.DESCRIPTION
    A executer UNE SEULE FOIS, en administrateur, sur SRV-AD01.
    Le serveur REDEMARRE automatiquement a la fin de la promotion.
    Attendre 5 a 10 minutes apres le redemarrage (le temps qu'AD Web Services
    demarre), puis lancer les etapes suivantes (03-dns, 04-dhcp, ...) ou
    directement ..\Run-All.ps1.

    Le domaine, le nom NetBIOS, etc. sont lus dans ..\00-common\config.json.

.PARAMETER SafeModePassword
    Mot de passe DSRM (mode restauration des services d'annuaire), SecureString.
    S'il n'est pas fourni, il est demande de facon interactive.

.PARAMETER ConfigPath
    Chemin d'un config.json alternatif (facultatif).

.EXAMPLE
    .\01-install-ad.ps1
#>
#Requires -RunAsAdministrator
param(
    [SecureString]$SafeModePassword,
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
Import-Module "$PSScriptRoot\..\00-common\common.psm1" -Force
$Config = Get-EstiamConfig -Path $ConfigPath

Initialize-EstiamPaths
Write-EstiamLog "=== Debut 01-install-ad.ps1 ===" "AD-INSTALL"

# Garde-fou : ne rien faire si le serveur est deja controleur de domaine
# (DomainRole 4 = DC de secours, 5 = DC principal).
$domainRole = (Get-CimInstance -ClassName Win32_ComputerSystem).DomainRole
if ($domainRole -ge 4) {
    Write-EstiamLog "Ce serveur est deja controleur de domaine, rien a faire." "AD-INSTALL"
    return
}

if (-not $SafeModePassword) {
    $SafeModePassword = Read-Host -Prompt "Mot de passe DSRM (mode restauration AD)" -AsSecureString
}

# 1. Installer les roles necessaires
Write-EstiamLog "Installation des roles AD-Domain-Services, DNS, RSAT, GPMC..." "AD-INSTALL"
$feature = Install-WindowsFeature -Name AD-Domain-Services, DNS, RSAT-AD-Tools, RSAT-DNS-Server, GPMC -IncludeManagementTools
if (-not $feature.Success) {
    throw "Echec de l'installation des roles AD DS / DNS."
}

# 2. Promotion en controleur de domaine (foret racine). Redemarrage automatique.
Write-EstiamLog "Lancement de Install-ADDSForest pour $($Config.DomainName) (redemarrage automatique a la fin)..." "AD-INSTALL"

Install-ADDSForest `
    -DomainName $Config.DomainName `
    -DomainNetbiosName $Config.NetbiosName `
    -SafeModeAdministratorPassword $SafeModePassword `
    -InstallDns:$true `
    -DatabasePath "C:\Windows\NTDS" `
    -LogPath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -Force:$true `
    -NoRebootOnCompletion:$false
