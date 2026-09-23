<#
.SYNOPSIS
    Etape 3 : installation et configuration du role DHCP (section 6).
    N'est execute que si EnableDhcp = true. Idempotent.
    NB : le reseau virtuel Azure ne relaie pas les broadcasts DHCP ; les VM
    Azure gardent leur adresse fournie par la plateforme (IP statiques ici).
#>
#Requires -RunAsAdministrator
param([string]$ConfigPath)

$here = $PSScriptRoot
Import-Module "$here\..\00-common\common.psm1" -Force
$Config = Get-EstiamConfig -Path $ConfigPath
if (-not (Wait-ForActiveDirectory -TimeoutSeconds 600)) {
    throw "Active Directory indisponible. Le serveur a-t-il fini de redemarrer apres 01-install-ad.ps1 ?"
}

if (-not $Config.EnableDhcp) {
    Write-EstiamLog "DHCP desactive dans la configuration, etape ignoree." "DHCP"
    return
}

Write-EstiamLog "Installation du role DHCP..." "DHCP"
if (-not (Get-WindowsFeature -Name DHCP).Installed) {
    Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
}
Import-Module DhcpServer -ErrorAction Stop

# Autorisation du serveur DHCP dans l'annuaire AD (obligatoire sur un DC)
$domain = (Get-ADDomain).DNSRoot
if (-not (Get-DhcpServerInDC | Where-Object { $_.DnsName -eq "$env:COMPUTERNAME.$domain" })) {
    Add-DhcpServerInDC -DnsName "$env:COMPUTERNAME.$domain" -IPAddress $Config.ServerIp
    Write-EstiamLog "Serveur DHCP autorise dans AD." "DHCP"
}

$octets = $Config.ServerIp.Split('.')
$scopeId = "$($octets[0]).$($octets[1]).$($octets[2]).0"
$scopeName = "Scope-ESTIAM-LAN"

if (-not (Get-DhcpServerv4Scope -ScopeId $scopeId -ErrorAction SilentlyContinue)) {
    Add-DhcpServerv4Scope -Name $scopeName `
        -StartRange $Config.DhcpScopeStart `
        -EndRange $Config.DhcpScopeEnd `
        -SubnetMask "255.255.255.0" `
        -State Active
    Write-EstiamLog "Etendue DHCP $scopeId ($($Config.DhcpScopeStart) - $($Config.DhcpScopeEnd)) creee." "DHCP"
} else {
    Write-EstiamLog "Etendue DHCP $scopeId deja presente." "DHCP"
}

Set-DhcpServerv4OptionValue -ScopeId $scopeId `
    -DnsServer $Config.ServerIp `
    -DnsDomain $Config.DomainName `
    -Router $Config.DhcpGateway

Write-EstiamLog "Options DHCP (routeur, DNS, suffixe) appliquees." "DHCP"
Write-EstiamLog "Configuration DHCP terminee." "DHCP"
