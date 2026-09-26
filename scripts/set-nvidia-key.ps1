#requires -Version 5.1
#requires -RunAsAdministrator
# Prompts for an NVIDIA API key (hidden input), checks it against Kimi K3, and stores it
# DPAPI-encrypted for this machine. The key is never printed. Run over SSH with a TTY:
#   ssh -t finprint-host powershell -NoProfile -ExecutionPolicy Bypass -File C:\AI\yanai\scripts\set-nvidia-key.ps1
param([string]$Root='C:\AI\yanai', [string]$Model='moonshotai/kimi-k3')
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$keyPath=Join-Path $Root '.secrets\nvidia-api-key.dpapi'

$secure=Read-Host 'Paste your NVIDIA API key (input is hidden), then press Enter' -AsSecureString
$bstr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $key=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim() } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
if ($key -notmatch '^nvapi-\S{20,}$') { throw 'That does not look like an NVIDIA API key (it should start with nvapi-). Nothing was saved.' }

Write-Host 'Checking the key with Kimi K3...'
$body=@{model=$Model;max_tokens=16;messages=@(@{role='user';content='Reply with OK.'})} | ConvertTo-Json -Depth 5
try {
    Invoke-RestMethod -Method Post 'https://integrate.api.nvidia.com/v1/chat/completions' -Headers @{Authorization="Bearer $key"} -ContentType 'application/json' -Body $body -TimeoutSec 180 | Out-Null
} catch {
    $code=if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 'network error' }
    $key=$null
    throw "NVIDIA did not accept the key or the request failed ($code). Nothing was saved."
}

Add-Type -AssemblyName System.Security
$cipher=[Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($key),$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
$key=$null
[IO.File]::WriteAllText($keyPath,[Convert]::ToBase64String($cipher),[Text.UTF8Encoding]::new($false))
Write-Host 'Key works with Kimi K3 and is saved (encrypted for this machine). You can tell Claude it is done.'
