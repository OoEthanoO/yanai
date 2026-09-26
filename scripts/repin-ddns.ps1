#requires -Version 5.1
#requires -RunAsAdministrator
# Re-links a DNS updater to its Vercel A record after Vercel gives the record a new ID (the
# updater refuses to touch a record whose ID changed). Shows the record and asks before changing
# anything, then runs the updater, which points the record at this server's public IP. Run with a TTY:
#   ssh -t finprint-host powershell -NoProfile -ExecutionPolicy Bypass -File C:\AI\yanai\scripts\repin-ddns.ps1
param(
    [string]$SettingsPath='C:\AI\yanai\.secrets\vercel-ddns.json',
    [string]$UpdaterPath='C:\AI\yanai\scripts\update-vercel-dns.ps1'
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$settings=Get-Content -Raw -LiteralPath $SettingsPath | ConvertFrom-Json
Add-Type -AssemblyName System.Security
$cipher=[Convert]::FromBase64String([IO.File]::ReadAllText($settings.TokenPath))
$plain=[Security.Cryptography.ProtectedData]::Unprotect($cipher,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
$headers=@{Authorization='Bearer '+[Text.Encoding]::UTF8.GetString($plain)}
[Array]::Clear($plain,0,$plain.Length)
$scope='slug='+[Uri]::EscapeDataString($settings.TeamSlug)
$records=@()
$uri="https://api.vercel.com/v5/domains/$($settings.Domain)/records?limit=100&$scope"
do {
    $page=Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 25
    $records+=@($page.records | Where-Object { $_.name -eq $settings.Subdomain })
    $next=if ($page.PSObject.Properties.Name -contains 'pagination' -and $page.pagination -and $page.pagination.PSObject.Properties.Name -contains 'next') { $page.pagination.next } else { $null }
    $uri=if ($next) { "https://api.vercel.com/v5/domains/$($settings.Domain)/records?limit=100&$scope&until=$next" } else { $null }
} while ($uri)
$headers=$null
if ($records.Count -ne 1 -or $records[0].type -ne 'A') {
    throw "Expected exactly one A record named '$($settings.Subdomain)'; found $($records.Count). Nothing changed."
}
$record=$records[0]
"Record:     $($settings.Subdomain).$($settings.Domain)  A  $($record.value)"
"Saved ID:   $($settings.RecordId)"
"Current ID: $($record.id)"
if ($record.id -ne $settings.RecordId) {
    $answer=Read-Host 'Link the updater to this record and point it at this server''s public IP? (y/N)'
    if ($answer -notmatch '^(y|yes)$') { 'Nothing changed.'; return }
    Copy-Item -LiteralPath $SettingsPath -Destination "$SettingsPath.bak-$(Get-Date -Format yyyyMMddHHmmss)"
    $settings.RecordId=$record.id
    [IO.File]::WriteAllText($SettingsPath,($settings | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
}
& $UpdaterPath -SettingsPath $SettingsPath
