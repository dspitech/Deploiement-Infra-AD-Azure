<#
.SYNOPSIS
    Etape 5 : creation des groupes de securite (section 9). Idempotent.
#>
param([Parameter(Mandatory = $true)]$Config)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\common.psm1" -Force
Import-Module ActiveDirectory -ErrorAction Stop

$domainDN = (Get-ADDomain).DistinguishedName
$groupsOu = "OU=Groups,OU=ESTIAM,$domainDN"
$departments = $Config.DepartmentsCsv.Split(',')

function New-AdGroupIfMissing {
    param([string]$Name)
    if (-not (Get-ADGroup -Filter "Name -eq '$Name'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $Name -GroupScope Global -GroupCategory Security -Path $groupsOu
        Write-EstiamLog "Groupe cree : $Name" "GROUPS"
    } else {
        Write-EstiamLog "Groupe deja present : $Name" "GROUPS"
    }
}

# Groupes metier (un par service)
foreach ($dept in $departments) {
    New-AdGroupIfMissing -Name "GG-ESTIAM-$($dept.ToUpper())"
}

# Groupes dedies aux ressources partagees
$resourceGroups = @(
    "GG-FS-PUBLIC-RW",
    "GG-FS-DIRECTION-RW",
    "GG-FS-RH-RW",
    "GG-FS-FINANCE-RW",
    "GG-FS-IT-RW",
    "GG-FS-MARKETING-RW",
    "GG-FS-ADMINISTRATION-RW"
)
foreach ($g in $resourceGroups) {
    New-AdGroupIfMissing -Name $g
}

# Groupe d'administration deleguee (section "Administration deleguee") :
# reinitialisation de mot de passe + deverrouillage de compte uniquement,
# sans les droits complets d'un administrateur de domaine.
New-AdGroupIfMissing -Name "GG-ESTIAM-HELPDESK"

Write-EstiamLog "Creation des groupes terminee." "GROUPS"
