# =============================================================================
# common.psm1 - Fonctions communes utilisées par tous les scripts ESTIAM
# =============================================================================

$Global:EstiamRoot = "C:\ESTIAM"
$Global:EstiamLogs = "$Global:EstiamRoot\Logs"
$Global:EstiamStageFile = "$Global:EstiamRoot\stage.json"

function Initialize-EstiamPaths {
    New-Item -ItemType Directory -Path $Global:EstiamRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $Global:EstiamLogs -Force | Out-Null
}

function Write-EstiamLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Component = "GENERAL"
    )
    Initialize-EstiamPaths
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts][$Component] $Message"
    Write-Output $line
    Add-Content -Path "$Global:EstiamLogs\estiam-bootstrap.log" -Value $line
}

function Get-EstiamStage {
    if (Test-Path $Global:EstiamStageFile) {
        return (Get-Content $Global:EstiamStageFile -Raw | ConvertFrom-Json)
    }
    return [PSCustomObject]@{ Stage = 0; Completed = @() }
}

function Set-EstiamStage {
    param([Parameter(Mandatory = $true)][int]$Stage)
    Initialize-EstiamPaths
    $state = Get-EstiamStage
    $state.Stage = $Stage
    if (-not ($state.Completed -contains $Stage)) {
        $state.Completed += $Stage
    }
    $state | ConvertTo-Json | Set-Content -Path $Global:EstiamStageFile
}

function Test-EstiamStageDone {
    param([Parameter(Mandatory = $true)][int]$Stage)
    $state = Get-EstiamStage
    return ($state.Completed -contains $Stage)
}

# Attend qu'un service Windows soit démarré (utile après reboot, avant d'agir sur AD/DNS/DHCP)
function Wait-ForService {
    param(
        [Parameter(Mandatory = $true)][string]$ServiceName,
        [int]$TimeoutSeconds = 300
    )
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') { return $true }
        Start-Sleep -Seconds 5
        $elapsed += 5
    }
    return $false
}

# Attend que le contrôleur de domaine soit interrogeable (AD Web Services)
function Wait-ForActiveDirectory {
    param([int]$TimeoutSeconds = 600)
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        try {
            Import-Module ActiveDirectory -ErrorAction Stop
            Get-ADDomain -ErrorAction Stop | Out-Null
            return $true
        } catch {
            Start-Sleep -Seconds 10
            $elapsed += 10
        }
    }
    return $false
}

Export-ModuleMember -Function * -Variable EstiamRoot, EstiamLogs, EstiamStageFile
