<#
.SYNOPSIS
    Etape 11 : durcissement complementaire du poste client, execute une fois
    apres la jonction au domaine (sections 15 a 21). Vient en complement des
    GPO deployees par 09-create-gpos.ps1, force leur application immediate
    et applique quelques reglages purement locaux.
#>
param([Parameter(Mandatory = $true)][string]$NetbiosName)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\common.psm1" -Force

Initialize-EstiamPaths
Write-EstiamLog "=== Debut client-hardening.ps1 (poste client) ===" "HARDENING"

# Force la remontee immediate des GPO du domaine (sinon jusqu'a 90-120 min)
Write-EstiamLog "Application immediate des GPO (gpupdate /force)..." "HARDENING"
gpupdate /force /target:computer 2>&1 | Out-Null
gpupdate /force /target:user 2>&1 | Out-Null

# Desactive le compte Invite local (non requis en environnement d'entreprise)
try {
    Disable-LocalUser -Name "Guest" -ErrorAction SilentlyContinue
    Write-EstiamLog "Compte Invite local desactive." "HARDENING"
} catch {
    Write-EstiamLog "Compte Invite deja absent/desactive." "HARDENING"
}

# Verifie explicitement que Defender et le pare-feu sont actifs (defense en
# profondeur, en plus de la GPO GPO-ESTIAM-Defender-Firewall)
try {
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction SilentlyContinue
    Write-EstiamLog "Windows Defender et pare-feu verifies actifs." "HARDENING"
} catch {
    Write-EstiamLog "Avertissement verification Defender/Firewall : $($_.Exception.Message)" "HARDENING"
}

# Le service "Application Identity" doit tourner pour qu'AppLocker soit
# applique (la GPO force son demarrage automatique, on le demarre aussi
# immediatement pour ne pas attendre le prochain redemarrage).
try {
    Set-Service -Name AppIDSvc -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name AppIDSvc -ErrorAction SilentlyContinue
    Write-EstiamLog "Service Application Identity (AppLocker) demarre." "HARDENING"
} catch {
    Write-EstiamLog "Avertissement demarrage AppIDSvc : $($_.Exception.Message)" "HARDENING"
}

# -----------------------------------------------------------------------------
# BitLocker : chiffrement du disque systeme, cle de recuperation sauvegardee
# dans Active Directory (exige par la GPO GPO-ESTIAM-BitLocker). Necessite
# un TPM (fourni par Trusted Launch sur la VM Azure) ; en son absence, un
# protecteur par mot de passe de recuperation est utilise en secours (pas
# de chiffrement transparent au demarrage dans ce cas dsecours).
# -----------------------------------------------------------------------------
try {
    gpupdate /force /target:computer 2>&1 | Out-Null  # s'assure que la GPO BitLocker est appliquee avant d'activer

    $volume = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop
    if ($volume.ProtectionStatus -eq "Off") {
        Write-EstiamLog "Activation de BitLocker sur C:..." "BITLOCKER"

        $tpm = Get-Tpm -ErrorAction SilentlyContinue
        if ($tpm -and $tpm.TpmPresent -and $tpm.TpmReady) {
            Enable-BitLocker -MountPoint "C:" -EncryptionMethod XtsAes256 -TpmProtector -UsedSpaceOnly -SkipHardwareTest -ErrorAction Stop
            Write-EstiamLog "Protecteur TPM active (chiffrement transparent au demarrage)." "BITLOCKER"
        } else {
            Write-EstiamLog "TPM absent/non pret : ajout d'un protecteur par mot de passe de recuperation uniquement." "BITLOCKER"
            Enable-BitLocker -MountPoint "C:" -EncryptionMethod XtsAes256 -RecoveryPasswordProtector -UsedSpaceOnly -SkipHardwareTest -ErrorAction Stop
        }

        # Sauvegarde de la cle de recuperation dans Active Directory (exigee
        # par la GPO). Necessite que le compte ordinateur ait les droits
        # d'ecriture sur son propre attribut msFVE-RecoveryInformation
        # (accorde par defaut aux ordinateurs sur leur propre objet AD).
        $protector = (Get-BitLockerVolume -MountPoint "C:").KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" } | Select-Object -First 1
        if ($protector) {
            Backup-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $protector.KeyProtectorId -ErrorAction Stop
            Write-EstiamLog "Cle de recuperation BitLocker sauvegardee dans Active Directory." "BITLOCKER"
        }

        Write-EstiamLog "BitLocker active sur C: (chiffrement en cours en arriere-plan, espace utilise uniquement pour un demo plus rapide)." "BITLOCKER"
    } else {
        Write-EstiamLog "BitLocker deja actif sur C: (statut : $($volume.ProtectionStatus))." "BITLOCKER"
    }
} catch {
    Write-EstiamLog "Avertissement BitLocker : $($_.Exception.Message) (Trusted Launch/vTPM requis - verifier la configuration Azure de la VM)." "BITLOCKER"
}

# Retire les membres non souhaites du groupe Administrateurs local restants
# d'une image par defaut (le groupe domaine attendu est gere par la GPO
# GPO-ESTIAM-RestrictedGroups-Workstations, appliquee au prochain gpupdate).
try {
    $localAdmins = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue
    Write-EstiamLog "Membres actuels du groupe Administrateurs local : $($localAdmins.Name -join ', ')" "HARDENING"
} catch {
    Write-EstiamLog "Impossible de lister le groupe Administrateurs local." "HARDENING"
}

Write-EstiamLog "=== Durcissement du poste client termine ===" "HARDENING"
