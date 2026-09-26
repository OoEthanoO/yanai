param([Parameter(Mandatory=$true)][string]$Script)
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("`$ProgressPreference='SilentlyContinue'; " + $Script))
& ssh -o BatchMode=yes finprint-host "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded"
if ($LASTEXITCODE -ne 0) { throw "Home server command exited with code $LASTEXITCODE" }
