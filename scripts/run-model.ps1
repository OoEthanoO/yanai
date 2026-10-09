param([string]$Root='C:\AI\yanai')
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
Set-Location $Root
$binary=Join-Path $Root 'bin\llama\llama-server.exe'
$model=Join-Path $Root 'models\gemma-4-12B-it-BF16.gguf'
$mmproj=Join-Path $Root 'models\mmproj-gemma-4-12B-it-BF16.gguf'
$alias='Gemma-4-12B-Reasoning'
$keyFile=Join-Path $Root '.secrets\llama-api-key.txt'
if (-not (Test-Path $binary) -or -not (Test-Path $model) -or -not (Test-Path $mmproj) -or -not (Test-Path $keyFile)) { throw 'Model, vision projector, runtime or API key is missing' }
# Original BF16 weights and projector, with an unquantized F16 attention cache.
# The context is explicit so --fit may adjust GPU offload but cannot shrink the native window.
# mlock uses VirtualLock on Windows for CPU weights; a working-set minimum alone did not prevent
# idle pageouts. Disable CUDA host buffers to avoid one huge CUDA-pinned allocation during loading.
$arguments=@(
    '--model',$model,'--alias',$alias,
    '--mmproj',$mmproj,'--no-mmproj-offload','--image-max-tokens','1120',
    '--host','127.0.0.1','--port','8081','--api-key-file',$keyFile,
    '--ctx-size','262144','--parallel','1','--threads','8','--threads-batch','8',
    '--batch-size','512','--ubatch-size','128',
    '--flash-attn','on','--fit','on','--fit-target','1024',
    '--cache-type-k','f16','--cache-type-v','f16',
    '--load-mode','mmap+mlock','--no-host','--lazy-mode','off','--sleep-idle-seconds','-1',
    # Bound auxiliary caches so old prompt snapshots cannot crowd out active model/context memory.
    '--cache-ram','512','--ctx-checkpoints','4',
    '--jinja','--no-context-shift','--no-reasoning-preserve','--reasoning','on',
    '--reasoning-format','deepseek',
    '--temp','1','--top-p','0.95','--top-k','64','--min-p','0',
    '--presence-penalty','0','--repeat-penalty','1'
)
# Keep the previous run's logs so a crash is still diagnosable after the automatic restart.
$logs=Join-Path $Root 'logs'
$readyFile=Join-Path $logs 'model-ready.json'
if (Test-Path $readyFile) { Remove-Item -LiteralPath $readyFile }
foreach ($stream in 'stdout','stderr') {
    $log=Join-Path $logs "model.$stream.log"
    if (Test-Path $log) { Move-Item -LiteralPath $log -Destination "$log.prev" -Force }
}
# Start-Process avoids PowerShell 5.1 wrapping every native stderr line in an ErrorRecord.
$process=Start-Process -FilePath $binary -ArgumentList $arguments -WorkingDirectory $Root -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logs 'model.stdout.log') -RedirectStandardError (Join-Path $logs 'model.stderr.log') -PassThru
$null=$process.Handle  # keep a handle so ExitCode is available after the process ends

# Warm prompt evaluation and token generation once at startup. Do not trim the process working set:
# that discards useful pages and makes the next request reload them. Do not log prompt/response text.
$pinLog=Join-Path $logs 'model.pin.log'
try {
    $deadline=(Get-Date).AddMinutes(15)
    $ready=$false
    while (-not $process.HasExited -and -not $ready -and (Get-Date) -lt $deadline) {
        Start-Sleep 5
        try { $ready=(Invoke-RestMethod 'http://127.0.0.1:8081/health' -TimeoutSec 5).status -eq 'ok' } catch { }
    }
    if ($ready) {
        $headers=@{Authorization='Bearer '+([IO.File]::ReadAllLines($keyFile) | Where-Object { $_ -and -not $_.StartsWith('#') } | Select-Object -First 1).Trim()}
        $text='The committee reviewed the annual budget and training schedule. ' * 12
        $body=@{model=$alias;max_tokens=2;messages=@(@{role='user';content="$text Summarise this in one word."})} | ConvertTo-Json -Depth 5
        Invoke-RestMethod -Method Post 'http://127.0.0.1:8081/v1/chat/completions' -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 600 | Out-Null
        $headers=$null
        $process.Refresh()
        $lockErrors=Select-String -Path (Join-Path $logs 'model.stderr.log') -Pattern 'failed to VirtualLock|failed to mlock|SetProcessWorkingSetSize failed' -Quiet
        Add-Content $pinLog ('{0} warmup=complete load_mode=mmap+mlock lock_warning={1} working_set_GB={2:N2}' -f (Get-Date -Format s), [bool]$lockErrors, ($process.WorkingSet64/1GB))
        [ordered]@{Pid=$process.Id;Model=$alias;Context=262144;Weights='BF16';Cache='F16';WarmupComplete=$true;LockWarning=[bool]$lockErrors;ReadyAt=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -Encoding ASCII $readyFile
    } else {
        Add-Content $pinLog ('{0} server not ready; warmup incomplete' -f (Get-Date -Format s))
    }
} catch {
    Add-Content $pinLog ('{0} warmup failed: {1}' -f (Get-Date -Format s), $_.Exception.Message)
}

$process.WaitForExit()
if (Test-Path $readyFile) { Remove-Item -LiteralPath $readyFile }
# The server is expected to stay running; let Task Scheduler restart it.
if ($process.ExitCode -eq 0) { exit 1 }
exit $process.ExitCode
