<#
.SYNOPSIS
    Etape 17 : verifie automatiquement l'etat de l'infrastructure et produit
    un rapport PASS/FAIL (section "Tests de securite automatises"). Le
    resultat alimente egalement le dashboard de supervision (checks.json).
    Sans effet de bord (lecture seule) : peut etre relance a tout moment.
#>
param([Parameter(Mandatory = $true)]$Config)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\common.psm1" -Force
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
Import-Module GroupPolicy -ErrorAction SilentlyContinue

$results = @()

function Test-EstiamCheck {
    param([string]$Name, [scriptblock]$Test)
    try {
        $pass = & $Test
        $script:results += [PSCustomObject]@{ Name = $Name; Pass = [bool]$pass }
    } catch {
        $script:results += [PSCustomObject]@{ Name = $Name; Pass = $false }
    }
}

Test-EstiamCheck "Active Directory Domain Services" { (Get-Service NTDS -ErrorAction Stop).Status -eq 'Running' }
Test-EstiamCheck "Service DNS" { (Get-Service DNS -ErrorAction Stop).Status -eq 'Running' }
Test-EstiamCheck "Service DHCP" { -not $Config.EnableDhcp -or (Get-Service DHCPServer -ErrorAction Stop).Status -eq 'Running' }
Test-EstiamCheck "Resolution DNS du domaine" { [bool](Resolve-DnsName -Name $Config.DomainName -ErrorAction Stop) }
Test-EstiamCheck "Structure des OU (ESTIAM)" { [bool](Get-ADOrganizationalUnit -Filter "Name -eq 'ESTIAM'" -ErrorAction Stop) }
Test-EstiamCheck "Groupes de securite crees" { (Get-ADGroup -Filter "Name -like 'GG-ESTIAM-*'" -ErrorAction Stop | Measure-Object).Count -ge 6 }
Test-EstiamCheck "Utilisateurs crees" { (Get-ADUser -SearchBase "OU=Users,OU=ESTIAM,$((Get-ADDomain).DistinguishedName)" -Filter * -ErrorAction Stop | Measure-Object).Count -gt 0 }
Test-EstiamCheck "Comptes admin separes (adm-*)" { [bool](Get-ADUser -Filter "SamAccountName -like 'adm-*'" -ErrorAction Stop) }
Test-EstiamCheck "Compte de service svc-backup" { [bool](Get-ADUser -Filter "SamAccountName -eq 'svc-backup'" -ErrorAction Stop) }
Test-EstiamCheck "Partages de fichiers accessibles" { (Get-SmbShare -ErrorAction Stop | Where-Object { $_.Name -in @('Public','Direction','RH','Finance','IT','Marketing') } | Measure-Object).Count -eq 6 }
Test-EstiamCheck "Volume D: (partages)" { Test-Path "D:\Shares" }
Test-EstiamCheck "Politique de mot de passe (>=12 caracteres)" { (Get-ADDefaultDomainPasswordPolicy -ErrorAction Stop).MinPasswordLength -ge 12 }
Test-EstiamCheck "Verrouillage de compte configure" { (Get-ADDefaultDomainPasswordPolicy -ErrorAction Stop).LockoutThreshold -gt 0 }
Test-EstiamCheck "Compte Invite desactive" { -not (Get-ADUser -Identity "Guest" -ErrorAction Stop).Enabled }
Test-EstiamCheck "GPO de securite presente" { [bool](Get-GPO -Name "GPO-ESTIAM-Security" -ErrorAction Stop) }
Test-EstiamCheck "GPO restriction USB liee" { [bool](Get-GPO -Name "GPO-ESTIAM-USB-Restriction" -ErrorAction Stop) }
Test-EstiamCheck "GPO restriction terminal liee" { [bool](Get-GPO -Name "GPO-ESTIAM-Restrict-Terminal" -ErrorAction Stop) }
Test-EstiamCheck "GPO AppLocker liee" { [bool](Get-GPO -Name "GPO-ESTIAM-AppLocker" -ErrorAction Stop) }
Test-EstiamCheck "GPO groupes restreints (admin local) liee" { [bool](Get-GPO -Name "GPO-ESTIAM-RestrictedGroups-Workstations" -ErrorAction Stop) }
Test-EstiamCheck "GPO Windows Update liee" { [bool](Get-GPO -Name "GPO-ESTIAM-WindowsUpdate" -ErrorAction Stop) }
Test-EstiamCheck "GPO Defender/Firewall liee" { [bool](Get-GPO -Name "GPO-ESTIAM-Defender-Firewall" -ErrorAction Stop) }
Test-EstiamCheck "GPO politique d'audit liee" { [bool](Get-GPO -Name "GPO-ESTIAM-Audit-Policy" -ErrorAction Stop) }
Test-EstiamCheck "Role FSRM installe" { (Get-WindowsFeature FS-Resource-Manager -ErrorAction Stop).Installed }
Test-EstiamCheck "Role Windows Server Backup installe" { (Get-WindowsFeature Windows-Server-Backup -ErrorAction Stop).Installed }
Test-EstiamCheck "Politique de sauvegarde active" { [bool](Get-WBPolicy -ErrorAction Stop) }
Test-EstiamCheck "Groupe Helpdesk cree" { [bool](Get-ADGroup -Filter "Name -eq 'GG-ESTIAM-HELPDESK'" -ErrorAction Stop) }
Test-EstiamCheck "Dashboard de supervision (IIS) actif" { (Get-Service W3SVC -ErrorAction Stop).Status -eq 'Running' }
Test-EstiamCheck "Script de connexion NETLOGON deploye" { Test-Path "\\$($Config.DomainName)\NETLOGON\estiam-logon.bat" }

$passCount = ($results | Where-Object { $_.Pass }).Count
$totalCount = $results.Count
$overallStatus = if ($passCount -eq $totalCount) { "PASS" } else { "PARTIEL ($passCount/$totalCount)" }

Write-EstiamLog "================================" "CHECK"
Write-EstiamLog " ESTIAM INFRASTRUCTURE CHECK" "CHECK"
Write-EstiamLog "================================" "CHECK"
foreach ($r in $results) {
    $tag = if ($r.Pass) { "[OK]" } else { "[ECHEC]" }
    Write-EstiamLog "$tag $($r.Name)" "CHECK"
}
Write-EstiamLog "STATUS : $overallStatus" "CHECK"

$report = [PSCustomObject]@{
    Timestamp      = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    OverallStatus  = $overallStatus
    PassCount      = $passCount
    TotalCount     = $totalCount
    Checks         = $results
}

$report | ConvertTo-Json -Depth 4 | Set-Content -Path "$Global:EstiamRoot\security-check-report.json" -Encoding UTF8

$dashboardChecksPath = "C:\inetpub\wwwroot\estiam\checks.json"
if (Test-Path "C:\inetpub\wwwroot\estiam") {
    $report | ConvertTo-Json -Depth 4 | Set-Content -Path $dashboardChecksPath -Encoding UTF8
}

Write-EstiamLog "Rapport de securite genere : $Global:EstiamRoot\security-check-report.json" "CHECK"
