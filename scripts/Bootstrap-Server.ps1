<#
.SYNOPSIS
    Orchestrateur relance a chaque demarrage par la tache planifiee
    "ESTIAM-Bootstrap-Continue". Deroule les etapes 2 a 17 dans l'ordre,
    de maniere idempotente (chaque etape verifie si elle a deja ete faite),
    puis se desenregistre lui-meme une fois termine.
#>

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\common.psm1" -Force

Initialize-EstiamPaths
Write-EstiamLog "=== Bootstrap-Server.ps1 declenche (demarrage systeme) ===" "BOOTSTRAP"

if (-not (Test-Path "$Global:EstiamRoot\config.json")) {
    Write-EstiamLog "Aucun config.json trouve, abandon." "BOOTSTRAP"
    exit 0
}
$cfg = Get-Content "$Global:EstiamRoot\config.json" -Raw | ConvertFrom-Json

Write-EstiamLog "Attente de la disponibilite d'Active Directory..." "BOOTSTRAP"
if (-not (Wait-ForActiveDirectory -TimeoutSeconds 900)) {
    Write-EstiamLog "ERREUR : Active Directory indisponible apres 15 minutes. Nouvel essai au prochain demarrage." "BOOTSTRAP"
    exit 1
}
Write-EstiamLog "Active Directory disponible." "BOOTSTRAP"

$steps = @(
    @{ Stage = 2;  Script = "02-configure-dns.ps1" }
    @{ Stage = 3;  Script = "03-configure-dhcp.ps1" }
    @{ Stage = 4;  Script = "04-create-ous.ps1" }
    @{ Stage = 5;  Script = "05-create-groups.ps1" }
    @{ Stage = 6;  Script = "06-create-users.ps1" }
    @{ Stage = 7;  Script = "07-create-shares.ps1" }
    @{ Stage = 8;  Script = "08-configure-permissions.ps1" }
    @{ Stage = 9;  Script = "09-create-gpos.ps1" }
    @{ Stage = 10; Script = "10-configure-fsrm.ps1" }
    @{ Stage = 11; Script = "11-configure-shadowcopies-print.ps1" }
    @{ Stage = 12; Script = "12-configure-applocker.ps1" }
    @{ Stage = 13; Script = "13-configure-laps.ps1" }
    @{ Stage = 14; Script = "14-configure-audit-delegation.ps1" }
    @{ Stage = 15; Script = "15-configure-backup.ps1" }
    @{ Stage = 16; Script = "16-configure-monitoring.ps1" }
    @{ Stage = 17; Script = "17-run-security-checks.ps1" }
)

foreach ($step in $steps) {
    if (Test-EstiamStageDone -Stage $step.Stage) {
        Write-EstiamLog "Etape $($step.Stage) ($($step.Script)) deja effectuee, on passe." "BOOTSTRAP"
        continue
    }

    Write-EstiamLog "Execution de l'etape $($step.Stage) : $($step.Script)" "BOOTSTRAP"
    try {
        & "$here\$($step.Script)" -Config $cfg
        Set-EstiamStage -Stage $step.Stage
        Write-EstiamLog "Etape $($step.Stage) terminee avec succes." "BOOTSTRAP"
    } catch {
        Write-EstiamLog "ERREUR a l'etape $($step.Stage) : $($_.Exception.Message)" "BOOTSTRAP"
        Write-EstiamLog "La tache planifiee reessaiera au prochain demarrage." "BOOTSTRAP"
        exit 1
    }
}

Write-EstiamLog "Toutes les etapes sont terminees. Desinscription de la tache planifiee." "BOOTSTRAP"
Unregister-ScheduledTask -TaskName "ESTIAM-Bootstrap-Continue" -Confirm:$false -ErrorAction SilentlyContinue
Write-EstiamLog "=== Bootstrap ESTIAM termine avec succes ===" "BOOTSTRAP"
