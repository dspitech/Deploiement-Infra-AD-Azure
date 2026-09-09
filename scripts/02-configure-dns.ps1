<#
.SYNOPSIS
    Etape 2 : configuration du role DNS (section 5 du cahier des charges).
    Idempotent : peut etre relance sans erreur.
#>
param([Parameter(Mandatory = $true)]$Config)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\common.psm1" -Force
Import-Module DnsServer -ErrorAction Stop

Write-EstiamLog "Configuration DNS pour $($Config.DomainName)" "DNS"

# Zone de recherche inversee (10.10.10.0/24 -> 10.10.10.in-addr.arpa)
$octets = $Config.ServerIp.Split('.')
$reverseZoneName = "$($octets[2]).$($octets[1]).$($octets[0]).in-addr.arpa"

if (-not (Get-DnsServerZone -Name $reverseZoneName -ErrorAction SilentlyContinue)) {
    Add-DnsServerPrimaryZone -NetworkID "$($octets[0]).$($octets[1]).$($octets[2]).0/24" -ReplicationScope "Domain"
    Write-EstiamLog "Zone inversee $reverseZoneName creee." "DNS"
} else {
    Write-EstiamLog "Zone inversee $reverseZoneName deja presente." "DNS"
}

# Forwarders : DNS Azure (168.63.129.16) pour la resolution Internet des mises a jour
$existingForwarders = (Get-DnsServerForwarder -ErrorAction SilentlyContinue).IPAddress.IPAddressToString
if (-not ($existingForwarders -contains "168.63.129.16")) {
    Set-DnsServerForwarder -IPAddress "168.63.129.16" -PassThru | Out-Null
    Write-EstiamLog "Forwarder DNS 168.63.129.16 configure." "DNS"
}

# Le serveur doit utiliser lui-meme comme resolveur DNS primaire
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses ("127.0.0.1", $Config.ServerIp)
Write-EstiamLog "Client DNS local pointe vers lui-meme." "DNS"

Write-EstiamLog "Configuration DNS terminee." "DNS"
