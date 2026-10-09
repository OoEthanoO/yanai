#requires -Version 5.1
#requires -RunAsAdministrator
# Prompts for a hosted-model API key (hidden input), checks that the provider accepts it, and stores it
# DPAPI-encrypted for this machine as .secrets\<name>-api-key.dpapi. The key is never printed.
# Run over SSH with a TTY, for example:
#   ssh -t finprint-host powershell -NoProfile -ExecutionPolicy Bypass -File C:\AI\yanai\scripts\set-api-key.ps1 -Name openrouter
param(
    [Parameter(Mandatory=$true)][ValidateSet('openrouter','nvidia')][string]$Name,
    [string]$Root='C:\AI\yanai'
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$prefix=@{ openrouter='sk-or-'; nvidia='nvapi-' }[$Name]
$keyPath=Join-Path $Root ".secrets\$Name-api-key.dpapi"

$secure=Read-Host "Paste your $Name API key (input is hidden), then press Enter" -AsSecureString
$bstr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $key=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim() } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
if (-not $key.StartsWith($prefix) -or $key.Length -lt 20) { throw "That does not look like a $Name API key (it should start with $prefix). Nothing was saved." }

Write-Host "Checking the key with $Name..."
$headers=@{Authorization="Bearer $key"}
try {
    if ($Name -eq 'openrouter') {
        # Key info costs no model requests, so it does not use up the free daily allowance.
        $info=(Invoke-RestMethod 'https://openrouter.ai/api/v1/key' -Headers $headers -TimeoutSec 60).data
        Write-Host ("Account on OpenRouter's free tier (no credits purchased, 50 free-model requests a day): {0}" -f $info.is_free_tier)
    } else {
        $body=@{model='moonshotai/kimi-k3';max_tokens=16;messages=@(@{role='user';content='Reply with OK.'})} | ConvertTo-Json -Depth 5
        Invoke-RestMethod -Method Post 'https://integrate.api.nvidia.com/v1/chat/completions' -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 180 | Out-Null
    }
} catch {
    $code=if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 'network error' }
    $key=$null; $headers=$null
    throw "$Name did not accept the key or the request failed ($code). Nothing was saved."
}
$headers=$null

Add-Type -AssemblyName System.Security
$cipher=[Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($key),$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
$key=$null
[IO.File]::WriteAllText($keyPath,[Convert]::ToBase64String($cipher),[Text.UTF8Encoding]::new($false))
Write-Host "Key accepted by $Name and saved (encrypted for this machine). You can tell Claude it is done."
