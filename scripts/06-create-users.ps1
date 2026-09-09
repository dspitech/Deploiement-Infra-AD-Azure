<#
.SYNOPSIS
    Etape 6 : creation des utilisateurs (section 8), et application du
    principe de moindre privilege : compte utilisateur / compte
    d'administration / compte de service strictement separes (convention
    de nommage jdupont / adm-jdupont / svc-xxx).
    Idempotent.
#>
param([Parameter(Mandatory = $true)]$Config)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\common.psm1" -Force
Import-Module ActiveDirectory -ErrorAction Stop

$domainDN      = (Get-ADDomain).DistinguishedName
$usersCsvPath  = "$here\users.csv"
$credsOutput   = "$Global:EstiamRoot\generated-credentials.csv"
$adminAccountsOu = "OU=AdminAccounts,OU=ESTIAM,$domainDN"
$serviceAccountsOu = "OU=ServiceAccounts,OU=ESTIAM,$domainDN"

if (-not (Test-Path $usersCsvPath)) {
    Write-EstiamLog "ERREUR : users.csv introuvable ($usersCsvPath)" "USERS"
    throw "users.csv introuvable"
}

$users = Import-Csv -Path $usersCsvPath
$createdCreds = @()

function New-RandomPassword {
    Add-Type -AssemblyName System.Web
    return [System.Web.Security.Membership]::GeneratePassword(16, 4)
}

foreach ($u in $users) {
    $samAccountName = $u.Username
    $ouPath = "OU=$($u.Department),OU=Users,OU=ESTIAM,$domainDN"

    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouPath'" -ErrorAction SilentlyContinue)) {
        Write-EstiamLog "OU manquante pour $samAccountName ($ouPath), utilisateur ignore." "USERS"
        continue
    }

    # Date d'expiration (comptes temporaires - stagiaires, prestataires...)
    $expirationDate = $null
    if ($u.ExpirationDate -and $u.ExpirationDate.Trim() -ne "") {
        try { $expirationDate = [DateTime]::Parse($u.ExpirationDate) } catch {
            Write-EstiamLog "Date d'expiration invalide pour $samAccountName : $($u.ExpirationDate)" "USERS"
        }
    }

    if (-not (Get-ADUser -Filter "SamAccountName -eq '$samAccountName'" -ErrorAction SilentlyContinue)) {
        $plainPwd  = New-RandomPassword
        $securePwd = ConvertTo-SecureString $plainPwd -AsPlainText -Force
        $homeDir   = "\\$($Config.ServerIp)\Users`$\$samAccountName"

        $newUserParams = @{
            Name                  = "$($u.FirstName) $($u.LastName)"
            GivenName             = $u.FirstName
            Surname               = $u.LastName
            SamAccountName        = $samAccountName
            UserPrincipalName     = "$samAccountName@$($Config.DomainName)"
            Path                  = $ouPath
            Title                 = $u.JobTitle
            Department            = $u.Department
            AccountPassword       = $securePwd
            ChangePasswordAtLogon = $true
            Enabled               = $true
            HomeDirectory         = $homeDir
            HomeDrive             = "H"
        }
        if ($expirationDate) { $newUserParams["AccountExpirationDate"] = $expirationDate }

        New-ADUser @newUserParams
        Write-EstiamLog "Utilisateur cree : $samAccountName ($($u.Department))$(if ($expirationDate) { " - expire le $expirationDate (compte temporaire)" })" "USERS"

        # Groupe metier
        $deptGroup = "GG-ESTIAM-$($u.Department.ToUpper())"
        if (Get-ADGroup -Filter "Name -eq '$deptGroup'" -ErrorAction SilentlyContinue) {
            Add-ADGroupMember -Identity $deptGroup -Members $samAccountName
        }
        # Groupe ressource associe (RW sur son propre partage)
        $resGroup = "GG-FS-$($u.Department.ToUpper())-RW"
        if (Get-ADGroup -Filter "Name -eq '$resGroup'" -ErrorAction SilentlyContinue) {
            Add-ADGroupMember -Identity $resGroup -Members $samAccountName
        }
        # Acces RW au partage Public pour tous
        if (Get-ADGroup -Filter "Name -eq 'GG-FS-PUBLIC-RW'" -ErrorAction SilentlyContinue) {
            Add-ADGroupMember -Identity "GG-FS-PUBLIC-RW" -Members $samAccountName
        }

        $createdCreds += [PSCustomObject]@{ Username = $samAccountName; Password = $plainPwd; Type = "Utilisateur" }
    } else {
        Write-EstiamLog "Utilisateur deja present : $samAccountName" "USERS"
        if ($expirationDate) {
            Set-ADUser -Identity $samAccountName -AccountExpirationDate $expirationDate
        }
    }

    # ---------------------------------------------------------------
    # Compte d'administration separe (principe du moindre privilege) :
    # uniquement pour le personnel IT. Convention : adm-<login>.
    # ---------------------------------------------------------------
    if ($u.Department -eq "IT") {
        $admAccountName = "adm-$samAccountName"
        if (-not (Get-ADUser -Filter "SamAccountName -eq '$admAccountName'" -ErrorAction SilentlyContinue)) {
            $admPlainPwd  = New-RandomPassword
            $admSecurePwd = ConvertTo-SecureString $admPlainPwd -AsPlainText -Force

            New-ADUser `
                -Name "ADM - $($u.FirstName) $($u.LastName)" `
                -SamAccountName $admAccountName `
                -UserPrincipalName "$admAccountName@$($Config.DomainName)" `
                -Path $adminAccountsOu `
                -Description "Compte d'administration IT associe a $samAccountName (usage exclusif taches d'admin)" `
                -AccountPassword $admSecurePwd `
                -ChangePasswordAtLogon $true `
                -Enabled $true

            Add-ADGroupMember -Identity "GG-ESTIAM-IT" -Members $admAccountName
            $createdCreds += [PSCustomObject]@{ Username = $admAccountName; Password = $admPlainPwd; Type = "Administration IT" }
            Write-EstiamLog "Compte d'administration separe cree : $admAccountName (associe a $samAccountName)" "USERS"
        }
    }
}

