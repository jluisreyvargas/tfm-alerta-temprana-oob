param([int]$TTLMinutes = 30)

$ErrorActionPreference = "Stop"

# 1. Revertir el Disabled que dejó rustdesk_disable.ps1
Set-Service -Name RustDesk -StartupType Manual
Start-Service -Name RustDesk
Start-Sleep -Seconds 5

# 2. Leer el ID real del host (nunca hardcodearlo en el repositorio)
$toml = "$env:APPDATA\RustDesk\config\RustDesk.toml"
$rustdeskId = ""
if (Test-Path $toml) {
    $m = Select-String -Path $toml -Pattern "^id\s*=\s*'(.+)'"
    if ($m) { $rustdeskId = $m.Matches.Groups[1].Value }
}

# 3. Contraseña de un solo uso para esta sesión break-glass
$pass = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 16 | ForEach-Object {[char]$_})
& "$env:ProgramFiles\RustDesk\rustdesk.exe" --password $pass

# 4. TTL
$action  = New-ScheduledTaskAction -Execute "PowerShell.exe" `
             -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\tfm-scripts\rustdesk_disable.ps1"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes($TTLMinutes)
Register-ScheduledTask -TaskName "RustDesk-AutoOff" -Action $action `
  -Trigger $trigger -RunLevel Highest -Force | Out-Null

# 5. Salida estructurada para el orquestador
@{ rustdesk_id = $rustdeskId; password = $pass; ttl_minutes = $TTLMinutes } |
  ConvertTo-Json -Compress
