param(
    [string]$Root='C:\AI\yanai',
    [string]$FileName='Qwen3.6-35B-A3B-Q4_K_M.gguf',
    # Pinned to a repository commit so the size and hash below stay valid.
    [string]$Uri='https://huggingface.co/ggml-org/Qwen3.6-35B-A3B-GGUF/resolve/baec3ebee244827cda0f4557eafa8b28f7545fa6/Qwen3.6-35B-A3B-Q4_K_M.gguf',
    [long]$Size=20419565568,
    [string]$Sha256='671e47e0ec53c665d048b98c3ecbfd5236b5ca9c3e02ed19fc8f81f7b85140c7'
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
