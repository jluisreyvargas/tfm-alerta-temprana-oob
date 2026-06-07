param([int]$TTLMinutes = 30)

Write-Host "RUSTDESK_ID=161 180 321"
Write-Host "RUSTDESK_TTL=$TTLMinutes"

$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
  -Argument "-File C:\tfm-scripts\rustdesk_disable.ps1"

$trigger = New-ScheduledTaskTrigger -Once `
  -At (Get-Date).AddMinutes($TTLMinutes)

Register-ScheduledTask `
  -TaskName "RustDesk-AutoOff" `
  -Action $action `
  -Trigger $trigger `
  -Force

Write-Host "TTL programado: $TTLMinutes minutos"