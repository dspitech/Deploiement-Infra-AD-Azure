<#
.SYNOPSIS
    Promeut DC02 en second controleur de domaine du domaine estiam.local
    deja cree par SRV-AD01 (haute disponibilite AD - pas de point de
    defaillance unique). Redemarrage automatique en fin de script.
    A la difference de SRV-AD01, DC02 n'a pas besoin d'orchestration
    multi-etapes post-redemarrage : une fois promu, il replique
    automatiquement OU/utilisateurs/groupes/GPO depuis SRV-AD01.
#>
param([Parameter(Mandatory = $true)][string]$ConfigBase64)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\common.psm1" -Force

$json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ConfigBase64))
$cfg  = $json | ConvertFrom-Json

Initialize-EstiamPaths
Write-EstiamLog "=== Debut 01b-install-dc02.ps1 ===" "DC02"

Write-EstiamLog "Installation du role AD-Domain-Services..." "DC02"
Install-WindowsFeature -Name AD-Domain-Services, DNS, RSAT-AD-Tools, RSAT-DNS-Server, GPMC -IncludeManagementTools | Out-Null

Write-EstiamLog "Attente que SRV-AD01 (10.10.10.10) soit joignable et resolve le domaine..." "DC02"
$elapsed = 0
while ($elapsed -lt 600) {
    if (Test-Connection -ComputerName $cfg.PrimaryDcIp -Count 1 -Quiet -ErrorAction SilentlyContinue) { break }
    Start-Sleep -Seconds 10
    $elapsed += 10
}

$domainCred = New-Object System.Management.Automation.PSCredential(
    "$($cfg.NetbiosName)\$($cfg.AdminUsername)",
    (ConvertTo-SecureString $cfg.AdminPassword -AsPlainText -Force)
)
$secureSafeModePwd = ConvertTo-SecureString $cfg.SafeModePassword -AsPlainText -Force

Write-EstiamLog "Promotion de DC02 en second controleur de domaine pour $($cfg.DomainName)..." "DC02"
Install-ADDSDomainController `
    -DomainName $cfg.DomainName `
    -Credential $domainCred `
    -SafeModeAdministratorPassword $secureSafeModePwd `
    -InstallDns:$true `
    -DatabasePath "C:\Windows\NTDS" `
    -LogPath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -NoGlobalCatalog:$false `
    -Force:$true `
    -NoRebootOnCompletion:$false
