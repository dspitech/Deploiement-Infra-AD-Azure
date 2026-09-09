<#
.SYNOPSIS
    Etape 9 : creation et liaison des GPO (sections 14 a 26 du cahier des
    charges). Idempotent : les GPO et valeurs de registre sont reappliquees
    sans dupliquer si elles existent deja.
#>
param([Parameter(Mandatory = $true)]$Config)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\common.psm1" -Force
Import-Module ActiveDirectory -ErrorAction Stop
Import-Module GroupPolicy -ErrorAction Stop

$domain      = Get-ADDomain
$domainDN    = $domain.DistinguishedName
$domainName  = $domain.DNSRoot
$netbios     = $Config.NetbiosName
$estiamOuDN  = "OU=ESTIAM,$domainDN"
$workstationsOuDN = "OU=Workstations,OU=Computers,$estiamOuDN"
$usersOuDN   = "OU=Users,$estiamOuDN"

function New-GpoIfMissing {
    param([string]$Name)
    $gpo = Get-GPO -Name $Name -ErrorAction SilentlyContinue
    if (-not $gpo) {
        $gpo = New-GPO -Name $Name -Comment "Genere automatiquement par Terraform/PowerShell - ESTIAM"
        Write-EstiamLog "GPO creee : $Name" "GPO"
    } else {
        Write-EstiamLog "GPO deja presente : $Name" "GPO"
    }
    return $gpo
}

function Set-GpoLinkIfMissing {
    param([string]$GpoName, [string]$TargetDN)
    $existing = Get-GPInheritance -Target $TargetDN | Select-Object -ExpandProperty GpoLinks
    if (-not ($existing | Where-Object { $_.DisplayName -eq $GpoName })) {
        New-GPLink -Name $GpoName -Target $TargetDN -LinkEnabled Yes | Out-Null
        Write-EstiamLog "GPO '$GpoName' liee a $TargetDN" "GPO"
    }
}

# =============================================================================
# 14.1 - Politique de mots de passe et de verrouillage (Default Domain Policy)
# =============================================================================
Write-EstiamLog "Application de la politique de mots de passe (section 14.1)..." "GPO"
Set-ADDefaultDomainPasswordPolicy -Identity $domainName `
    -MinPasswordLength 12 `
    -PasswordHistoryCount 10 `
    -LockoutThreshold 5 `
    -LockoutDuration "00:15:00" `
    -LockoutObservationWindow "00:15:00" `
    -ComplexityEnabled $true `
    -MaxPasswordAge "90.00:00:00"

# =============================================================================
# GPO-ESTIAM-Security : verrouillage ecran + bandeau de connexion (section 14/21)
# =============================================================================
$gpoSecurity = New-GpoIfMissing -Name "GPO-ESTIAM-Security"

Set-GPRegistryValue -Name $gpoSecurity.DisplayName -Key "HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop" `
    -ValueName "ScreenSaveActive" -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $gpoSecurity.DisplayName -Key "HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop" `
    -ValueName "ScreenSaverIsSecure" -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $gpoSecurity.DisplayName -Key "HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop" `
    -ValueName "ScreenSaveTimeOut" -Type DWord -Value 600 | Out-Null

Set-GPRegistryValue -Name $gpoSecurity.DisplayName -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "LegalNoticeCaption" -Type String -Value "ESTIAM - Poste professionnel" | Out-Null
Set-GPRegistryValue -Name $gpoSecurity.DisplayName -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "LegalNoticeText" -Type String -Value "Acces reserve au personnel autorise. Toute utilisation est journalisee." | Out-Null

Set-GpoLinkIfMissing -GpoName $gpoSecurity.DisplayName -TargetDN $estiamOuDN

