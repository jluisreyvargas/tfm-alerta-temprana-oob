param([string]$target)
Write-Host "TFM-AGENT: Habilitando cuenta AD: $target"
Write-Host "DRY-RUN OK - Enable-ADAccount -Identity $target"
# En producción:
# Enable-ADAccount -Identity $target