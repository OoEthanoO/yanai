param(
    [string]$Root='C:\AI\yanai',
    [string]$FileName='gemma-4-12B-it-BF16.gguf',
    # Pinned to a repository commit so the size and hash below stay valid.
    [string]$Uri='https://huggingface.co/ggml-org/gemma-4-12B-it-GGUF/resolve/e3e681731089efaa3f0917336944ac64752db8ba/gemma-4-12B-it-BF16.gguf',
    [long]$Size=23832066176,
    [string]$Sha256='2851bc5b1a24e766e861652c6e5f72105b3b1efd55be35642456f1171714c292'
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$log=Join-Path $Root 'logs\download.log'
$status=Join-Path $Root 'logs\download-status.txt'
'RUNNING' | Set-Content $status
Start-Transcript -Path $log -Append
try {
    $model=Join-Path $Root "models\$FileName"
    if (-not (Test-Path $model)) {
        & curl.exe -sS -L --fail --retry 8 --retry-delay 5 --continue-at - --output "$model.partial" $Uri
        if ($LASTEXITCODE -ne 0) { throw 'Model download failed' }
        if ((Get-Item "$model.partial").Length -ne $Size) { throw 'Model size mismatch' }
        if ((Get-FileHash "$model.partial" -Algorithm SHA256).Hash -ne $Sha256) { throw 'Model SHA256 mismatch' }
        Move-Item -LiteralPath "$model.partial" -Destination $model
    } else {
        if ((Get-Item $model).Length -ne $Size) { throw 'Existing model size mismatch' }
        if ((Get-FileHash $model -Algorithm SHA256).Hash -ne $Sha256) { throw 'Existing model SHA256 mismatch' }
    }
    if (-not (Test-Path (Join-Path $Root 'bin\llama\llama-server.exe'))) {
        foreach ($name in 'llama-b10964-bin-win-cuda-12.4-x64.zip','cudart-llama-bin-win-cuda-12.4-x64.zip') {
            $zip=Join-Path $Root "bin\$name"
            & curl.exe -sS -L --fail --retry 5 --continue-at - --output $zip "https://github.com/ggml-org/llama.cpp/releases/download/b10964/$name"
            if ($LASTEXITCODE -ne 0) { throw "Download failed: $name" }
            Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $Root 'bin\llama') -Force
        }
    }
    "VERIFIED $FileName" | Set-Content $status
} catch {
    "FAILED $FileName $($_.Exception.Message)" | Set-Content $status
    throw
} finally { Stop-Transcript }
