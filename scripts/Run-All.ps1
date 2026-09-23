<#
.SYNOPSIS
    Facultatif : enchaine les etapes serveur 03 a 19 dans l'ordre, sur SRV-AD01.

.DESCRIPTION
    A lancer en administrateur sur SRV-AD01 APRES 01-install-ad.ps1 et le
    redemarrage qui suit. S'arrete a la premiere erreur ; on peut ensuite
    reprendre avec -From <numero>. Les scripts sont idempotents.
    Non inclus : 02-second-dc (autre machine) et 20-client-pc (poste client).

.EXAMPLE
    .\Run-All.ps1
    .\Run-All.ps1 -From 10          # reprendre a l'etape 10 (GPO)
    .\Run-All.ps1 -From 7 -To 9     # jouer uniquement les etapes 7 a 9
#>
#Requires -RunAsAdministrator
param(
    [ValidateRange(3, 19)][int]$From = 3,
    [ValidateRange(3, 19)][int]$To = 19,
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
Import-Module "$PSScriptRoot\00-common\common.psm1" -Force

$steps = @(
    @{ N = 3;  Path = "03-dns\03-configure-dns.ps1" }
    @{ N = 4;  Path = "04-dhcp\04-configure-dhcp.ps1" }
    @{ N = 5;  Path = "05-organizational-units\05-create-ous.ps1" }
    @{ N = 6;  Path = "06-groups\06-create-groups.ps1" }
    @{ N = 7;  Path = "07-users\07-create-users.ps1" }
    @{ N = 8;  Path = "08-file-shares\08-create-shares.ps1" }
    @{ N = 9;  Path = "09-ntfs-permissions\09-configure-permissions.ps1" }
    @{ N = 10; Path = "10-gpo\10-create-gpos.ps1" }
    @{ N = 11; Path = "11-fsrm\11-configure-fsrm.ps1" }
    @{ N = 12; Path = "12-shadow-copies\12-configure-shadowcopies.ps1" }
    @{ N = 13; Path = "13-print-server\13-configure-print-server.ps1" }
    @{ N = 14; Path = "14-applocker\14-configure-applocker.ps1" }
    @{ N = 15; Path = "15-laps\15-configure-laps.ps1" }
    @{ N = 16; Path = "16-audit-delegation\16-configure-audit-delegation.ps1" }
    @{ N = 17; Path = "17-backup\17-configure-backup.ps1" }
    @{ N = 18; Path = "18-monitoring\18-configure-monitoring.ps1" }
    @{ N = 19; Path = "19-security-checks\19-run-security-checks.ps1" }
)

$extra = @{}
if ($ConfigPath) { $extra["ConfigPath"] = $ConfigPath }

foreach ($step in ($steps | Where-Object { $_.N -ge $From -and $_.N -le $To })) {
    Write-EstiamLog "--- Etape $($step.N) : $($step.Path) ---" "RUN-ALL"
    try {
        & (Join-Path $PSScriptRoot $step.Path) @extra
    } catch {
        Write-EstiamLog "ERREUR a l'etape $($step.N) : $($_.Exception.Message)" "RUN-ALL"
        Write-EstiamLog "Corriger puis relancer : .\Run-All.ps1 -From $($step.N)" "RUN-ALL"
        exit 1
    }
}
Write-EstiamLog "=== Etapes $From a $To terminees ===" "RUN-ALL"
