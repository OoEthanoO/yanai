param([string]$Root='C:\AI\yanai')
$ErrorActionPreference='Stop'
$active='C:\Users\ethan\finprint\scripts\selfhost\Caddyfile'
$caddy=(Get-CimInstance Win32_Process -Filter "Name='caddy.exe'" | Select-Object -First 1).ExecutablePath
if (-not $caddy) { throw 'Existing Caddy process not found' }
$health=Invoke-RestMethod http://127.0.0.1:8082/health -TimeoutSec 15
if (-not $health.status) { throw 'Open WebUI is not healthy' }
$config=Invoke-RestMethod http://127.0.0.1:8082/api/config -TimeoutSec 15
if ($config.onboarding) { throw 'Create the private admin account before publishing' }
$text=Get-Content $active -Raw
$import='import C:/AI/yanai/Caddyfile'
if (-not $text.Contains($import)) {
    $backup=$active+'.yanai-backup-'+(Get-Date -Format yyyyMMddHHmmss)
    Copy-Item -LiteralPath $active -Destination $backup
    # Same managed-block convention as the yanvpn edits in this Caddyfile.
    [IO.File]::WriteAllText($active,($text.TrimEnd()+"`r`n`r`n# BEGIN yanai (managed)`r`n$import`r`n# END yanai (managed)`r`n"),[Text.UTF8Encoding]::new($false))
    $ErrorActionPreference='Continue'
    & $caddy validate --config $active
    if ($LASTEXITCODE -ne 0) { Copy-Item -LiteralPath $backup -Destination $active -Force; throw 'Caddy validation failed; configuration restored' }
    & $caddy reload --config $active
    if ($LASTEXITCODE -ne 0) { Copy-Item -LiteralPath $backup -Destination $active -Force; & $caddy reload --config $active; throw 'Caddy reload failed; configuration restored' }
} else {
    $ErrorActionPreference='Continue'
    & $caddy validate --config $active
    if ($LASTEXITCODE -ne 0) { throw 'Caddy validation failed' }
    & $caddy reload --config $active
    if ($LASTEXITCODE -ne 0) { throw 'Caddy reload failed' }
}
