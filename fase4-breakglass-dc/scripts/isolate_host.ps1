param([string]$target)
Write-Host "TFM-AGENT: Aislando host: $target"
Write-Host "DRY-RUN OK - isolate_host sobre $target"
# En producción, por ejemplo bloquear con firewall:
# netsh advfirewall set allprofiles firewallpolicy blockinbound,blockoutbound