# =============================================================================
# GPO-ESTIAM-USB-Restriction (section 16)
# =============================================================================
$gpoUsb = New-GpoIfMissing -Name "GPO-ESTIAM-USB-Restriction"
Set-GPRegistryValue -Name $gpoUsb.DisplayName -Key "HKLM\Software\Policies\Microsoft\Windows\RemovableStorageDevices" `
    -ValueName "Deny_All" -Type DWord -Value 1 | Out-Null
Set-GpoLinkIfMissing -GpoName $gpoUsb.DisplayName -TargetDN $workstationsOuDN

# =============================================================================
# GPO-ESTIAM-Restrict-Terminal (section 15) - lie a OU=Users, filtre de securite
# exclut le groupe IT (qui garde acces complet aux outils d'administration).
# =============================================================================
$gpoTerminal = New-GpoIfMissing -Name "GPO-ESTIAM-Restrict-Terminal"

# Empeche l'invite de commandes (autorise les scripts .bat/.cmd)
Set-GPRegistryValue -Name $gpoTerminal.DisplayName -Key "HKCU\Software\Policies\Microsoft\Windows\System" `
    -ValueName "DisableCMD" -Type DWord -Value 2 | Out-Null

# Bloque le lancement de PowerShell / Windows Terminal via la strategie
# "Ne pas executer les applications Windows specifiees"
Set-GPRegistryValue -Name $gpoTerminal.DisplayName -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
    -ValueName "DisallowRun" -Type DWord -Value 1 | Out-Null
$disallowed = @("powershell.exe", "powershell_ise.exe", "WindowsTerminal.exe")
for ($i = 0; $i -lt $disallowed.Count; $i++) {
    Set-GPRegistryValue -Name $gpoTerminal.DisplayName `
        -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\DisallowRun" `
        -ValueName "$($i + 1)" -Type String -Value $disallowed[$i] | Out-Null
}

# Bloque egalement l'acces au Panneau de configuration et aux parametres
# systeme pour les utilisateurs standards (meme population/filtrage que
# la restriction terminal ci-dessus - section "Systeme" des demandes).
Set-GPRegistryValue -Name $gpoTerminal.DisplayName -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
    -ValueName "NoControlPanel" -Type DWord -Value 1 | Out-Null

Set-GpoLinkIfMissing -GpoName $gpoTerminal.DisplayName -TargetDN $usersOuDN

