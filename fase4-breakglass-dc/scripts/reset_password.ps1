param([string]$target)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Web
$newPass = [System.Web.Security.Membership]::GeneratePassword(20, 5)

Write-Host "TFM-AGENT: Reset de contrasena para: $target"
Write-Host "DRY-RUN OK - Set-ADAccountPassword -Identity $target"
# Producción:
# $secure = ConvertTo-SecureString $newPass -AsPlainText -Force
# Set-ADAccountPassword -Identity $target -Reset -NewPassword $secure
# Set-ADUser -Identity $target -ChangePasswordAtLogon $true

@{ target = $target; password = $newPass; must_change = $true } | ConvertTo-Json -Compress
