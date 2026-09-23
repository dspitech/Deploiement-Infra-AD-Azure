<#
.SYNOPSIS
    Etape 13 : deploie un serveur d'impression de demonstration
    (imprimante partagee PRINTER-ESTIAM) et l'ajoute au script de connexion.
    Prerequis : 10-gpo (le script NETLOGON existe deja). Idempotent.
#>
#Requires -RunAsAdministrator
param([string]$ConfigPath)

$here = $PSScriptRoot
Import-Module "$here\..\00-common\common.psm1" -Force
$Config = Get-EstiamConfig -Path $ConfigPath
if (-not (Wait-ForActiveDirectory -TimeoutSeconds 600)) {
    throw "Active Directory indisponible. Le serveur a-t-il fini de redemarrer apres 01-install-ad.ps1 ?"
}

# -----------------------------------------------------------------------------
# Serveur d'impression de demonstration
# -----------------------------------------------------------------------------
Write-EstiamLog "Installation du role Print Server..." "PRINT"
if (-not (Get-WindowsFeature -Name Print-Server).Installed) {
    Install-WindowsFeature -Name Print-Server, Print-Services -IncludeManagementTools | Out-Null
}
Import-Module PrintManagement -ErrorAction Stop

$printerPortName = "PORT-ESTIAM-PDF"
$printerName     = "PRINTER-ESTIAM"

# Port et pilote de demonstration : "Microsoft Print to PDF" (fourni en boite,
# ne necessite aucun materiel physique - suffisant pour valider le deploiement
# GPO/logon script d'une imprimante reseau dans un lab).
if (-not (Get-PrinterDriver -Name "Microsoft Print To PDF" -ErrorAction SilentlyContinue)) {
    Add-PrinterDriver -Name "Microsoft Print To PDF" -ErrorAction SilentlyContinue
}

if (-not (Get-PrinterPort -Name $printerPortName -ErrorAction SilentlyContinue)) {
    Add-PrinterPort -Name $printerPortName -PrinterHostAddress "127.0.0.1" -ErrorAction SilentlyContinue | Out-Null
}

if (-not (Get-Printer -Name $printerName -ErrorAction SilentlyContinue)) {
    Add-Printer -Name $printerName -DriverName "Microsoft Print To PDF" -PortName $printerPortName -Shared -ShareName $printerName | Out-Null
    Write-EstiamLog "Imprimante partagee '$printerName' creee (\\$env:COMPUTERNAME\$printerName)." "PRINT"
} else {
    Write-EstiamLog "Imprimante '$printerName' deja presente." "PRINT"
}

# Ajout de la connexion imprimante au script de connexion NETLOGON existant
$netlogonScript = "\\$($Config.DomainName)\NETLOGON\estiam-logon.bat"
if (Test-Path $netlogonScript) {
    $content = Get-Content $netlogonScript -Raw
    $printerLine = "rundll32 printui.dll,PrintUIEntry /in /n \\$env:COMPUTERNAME\$printerName /q"
    if ($content -notmatch [regex]::Escape($printerLine)) {
        Add-Content -Path $netlogonScript -Value $printerLine
        Write-EstiamLog "Connexion automatique a l'imprimante ajoutee au script de connexion." "PRINT"
    }
} else {
    Write-EstiamLog "Script de connexion NETLOGON pas encore present (sera complete a l'etape GPO)." "PRINT"
}

Write-EstiamLog "Configuration Shadow Copies + serveur d'impression terminee." "PRINT"