# ---------------------------------------------------------------------------
# Compte de service (ex: sauvegarde) - jamais utilise pour une connexion
# interactive, mot de passe non expirant (limitation assumee : l'ideal
# serait un compte de service gere - gMSA - hors perimetre d'un seul DC).
# ---------------------------------------------------------------------------
$svcAccountName = "svc-backup"
if (-not (Get-ADUser -Filter "SamAccountName -eq '$svcAccountName'" -ErrorAction SilentlyContinue)) {
    $svcPlainPwd  = New-RandomPassword
    $svcSecurePwd = ConvertTo-SecureString $svcPlainPwd -AsPlainText -Force

    New-ADUser `
        -Name "SVC - Backup" `
        -SamAccountName $svcAccountName `
        -UserPrincipalName "$svcAccountName@$($Config.DomainName)" `
        -Path $serviceAccountsOu `
        -Description "Compte de service dedie aux taches de sauvegarde planifiees" `
        -AccountPassword $svcSecurePwd `
        -ChangePasswordAtLogon $false `
        -PasswordNeverExpires $true `
        -CannotChangePassword $true `
        -Enabled $true

    $createdCreds += [PSCustomObject]@{ Username = $svcAccountName; Password = $svcPlainPwd; Type = "Compte de service" }
    Write-EstiamLog "Compte de service cree : $svcAccountName" "USERS"
}

if ($createdCreds.Count -gt 0) {
    $createdCreds | Export-Csv -Path $credsOutput -NoTypeInformation -Encoding UTF8 -Append
    icacls $credsOutput /inheritance:r /grant:r "Administrators:F" "SYSTEM:F" | Out-Null
    Write-EstiamLog "Identifiants generes stockes (acces restreint) dans $credsOutput" "USERS"
}

Write-EstiamLog "Creation des utilisateurs / comptes admin / comptes de service terminee." "USERS"
