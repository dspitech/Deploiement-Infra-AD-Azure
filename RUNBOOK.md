# ESTIAM - Runbook incidents

Procédures de référence. À dérouler depuis `SRV-AD01` via Azure Bastion.

## 1. Un utilisateur a supprimé un fichier par erreur

```powershell
# Lister les versions disponibles d'un dossier partagé
Get-ChildItem "D:\Shares\Direction" -Force
# Via l'explorateur Windows sur le client : clic droit sur le dossier
# parent > Propriétés > Versions précédentes (Shadow Copies, 2 clichés/jour)
```

Si le fichier est plus ancien que les clichés disponibles, restaurer depuis
la sauvegarde Windows Server Backup :

```powershell
Get-WBBackupSet | Format-List
Start-WBFileRecovery -BackupSet <BackupSet> -SourcePath "D:\Shares\Direction" -TargetPath "D:\Shares\Direction\Restauré" -Recursive
```

## 2. Le serveur ne démarre plus / corruption AD

1. Redémarrer en mode DSRM (Directory Services Restore Mode) si nécessaire
   (`bcdedit /set safeboot dsrepair`).
2. Restaurer le System State depuis la dernière sauvegarde :
   ```powershell
   wbadmin get versions
   wbadmin start systemstaterecovery -version:<version> -backupTarget:E:
   ```
3. Vérifier l'intégrité AD après restauration : `dcdiag /v`, `repadmin /replsummary`.
4. Repasser en démarrage normal (`bcdedit /deletevalue safeboot`) et redémarrer.

## 3. Un compte est verrouillé / mot de passe oublié

Le groupe `GG-ESTIAM-HELPDESK` dispose des droits nécessaires (délégation
via `dsacls`, voir README) sans être administrateur du domaine :

```powershell
Unlock-ADAccount -Identity jdupont
Set-ADAccountPassword -Identity jdupont -Reset -NewPassword (ConvertTo-SecureString "Nouveau-Mdp-Temp!" -AsPlainText -Force)
Set-ADUser -Identity jdupont -ChangePasswordAtLogon $true
```

## 4. Vérifier la santé globale de l'infrastructure

```powershell
C:\ESTIAM\Scripts\17-run-security-checks.ps1 -Config (Get-Content C:\ESTIAM\config.json -Raw | ConvertFrom-Json)
Get-Content C:\ESTIAM\security-check-report.json | ConvertFrom-Json | Select -ExpandProperty Checks
```

Ou consulter directement le dashboard : `http://10.10.10.10/estiam/`.

## 5. Test de restauration périodique (recommandé trimestriel)

Une sauvegarde non testée n'est pas une stratégie de sauvegarde :

1. Créer un fichier de test dans `D:\Shares\Public\test-restore.txt`.
2. Attendre la prochaine sauvegarde planifiée (02h00) ou en lancer une
   manuellement : `Start-WBBackup -Policy (Get-WBPolicy)`.
3. Supprimer le fichier de test.
4. Restaurer via `Start-WBFileRecovery` (voir procédure 1) et confirmer que
   le fichier revient intact.
5. Documenter la date et le résultat du test dans le registre de suivi.
