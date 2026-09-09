<#
.SYNOPSIS
    Etape 7 : initialisation du disque de donnees, arborescence et partages
    SMB (section 10 et 12). Idempotent.
#>
param([Parameter(Mandatory = $true)]$Config)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\common.psm1" -Force
Import-Module ActiveDirectory -ErrorAction Stop
Import-Module SmbShare -ErrorAction Stop

# --- Initialisation du disque de donnees (D:) s'il n'est pas deja pret ---
# Selection explicite par taille (32 Go) pour ne pas confondre avec le
# disque de sauvegarde (64 Go, initialise separement a l'etape 15).
$dataDisk = Get-Disk | Where-Object { $_.PartitionStyle -eq "RAW" -and [math]::Round($_.Size / 1GB) -in 30..34 } | Select-Object -First 1
if ($dataDisk) {
    Write-EstiamLog "Initialisation du disque de donnees $($dataDisk.Number)..." "SHARES"
    Initialize-Disk -Number $dataDisk.Number -PartitionStyle GPT -PassThru |
        New-Partition -DriveLetter D -UseMaximumSize |
        Format-Volume -FileSystem NTFS -NewFileSystemLabel "ESTIAM-DATA" -Confirm:$false | Out-Null
    Write-EstiamLog "Disque D: initialise et formate." "SHARES"
} else {
    Write-EstiamLog "Disque de donnees deja initialise (ou introuvable), poursuite." "SHARES"
}

if (-not (Test-Path "D:\")) {
    Write-EstiamLog "ERREUR : le volume D: n'est pas disponible." "SHARES"
    throw "Volume D: indisponible"
}

$sharesRoot = "D:\Shares"
$departments = $Config.DepartmentsCsv.Split(',')
$folders = @("Public") + $departments

New-Item -ItemType Directory -Path $sharesRoot -Force | Out-Null

foreach ($folder in $folders) {
    $path = Join-Path $sharesRoot $folder
    New-Item -ItemType Directory -Path $path -Force | Out-Null

    $shareName = $folder
    if (-not (Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue)) {
        New-SmbShare -Name $shareName -Path $path -FullAccess "Everyone" | Out-Null
        # Le controle d'acces reel est gere par NTFS (voir 08-configure-permissions.ps1),
        # la permission de partage SMB reste large pour ne pas dupliquer la logique.
        Write-EstiamLog "Partage SMB cree : \\$env:COMPUTERNAME\$shareName -> $path" "SHARES"
    } else {
        Write-EstiamLog "Partage SMB deja present : $shareName" "SHARES"
    }
}

# --- Dossiers personnels (Users$) ---
$usersShareRoot = Join-Path $sharesRoot "Users"
New-Item -ItemType Directory -Path $usersShareRoot -Force | Out-Null

if (-not (Get-SmbShare -Name "Users$" -ErrorAction SilentlyContinue)) {
    New-SmbShare -Name "Users$" -Path $usersShareRoot -FullAccess "Everyone" | Out-Null
    Write-EstiamLog "Partage cache Users$ cree." "SHARES"
}

$allAdUsers = Get-ADUser -SearchBase "OU=Users,OU=ESTIAM,$((Get-ADDomain).DistinguishedName)" -Filter *
foreach ($u in $allAdUsers) {
    $personalPath = Join-Path $usersShareRoot $u.SamAccountName
    if (-not (Test-Path $personalPath)) {
        New-Item -ItemType Directory -Path $personalPath -Force | Out-Null
        # L'utilisateur est seul proprietaire de son dossier personnel
        $acl = Get-Acl $personalPath
        $acl.SetAccessRuleProtection($true, $false)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "$($Config.NetbiosName)\$($u.SamAccountName)", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)
        $acl.AddAccessRule($adminRule)
        Set-Acl -Path $personalPath -AclObject $acl
        Write-EstiamLog "Dossier personnel cree pour $($u.SamAccountName)" "SHARES"
    }
}

Write-EstiamLog "Creation des partages et dossiers personnels terminee." "SHARES"
