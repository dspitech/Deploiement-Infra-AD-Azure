<#
.SYNOPSIS
    Etape 10 : File Server Resource Manager - quotas sur les dossiers
    personnels + filtrage des types de fichiers executables sur les
    partages (section "Gestion avancee des fichiers"). Idempotent.
#>
param([Parameter(Mandatory = $true)]$Config)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\common.psm1" -Force

Write-EstiamLog "Installation du role FSRM (File Server Resource Manager)..." "FSRM"
if (-not (Get-WindowsFeature -Name FS-Resource-Manager).Installed) {
    Install-WindowsFeature -Name FS-Resource-Manager -IncludeManagementTools | Out-Null
    Start-Sleep -Seconds 15
}
Import-Module FileServerResourceManager -ErrorAction Stop

$sharesRoot = "D:\Shares"
$usersShareRoot = Join-Path $sharesRoot "Users"

# -----------------------------------------------------------------------------
# Quotas : 2 Go par dossier personnel
# -----------------------------------------------------------------------------
if (-not (Get-FsrmQuotaTemplate -Name "ESTIAM-Personal-2GB" -ErrorAction SilentlyContinue)) {
    New-FsrmQuotaTemplate -Name "ESTIAM-Personal-2GB" -Size 2GB -SoftLimit:$false `
        -Description "Quota standard des dossiers personnels ESTIAM (2 Go)" | Out-Null
    Write-EstiamLog "Modele de quota ESTIAM-Personal-2GB cree (2 Go, quota dur)." "FSRM"
}

if (Test-Path $usersShareRoot) {
    if (-not (Get-FsrmQuota -Path $usersShareRoot -ErrorAction SilentlyContinue)) {
        New-FsrmQuota -Path $usersShareRoot -Template "ESTIAM-Personal-2GB" | Out-Null
        Write-EstiamLog "Quota auto-apply (2 Go) applique sur $usersShareRoot (chaque sous-dossier utilisateur herite du quota)." "FSRM"
    }
    # Quota auto-apply : tout nouveau dossier personnel cree recevra automatiquement le quota
    $autoQuota = Get-FsrmAutoQuota -Path $usersShareRoot -ErrorAction SilentlyContinue
    if (-not $autoQuota) {
        New-FsrmAutoQuota -Path $usersShareRoot -Template "ESTIAM-Personal-2GB" | Out-Null
        Write-EstiamLog "Quota automatique active pour les futurs dossiers personnels." "FSRM"
    }
}

# -----------------------------------------------------------------------------
# File Screening : interdire le depot d'executables/scripts sur les partages
# metier (Public, Direction, RH, Finance, Marketing, Administration).
# Le partage IT reste exempt (les administrateurs y deposent des scripts).
# -----------------------------------------------------------------------------
$blockedGroupName = "Fichiers executables"
if (-not (Get-FsrmFileGroup -Name $blockedGroupName -ErrorAction SilentlyContinue)) {
    New-FsrmFileGroup -Name $blockedGroupName -IncludePattern @("*.exe", "*.bat", "*.cmd", "*.ps1", "*.vbs", "*.js", "*.scr", "*.msi") | Out-Null
    Write-EstiamLog "Groupe de fichiers '$blockedGroupName' cree." "FSRM"
}

$templateName = "ESTIAM-Block-Executables"
if (-not (Get-FsrmFileScreenTemplate -Name $templateName -ErrorAction SilentlyContinue)) {
    New-FsrmFileScreenTemplate -Name $templateName -IncludeGroup $blockedGroupName -Active:$true `
        -Description "Bloque le depot de fichiers executables/scripts sur les partages metier" | Out-Null
    Write-EstiamLog "Modele de filtrage '$templateName' cree." "FSRM"
}

$departments = $Config.DepartmentsCsv.Split(',')
$screenedFolders = @("Public") + $departments | Where-Object { $_ -ne "IT" }

foreach ($folder in $screenedFolders) {
    $path = Join-Path $sharesRoot $folder
    if ((Test-Path $path) -and (-not (Get-FsrmFileScreen -Path $path -ErrorAction SilentlyContinue))) {
        New-FsrmFileScreen -Path $path -Template $templateName | Out-Null
        Write-EstiamLog "Filtrage de fichiers applique sur $path (executables/scripts bloques)." "FSRM"
    }
}

Write-EstiamLog "Configuration FSRM (quotas + filtrage) terminee." "FSRM"
