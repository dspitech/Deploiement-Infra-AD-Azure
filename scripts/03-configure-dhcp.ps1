<#
.SYNOPSIS
    Etape 3 : installation et configuration du role DHCP (section 6).
    N'est execute que si EnableDhcp = true. Idempotent.
#>
param([Parameter(Mandatory = $true)]$Config)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\common.psm1" -Force

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
