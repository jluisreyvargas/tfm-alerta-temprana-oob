param([string]$target)
Write-Host "TFM-AGENT: Deshabilitando cuenta AD: $target"
# En lab sin AD real, solo dry-run:
Write-Host "DRY-RUN OK - Disable-ADAccount -Identity $target"
# En producción descomentar la siguiente línea:
# Disable-ADAccount -Identity $target