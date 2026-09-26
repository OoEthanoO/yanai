param([string]$Root='C:\AI\yanai')
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$source=Get-Content 'C:\ProgramData\yanvpn\ddns\vercel-ddns.json' -Raw | ConvertFrom-Json
Add-Type -AssemblyName System.Security
$cipher=[Convert]::FromBase64String([IO.File]::ReadAllText($source.TokenPath))
$plain=[Security.Cryptography.ProtectedData]::Unprotect($cipher,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
$headers=@{Authorization='Bearer '+[Text.Encoding]::UTF8.GetString($plain)}
[Array]::Clear($plain,0,$plain.Length)
$scope='slug='+[Uri]::EscapeDataString($source.TeamSlug)
$uri="https://api.vercel.com/v5/domains/ethanyanxu.com/records?limit=100&$scope"
$records=@()
do {
    $page=Invoke-RestMethod -Uri $uri -Headers $headers
    $records+=@($page.records | Where-Object {$_.name -eq 'ai'})
    if ($page.pagination.next) { $uri="https://api.vercel.com/v5/domains/ethanyanxu.com/records?limit=100&$scope&until=$($page.pagination.next)" } else { $uri=$null }
} while ($uri)
$ip1=(Invoke-RestMethod 'https://api.ipify.org' -TimeoutSec 15).Trim()
$ip2=(Invoke-RestMethod 'https://checkip.amazonaws.com' -TimeoutSec 15).Trim()
if ($ip1 -ne $ip2 -or $ip1 -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { throw 'Public IP checks disagree' }
if ($records.Count -eq 0) {
    $body=@{name='ai';type='A';value=$ip1;ttl=60} | ConvertTo-Json
    $created=Invoke-RestMethod -Method Post -Uri "https://api.vercel.com/v2/domains/ethanyanxu.com/records?$scope" -Headers $headers -Body $body -ContentType application/json
    $recordId=$created.uid
    if (-not $recordId) { $recordId=$created.id }
} elseif ($records.Count -eq 1 -and $records[0].type -eq 'A' -and $records[0].value -eq $ip1) {
    $recordId=$records[0].id
} else { throw 'ai has an existing conflicting DNS record; nothing changed' }
if (-not $recordId) { throw 'DNS API did not return a record ID' }
$settings=[ordered]@{Domain='ethanyanxu.com';Subdomain='ai';TeamSlug=$source.TeamSlug;RecordId=$recordId;TokenPath=$source.TokenPath;TokenExpires=$source.TokenExpires}
$settingsPath=Join-Path $Root '.secrets\vercel-ddns.json'
[IO.File]::WriteAllText($settingsPath,($settings | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
$action=New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Root\scripts\update-vercel-dns.ps1`" -SettingsPath `"$settingsPath`"" -WorkingDirectory $Root
$principal=New-ScheduledTaskPrincipal -UserId SYSTEM -LogonType ServiceAccount -RunLevel Highest
$taskSettings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 4) -MultipleInstances IgnoreNew
$startup=New-ScheduledTaskTrigger -AtStartup
$repeat=New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName yanai-ddns -Action $action -Principal $principal -Settings $taskSettings -Trigger @($startup,$repeat) -Description 'Keep ai.ethanyanxu.com pointed at the home server' -Force | Out-Null
& "$Root\scripts\update-vercel-dns.ps1" -SettingsPath $settingsPath
