#requires -Version 5.1
param([string]$Root='C:\AI\yanai')
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
foreach ($directory in 'models','bin','logs') {
    New-Item -ItemType Directory -Force -Path (Join-Path $Root $directory) | Out-Null
}
$status=Join-Path $Root 'logs\gemma-download-status.txt'
$source='https://huggingface.co/ggml-org/gemma-4-12B-it-GGUF/resolve/e3e681731089efaa3f0917336944ac64752db8ba'
try {
    'DOWNLOADING_MODEL' | Set-Content $status
    & "$PSScriptRoot\download-model.ps1" -Root $Root -FileName 'gemma-4-12B-it-BF16.gguf' -Uri "$source/gemma-4-12B-it-BF16.gguf" -Size 23832066176 -Sha256 '2851bc5b1a24e766e861652c6e5f72105b3b1efd55be35642456f1171714c292'
    'DOWNLOADING_PROJECTOR' | Set-Content $status
    & "$PSScriptRoot\download-model.ps1" -Root $Root -FileName 'mmproj-gemma-4-12B-it-BF16.gguf' -Uri "$source/mmproj-gemma-4-12B-it-BF16.gguf" -Size 175115616 -Sha256 '9b1edfa05b634728ca4bfd60b4e6b278e95166c078fa54ae4fa83e680112fd1d'
    'VERIFIED' | Set-Content $status
} catch {
    ('FAILED: ' + $_.Exception.Message) | Set-Content $status
    throw
}
