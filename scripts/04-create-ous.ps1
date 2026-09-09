<#
.SYNOPSIS
    Etape 4 : creation de la structure d'unites organisationnelles (section 7).
    Idempotent.
#>
param([Parameter(Mandatory = $true)]$Config)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\common.psm1" -Force
Import-Module ActiveDirectory -ErrorAction Stop

$domainDN = (Get-ADDomain).DistinguishedName
$departments = $Config.DepartmentsCsv.Split(',')

function New-OuIfMissing {
    param([string]$Name, [string]$ParentDN)
    $dn = "OU=$Name,$ParentDN"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $Name -Path $ParentDN -ProtectedFromAccidentalDeletion $true
        Write-EstiamLog "OU creee : $dn" "OU"
    } else {
        Write-EstiamLog "OU deja presente : $dn" "OU"
    }
    return $dn
}

# OU=ESTIAM
$estiamOu = New-OuIfMissing -Name "ESTIAM" -ParentDN $domainDN

# OU=Users et sous-OU par service
$usersOu = New-OuIfMissing -Name "Users" -ParentDN $estiamOu
foreach ($dept in $departments) {
    New-OuIfMissing -Name $dept -ParentDN $usersOu | Out-Null
}
# OU dediee aux comptes desactives (cycle de vie utilisateur / offboarding)
New-OuIfMissing -Name "Disabled" -ParentDN $usersOu | Out-Null

# OU=Groups
New-OuIfMissing -Name "Groups" -ParentDN $estiamOu | Out-Null

# OU=Computers > OU=Workstations
$computersOu = New-OuIfMissing -Name "Computers" -ParentDN $estiamOu
New-OuIfMissing -Name "Workstations" -ParentDN $computersOu | Out-Null

# OU=Servers
New-OuIfMissing -Name "Servers" -ParentDN $estiamOu | Out-Null

# OU=ServiceAccounts
New-OuIfMissing -Name "ServiceAccounts" -ParentDN $estiamOu | Out-Null

# OU=AdminAccounts : comptes d'administration separes des comptes utilisateurs
# (principe du moindre privilege - convention adm-<login>)
New-OuIfMissing -Name "AdminAccounts" -ParentDN $estiamOu | Out-Null

Write-EstiamLog "Structure des OU creee avec succes." "OU"
