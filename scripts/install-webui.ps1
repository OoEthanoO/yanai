#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\AI\yanai',
    [string]$ConfigPath,
    [string]$PythonPath,
    [string]$UvPath,
    [string]$OpenAIBaseUrl = 'http://127.0.0.1:8081/v1',
    [string]$OpenAIApiKey,
    [string]$DefaultModel = 'Gemma-4-12B-Reasoning',
    [string]$WebuiUrl = 'https://ai.ethanyanxu.com',
    [ValidateRange(1024, 65535)][int]$Port = 8082,
    [switch]$Start
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
if (-not $ConfigPath) { $ConfigPath = Join-Path $InstallRoot '.secrets\webui.json' }
$ConfigPath = [IO.Path]::GetFullPath($ConfigPath)
if (-not $ConfigPath.StartsWith($InstallRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'ConfigPath must be inside the dedicated InstallRoot.'
}

function New-RandomSecret {
    $bytes = New-Object byte[] 48
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return [Convert]::ToBase64String($bytes)
}

function Invoke-NativeChecked {
    param([string]$FilePath, [string[]]$ArgumentList, [string]$FailureMessage)
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "Executable does not exist: $FilePath"
    }
    $previousPreference = $ErrorActionPreference
    try {
        # PowerShell 5.1 can treat normal native stderr (including uv progress)
        # as an error. The executable's exit code determines installation success.
        $ErrorActionPreference = 'Continue'
        & $FilePath @ArgumentList
        $nativeExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($nativeExitCode -ne 0) { throw "$FailureMessage (exit $nativeExitCode)." }
}

function Protect-Directory([string]$Path) {
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
        $identity = New-Object Security.Principal.SecurityIdentifier($sid)
        $rule = New-Object Security.AccessControl.FileSystemAccessRule(
            $identity, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow'
        )
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

# Scripts executed as SYSTEM and account/chat data must not be writable by other users.
New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
Protect-Directory $InstallRoot
foreach ($relativePath in @('.secrets', 'data', 'logs', 'runtime', 'cache\uv', 'scripts')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot $relativePath) | Out-Null
}
$configDirectory = Split-Path -Parent $ConfigPath
New-Item -ItemType Directory -Force -Path $configDirectory | Out-Null
Protect-Directory $configDirectory

$sourceRoot = Split-Path -Parent $PSScriptRoot
$requirementsSource = Join-Path $sourceRoot 'requirements-webui.txt'
$requirementsTarget = Join-Path $InstallRoot 'requirements-webui.txt'
$runnerSource = Join-Path $PSScriptRoot 'run-webui.ps1'
$runnerTarget = Join-Path $InstallRoot 'scripts\run-webui.ps1'
foreach ($pair in @(@($requirementsSource, $requirementsTarget), @($runnerSource, $runnerTarget))) {
    if (-not (Test-Path -LiteralPath $pair[0])) { throw "Missing deployment file: $($pair[0])" }
    if ([IO.Path]::GetFullPath($pair[0]) -ne [IO.Path]::GetFullPath($pair[1])) {
        Copy-Item -LiteralPath $pair[0] -Destination $pair[1] -Force
    }
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    if (-not $OpenAIApiKey) { $OpenAIApiKey = New-RandomSecret }
    $config = [ordered]@{
        WebuiSecretKey = New-RandomSecret
        OpenAIBaseUrl = $OpenAIBaseUrl
        OpenAIApiKey = $OpenAIApiKey
        DefaultModel = $DefaultModel
        WebuiUrl = $WebuiUrl
        Port = $Port
        DataDir = (Join-Path $InstallRoot 'data')
    }
    [IO.File]::WriteAllText($ConfigPath, ($config | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
    Write-Host "Created protected configuration: $ConfigPath"
} else {
    Write-Host "Preserving existing configuration: $ConfigPath"
}

if (-not $UvPath) {
    $uvDirectory = Join-Path $InstallRoot 'runtime\uv'
    $UvPath = Join-Path $uvDirectory 'uv.exe'
    if (-not (Test-Path -LiteralPath $UvPath)) {
        $uvArchive = Join-Path $InstallRoot 'runtime\uv-0.12.17.zip'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/astral-sh/uv/releases/download/0.12.17/uv-x86_64-pc-windows-msvc.zip' -OutFile $uvArchive
        $expectedHash = 'A252121D5B59398FCB137C6EA448176459A44010F33F67E0072305A637119CA7'
        if ((Get-FileHash -LiteralPath $uvArchive -Algorithm SHA256).Hash -ne $expectedHash) {
            throw 'uv archive SHA-256 verification failed.'
        }
        Expand-Archive -LiteralPath $uvArchive -DestinationPath $uvDirectory -Force
    }
}
if (-not (Test-Path -LiteralPath $UvPath)) { throw "uv executable missing: $UvPath" }
$env:UV_CACHE_DIR = Join-Path $InstallRoot 'cache\uv'
$env:UV_PYTHON_INSTALL_DIR = Join-Path $InstallRoot 'runtime\python'
$env:UV_LINK_MODE = 'copy'
if (-not $PythonPath) {
    foreach ($candidate in @('C:\Program Files\Python312\python.exe', 'C:\Program Files\Python311\python.exe')) {
        if (Test-Path -LiteralPath $candidate) { $PythonPath = $candidate; break }
    }
}
if (-not $PythonPath) {
    Invoke-NativeChecked -FilePath $UvPath -ArgumentList @('python', 'install', '3.11') -FailureMessage 'Managed Python installation failed'
    $PythonPath = (Invoke-NativeChecked -FilePath $UvPath -ArgumentList @('python', 'find', '--managed-python', '3.11') -FailureMessage 'Managed Python lookup failed' | Select-Object -Last 1).Trim()
}
Invoke-NativeChecked -FilePath $PythonPath -ArgumentList @('-c', "import sys; assert sys.version_info[:2] in ((3, 11), (3, 12)), 'Python 3.11 or 3.12 required'") -FailureMessage 'Unsupported Python version'
$venvPath = Join-Path $InstallRoot '.venv'
$venvPython = Join-Path $venvPath 'Scripts\python.exe'
if (-not (Test-Path -LiteralPath $venvPython)) {
    Invoke-NativeChecked -FilePath $UvPath -ArgumentList @('venv', '--python', $PythonPath, $venvPath) -FailureMessage 'Virtual environment creation failed'
}
Invoke-NativeChecked -FilePath $UvPath -ArgumentList @('pip', 'install', '--python', $venvPython, '--requirements', $requirementsTarget) -FailureMessage 'Open WebUI package installation failed'
Invoke-NativeChecked -FilePath $UvPath -ArgumentList @('pip', 'check', '--python', $venvPython) -FailureMessage 'Installed dependency validation failed'
Invoke-NativeChecked -FilePath $venvPython -ArgumentList @('-c', "import importlib.metadata; print('Open WebUI ' + importlib.metadata.version('open-webui'))") -FailureMessage 'Open WebUI version verification failed'

$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -InstallRoot "{1}" -ConfigPath "{2}"' -f $runnerTarget, $InstallRoot, $ConfigPath
$action = New-ScheduledTaskAction -Execute $powershell -Argument $arguments -WorkingDirectory $InstallRoot
$trigger = New-ScheduledTaskTrigger -AtStartup
$trigger.Delay = 'PT20S'
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName 'yanai-webui' -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'Local Open WebUI for YanAI; localhost only, protected account data, automatic restart.' -Force | Out-Null
if ($Start) { Start-ScheduledTask -TaskName 'yanai-webui' }
Write-Host 'Open WebUI installed; startup task: yanai-webui.'
Write-Host 'Before exposing the reverse proxy, create the first admin through localhost (provision-admin.py); later signups stay pending until approved.'