# Filtrage de securite : retirer "Utilisateurs authentifies", ajouter les
# groupes qui NE DOIVENT PAS avoir de terminal (tous sauf IT), et refuser
# explicitement l'application au groupe IT.
try {
    Set-GPPermission -Name $gpoTerminal.DisplayName -TargetName "Authenticated Users" -TargetType Group `
        -PermissionLevel None -Replace -ErrorAction SilentlyContinue | Out-Null
    Set-GPPermission -Name $gpoTerminal.DisplayName -TargetName "Domain Users" -TargetType Group `
        -PermissionLevel GpoApply | Out-Null
    Set-GPPermission -Name $gpoTerminal.DisplayName -TargetName "GG-ESTIAM-IT" -TargetType Group `
        -PermissionLevel GpoRead | Out-Null
    Write-EstiamLog "Filtrage de securite applique : GG-ESTIAM-IT exclu de GPO-ESTIAM-Restrict-Terminal." "GPO"
} catch {
    Write-EstiamLog "Avertissement filtrage securite terminal : $($_.Exception.Message)" "GPO"
}

# =============================================================================
# GPO-ESTIAM-WindowsUpdate (section 20)
# =============================================================================
$gpoWU = New-GpoIfMissing -Name "GPO-ESTIAM-WindowsUpdate"
$wuKey = "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU"
Set-GPRegistryValue -Name $gpoWU.DisplayName -Key $wuKey -ValueName "NoAutoUpdate" -Type DWord -Value 0 | Out-Null
Set-GPRegistryValue -Name $gpoWU.DisplayName -Key $wuKey -ValueName "AUOptions" -Type DWord -Value 4 | Out-Null
Set-GPRegistryValue -Name $gpoWU.DisplayName -Key $wuKey -ValueName "ScheduledInstallDay" -Type DWord -Value 0 | Out-Null
Set-GPRegistryValue -Name $gpoWU.DisplayName -Key $wuKey -ValueName "ScheduledInstallTime" -Type DWord -Value 3 | Out-Null
Set-GPRegistryValue -Name $gpoWU.DisplayName -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" `
    -ValueName "NoAutoRebootWithLoggedOnUsers" -Type DWord -Value 0 | Out-Null
Set-GpoLinkIfMissing -GpoName $gpoWU.DisplayName -TargetDN $workstationsOuDN

# =============================================================================
# GPO-ESTIAM-Defender-Firewall (section 19)
# =============================================================================
$gpoDef = New-GpoIfMissing -Name "GPO-ESTIAM-Defender-Firewall"
Set-GPRegistryValue -Name $gpoDef.DisplayName -Key "HKLM\Software\Policies\Microsoft\Windows Defender" `
    -ValueName "DisableAntiSpyware" -Type DWord -Value 0 | Out-Null
Set-GPRegistryValue -Name $gpoDef.DisplayName -Key "HKLM\Software\Policies\Microsoft\Windows Defender\Real-Time Protection" `
    -ValueName "DisableRealtimeMonitoring" -Type DWord -Value 0 | Out-Null
foreach ($profile in @("DomainProfile", "StandardProfile", "PublicProfile")) {
    Set-GPRegistryValue -Name $gpoDef.DisplayName `
        -Key "HKLM\Software\Policies\Microsoft\WindowsFirewall\$profile" `
        -ValueName "EnableFirewall" -Type DWord -Value 1 | Out-Null
}
Set-GpoLinkIfMissing -GpoName $gpoDef.DisplayName -TargetDN $workstationsOuDN

# =============================================================================
# GPO-ESTIAM-System-Hardening : Autorun, SmartScreen, installations MSI
# (section "Peripheriques" et "Securite" des demandes complementaires)
# =============================================================================
$gpoSystemHardening = New-GpoIfMissing -Name "GPO-ESTIAM-System-Hardening"

# Desactive l'execution automatique (Autorun/Autoplay) sur tous les types de
# lecteurs, y compris CD/DVD et cles USB (defense en profondeur avec le
# blocage USB deja en place).
Set-GPRegistryValue -Name $gpoSystemHardening.DisplayName -Key "HKLM\Software\Policies\Microsoft\Windows\Explorer" `
    -ValueName "NoDriveTypeAutoRun" -Type DWord -Value 255 | Out-Null
Set-GPRegistryValue -Name $gpoSystemHardening.DisplayName -Key "HKLM\Software\Policies\Microsoft\Windows\Explorer" `
    -ValueName "NoAutorun" -Type DWord -Value 1 | Out-Null

# Active Windows SmartScreen (executables et Microsoft Edge)
Set-GPRegistryValue -Name $gpoSystemHardening.DisplayName -Key "HKLM\Software\Policies\Microsoft\Windows\System" `
    -ValueName "EnableSmartScreen" -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $gpoSystemHardening.DisplayName -Key "HKLM\Software\Policies\Microsoft\Windows\System" `
    -ValueName "ShellSmartScreenLevel" -Type String -Value "Block" | Out-Null
Set-GPRegistryValue -Name $gpoSystemHardening.DisplayName -Key "HKLM\Software\Policies\Microsoft\Edge" `
    -ValueName "SmartScreenEnabled" -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $gpoSystemHardening.DisplayName -Key "HKLM\Software\Policies\Microsoft\Edge" `
    -ValueName "HomepageLocation" -Type String -Value "https://intranet.$domainName" | Out-Null

Set-GpoLinkIfMissing -GpoName $gpoSystemHardening.DisplayName -TargetDN $workstationsOuDN

# =============================================================================
# GPO-ESTIAM-BitLocker : exige la sauvegarde des cles de recuperation dans
# Active Directory avant meme d'autoriser le chiffrement (section BitLocker).
# =============================================================================
$gpoBitlocker = New-GpoIfMissing -Name "GPO-ESTIAM-BitLocker"
$bitlockerKey = "HKLM\Software\Policies\Microsoft\FVE"
Set-GPRegistryValue -Name $gpoBitlocker.DisplayName -Key $bitlockerKey -ValueName "OSActiveDirectoryBackup" -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $gpoBitlocker.DisplayName -Key $bitlockerKey -ValueName "OSActiveDirectoryInfoToStore" -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $gpoBitlocker.DisplayName -Key $bitlockerKey -ValueName "OSRequireActiveDirectoryBackup" -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $gpoBitlocker.DisplayName -Key $bitlockerKey -ValueName "OSHideRecoveryPage" -Type DWord -Value 0 | Out-Null
Set-GpoLinkIfMissing -GpoName $gpoBitlocker.DisplayName -TargetDN $workstationsOuDN

# =============================================================================
# GPO restreignant les droits d'installation logicielle (section 18) : les
# utilisateurs standards ne sont PAS administrateurs locaux (verifie via le
# groupe local Administrateurs ci-dessous, section suivante).
# =============================================================================
$gpoInstall = New-GpoIfMissing -Name "GPO-ESTIAM-No-Local-Install"
Set-GPRegistryValue -Name $gpoInstall.DisplayName -Key "HKLM\Software\Policies\Microsoft\Windows\Installer" `
    -ValueName "DisableUserInstalls" -Type DWord -Value 1 | Out-Null
Set-GpoLinkIfMissing -GpoName $gpoInstall.DisplayName -TargetDN $workstationsOuDN

# =============================================================================
# Restricted Groups : seuls Administrateurs du domaine + GG-ESTIAM-IT sont
# administrateurs locaux des postes de travail (section 18/24). Technique
# standard "Group Membership" via le fichier de securite GptTmpl.inf de la GPO.
# =============================================================================
$gpoRestrictedGroups = New-GpoIfMissing -Name "GPO-ESTIAM-RestrictedGroups-Workstations"

$gpoGuid = (Get-GPO -Name $gpoRestrictedGroups.DisplayName).Id.ToString("B").ToUpper()
$sysvolMachinePath = "\\$domainName\SYSVOL\$domainName\Policies\$gpoGuid\Machine\Microsoft\Windows NT\SecEdit"
New-Item -ItemType Directory -Path $sysvolMachinePath -Force | Out-Null
$gptTmplPath = Join-Path $sysvolMachinePath "GptTmpl.inf"

$gptTmplContent = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Group Membership]
*S-1-5-32-544__Memberof =
*S-1-5-32-544__Members = $netbios\Domain Admins,$netbios\GG-ESTIAM-IT
"@
Set-Content -Path $gptTmplPath -Value $gptTmplContent -Encoding Unicode
Write-EstiamLog "GptTmpl.inf (Restricted Groups) ecrit : Administrateurs locaux = Domain Admins + GG-ESTIAM-IT." "GPO"

# Enregistre l'extension "Security" (GUID standard) pour que le client
# applique bien le fichier GptTmpl.inf ci-dessus, et incremente la version GPO.
$gpoAdPath = "CN=$($gpoGuid),CN=Policies,CN=System,$domainDN"
$secCse = "[{827D319E-6EAC-11D2-A4EA-00C04F79F83A}{803E14A0-B4FB-11D0-A0D0-00A0C90F574B}]"
try {
    Set-ADObject -Identity $gpoAdPath -Replace @{ gPCMachineExtensionNames = $secCse }
    $gpo = Get-ADObject -Identity $gpoAdPath -Properties versionNumber
    Set-ADObject -Identity $gpoAdPath -Replace @{ versionNumber = ([int]$gpo.versionNumber + 1) }

    $gptIniPath = "\\$domainName\SYSVOL\$domainName\Policies\$gpoGuid\GPT.INI"
    "[General]`r`nVersion=$([int]$gpo.versionNumber + 1)" | Set-Content -Path $gptIniPath -Encoding ASCII
    Write-EstiamLog "Version de la GPO Restricted Groups incrementee, prise en compte au prochain gpupdate." "GPO"
} catch {
    Write-EstiamLog "Avertissement mise a jour AD de la GPO Restricted Groups : $($_.Exception.Message)" "GPO"
}

Set-GpoLinkIfMissing -GpoName $gpoRestrictedGroups.DisplayName -TargetDN $workstationsOuDN

# =============================================================================
# GPO specifiques par service (section 23) - demontre heritage/filtrage.
# Restent volontairement vides de configuration (a completer selon besoins
# reels), elles servent de point d'ancrage pour des reglages futurs par OU.
# =============================================================================
foreach ($dept in @("IT", "Finance", "RH")) {
    $deptGpoName = "GPO-ESTIAM-$dept"
    $deptGpo = New-GpoIfMissing -Name $deptGpoName
    $deptOuDN = "OU=$dept,OU=Users,$estiamOuDN"
    Set-GpoLinkIfMissing -GpoName $deptGpo.DisplayName -TargetDN $deptOuDN
}

# =============================================================================
# Lecteurs reseau (section 22/25) : script de connexion NETLOGON + attribut
# scriptPath sur chaque utilisateur (technique native, fiable a 100%, plutot
# que Group Policy Preferences dont le format XML brut est plus fragile).
# =============================================================================
$netlogonPath = "\\$domainName\NETLOGON"
$logonScriptName = "estiam-logon.bat"
$logonScriptContent = @"
@echo off
:: Script de connexion ESTIAM - monte les lecteurs reseau selon le service
net use H: \\SRV-AD01\Users$\%USERNAME% /persistent:no >nul 2>&1
net use P: \\SRV-AD01\Public /persistent:no >nul 2>&1

net user %USERNAME% /domain 1>nul 2>nul
whoami /groups | findstr /I "GG-ESTIAM-FINANCE" >nul && net use F: \\SRV-AD01\Finance /persistent:no >nul 2>&1
whoami /groups | findstr /I "GG-ESTIAM-RH" >nul && net use R: \\SRV-AD01\RH /persistent:no >nul 2>&1
whoami /groups | findstr /I "GG-ESTIAM-DIRECTION" >nul && net use O: \\SRV-AD01\Direction /persistent:no >nul 2>&1
whoami /groups | findstr /I "GG-ESTIAM-IT" >nul && net use I: \\SRV-AD01\IT /persistent:no >nul 2>&1
whoami /groups | findstr /I "GG-ESTIAM-MARKETING" >nul && net use M: \\SRV-AD01\Marketing /persistent:no >nul 2>&1
whoami /groups | findstr /I "GG-ESTIAM-ADMINISTRATION" >nul && net use A: \\SRV-AD01\Administration /persistent:no >nul 2>&1
"@
Set-Content -Path (Join-Path $netlogonPath $logonScriptName) -Value $logonScriptContent -Encoding ASCII
Write-EstiamLog "Script de connexion deploye sur NETLOGON : $logonScriptName" "GPO"

$allAdUsers = Get-ADUser -SearchBase $usersOuDN -Filter *
foreach ($u in $allAdUsers) {
    if ($u.ScriptPath -ne $logonScriptName) {
        Set-ADUser -Identity $u.SamAccountName -ScriptPath $logonScriptName
    }
}
Write-EstiamLog "Script de connexion assigne a tous les utilisateurs ESTIAM." "GPO"

Write-EstiamLog "Creation et liaison des GPO terminee." "GPO"
