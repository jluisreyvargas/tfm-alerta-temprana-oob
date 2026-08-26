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

> **Requisito previo de red/PKI:** antes de desplegar, el nodo del DC debe tener
> instalada la CA del enclave (ver `fase1-infraestructura/`) y debe poder resolver
> `hs.oob.local` (registrado en Headscale/MagicDNS o vía `/etc/hosts`/`hosts` local),
> ya que tanto el registro en la tailnet como cualquier llamada saliente que valide
> TLS contra el enclave dependen de ello.

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
│   ├── agent_dc.py
│   ├── requirements.txt
│   └── logs\
└── tfm-scripts\
    ├── disable_account.ps1
    ├── enable_account.ps1
    ├── collect_logs.ps1
    ├── isolate_host.ps1
    ├── reset_password.ps1
    ├── rustdesk_enable.ps1
    └── rustdesk_disable.ps1
```

Ver `fase4-breakglass-dc/dcagent/README-despliegue.md` para el detalle completo de
ACLs de directorio y registro como servicio Windows con NSSM.

Crear los directorios:

```powershell
mkdir C:\tfm-agent
mkdir C:\tfm-scripts
```

## Código del agente

### `C:\tfm-agent\agent_dc.py`

> El código siguiente es un **reflejo literal** de `fase4-breakglass-dc/dcagent/agent_dc.py`
> en su versión endurecida (v2.0): anclaje de ruta de scripts, comparación de token en
> tiempo constante, firma HMAC-SHA256 opcional anti-replay, validación estricta del
> parámetro `target`, saneado de stdout y logging a fichero. Ver el fichero fuente para
> la versión siempre actualizada; no la dupliques manualmente si vuelve a cambiar.

```python
"""
TFM DC Agent — ejecución controlada de scripts de respuesta en un DC W2025.

Endurecimientos respecto a la versión inicial:
  - Ruta de scripts anclada y validada contra path traversal.
  - Comparación de token en tiempo constante.
  - Firma HMAC-SHA256 + ventana temporal + nonce anti-replay (por bandera).
  - Validación estricta del parámetro 'target' (argument injection en Windows).
  - Mapeo de parámetros por script.
  - PowerShell con -NoProfile -NonInteractive.
  - Saneado y truncado de stdout antes de devolverlo al orquestador.
  - Logging a fichero, consumible por el agente Wazuh del DC.
"""

import hashlib
import hmac
import json
import logging
import os
import re
import secrets
import subprocess
import time
from logging.handlers import RotatingFileHandler
from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

VALID_TOKEN = os.environ.get("AGENT_TOKEN", "")
HMAC_SECRET = os.environ.get("AGENT_HMAC_SECRET", "").encode()
REQUIRE_HMAC = os.environ.get("AGENT_REQUIRE_HMAC", "false").lower() == "true"

SCRIPTS_DIR = Path(os.environ.get("TFM_SCRIPTS_DIR", r"C:\tfm-scripts")).resolve()
LOG_PATH = Path(os.environ.get("TFM_LOG_PATH", r"C:\tfm-agent\logs\agent.log"))

MAX_SKEW = 300          # segundos de tolerancia para el timestamp
MAX_STDOUT = 8000       # caracteres devueltos al orquestador
EXEC_TIMEOUT = 60

ALLOWED_SCRIPTS = [
    "disable_account.ps1",
    "enable_account.ps1",
    "collect_logs.ps1",
    "isolate_host.ps1",
    "reset_password.ps1",
    "rustdesk_enable.ps1",
    "rustdesk_disable.ps1",
]

# rustdesk_disable.ps1 no acepta parámetros; rustdesk_enable.ps1 usa TTLMinutes.
SCRIPT_PARAMS = {
    "rustdesk_enable.ps1": "ttl",
    "rustdesk_disable.ps1": None,
}  # el resto usa "target"

TARGET_RE = re.compile(r"^[A-Za-z0-9._\-\\]{1,64}$")
CONTROL_CHARS_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")

LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
logger = logging.getLogger("tfm-dc-agent")
logger.setLevel(logging.INFO)
_handler = RotatingFileHandler(LOG_PATH, maxBytes=10_485_760, backupCount=5,
                               encoding="utf-8")
_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
logger.addHandler(_handler)
logger.addHandler(logging.StreamHandler())

