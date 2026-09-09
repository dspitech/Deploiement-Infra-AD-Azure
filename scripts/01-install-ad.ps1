<#
.SYNOPSIS
    Etape 1 : installe le role AD DS, promeut le serveur en controleur de
    domaine pour la foret estiam.local, et enregistre la suite de
    l'orchestration (DNS/DHCP/OU/users/shares/permissions/GPO) sous forme de
    tache planifiee qui reprendra automatiquement au redemarrage.
.NOTES
    Execute une seule fois par la Custom Script Extension Terraform.
#>
param(
    # Configuration encodee en Base64 (JSON) pour eviter tout probleme
    # d'echappement de guillemets/caracteres speciaux via cmd.exe (le mot de
    # passe genere automatiquement peut contenir des caracteres speciaux).
    [Parameter(Mandatory = $true)][string]$ConfigBase64
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\common.psm1" -Force

$json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ConfigBase64))
$cfg  = $json | ConvertFrom-Json

$DomainName       = $cfg.DomainName
$NetbiosName      = $cfg.NetbiosName
$SafeModePassword = $cfg.SafeModePassword
$AdminUsername    = $cfg.AdminUsername
$AdminPassword    = $cfg.AdminPassword
$DepartmentsCsv   = $cfg.DepartmentsCsv
$EnableDhcp       = [bool]$cfg.EnableDhcp
$DhcpScopeStart   = $cfg.DhcpScopeStart
$DhcpScopeEnd     = $cfg.DhcpScopeEnd
$DhcpGateway      = $cfg.DhcpGateway
$ServerIp         = $cfg.ServerIp

Initialize-EstiamPaths
Write-EstiamLog "=== Debut 01-install-ad.ps1 ===" "AD-INSTALL"

# 1. Copier tous les scripts vers un emplacement persistant (le dossier de
#    telechargement de la CSE n'est pas garanti stable apres reboot).
$persistentScripts = "$Global:EstiamRoot\Scripts"
New-Item -ItemType Directory -Path $persistentScripts -Force | Out-Null
Copy-Item -Path "$here\*.ps1", "$here\*.psm1", "$here\*.csv" -Destination $persistentScripts -Force
Write-EstiamLog "Scripts copies vers $persistentScripts" "AD-INSTALL"

# 2. Sauvegarder la configuration pour que Bootstrap-Server.ps1 (relance via
#    tache planifiee, donc sans les parametres originaux) puisse les relire.
$config = [PSCustomObject]@{
    DomainName       = $DomainName
    NetbiosName      = $NetbiosName
    AdminUsername    = $AdminUsername
    AdminPassword    = $AdminPassword
    DepartmentsCsv   = $DepartmentsCsv
    EnableDhcp       = $EnableDhcp
    DhcpScopeStart   = $DhcpScopeStart
    DhcpScopeEnd     = $DhcpScopeEnd
    DhcpGateway      = $DhcpGateway
    ServerIp         = $ServerIp
}
$config | ConvertTo-Json | Set-Content -Path "$Global:EstiamRoot\config.json" -Encoding UTF8
Write-EstiamLog "Configuration persistee dans $Global:EstiamRoot\config.json" "AD-INSTALL"

# 3. Installer les roles necessaires
Write-EstiamLog "Installation des roles AD-Domain-Services, DNS, RSAT..." "AD-INSTALL"
Install-WindowsFeature -Name AD-Domain-Services, DNS, RSAT-AD-Tools, RSAT-DNS-Server, GPMC -IncludeManagementTools | Out-Null

# 4. Enregistrer la tache planifiee de continuation (executee par SYSTEM a
#    chaque demarrage ; Bootstrap-Server.ps1 se desenregistre lui-meme une
#    fois toutes les etapes terminees - voir stage machine dans common.psm1).
$taskName = "ESTIAM-Bootstrap-Continue"
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Unrestricted -File `"$persistentScripts\Bootstrap-Server.ps1`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
Write-EstiamLog "Tache planifiee '$taskName' enregistree (demarrage automatique)." "AD-INSTALL"

Set-EstiamStage -Stage 1

# 5. Promotion en controleur de domaine (foret racine). Le redemarrage est
#    automatique : la suite s'execute via la tache planifiee ci-dessus.
Write-EstiamLog "Lancement de Install-ADDSForest pour le domaine $DomainName (redemarrage automatique)..." "AD-INSTALL"

$secureSafeModePwd = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force

Install-ADDSForest `
    -DomainName $DomainName `
    -DomainNetbiosName $NetbiosName `
    -SafeModeAdministratorPassword $secureSafeModePwd `
    -InstallDns:$true `
    -DatabasePath "C:\Windows\NTDS" `
    -LogPath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -Force:$true `
    -NoRebootOnCompletion:$false
