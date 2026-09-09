<#
.SYNOPSIS
    Etape 12 : politique AppLocker sur les postes de travail - autorise
    l'execution standard (Windows, Program Files, Administrateurs) et
    bloque explicitement l'execution depuis les dossiers Temp/Downloads.
    Complement des restrictions Terminal/USB.
    Construite via XML (format natif AppLocker, plus fiable a generer que
    des objets .NET) puis publiee sur la GPO via Set-AppLockerPolicy -Ldap.
    Idempotent.
#>
param([Parameter(Mandatory = $true)]$Config)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\common.psm1" -Force
Import-Module GroupPolicy -ErrorAction Stop
Import-Module AppLocker -ErrorAction Stop

$domainDN         = (Get-ADDomain).DistinguishedName
$workstationsOuDN = "OU=Workstations,OU=Computers,OU=ESTIAM,$domainDN"

$gpo = Get-GPO -Name "GPO-ESTIAM-AppLocker" -ErrorAction SilentlyContinue
if (-not $gpo) {
    $gpo = New-GPO -Name "GPO-ESTIAM-AppLocker" -Comment "Genere automatiquement - ESTIAM AppLocker"
    Write-EstiamLog "GPO creee : GPO-ESTIAM-AppLocker" "APPLOCKER"
}
$gpoLdapPath = "LDAP://$($gpo.Path)"

# Regles Exe : autoriser Windows/Program Files/Administrateurs (regles par
# defaut recommandees par Microsoft, indispensables pour ne pas bloquer le
# systeme), puis bloquer explicitement Temp/Downloads pour tout le monde.
$policyXml = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePathRule Id="921cc481-6e17-4653-8f75-050b80acca20" Name="(Regle par defaut) Dossier Windows" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%WINDIR%\*" /></Conditions>
    </FilePathRule>
    <FilePathRule Id="a61c8b2c-a319-4cd0-9690-d2177cad7b51" Name="(Regle par defaut) Dossier Program Files" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%PROGRAMFILES%\*" /></Conditions>
    </FilePathRule>
    <FilePathRule Id="fd686d83-a829-4351-8ff4-27c7de5755d2" Name="(Regle par defaut) Administrateurs - tout" Description="" UserOrGroupSid="S-1-5-32-544" Action="Allow">
      <Conditions><FilePathCondition Path="*" /></Conditions>
    </FilePathRule>
    <FilePathRule Id="3d5a2c39-4b8e-4a2a-9c1a-1e6a1f9b6c11" Name="ESTIAM - Bloque execution depuis Temp" Description="Protection contre les executables telecharges/temporaires" UserOrGroupSid="S-1-1-0" Action="Deny">
      <Conditions><FilePathCondition Path="%OSDRIVE%\Users\*\AppData\Local\Temp\*" /></Conditions>
    </FilePathRule>
    <FilePathRule Id="6b6a6e2b-2f0e-4a68-9d3a-2f8a7a8b9c22" Name="ESTIAM - Bloque execution depuis Downloads" Description="Protection contre les executables telecharges" UserOrGroupSid="S-1-1-0" Action="Deny">
      <Conditions><FilePathCondition Path="%OSDRIVE%\Users\*\Downloads\*" /></Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
"@

$policyFile = "$Global:EstiamRoot\applocker-policy.xml"
Set-Content -Path $policyFile -Value $policyXml -Encoding UTF8

try {
    Set-AppLockerPolicy -XMLPolicy $policyFile -Ldap $gpoLdapPath
    Write-EstiamLog "Politique AppLocker publiee sur GPO-ESTIAM-AppLocker (Allow Windows/ProgramFiles/Admins, Deny Temp/Downloads)." "APPLOCKER"
} catch {
    Write-EstiamLog "Avertissement publication AppLocker : $($_.Exception.Message)" "APPLOCKER"
}

# Le service "Application Identity" (AppIDSvc) doit tourner sur les clients
# pour qu'AppLocker soit applique (demarrage force via GPO + client-hardening.ps1).
Set-GPRegistryValue -Name $gpo.DisplayName -Key "HKLM\System\CurrentControlSet\Services\AppIDSvc" `
    -ValueName "Start" -Type DWord -Value 2 | Out-Null

$existing = Get-GPInheritance -Target $workstationsOuDN | Select-Object -ExpandProperty GpoLinks
if (-not ($existing | Where-Object { $_.DisplayName -eq $gpo.DisplayName })) {
    New-GPLink -Name $gpo.DisplayName -Target $workstationsOuDN -LinkEnabled Yes | Out-Null
    Write-EstiamLog "GPO AppLocker liee a $workstationsOuDN" "APPLOCKER"
}

Write-EstiamLog "Configuration AppLocker terminee." "APPLOCKER"
