param([int]$TTLMinutes = 30)

$ErrorActionPreference = "Stop"
$warnings = @()

# 1. Revertir el Disabled que dejó rustdesk_disable.ps1
Set-Service -Name RustDesk -StartupType Manual
Start-Service -Name RustDesk
Start-Sleep -Seconds 5
$svc = Get-Service -Name RustDesk

# 2. Identificador del par: NO se resuelve en el propio DC. En un escenario
# break-glass el endpoint puede estar comprometido, asi que la identidad del
# par debe proceder del componente bajo control del equipo de respuesta (el
# servidor hbbs), no del sistema bajo investigacion. El orquestador resuelve
# el ID real consultando rustdesk/data/db_v2.sqlite3 en hbbs
# (ver docs/README-fase4-validacion.md, seccion 5.2).
$rustdeskId = "resolver_en_hbbs"

# 3. Contraseña de un solo uso para esta sesión break-glass.
# RandomNumberGenerator en vez de Get-Random: Get-Random usa un PRNG no apto
# para material criptográfico.
$bytes = New-Object byte[] 16
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
$pass = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })

try {
    & "$env:ProgramFiles\RustDesk\rustdesk.exe" --password $pass
} catch {
    $warnings += "No se pudo fijar la contrasena en el cliente RustDesk: $_"
}

# 4. TTL. Principal explicito requerido: sin -Principal con LogonType
# ServiceAccount, Register-ScheduledTask falla con 0x80070534 cuando se
# invoca bajo el contexto SYSTEM del servicio del agente (no se manifiesta
# al ejecutar el script desde una sesion interactiva).
$action    = New-ScheduledTaskAction -Execute "PowerShell.exe" `
               -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\tfm-scripts\rustdesk_disable.ps1"
$trigger   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes($TTLMinutes)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "RustDesk-AutoOff" -Action $action `
  -Trigger $trigger -Principal $principal -Force | Out-Null
$task = Get-ScheduledTask -TaskName "RustDesk-AutoOff"

# 5. Salida estructurada para el orquestador
[ordered]@{
    password    = $pass
    rustdesk_id = $rustdeskId
    service     = $svc.Status.ToString()
    ttl_task    = $task.State.ToString()
    warnings    = $warnings
    ttl_minutes = $TTLMinutes
} | ConvertTo-Json -Compress