app = FastAPI(title="TFM DC Agent", version="2.0")
security = HTTPBearer()

_seen_nonces: dict[str, float] = {}


def verify_token(creds: HTTPAuthorizationCredentials = Depends(security)) -> None:
    if not VALID_TOKEN:
        logger.error("AGENT_TOKEN no configurado")
        raise HTTPException(status_code=500, detail="AGENT_TOKEN not set")
    if not secrets.compare_digest(creds.credentials, VALID_TOKEN):
        logger.warning("Token invalido")
        raise HTTPException(status_code=403, detail="Forbidden")


async def verify_signature(request: Request, body: bytes) -> None:
    """HMAC-SHA256 sobre timestamp.nonce.body, coherente con la Fase 2."""
    if not REQUIRE_HMAC:
        return
    if not HMAC_SECRET:
        logger.error("AGENT_HMAC_SECRET no configurado con HMAC obligatorio")
        raise HTTPException(status_code=500, detail="HMAC secret not set")

    ts = request.headers.get("x-timestamp", "")
    nonce = request.headers.get("x-nonce", "")
    sig = request.headers.get("x-signature", "")
    if not (ts and nonce and sig):
        raise HTTPException(status_code=400, detail="Missing signature headers")

    try:
        skew = abs(time.time() - float(ts))
    except ValueError:
        raise HTTPException(status_code=400, detail="Bad timestamp")
    if skew > MAX_SKEW:
        logger.warning("Timestamp fuera de ventana: %.0fs", skew)
        raise HTTPException(status_code=400, detail="Timestamp outside window")

    now = time.time()
    for key, seen_at in list(_seen_nonces.items()):
        if now - seen_at > MAX_SKEW:
            del _seen_nonces[key]
    if nonce in _seen_nonces:
        logger.warning("Replay detectado, nonce=%s", nonce)
        raise HTTPException(status_code=409, detail="Replay detected")
    _seen_nonces[nonce] = now

    expected = hmac.new(HMAC_SECRET, f"{ts}.{nonce}.".encode() + body,
                        hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected, sig):
        logger.warning("Firma HMAC invalida")
        raise HTTPException(status_code=403, detail="Bad signature")


def sanitize_output(text: str) -> tuple[str, bool]:
    """
    stdout puede contener datos controlados por un atacante: collect_logs.ps1
    lee el campo Message del log de seguridad de Windows. Ese texto viaja
    DC -> orquestador -> motor de triaje, así que es una superficie de
    inyección indirecta por el canal de respuesta.
    """
    if not text:
        return "", False
    cleaned = CONTROL_CHARS_RE.sub("", text)
    truncated = len(cleaned) > MAX_STDOUT
    return cleaned[:MAX_STDOUT], truncated


@app.post("/run")
async def run_script(request: Request, _=Depends(verify_token)):
    body = await request.body()
    await verify_signature(request, body)

    try:
        payload = json.loads(body or b"{}")
    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="Invalid JSON")
    if not isinstance(payload, dict):
        raise HTTPException(status_code=400, detail="Invalid payload")

    script = payload.get("script", "")
    target = payload.get("target", "")
    ttl = payload.get("ttl_minutes", 30)

    if script not in ALLOWED_SCRIPTS:
        logger.warning("Script rechazado: %r", script)
        raise HTTPException(status_code=400, detail=f"Script no permitido: {script}")

    # Anclaje de ruta: la allowlist valida el nombre, esto valida la ubicación.
    script_path = (SCRIPTS_DIR / script).resolve()
    if script_path.parent != SCRIPTS_DIR or not script_path.is_file():
        logger.error("Ruta de script invalida: %s", script_path)
        raise HTTPException(status_code=400, detail="Script path invalid")

    param_kind = SCRIPT_PARAMS.get(script, "target")
    args: list[str] = []
    if param_kind == "target":
        if target and not TARGET_RE.fullmatch(str(target)):
            logger.warning("Target invalido: %r", target)
            raise HTTPException(status_code=400, detail="Invalid target")
        args = ["-target", str(target)]
    elif param_kind == "ttl":
        if not isinstance(ttl, int) or not 1 <= ttl <= 480:
            raise HTTPException(status_code=400, detail="Invalid ttl_minutes")
        args = ["-TTLMinutes", str(ttl)]

    logger.info("EJECUCION script=%s target=%s args=%s", script, target, args)

    try:
        result = subprocess.run(
            ["powershell.exe", "-NoProfile", "-NonInteractive",
             "-ExecutionPolicy", "Bypass", "-File", str(script_path), *args],
            capture_output=True, text=True, timeout=EXEC_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        logger.error("TIMEOUT script=%s", script)
        raise HTTPException(status_code=504, detail="Script timeout")

    stdout, truncated = sanitize_output(result.stdout)
    stderr, _ = sanitize_output(result.stderr)
    logger.info("RESULTADO script=%s returncode=%s", script, result.returncode)

    return {
        "script": script,
        "target": target,
        "stdout": stdout,
        "stderr": stderr,
        "returncode": result.returncode,
        "truncated": truncated,
    }


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "agent": "dc01-tfm",
        "version": "2.0",
        "hmac_required": REQUIRE_HMAC,
        "scripts_dir": str(SCRIPTS_DIR),
    }
