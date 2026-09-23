# =============================================================================
# common.psm1 - Fonctions communes utilisees par tous les scripts ESTIAM
# NB : ce fichier est volontairement en ASCII pur (pas d'accents) pour rester
# compatible avec Windows PowerShell 5.1 quel que soit l'encodage du fichier.
# =============================================================================

$Global:EstiamRoot    = "C:\ESTIAM"
$Global:EstiamLogs    = "$Global:EstiamRoot\Logs"
$Global:EstiamScripts = "$Global:EstiamRoot\Scripts"

function Initialize-EstiamPaths {
    New-Item -ItemType Directory -Path $Global:EstiamRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $Global:EstiamLogs -Force | Out-Null
    New-Item -ItemType Directory -Path $Global:EstiamScripts -Force | Out-Null
}

function Write-EstiamLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Component = "GENERAL"
    )
    Initialize-EstiamPaths
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts][$Component] $Message"
    Write-Host $line
    Add-Content -Path "$Global:EstiamLogs\estiam-bootstrap.log" -Value $line
}

# Charge la configuration ESTIAM (domaine, IP du serveur, departements, DHCP...).
# Par defaut : config.json place a cote de ce module (dossier 00-common).
function Get-EstiamConfig {
    param([string]$Path)

    if (-not $Path) { $Path = Join-Path $PSScriptRoot "config.json" }
    if (-not (Test-Path $Path)) {
        throw "Fichier de configuration introuvable : $Path"
    }

    $cfg = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($key in @("DomainName", "NetbiosName", "ServerIp", "Departments")) {
        if (-not $cfg.$key) {
            throw "Parametre '$key' manquant ou vide dans $Path"
        }
    }
    return $cfg
}

# Attend qu'un service Windows soit demarre (utile apres reboot, avant d'agir sur AD/DNS/DHCP)
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

# Attend que le controleur de domaine soit interrogeable (AD Web Services).
# Utile juste apres le redemarrage qui suit la promotion (01-install-ad.ps1).
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

# Attend que le Global Catalog soit annonce (enregistrement DNS _gc._tcp +
# indicateur NTDS Settings). Indispensable AVANT tout appel GPMC qui touche
# aux permissions (Set-GPPermission), car ces cmdlets resolvent les comptes
# via le GC et RESTENT BLOQUES (sans lever d'exception, donc sans etre
# rattrapes par un try/catch) si le GC n'est pas encore pret - ce qui peut
# prendre plusieurs minutes juste apres une promotion, meme si
# Get-ADDomain (utilise par Wait-ForActiveDirectory) repond deja.
function Wait-ForGlobalCatalog {
    param([int]$TimeoutSeconds = 300)
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        try {
            $dc = Get-ADDomainController -Discover -Service GlobalCatalog -ErrorAction Stop
            if ($dc) { return $true }
        } catch {
            # Pas encore annonce, on reessaie
        }
        Start-Sleep -Seconds 10
        $elapsed += 10
    }
    return $false
}

Export-ModuleMember -Function *
