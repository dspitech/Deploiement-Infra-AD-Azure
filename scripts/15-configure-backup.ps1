<#
.SYNOPSIS
    Etape 15 : sauvegarde automatisee (section "Sauvegarde") - initialise le
    disque de sauvegarde dedie (E:), installe Windows Server Backup, et
    programme une sauvegarde quotidienne de D:\Shares + System State.
    Idempotent.
#>
param([Parameter(Mandatory = $true)]$Config)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\common.psm1" -Force

# --- Initialisation du disque de sauvegarde (E:), 64 Go, distinct de D: ---
$backupDisk = Get-Disk | Where-Object { $_.PartitionStyle -eq "RAW" -and [math]::Round($_.Size / 1GB) -in 60..70 } | Select-Object -First 1
if ($backupDisk) {
    Write-EstiamLog "Initialisation du disque de sauvegarde $($backupDisk.Number)..." "BACKUP"
    Initialize-Disk -Number $backupDisk.Number -PartitionStyle GPT -PassThru |
        New-Partition -DriveLetter E -UseMaximumSize |
        Format-Volume -FileSystem NTFS -NewFileSystemLabel "ESTIAM-BACKUP" -Confirm:$false | Out-Null
    Write-EstiamLog "Disque E: initialise et formate (dedie aux sauvegardes)." "BACKUP"
} else {
    Write-EstiamLog "Disque de sauvegarde deja initialise (ou introuvable), poursuite." "BACKUP"
}

if (-not (Test-Path "E:\")) {
    Write-EstiamLog "ERREUR : le volume E: n'est pas disponible, sauvegarde non configuree." "BACKUP"
    return
}

Write-EstiamLog "Installation de Windows Server Backup..." "BACKUP"
if (-not (Get-WindowsFeature -Name Windows-Server-Backup).Installed) {
    Install-WindowsFeature -Name Windows-Server-Backup -IncludeManagementTools | Out-Null
}
Import-Module WindowsServerBackup -ErrorAction Stop

$existingPolicy = Get-WBPolicy -ErrorAction SilentlyContinue
if (-not $existingPolicy -or -not $existingPolicy.Schedule) {
    $policy = New-WBPolicy

    # Cible de sauvegarde : disque E: dedie
    $backupTarget = New-WBBackupTarget -VolumePath "E:"
    Add-WBBackupTarget -Policy $policy -Target $backupTarget | Out-Null

    # Donnees a sauvegarder : partages + System State (config du serveur/AD)
    $volumeToBackup = Get-WBVolume -VolumePath "D:"
    Add-WBVolume -Policy $policy -Volume $volumeToBackup | Out-Null
    Add-WBSystemState -Policy $policy | Out-Null

    # Planification quotidienne a 02h00
    Set-WBSchedule -Policy $policy -Schedule "02:00" | Out-Null

    Set-WBPolicy -Policy $policy -Force
    Write-EstiamLog "Politique de sauvegarde configuree : D:\ + System State, quotidienne a 02h00, cible E:." "BACKUP"
} else {
    Write-EstiamLog "Une politique de sauvegarde est deja active, aucune modification." "BACKUP"
}

# Lance une premiere sauvegarde immediate pour valider que la chaine fonctionne
# de bout en bout (le test de restauration reste une procedure documentee,
# voir RUNBOOK.md - une restauration reelle ne doit pas etre automatisee en
# aveugle sur un environnement de production).
try {
    Write-EstiamLog "Lancement d'une sauvegarde de validation initiale (peut prendre plusieurs minutes)..." "BACKUP"
    $currentPolicy = Get-WBPolicy
    Start-WBBackup -Policy $currentPolicy -Async | Out-Null
    Write-EstiamLog "Sauvegarde de validation lancee en arriere-plan (Get-WBJob pour suivre l'etat)." "BACKUP"
} catch {
    Write-EstiamLog "Avertissement lancement sauvegarde initiale : $($_.Exception.Message)" "BACKUP"
}

Write-EstiamLog "Configuration de la sauvegarde terminee." "BACKUP"