```

Variables de entorno nuevas respecto a la v1.0 (detalle completo en
`dcagent/README-despliegue.md`): `AGENT_HMAC_SECRET`, `AGENT_REQUIRE_HMAC`,
`TFM_SCRIPTS_DIR`, `TFM_LOG_PATH`.

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

`Get-EventLog` está deprecado y ausente en PowerShell 7; se sustituyó por
`Get-WinEvent` con salida JSON hasheada (SHA-256), parseable por la custodia de
evidencias de la Fase 5:

```powershell
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
```

### `C:\tfm-scripts\isolate_host.ps1`

La versión anterior cortaba el tráfico saliente por completo, incluido el túnel
WireGuard del propio host — aislaba el DC y lo dejaba irrecuperable de forma
remota. La versión actual crea primero reglas `Allow` explícitas para preservar
el canal OOB (Headscale/tailnet/WireGuard) antes de cualquier bloqueo:

```powershell
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
```

### `C:\tfm-scripts\reset_password.ps1`

`Read-Host -AsSecureString` es inejecutable desde un servicio no interactivo
(cuelga o falla); se sustituyó por generación de contraseña con
`System.Web.Security.Membership`:

```powershell
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
```

### `C:\tfm-scripts\rustdesk_enable.ps1`

Documentado en detalle en `README-fase4e-rustdesk-breakglass.md`; se incluye
aquí porque forma parte de la `ALLOWED_SCRIPTS` del agente:

```powershell
param([int]$TTLMinutes = 30)

$ErrorActionPreference = "Stop"

Set-Service -Name RustDesk -StartupType Manual
Start-Service -Name RustDesk
Start-Sleep -Seconds 5

$toml = "$env:APPDATA\RustDesk\config\RustDesk.toml"
$rustdeskId = ""
if (Test-Path $toml) {
    $m = Select-String -Path $toml -Pattern "^id\s*=\s*'(.+)'"
    if ($m) { $rustdeskId = $m.Matches.Groups[1].Value }
}

$pass = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 16 | ForEach-Object {[char]$_})
& "$env:ProgramFiles\RustDesk\rustdesk.exe" --password $pass

$action  = New-ScheduledTaskAction -Execute "PowerShell.exe" `
             -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\tfm-scripts\rustdesk_disable.ps1"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes($TTLMinutes)
Register-ScheduledTask -TaskName "RustDesk-AutoOff" -Action $action `
  -Trigger $trigger -RunLevel Highest -Force | Out-Null

@{ rustdesk_id = $rustdeskId; password = $pass; ttl_minutes = $TTLMinutes } |
  ConvertTo-Json -Compress
```

### `C:\tfm-scripts\rustdesk_disable.ps1`

```powershell
param()

Stop-Service -Name RustDesk -ErrorAction SilentlyContinue
Set-Service -Name RustDesk -StartupType Disabled
Unregister-ScheduledTask -TaskName "RustDesk-AutoOff" -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "RustDesk deshabilitado y TTL cancelado"
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
pip install -r C:\tfm-agent\requirements.txt
```

Arrancar el agente en PowerShell como administrador:

```powershell
$env:AGENT_TOKEN = "REEMPLAZAR"   # ver dcagent/README-despliegue.md, paso 4
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
  -H "Authorization: Bearer ${AGENT_TOKEN}" \
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
  -H "Authorization: Bearer ${AGENT_TOKEN}" \
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
