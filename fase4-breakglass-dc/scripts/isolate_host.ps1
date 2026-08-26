param([string]$target)

$ErrorActionPreference = "Stop"

$HeadscaleIP = $env:TFM_HEADSCALE_IP    # host Traefik/Headscale
$TailnetCIDR = "100.64.0.0/10"

Write-Host "TFM-AGENT: Aislando host: $target"

# Preservar SIEMPRE el canal OOB antes de bloquear.
New-NetFirewallRule -DisplayName "TFM-OOB-Keepalive-Control" -Direction Outbound `
  -RemoteAddress $HeadscaleIP -Action Allow -Enabled True -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "TFM-OOB-Keepalive-Tailnet" -Direction Outbound `
  -RemoteAddress $TailnetCIDR -Action Allow -Enabled True -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "TFM-OOB-Keepalive-Wireguard" -Direction Outbound `
  -Protocol UDP -LocalPort 41641 -Action Allow -Enabled True -ErrorAction SilentlyContinue | Out-Null

Write-Host "DRY-RUN OK - reglas de preservacion OOB creadas; bloqueo pendiente de descomentar"
# Producción:
# Set-NetFirewallProfile -All -DefaultInboundAction Block -DefaultOutboundAction Block
