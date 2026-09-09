<#
.SYNOPSIS
    Etape 14 : politique d'audit AD (section "Audit Active Directory"),
    delegation d'administration Helpdesk (reset mdp / deverrouillage
    uniquement), et desactivation automatique des comptes inactifs
    (cycle de vie utilisateur). Idempotent.
#>
param([Parameter(Mandatory = $true)]$Config)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\common.psm1" -Force
Import-Module ActiveDirectory -ErrorAction Stop
Import-Module GroupPolicy -ErrorAction Stop

$domain     = Get-ADDomain
$domainDN   = $domain.DistinguishedName
$domainName = $domain.DNSRoot
$usersOuDN  = "OU=Users,OU=ESTIAM,$domainDN"

# =============================================================================
# Politique d'audit (categories de base) via GptTmpl.inf, meme technique que
# pour les groupes restreints (section 09) : 0=aucun, 1=succes, 2=echec, 3=les deux
# =============================================================================
$gpo = Get-GPO -Name "GPO-ESTIAM-Audit-Policy" -ErrorAction SilentlyContinue
if (-not $gpo) {
    $gpo = New-GPO -Name "GPO-ESTIAM-Audit-Policy" -Comment "Genere automatiquement - ESTIAM Audit"
    Write-EstiamLog "GPO creee : GPO-ESTIAM-Audit-Policy" "AUDIT"
}

$gpoGuid = (Get-GPO -Name $gpo.DisplayName).Id.ToString("B").ToUpper()
$sysvolMachinePath = "\\$domainName\SYSVOL\$domainName\Policies\$gpoGuid\Machine\Microsoft\Windows NT\SecEdit"
New-Item -ItemType Directory -Path $sysvolMachinePath -Force | Out-Null
$gptTmplPath = Join-Path $sysvolMachinePath "GptTmpl.inf"

$gptTmplContent = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Event Audit]
AuditSystemEvents=3
AuditLogonEvents=3
AuditObjectAccess=2
AuditPrivilegeUse=2
AuditPolicyChange=3
AuditAccountManage=3
AuditProcessTracking=0
AuditDSAccess=3
AuditAccountLogon=3
"@
Set-Content -Path $gptTmplPath -Value $gptTmplContent -Encoding Unicode
Write-EstiamLog "Politique d'audit ecrite (connexions, gestion des comptes, GPO, DS Access, systeme)." "AUDIT"

$gpoAdPath = "CN=$($gpoGuid),CN=Policies,CN=System,$domainDN"
$secCse = "[{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}]"
try {
    Set-ADObject -Identity $gpoAdPath -Replace @{ gPCMachineExtensionNames = $secCse }
    $gpoObj = Get-ADObject -Identity $gpoAdPath -Properties versionNumber
    $newVersion = [int]$gpoObj.versionNumber + 1
    Set-ADObject -Identity $gpoAdPath -Replace @{ versionNumber = $newVersion }
    "[General]`r`nVersion=$newVersion" | Set-Content -Path "\\$domainName\SYSVOL\$domainName\Policies\$gpoGuid\GPT.INI" -Encoding ASCII
    Write-EstiamLog "GPO d'audit publiee (version $newVersion)." "AUDIT"
} catch {
    Write-EstiamLog "Avertissement publication GPO audit : $($_.Exception.Message)" "AUDIT"
}

$existing = Get-GPInheritance -Target "OU=ESTIAM,$domainDN" | Select-Object -ExpandProperty GpoLinks
if (-not ($existing | Where-Object { $_.DisplayName -eq $gpo.DisplayName })) {
    New-GPLink -Name $gpo.DisplayName -Target "OU=ESTIAM,$domainDN" -LinkEnabled Yes | Out-Null
    Write-EstiamLog "GPO d'audit liee a OU=ESTIAM." "AUDIT"
}

# =============================================================================
# Delegation Helpdesk : reset mot de passe + deverrouillage de compte
# UNIQUEMENT (pas de droits d'administration complets) sur OU=Users.
# =============================================================================
Write-EstiamLog "Delegation des droits Helpdesk (reset mdp / deverrouillage) sur $usersOuDN..." "DELEGATION"
try {
    dsacls.exe $usersOuDN /I:S /G "$($Config.NetbiosName)\GG-ESTIAM-HELPDESK:CA;Reset Password;user" | Out-Null
    dsacls.exe $usersOuDN /I:S /G "$($Config.NetbiosName)\GG-ESTIAM-HELPDESK:WP;lockoutTime;user" | Out-Null
    dsacls.exe $usersOuDN /I:S /G "$($Config.NetbiosName)\GG-ESTIAM-HELPDESK:WP;pwdLastSet;user" | Out-Null
    Write-EstiamLog "Delegation Helpdesk appliquee (dsacls) : reset mdp + deverrouillage de compte." "DELEGATION"
} catch {
    Write-EstiamLog "Avertissement delegation Helpdesk : $($_.Exception.Message)" "DELEGATION"
}

# =============================================================================
# Cycle de vie utilisateur : desactivation automatique des comptes inactifs
# depuis plus de 90 jours (hors comptes de service/admin, prefixes svc-/adm-).
# =============================================================================
$inactiveScriptPath = "$Global:EstiamRoot\Scripts\Disable-InactiveAccounts.ps1"
$inactiveScriptContent = @'
Import-Module ActiveDirectory
$domainDN = (Get-ADDomain).DistinguishedName
$usersOuDN = "OU=Users,OU=ESTIAM,$domainDN"
$threshold = (Get-Date).AddDays(-90)

$inactive = Search-ADAccount -SearchBase $usersOuDN -AccountInactive -UsersOnly -TimeSpan (New-TimeSpan -Days 90) |
    Where-Object { $_.Enabled -eq $true -and $_.SamAccountName -notmatch '^(adm-|svc-)' }

foreach ($acct in $inactive) {
    Disable-ADAccount -Identity $acct.SamAccountName
    $logPath = "C:\ESTIAM\Logs\estiam-bootstrap.log"
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][LIFECYCLE] Compte desactive pour inactivite (>90j) : $($acct.SamAccountName)"
    Add-Content -Path $logPath -Value $line
}
'@
Set-Content -Path $inactiveScriptPath -Value $inactiveScriptContent -Encoding UTF8

$taskName = "ESTIAM-Disable-Inactive-Accounts"
if (-not (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Unrestricted -File `"$inactiveScriptPath`""
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "03:00"
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal | Out-Null
    Write-EstiamLog "Tache planifiee '$taskName' creee (verification hebdomadaire, dimanche 03h00)." "LIFECYCLE"
}

Write-EstiamLog "Configuration audit + delegation + cycle de vie terminee." "AUDIT-DELEGATION"
