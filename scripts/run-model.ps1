param([string]$Root='C:\AI\yanai')
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
Set-Location $Root
$binary=Join-Path $Root 'bin\llama\llama-server.exe'
$model=Join-Path $Root 'models\Qwen3.6-35B-A3B-Q4_K_M.gguf'
$mmproj=Join-Path $Root 'models\mmproj-Qwen3.6-35B-A3B-Q8_0.gguf'
$keyFile=Join-Path $Root '.secrets\llama-api-key.txt'
if (-not (Test-Path $binary) -or -not (Test-Path $model) -or -not (Test-Path $mmproj) -or -not (Test-Path $keyFile)) { throw 'Model, vision projector, runtime or API key is missing' }
# MoE model: --fit keeps attention and shared weights on the GPU and spills expert weights to the CPU.
# Sampling follows Qwen's recommendation for thinking mode on general tasks. The chat template drops
# earlier turns' thinking by default; --no-reasoning-preserve keeps it that way to save context.
$arguments=@(
    '--model',$model,'--alias','Qwen3.6-35B-A3B',
    # Image input. The token cap (~2 megapixels) keeps big phone photos from exhausting the 8 GB GPU.
    '--mmproj',$mmproj,'--image-max-tokens','2048',
    '--host','127.0.0.1','--port','8081','--api-key-file',$keyFile,
    '--ctx-size','65536','--parallel','1','--threads','8','--threads-batch','8',
    '--flash-attn','on','--fit','on','--fit-target','768',
    '--cache-type-k','q8_0','--cache-type-v','q8_0',
    '--jinja','--no-context-shift','--no-reasoning-preserve',
    '--temp','1','--top-p','0.95','--top-k','20','--min-p','0',
    '--presence-penalty','1.5','--repeat-penalty','1'
)
# Keep the previous run's logs so a crash is still diagnosable after the automatic restart.
$logs=Join-Path $Root 'logs'
foreach ($stream in 'stdout','stderr') {
    $log=Join-Path $logs "model.$stream.log"
    if (Test-Path $log) { Move-Item -LiteralPath $log -Destination "$log.prev" -Force }
}
# Start-Process avoids PowerShell 5.1 wrapping every native stderr line in an ErrorRecord.
$process=Start-Process -FilePath $binary -ArgumentList $arguments -WorkingDirectory $Root -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logs 'model.stdout.log') -RedirectStandardError (Join-Path $logs 'model.stderr.log') -PassThru -Wait
# The server is expected to stay running; let Task Scheduler restart it.
if ($process.ExitCode -eq 0) { exit 1 }
exit $process.ExitCode
