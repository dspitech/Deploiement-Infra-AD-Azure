<#
.SYNOPSIS
    Etape 16 : deploie un dashboard de supervision (HTML/CSS/JS) servi par
    IIS, alimente par un collecteur PowerShell execute toutes les minutes
    (CPU, RAM, disques, services AD/DNS/DHCP, comptes AD, evenements de
    securite, disponibilite). Section "Monitoring du serveur". Idempotent.
#>
param([Parameter(Mandatory = $true)]$Config)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module "$here\common.psm1" -Force

Write-EstiamLog "Installation d'IIS pour le dashboard de supervision..." "MONITORING"
if (-not (Get-WindowsFeature -Name Web-Server).Installed) {
    Install-WindowsFeature -Name Web-Server, Web-Static-Content, Web-Default-Doc -IncludeManagementTools | Out-Null
}

$dashboardRoot = "C:\inetpub\wwwroot\estiam"
New-Item -ItemType Directory -Path $dashboardRoot -Force | Out-Null

# S'assure que IIS sert bien les fichiers .json (mappe par defaut sur les
# versions recentes, mais on le force au cas ou)
Import-Module WebAdministration -ErrorAction SilentlyContinue
try {
    $existingMime = Get-WebConfiguration -Filter "system.webServer/staticContent/mimeMap[@fileExtension='.json']" -PSPath "IIS:\" -ErrorAction SilentlyContinue
    if (-not $existingMime) {
        Add-WebConfiguration -Filter "system.webServer/staticContent" -PSPath "IIS:\" -Value @{fileExtension = ".json"; mimeType = "application/json" } | Out-Null
    }
} catch {
    Write-EstiamLog "Avertissement mimeMap JSON : $($_.Exception.Message)" "MONITORING"
}

# =============================================================================
# Collecteur de metriques (PowerShell), copie dans le dossier persistant et
# execute chaque minute par une tache planifiee.
# =============================================================================
$collectorPath = "$Global:EstiamRoot\Scripts\Collect-EstiamMetrics.ps1"
$collectorContent = @'
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
$dashboardRoot = "C:\inetpub\wwwroot\estiam"
$outFile = Join-Path $dashboardRoot "metrics.json"

function Get-SafeValue { param($Block) try { & $Block } catch { $null } }

$cpu = Get-SafeValue { (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average }
$os  = Get-SafeValue { Get-CimInstance Win32_OperatingSystem }
$ramTotalMB = if ($os) { [math]::Round($os.TotalVisibleMemorySize / 1024) } else { $null }
$ramFreeMB  = if ($os) { [math]::Round($os.FreePhysicalMemory / 1024) } else { $null }
$ramUsedPct = if ($ramTotalMB -and $ramTotalMB -gt 0) { [math]::Round((($ramTotalMB - $ramFreeMB) / $ramTotalMB) * 100, 1) } else { $null }
$uptime = if ($os) { (Get-Date) - $os.LastBootUpTime } else { $null }

$disks = Get-SafeValue {
    Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        [PSCustomObject]@{
            Drive    = $_.DeviceID
            SizeGB   = [math]::Round($_.Size / 1GB, 1)
            FreeGB   = [math]::Round($_.FreeSpace / 1GB, 1)
            UsedPct  = if ($_.Size -gt 0) { [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1) } else { 0 }
        }
    }
}

$services = @("NTDS", "DNS", "DHCPServer", "Netlogon", "W3SVC", "AppIDSvc") | ForEach-Object {
    $svc = Get-Service -Name $_ -ErrorAction SilentlyContinue
    [PSCustomObject]@{ Name = $_; Status = if ($svc) { $svc.Status.ToString() } else { "AbsentE" } }
}

$adStats = Get-SafeValue {
    [PSCustomObject]@{
        Users      = (Get-ADUser -Filter *).Count
        Groups     = (Get-ADGroup -Filter *).Count
        OUs        = (Get-ADOrganizationalUnit -Filter *).Count
        Computers  = (Get-ADComputer -Filter *).Count
        DisabledUsers = (Get-ADUser -Filter { Enabled -eq $false }).Count
    }
}

$failedLogons = Get-SafeValue {
    (Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4625; StartTime = (Get-Date).AddHours(-1) } -ErrorAction SilentlyContinue | Measure-Object).Count
}

$checksPath = Join-Path $dashboardRoot "checks.json"
$checks = if (Test-Path $checksPath) { Get-Content $checksPath -Raw | ConvertFrom-Json } else { $null }

