# Fase 4c — Python Agent en el DC (via Headscale)

## Objetivo

Desplegar un agente Python (FastAPI + Uvicorn) en el Domain Controller Windows 2025 para exponer un endpoint HTTP autenticado y controlado, accesible exclusivamente a través de la red privada Headscale/Tailscale del enclave OOB.

El agente permite al orquestador ejecutar scripts PowerShell predefinidos en el DC de forma segura, con autenticación Bearer Token, allowlist estricta de scripts y logging de cada ejecución. Ningún puerto del DC queda expuesto a Internet ni a la red corporativa general.

## Alcance

- Instalación de Python 3.11 en el DC Windows 2025 vía winget.
- Despliegue del agente FastAPI en `C:\tfm-agent\agent_dc.py`.
- Scripts PowerShell de acción en `C:\tfm-scripts\`.
- Regla de firewall Windows para limitar acceso al puerto 8000 únicamente desde la red Tailscale (100.64.0.0/10).
- Validación end-to-end desde el orquestador Linux por la red Headscale.

## Prerrequisitos

- Fase 4a cerrada: Headscale operativo en Docker en el enclave.
- Fase 4b cerrada: nodos `orchestrator-tfm` (100.64.0.1) y `dc01-tfm` (100.64.0.2) registrados y activos en la tailnet.
- Conectividad directa entre nodos validada (`active; direct`).
- Python instalado en el DC Windows 2025.

## Instalación de Python en el DC

Ejecutar en PowerShell como administrador:

```powershell
winget install -e --id Python.Python.3.11 --scope machine
```

Verificar instalación (nueva sesión PowerShell):

```powershell
python --version
pip --version
```

## Estructura de ficheros en el DC

```text
C:\
├── tfm-agent\
│   └── agent_dc.py
└── tfm-scripts\
    ├── disable_account.ps1
    ├── enable_account.ps1
    ├── collect_logs.ps1
    ├── isolate_host.ps1
    └── reset_password.ps1
```

Crear los directorios:

```powershell
mkdir C:\tfm-agent
mkdir C:\tfm-scripts
```

## Código del agente

### `C:\tfm-agent\agent_dc.py`

```python
from fastapi import FastAPI, Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import subprocess, os, logging

app = FastAPI(title="TFM DC Agent", version="1.0")
security = HTTPBearer()
VALID_TOKEN = os.environ.get("AGENT_TOKEN", "")

