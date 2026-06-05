param([string]$target)
Write-Host "TFM-AGENT: Reset de contraseña para: $target"
Write-Host "DRY-RUN OK - Set-ADAccountPassword -Identity $target"
# En producción:
# Set-ADAccountPassword -Identity $target -Reset -NewPassword (Read-Host -AsSecureString)