<#
.SYNOPSIS
    Etape optionnelle : promeut DC02 en second controleur de domaine du
    domaine cree par SRV-AD01 (haute disponibilite AD).

.DESCRIPTION
    A executer sur DC02 (VM deployee par Terraform avec enable_second_dc = true),
    en administrateur, APRES que SRV-AD01 est promu et operationnel.
    Le serveur redemarre automatiquement a la fin. Une fois promu, DC02
    replique automatiquement OU / utilisateurs / groupes / GPO depuis SRV-AD01.

.PARAMETER DomainCredential
    Compte administrateur du domaine (ex : ESTIAM\estiamadmin). Demande si absent.

.PARAMETER SafeModePassword
    Mot de passe DSRM de DC02 (SecureString). Demande si absent.

.PARAMETER ConfigPath
    Chemin d'un config.json alternatif (facultatif).
#>
#Requires -RunAsAdministrator
param(
    [PSCredential]$DomainCredential,
    [SecureString]$SafeModePassword,
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
Import-Module "$PSScriptRoot\..\00-common\common.psm1" -Force
$Config = Get-EstiamConfig -Path $ConfigPath

Initialize-EstiamPaths
Write-EstiamLog "=== Debut 02-install-dc02.ps1 ===" "DC02"

$domainRole = (Get-CimInstance -ClassName Win32_ComputerSystem).DomainRole
if ($domainRole -ge 4) {
    Write-EstiamLog "Ce serveur est deja controleur de domaine, rien a faire." "DC02"
    return
}

if (-not $DomainCredential) {
    $DomainCredential = Get-Credential -Message "Administrateur du domaine $($Config.DomainName)" -UserName "$($Config.NetbiosName)\estiamadmin"
}
if (-not $SafeModePassword) {
    $SafeModePassword = Read-Host -Prompt "Mot de passe DSRM de DC02" -AsSecureString
}

Write-EstiamLog "Installation des roles AD-Domain-Services, DNS, RSAT, GPMC..." "DC02"
$feature = Install-WindowsFeature -Name AD-Domain-Services, DNS, RSAT-AD-Tools, RSAT-DNS-Server, GPMC -IncludeManagementTools
if (-not $feature.Success) {
    throw "Echec de l'installation des roles AD DS / DNS."
}

# SRV-AD01 doit etre joignable ET resoudre le domaine (le DNS de la NIC de
# DC02 pointe deja sur SRV-AD01 grace a Terraform).
Write-EstiamLog "Verification que SRV-AD01 ($($Config.ServerIp)) est joignable..." "DC02"
if (-not (Test-Connection -ComputerName $Config.ServerIp -Count 2 -Quiet -ErrorAction SilentlyContinue)) {
    throw "SRV-AD01 ($($Config.ServerIp)) injoignable. Verifier qu'il est demarre et promu."
}
try {
    Resolve-DnsName -Name $Config.DomainName -ErrorAction Stop | Out-Null
} catch {
    throw "Le domaine $($Config.DomainName) n'est pas resolu par le DNS. SRV-AD01 est-il pleinement operationnel ?"
}

Write-EstiamLog "Promotion de DC02 en second controleur de domaine pour $($Config.DomainName) (redemarrage automatique)..." "DC02"
Install-ADDSDomainController `
    -DomainName $Config.DomainName `
    -Credential $DomainCredential `
    -SafeModeAdministratorPassword $SafeModePassword `
    -InstallDns:$true `
    -DatabasePath "C:\Windows\NTDS" `
    -LogPath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -NoGlobalCatalog:$false `
    -Force:$true `
    -NoRebootOnCompletion:$false
