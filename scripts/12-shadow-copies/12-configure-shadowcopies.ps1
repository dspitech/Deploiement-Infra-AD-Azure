<#
.SYNOPSIS
    Etape 12 : active les cliches instantanes (Shadow Copies / Previous
    Versions) sur le volume D: - 2 cliches par jour (07h00 et 12h00).
    Prerequis : 08-file-shares (volume D: initialise). Idempotent.
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

Write-EstiamLog "Configuration des cliches instantanes terminee." "VSS"
