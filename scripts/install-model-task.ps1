param([string]$Root='C:\AI\yanai',[switch]$Start)
$ErrorActionPreference='Stop'
$config=Get-Content (Join-Path $Root '.secrets\webui.json') -Raw | ConvertFrom-Json
if (-not $config.OpenAIApiKey) { throw 'WebUI configuration needs OpenAIApiKey' }
[IO.File]::WriteAllText((Join-Path $Root '.secrets\llama-api-key.txt'),$config.OpenAIApiKey,[Text.UTF8Encoding]::new($false))
$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Root\scripts\run-model.ps1`" -Root `"$Root`"" -WorkingDirectory $Root
$principal=New-ScheduledTaskPrincipal -UserId SYSTEM -LogonType ServiceAccount -RunLevel Highest
$settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
$trigger=New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName 'yanai-model' -Action $action -Principal $principal -Settings $settings -Trigger $trigger -Description 'Local llama.cpp CUDA inference (see run-model.ps1) on loopback' -Force | Out-Null
if ($Start) { Start-ScheduledTask yanai-model }
