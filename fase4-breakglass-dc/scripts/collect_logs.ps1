param([string]$target)

$ErrorActionPreference = "Stop"

$events = Get-WinEvent -FilterHashtable @{LogName='Security'} -MaxEvents 50 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, LevelDisplayName, MachineName,
                  @{N='Message';E={ $_.Message -replace '[\r\n]+',' ' }}

$json = $events | ConvertTo-Json -Depth 4 -Compress
$hash = [System.BitConverter]::ToString(
    [System.Security.Cryptography.SHA256]::Create().ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($json))).Replace("-","").ToLower()

@{
    collector   = "collect_logs.ps1"
    target      = $target
    host        = $env:COMPUTERNAME
    collected_at= (Get-Date).ToUniversalTime().ToString("o")
    event_count = $events.Count
    sha256      = $hash
    events      = $events
} | ConvertTo-Json -Depth 5 -Compress
