<#
.SYNOPSIS
    Etape 13 : Windows LAPS (Local Administrator Password Solution) -
    mot de passe administrateur local unique et a rotation automatique
    par poste, stocke chiffre dans Active Directory.
    Necessite Windows Server 2022 (mises a jour recentes) pour le module
    LAPS natif. Idempotent, avec gestion d'erreur explicite si le module
    n'est pas disponible (mise a jour Windows manquante).
#>
param([Parameter(Mandatory = $true)]$Config)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\common.psm1" -Force
Import-Module GroupPolicy -ErrorAction Stop

$domainDN         = (Get-ADDomain).DistinguishedName
$workstationsOuDN = "OU=Workstations,OU=Computers,OU=ESTIAM,$domainDN"

if (-not (Get-Module -ListAvailable -Name LAPS)) {
    Write-EstiamLog "Module LAPS natif indisponible (necessite une mise a jour Windows Server 2022 recente). Etape ignoree - a rejouer apres Windows Update." "LAPS"
    return
}
Import-Module LAPS -ErrorAction Stop

# Extension du schema AD pour LAPS (operation unique, sans effet si deja fait)
try {
    Update-LapsADSchema -ErrorAction Stop
    Write-EstiamLog "Schema AD etendu pour Windows LAPS." "LAPS"
} catch {
    Write-EstiamLog "Extension du schema LAPS : $($_.Exception.Message) (deja fait ou droits insuffisants)" "LAPS"
}

# Autorise chaque ordinateur a mettre a jour son propre mot de passe LAPS
try {
    Set-LapsADComputerSelfPermission -Identity $workstationsOuDN -ErrorAction Stop | Out-Null
    Write-EstiamLog "Permission 'self-update' LAPS accordee sur $workstationsOuDN" "LAPS"
} catch {
    Write-EstiamLog "Permission self-update LAPS : $($_.Exception.Message)" "LAPS"
}

# Seul le groupe IT peut lire les mots de passe LAPS stockes
try {
    Set-LapsADReadPasswordPermission -Identity $workstationsOuDN -AllowedPrincipals "GG-ESTIAM-IT" -ErrorAction Stop | Out-Null
    Write-EstiamLog "Droit de lecture des mots de passe LAPS accorde a GG-ESTIAM-IT." "LAPS"
} catch {
    Write-EstiamLog "Permission lecture LAPS : $($_.Exception.Message)" "LAPS"
}

# -----------------------------------------------------------------------------
# GPO activant LAPS sur les postes de travail (Computer Configuration)
# -----------------------------------------------------------------------------
$gpo = Get-GPO -Name "GPO-ESTIAM-LAPS" -ErrorAction SilentlyContinue
if (-not $gpo) {
    $gpo = New-GPO -Name "GPO-ESTIAM-LAPS" -Comment "Genere automatiquement - ESTIAM LAPS"
    Write-EstiamLog "GPO creee : GPO-ESTIAM-LAPS" "LAPS"
}

$lapsKey = "HKLM\Software\Microsoft\Policies\LAPS"
Set-GPRegistryValue -Name $gpo.DisplayName -Key $lapsKey -ValueName "BackupDirectory" -Type DWord -Value 2 | Out-Null   # 2 = Active Directory
Set-GPRegistryValue -Name $gpo.DisplayName -Key $lapsKey -ValueName "PasswordComplexity" -Type DWord -Value 4 | Out-Null # 4 = maj+min+chiffres+symboles
Set-GPRegistryValue -Name $gpo.DisplayName -Key $lapsKey -ValueName "PasswordLength" -Type DWord -Value 16 | Out-Null
Set-GPRegistryValue -Name $gpo.DisplayName -Key $lapsKey -ValueName "PasswordAgeDays" -Type DWord -Value 30 | Out-Null
Set-GPRegistryValue -Name $gpo.DisplayName -Key $lapsKey -ValueName "PostAuthenticationResetDelay" -Type DWord -Value 4 | Out-Null

$existing = Get-GPInheritance -Target $workstationsOuDN | Select-Object -ExpandProperty GpoLinks
if (-not ($existing | Where-Object { $_.DisplayName -eq $gpo.DisplayName })) {
    New-GPLink -Name $gpo.DisplayName -Target $workstationsOuDN -LinkEnabled Yes | Out-Null
    Write-EstiamLog "GPO LAPS liee a $workstationsOuDN" "LAPS"
}

Write-EstiamLog "Configuration Windows LAPS terminee (rotation tous les 30 jours, mdp 16 caracteres complexes)." "LAPS"