$metrics = [PSCustomObject]@{
    Timestamp      = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    ComputerName   = $env:COMPUTERNAME
    CpuPercent     = $cpu
    RamUsedPercent = $ramUsedPct
    RamTotalMB     = $ramTotalMB
    UptimeHours    = if ($uptime) { [math]::Round($uptime.TotalHours, 1) } else { $null }
    Disks          = $disks
    Services       = $services
    ActiveDirectory = $adStats
    FailedLogonsLastHour = $failedLogons
    SecurityChecks = $checks
}

$metrics | ConvertTo-Json -Depth 5 | Set-Content -Path $outFile -Encoding UTF8
'@
Set-Content -Path $collectorPath -Value $collectorContent -Encoding UTF8
Write-EstiamLog "Collecteur de metriques deploye : $collectorPath" "MONITORING"

$taskName = "ESTIAM-Metrics-Collector"
if (-not (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Unrestricted -File `"$collectorPath`""
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration ([TimeSpan]::MaxValue)
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal | Out-Null
    Write-EstiamLog "Tache planifiee '$taskName' creee (collecte toutes les minutes)." "MONITORING"
}

# Premiere collecte immediate pour que le dashboard affiche des donnees des l'ouverture
powershell -NoProfile -ExecutionPolicy Unrestricted -File $collectorPath

# =============================================================================
# Dashboard HTML/CSS/JS (autonome, aucune dependance externe/CDN)
# =============================================================================
$dashboardHtml = @'
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>ESTIAM - Supervision infrastructure</title>
<meta http-equiv="refresh-hint" content="poll">
<style>
  :root{--bg:#0f172a;--card:#1e293b;--text:#e2e8f0;--muted:#94a3b8;--ok:#22c55e;--warn:#f59e0b;--bad:#ef4444;--accent:#3b82f6;}
  *{box-sizing:border-box;}
  body{margin:0;font-family:Segoe UI,Arial,sans-serif;background:var(--bg);color:var(--text);padding:24px;}
  h1{font-size:22px;margin:0 0 4px;}
  .sub{color:var(--muted);font-size:13px;margin-bottom:24px;}
  .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:16px;}
  .card{background:var(--card);border-radius:10px;padding:18px;box-shadow:0 1px 3px rgba(0,0,0,.4);}
  .card h2{font-size:13px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);margin:0 0 12px;}
  .metric{font-size:28px;font-weight:600;}
  .bar-bg{background:#334155;border-radius:6px;height:8px;overflow:hidden;margin-top:8px;}
  .bar-fill{height:100%;border-radius:6px;transition:width .4s ease;}
  .row{display:flex;justify-content:space-between;align-items:center;padding:6px 0;border-bottom:1px solid #334155;font-size:13px;}
  .row:last-child{border-bottom:none;}
  .dot{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:6px;}
  .dot-ok{background:var(--ok);} .dot-bad{background:var(--bad);} .dot-warn{background:var(--warn);}
  .badge{padding:2px 8px;border-radius:12px;font-size:11px;font-weight:600;}
  .badge-ok{background:rgba(34,197,94,.15);color:var(--ok);}
  .badge-bad{background:rgba(239,68,68,.15);color:var(--bad);}
  footer{margin-top:24px;color:var(--muted);font-size:12px;}
</style>
</head>
<body>
  <h1>ESTIAM - Tableau de bord infrastructure</h1>
  <div class="sub" id="lastUpdate">Chargement...</div>

  <div class="grid">
    <div class="card">
      <h2>Processeur (CPU)</h2>
      <div class="metric" id="cpuVal">--%</div>
      <div class="bar-bg"><div class="bar-fill" id="cpuBar" style="width:0%;background:var(--accent);"></div></div>
    </div>
    <div class="card">
      <h2>Memoire (RAM)</h2>
      <div class="metric" id="ramVal">--%</div>
      <div class="bar-bg"><div class="bar-fill" id="ramBar" style="width:0%;background:var(--accent);"></div></div>
    </div>
    <div class="card">
      <h2>Disponibilite</h2>
      <div class="metric" id="uptimeVal">-- h</div>
      <div class="sub" style="margin:6px 0 0;">Depuis le dernier redemarrage</div>
    </div>
    <div class="card">
      <h2>Connexions echouees (1h)</h2>
      <div class="metric" id="failedLogons">--</div>
      <div class="sub" style="margin:6px 0 0;">Evenements de securite 4625</div>
    </div>

    <div class="card" id="disksCard">
      <h2>Disques</h2>
    </div>

    <div class="card" id="servicesCard">
      <h2>Services (AD / DNS / DHCP / IIS / AppLocker)</h2>
    </div>

    <div class="card" id="adCard">
      <h2>Active Directory</h2>
    </div>

    <div class="card" id="checksCard">
      <h2>Controles de securite</h2>
    </div>
  </div>

  <footer>ESTIAM - genere automatiquement par Terraform/PowerShell - rafraichissement toutes les 5 secondes</footer>

<script>
function colorFor(pct){ if(pct>85) return 'var(--bad)'; if(pct>65) return 'var(--warn)'; return 'var(--ok)'; }

function render(data){
  document.getElementById('lastUpdate').textContent = 'Serveur ' + data.ComputerName + ' - derniere collecte : ' + data.Timestamp;

  var cpu = data.CpuPercent ?? 0;
  document.getElementById('cpuVal').textContent = cpu + '%';
  document.getElementById('cpuBar').style.width = cpu + '%';
  document.getElementById('cpuBar').style.background = colorFor(cpu);

  var ram = data.RamUsedPercent ?? 0;
  document.getElementById('ramVal').textContent = ram + '%';
  document.getElementById('ramBar').style.width = ram + '%';
  document.getElementById('ramBar').style.background = colorFor(ram);

  document.getElementById('uptimeVal').textContent = (data.UptimeHours ?? '--') + ' h';
  document.getElementById('failedLogons').textContent = data.FailedLogonsLastHour ?? '--';

  var disksHtml = '<h2>Disques</h2>';
  (data.Disks || []).forEach(function(d){
    disksHtml += '<div class="row"><span>' + d.Drive + ' (' + d.SizeGB + ' Go)</span>' +
      '<span>' + d.UsedPct + '% utilise, ' + d.FreeGB + ' Go libres</span></div>';
  });
  document.getElementById('disksCard').innerHTML = disksHtml;

  var svcHtml = '<h2>Services (AD / DNS / DHCP / IIS / AppLocker)</h2>';
  (data.Services || []).forEach(function(s){
    var ok = s.Status === 'Running';
    svcHtml += '<div class="row"><span><span class="dot ' + (ok ? 'dot-ok' : 'dot-bad') + '"></span>' + s.Name + '</span>' +
      '<span class="badge ' + (ok ? 'badge-ok' : 'badge-bad') + '">' + s.Status + '</span></div>';
  });
  document.getElementById('servicesCard').innerHTML = svcHtml;

  var ad = data.ActiveDirectory || {};
  var adHtml = '<h2>Active Directory</h2>' +
    '<div class="row"><span>Utilisateurs</span><span>' + (ad.Users ?? '--') + '</span></div>' +
    '<div class="row"><span>dont desactives</span><span>' + (ad.DisabledUsers ?? '--') + '</span></div>' +
    '<div class="row"><span>Groupes</span><span>' + (ad.Groups ?? '--') + '</span></div>' +
    '<div class="row"><span>Unites organisationnelles</span><span>' + (ad.OUs ?? '--') + '</span></div>' +
    '<div class="row"><span>Ordinateurs</span><span>' + (ad.Computers ?? '--') + '</span></div>';
  document.getElementById('adCard').innerHTML = adHtml;

  var checksHtml = '<h2>Controles de securite</h2>';
  var checks = data.SecurityChecks;
  if (checks && checks.Checks) {
    checks.Checks.forEach(function(c){
      checksHtml += '<div class="row"><span><span class="dot ' + (c.Pass ? 'dot-ok' : 'dot-bad') + '"></span>' + c.Name + '</span>' +
        '<span class="badge ' + (c.Pass ? 'badge-ok' : 'badge-bad') + '">' + (c.Pass ? 'OK' : 'ECHEC') + '</span></div>';
    });
  } else {
    checksHtml += '<div class="row"><span>En attente du premier controle (etape 17)</span></div>';
  }
  document.getElementById('checksCard').innerHTML = checksHtml;
}

function poll(){
  fetch('metrics.json?_=' + Date.now())
    .then(function(r){ return r.json(); })
    .then(render)
    .catch(function(e){ console.error('Erreur chargement metriques', e); });
}
poll();
setInterval(poll, 5000);
</script>
</body>
</html>
'@
Set-Content -Path (Join-Path $dashboardRoot "index.html") -Value $dashboardHtml -Encoding UTF8
Write-EstiamLog "Dashboard HTML/CSS/JS deploye sur http://$($Config.ServerIp)/estiam/" "MONITORING"

Write-EstiamLog "Configuration du monitoring terminee." "MONITORING"
