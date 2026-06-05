param([string]$target)
Write-Host "TFM-AGENT: Recogiendo logs del sistema"
$logs = Get-EventLog -LogName Security -Newest 20 | Select-Object TimeGenerated, EntryType, Message
$logs | Format-List
Write-Host "DRY-RUN OK - collect_logs sobre $target"