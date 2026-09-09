<#
.SYNOPSIS
    Etape 8 : application de la matrice de permissions NTFS (section 11).
    Basee sur les groupes de securite AD, pas sur les utilisateurs.
    Idempotent (reapplique la matrice a chaque execution).
#>
param([Parameter(Mandatory = $true)]$Config)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\common.psm1" -Force

$sharesRoot = "D:\Shares"
$netbios = $Config.NetbiosName

# Matrice de droits : Dossier => liste de (Groupe, Droit)
# Droit : "RW" (Modify) ou "R" (ReadAndExecute)
$matrix = @{
    "Public"         = @(@{Group = "GG-FS-PUBLIC-RW"; Right = "RW"})
    "Direction"      = @(
        @{Group = "GG-ESTIAM-DIRECTION"; Right = "RW"},
        @{Group = "GG-ESTIAM-IT";        Right = "R"}
    )
    "RH"             = @(
        @{Group = "GG-ESTIAM-DIRECTION"; Right = "R"},
        @{Group = "GG-ESTIAM-RH";        Right = "RW"},
        @{Group = "GG-ESTIAM-IT";        Right = "R"}
    )
    "Finance"        = @(
        @{Group = "GG-ESTIAM-DIRECTION"; Right = "R"},
        @{Group = "GG-ESTIAM-FINANCE";   Right = "RW"},
        @{Group = "GG-ESTIAM-IT";        Right = "R"}
    )
    "IT"             = @(
        @{Group = "GG-ESTIAM-DIRECTION"; Right = "R"},
        @{Group = "GG-ESTIAM-RH";        Right = "R"},
        @{Group = "GG-ESTIAM-FINANCE";   Right = "R"},
        @{Group = "GG-ESTIAM-IT";        Right = "RW"},
        @{Group = "GG-ESTIAM-MARKETING"; Right = "R"}
    )
    "Marketing"      = @(
        @{Group = "GG-ESTIAM-DIRECTION"; Right = "R"},
        @{Group = "GG-ESTIAM-IT";        Right = "R"},
        @{Group = "GG-ESTIAM-MARKETING"; Right = "RW"}
    )
    "Administration" = @(
        @{Group = "GG-ESTIAM-DIRECTION";      Right = "R"},
        @{Group = "GG-ESTIAM-IT";             Right = "R"},
        @{Group = "GG-ESTIAM-ADMINISTRATION"; Right = "RW"}
    )
}

function Set-EstiamNtfsAcl {
    param([string]$Path, [array]$Rules)

    if (-not (Test-Path $Path)) {
        Write-EstiamLog "Chemin introuvable, permission ignoree : $Path" "PERMS"
        return
    }

    $acl = Get-Acl $Path
    $acl.SetAccessRuleProtection($true, $false)  # coupe l'heritage, part d'une base propre

    # SYSTEM et Administrateurs du domaine gardent toujours le controle total
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))

    foreach ($rule in $Rules) {
        $ntfsRight = if ($rule.Right -eq "RW") { "Modify" } else { "ReadAndExecute" }
        $identity = "$netbios\$($rule.Group)"
        try {
            $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                $identity, $ntfsRight, "ContainerInherit,ObjectInherit", "None", "Allow")))
        } catch {
            Write-EstiamLog "Impossible d'ajouter la regle pour $identity sur $Path : $($_.Exception.Message)" "PERMS"
        }
    }

    Set-Acl -Path $Path -AclObject $acl
    Write-EstiamLog "Permissions NTFS appliquees sur $Path" "PERMS"
}

foreach ($folder in $matrix.Keys) {
    $path = Join-Path $sharesRoot $folder
    Set-EstiamNtfsAcl -Path $path -Rules $matrix[$folder]
}

Write-EstiamLog "Application de la matrice de permissions terminee." "PERMS"