logging.basicConfig(level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s")

ALLOWED_SCRIPTS = [
    "disable_account.ps1",
    "enable_account.ps1",
    "collect_logs.ps1",
    "isolate_host.ps1",
    "reset_password.ps1"
]

def verify_token(creds: HTTPAuthorizationCredentials = Depends(security)):
    if not VALID_TOKEN:
        raise HTTPException(status_code=500, detail="AGENT_TOKEN not set")
    if creds.credentials != VALID_TOKEN:
        raise HTTPException(status_code=403, detail="Forbidden")

@app.post("/run")
async def run_script(payload: dict, _=Depends(verify_token)):
    script = payload.get("script", "")
    target = payload.get("target", "")
    if script not in ALLOWED_SCRIPTS:
        logging.warning(f"Script rechazado: {script}")
        raise HTTPException(status_code=400, detail=f"Script no permitido: {script}")
    logging.info(f"Ejecutando {script} sobre target={target}")
    result = subprocess.run(
        ["powershell.exe", "-ExecutionPolicy", "Bypass",
         "-File", f"C:\\tfm-scripts\\{script}",
         "-target", target],
        capture_output=True, text=True, timeout=60
    )
    logging.info(f"returncode={result.returncode}")
    return {
        "script": script,
        "target": target,
        "stdout": result.stdout,
        "stderr": result.stderr,
        "returncode": result.returncode
    }

@app.get("/health")
async def health():
    return {"status": "ok", "agent": "dc01-tfm"}
```

## Scripts PowerShell

### `C:\tfm-scripts\disable_account.ps1`

```powershell
param([string]$target)
Write-Host "TFM-AGENT: Deshabilitando cuenta AD: $target"
Write-Host "DRY-RUN OK - Disable-ADAccount -Identity $target"
# Producción: Disable-ADAccount -Identity $target
```

### `C:\tfm-scripts\enable_account.ps1`

```powershell
param([string]$target)
Write-Host "TFM-AGENT: Habilitando cuenta AD: $target"
Write-Host "DRY-RUN OK - Enable-ADAccount -Identity $target"
# Producción: Enable-ADAccount -Identity $target
```

### `C:\tfm-scripts\collect_logs.ps1`

```powershell
param([string]$target)
Write-Host "TFM-AGENT: Recogiendo logs del sistema"
$logs = Get-EventLog -LogName Security -Newest 20 |
    Select-Object TimeGenerated, EntryType, Message
$logs | Format-List
Write-Host "DRY-RUN OK - collect_logs sobre $target"
```

### `C:\tfm-scripts\isolate_host.ps1`

```powershell
param([string]$target)
Write-Host "TFM-AGENT: Aislando host: $target"
Write-Host "DRY-RUN OK - isolate_host sobre $target"
# Producción: netsh advfirewall set allprofiles firewallpolicy blockinbound,blockoutbound
```

### `C:\tfm-scripts\reset_password.ps1`

```powershell
param([string]$target)
Write-Host "TFM-AGENT: Reset de contraseña para: $target"
Write-Host "DRY-RUN OK - Set-ADAccountPassword -Identity $target"
# Producción: Set-ADAccountPassword -Identity $target -Reset -NewPassword (Read-Host -AsSecureString)
```

## Regla de firewall Windows

Ejecutar en PowerShell como administrador para restringir el acceso al agente exclusivamente desde la red Tailscale:

```powershell
New-NetFirewallRule `
  -DisplayName "TFM DC Agent - Solo Tailscale" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 8000 `
  -RemoteAddress 100.64.0.0/10 `
  -Action Allow
```

## Resolución de nombres en el orquestador

Para poder usar el nombre `dc01-tfm` desde el orquestador Linux, se ha añadido la entrada correspondiente en `/etc/hosts`:

```bash
sudo nano /etc/hosts
```

Línea añadida:

```
100.64.0.2   dc01-tfm
```

## Arranque del agente

Instalar dependencias (una sola vez):

```powershell
pip install fastapi uvicorn
```

Arrancar el agente en PowerShell como administrador:

```powershell
$env:AGENT_TOKEN = "tfm-token-secreto-2024"
cd C:\tfm-agent
uvicorn agent_dc:app --host 0.0.0.0 --port 8000
```

Salida esperada al arrancar correctamente:

```
INFO:     Started server process
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000
```

## Validación end-to-end

Todas las pruebas se ejecutan desde el orquestador Linux (`orchestrator-tfm`, 100.64.0.1) hacia el DC (`dc01-tfm`, 100.64.0.2) por la red privada Headscale.

### Prueba 1 — Health check

```bash
curl http://dc01-tfm:8000/health
```

Respuesta obtenida:

```json
{"status":"ok","agent":"dc01-tfm"}
```

### Prueba 2 — Ejecución de script válido (dry-run)

```bash
curl -s -X POST http://dc01-tfm:8000/run \
  -H "Authorization: Bearer tfm-token-secreto-2024" \
  -H "Content-Type: application/json" \
  -d '{"script":"disable_account.ps1","target":"usuario.prueba"}'
```

Respuesta obtenida:

```json
{
  "script": "disable_account.ps1",
  "target": "usuario.prueba",
  "stdout": "TFM-AGENT: Deshabilitando cuenta AD: usuario.prueba\nDRY-RUN OK - Disable-ADAccount -Identity usuario.prueba\n",
  "stderr": "",
  "returncode": 0
}
```

### Prueba 3 — Script fuera del allowlist (debe rechazarse)

```bash
curl -s -X POST http://dc01-tfm:8000/run \
  -H "Authorization: Bearer tfm-token-secreto-2024" \
  -H "Content-Type: application/json" \
  -d '{"script":"malicioso.ps1","target":"x"}'
```

Respuesta obtenida:

```json
{"detail":"Script no permitido: malicioso.ps1"}
```

### Prueba 4 — Token incorrecto (debe rechazarse con 403)

```bash
curl -s -X POST http://dc01-tfm:8000/run \
  -H "Authorization: Bearer token-incorrecto" \
  -H "Content-Type: application/json" \
  -d '{"script":"disable_account.ps1","target":"test"}'
```

Respuesta obtenida:

```json
{"detail":"Forbidden"}
```

## Estado de la tailnet en el momento de la validación

```
100.64.0.1  orchestrator-tfm  tfm-oob  linux    -
100.64.0.2  dc01-tfm          tfm-oob  windows  active; direct 192.168.127.153:41641, tx 860 rx 852
```

La conexión es `direct` (sin pasar por servidor DERP de relay), lo que confirma conectividad WireGuard directa entre los nodos.

## Resultado de la Fase 4c

La Fase 4c queda completada con el agente Python operativo en el DC Windows 2025, accesible desde el orquestador exclusivamente por la red privada Headscale, con autenticación Bearer Token validada, allowlist de scripts funcional y logging de cada ejecución.

El sistema está preparado para continuar con la Fase 4d — integración del flujo de aprobaciones Rocket.Chat → Orquestador → DC Agent → callback.

## Comandos de commit

```bash
cd /home/jose/tfm-alerta-temprana-oob

git add fase4-breakglass-dc/
git commit -m "fase4c: python agent en DC validado via headscale tailnet"
git push origin main
```
