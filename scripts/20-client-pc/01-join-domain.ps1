<#
.SYNOPSIS
    Joint PC-CLIENT01 au domaine Active Directory, dans l'OU
    Workstations (OU=Workstations,OU=Computers,OU=ESTIAM,...).

.DESCRIPTION
    A executer sur PC-CLIENT01, en administrateur local, APRES que SRV-AD01
    est promu et que l'etape 05-organizational-units a ete jouee (l'OU cible
    doit exister). Le DNS de la carte reseau du client pointe deja sur
    SRV-AD01 (configure par Terraform). Le poste redemarre a la fin.

.PARAMETER DomainCredential
    Compte administrateur du domaine (ex : ESTIAM\estiamadmin). Demande si absent.

.PARAMETER NoRestart
    Ne pas redemarrer automatiquement apres la jonction.

.PARAMETER ConfigPath
    Chemin d'un config.json alternatif (facultatif).
#>
#Requires -RunAsAdministrator
param(
    [PSCredential]$DomainCredential,
    [switch]$NoRestart,
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
Import-Module "$PSScriptRoot\..\00-common\common.psm1" -Force
$Config = Get-EstiamConfig -Path $ConfigPath

Initialize-EstiamPaths
Write-EstiamLog "=== Debut 01-join-domain.ps1 (poste client) ===" "JOIN"

if ((Get-CimInstance -ClassName Win32_ComputerSystem).PartOfDomain) {
    Write-EstiamLog "Ce poste est deja joint a un domaine, rien a faire." "JOIN"
    return
}

# Le DNS doit resoudre le domaine, sinon la jonction echouera.
try {
    Resolve-DnsName -Name $Config.DomainName -ErrorAction Stop | Out-Null
} catch {
    throw "Le domaine $($Config.DomainName) n'est pas resolu. Verifier que SRV-AD01 est promu et que le DNS du client pointe sur $($Config.ServerIp)."
}

$domainDn = ($Config.DomainName.Split('.') | ForEach-Object { "DC=$_" }) -join ','
$ouPath   = "OU=Workstations,OU=Computers,OU=ESTIAM,$domainDn"

if (-not $DomainCredential) {
    $DomainCredential = Get-Credential -Message "Administrateur du domaine $($Config.DomainName)" -UserName "$($Config.NetbiosName)\estiamadmin"
}

Write-EstiamLog "Jonction au domaine $($Config.DomainName) dans $ouPath..." "JOIN"
try {
    Add-Computer -DomainName $Config.DomainName -OUPath $ouPath -Credential $DomainCredential -Force -Restart:(-not $NoRestart)
    Write-EstiamLog "Jonction reussie." "JOIN"
} catch {
    Write-EstiamLog "ECHEC de la jonction : $($_.Exception.Message)" "JOIN"
    Write-EstiamLog "Si l'OU est introuvable, jouer d'abord 05-organizational-units\05-create-ous.ps1 sur SRV-AD01." "JOIN"
    throw
}
