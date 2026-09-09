<#
.SYNOPSIS
    Etape 11 : active les cliches instantanes (Shadow Copies / Previous
    Versions) sur le volume D:, et deploie un serveur d'impression de
    demonstration (section "Serveur d'impression" et "Shadow Copies").
    Idempotent.
#>
param([Parameter(Mandatory = $true)]$Config)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\common.psm1" -Force

# -----------------------------------------------------------------------------
# Shadow Copies sur D: (2 cliches par jour, 07h00 et 12h00)
# -----------------------------------------------------------------------------
Write-EstiamLog "Configuration des cliches instantanes (Shadow Copies) sur D:..." "VSS"

$existingShadowStorage = vssadmin list shadowstorage /for=D: 2>$null
if (-not $existingShadowStorage -or ($LASTEXITCODE -ne 0)) {
    # Alloue jusqu'a 10% du volume D: au stockage des cliches
    vssadmin resize shadowstorage /for=D: /on=D: /maxsize=10% 2>$null | Out-Null
    vssadmin add shadowstorage /for=D: /on=D: /maxsize=10% 2>$null | Out-Null
    Write-EstiamLog "Stockage des cliches instantanes configure sur D: (10% max)." "VSS"
} else {
    Write-EstiamLog "Stockage des cliches instantanes deja configure sur D:." "VSS"
}

$taskName = "ESTIAM-ShadowCopy-D"
if (-not (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
    $action = New-ScheduledTaskAction -Execute "vssadmin.exe" -Argument "create shadow /for=D:"
    $trigger1 = New-ScheduledTaskTrigger -Daily -At "07:00"
    $trigger2 = New-ScheduledTaskTrigger -Daily -At "12:00"
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($trigger1, $trigger2) -Principal $principal | Out-Null
    Write-EstiamLog "Tache planifiee '$taskName' creee (cliches a 07h00 et 12h00)." "VSS"
}

# Premier cliche immediat pour disposer d'une version des maintenant
vssadmin create shadow /for=D: 2>$null | Out-Null
Write-EstiamLog "Cliche instantane initial cree." "VSS"

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
    $printerLine = "rundll32 printui.dll,PrintUIEntry /in /n \\SRV-AD01\$printerName /q"
    if ($content -notmatch [regex]::Escape($printerLine)) {
        Add-Content -Path $netlogonScript -Value $printerLine
        Write-EstiamLog "Connexion automatique a l'imprimante ajoutee au script de connexion." "PRINT"
    }
} else {
    Write-EstiamLog "Script de connexion NETLOGON pas encore present (sera complete a l'etape GPO)." "PRINT"
}

Write-EstiamLog "Configuration Shadow Copies + serveur d'impression terminee." "VSS-PRINT"
