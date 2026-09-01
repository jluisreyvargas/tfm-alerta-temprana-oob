# Fase 4c — Python Agent en el DC (via Headscale)

## Objetivo

Desplegar un agente Python (FastAPI + Uvicorn) en el Domain Controller Windows 2025 para exponer un endpoint HTTP autenticado y controlado, accesible exclusivamente a través de la red privada Headscale/Tailscale del enclave OOB.

El agente permite al orquestador ejecutar scripts PowerShell predefinidos en el DC de forma segura, con autenticación Bearer Token, allowlist estricta de scripts y logging de cada ejecución. Ningún puerto del DC queda expuesto a Internet ni a la red corporativa general.

## Alcance

- Instalación de Python 3.11 en el DC Windows 2025 vía winget.
- Despliegue del agente FastAPI en `C:\tfm-dc-agent\agent_dc.py`.
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
├── tfm-dc-agent\
│   ├── .venv\                  # entorno virtual Python
│   ├── agent_dc.py
│   ├── requirements.txt
│   └── logs\
│       ├── agent.log           # auditoría de ejecuciones (consumido por Wazuh)
│       └── service.log         # stdout/stderr del servicio NSSM
└── tfm-scripts\
    ├── disable_account.ps1
    ├── enable_account.ps1
    ├── collect_logs.ps1
    ├── isolate_host.ps1
    ├── reset_password.ps1
    ├── rustdesk_enable.ps1
    └── rustdesk_disable.ps1
```

> La separación entre `tfm-dc-agent` y `tfm-scripts` es deliberada, no incidental:
> mantenerlos en el mismo árbol anularía el valor del anclaje de ruta del agente
> (`SCRIPTS_DIR` en `agent_dc.py`), porque código, entorno virtual y scripts
> compartirían el mismo conjunto de permisos de directorio. Con dos raíces
> separadas, la ACL de cada una puede ser distinta (ver
> [Control de acceso al sistema de ficheros](#control-de-acceso-al-sistema-de-ficheros)).

Ver `fase4-breakglass-dc/dcagent/README-despliegue.md` para el detalle completo de
ACLs de directorio y registro como servicio Windows con NSSM.

Crear los directorios:

```powershell
mkdir C:\tfm-dc-agent
mkdir C:\tfm-scripts
```

## Código del agente

### `C:\tfm-dc-agent\agent_dc.py`

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
LOG_PATH = Path(os.environ.get("TFM_LOG_PATH", r"C:\tfm-dc-agent\logs\agent.log"))

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
        "token_configured": bool(VALID_TOKEN),
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

Documentado en detalle en `README-fase4e-rustdesk-breakglass.md` y validado en
`docs/README-fase4-validacion.md` (sección 5); se incluye aquí porque forma
parte de la `ALLOWED_SCRIPTS` del agente. El identificador del par **no** se
resuelve en el propio DC (autoinforme de un endpoint potencialmente
comprometido): se delega al servidor `hbbs`, bajo control del equipo de
respuesta.

```powershell
param([int]$TTLMinutes = 30)

$ErrorActionPreference = "Stop"
$warnings = @()

Set-Service -Name RustDesk -StartupType Manual
Start-Service -Name RustDesk
Start-Sleep -Seconds 5
$svc = Get-Service -Name RustDesk

# El ID se resuelve en hbbs (rustdesk/data/db_v2.sqlite3), no en el propio DC.
$rustdeskId = "resolver_en_hbbs"

# RandomNumberGenerator: criptográficamente seguro, a diferencia de Get-Random.
$bytes = New-Object byte[] 16
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
$pass = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })

try {
    & "$env:ProgramFiles\RustDesk\rustdesk.exe" --password $pass
} catch {
    $warnings += "No se pudo fijar la contrasena en el cliente RustDesk: $_"
}

# -Principal explicito: sin el, Register-ScheduledTask falla con 0x80070534
# bajo el contexto SYSTEM del servicio del agente.
$action    = New-ScheduledTaskAction -Execute "PowerShell.exe" `
             -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\tfm-scripts\rustdesk_disable.ps1"
$trigger   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes($TTLMinutes)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "RustDesk-AutoOff" -Action $action `
  -Trigger $trigger -Principal $principal -Force | Out-Null
$task = Get-ScheduledTask -TaskName "RustDesk-AutoOff"

[ordered]@{
    password    = $pass
    rustdesk_id = $rustdeskId
    service     = $svc.Status.ToString()
    ttl_task    = $task.State.ToString()
    warnings    = $warnings
    ttl_minutes = $TTLMinutes
} | ConvertTo-Json -Compress
```

### `C:\tfm-scripts\rustdesk_disable.ps1`

```powershell
param()

Stop-Service -Name RustDesk -ErrorAction SilentlyContinue
Set-Service -Name RustDesk -StartupType Disabled
Unregister-ScheduledTask -TaskName "RustDesk-AutoOff" -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "RustDesk deshabilitado y TTL cancelado"
```

## Comprobación de salud (`/health`) y allowlist

Respuesta real del endpoint `GET /health` (reflejo literal de `agent_dc.py`, función `health()`).
Desde el Paso 9 el servicio corre con `AGENT_REQUIRE_HMAC=true`, por lo que
`hmac_required` es ahora `true`:

```json
{
  "status": "ok",
  "agent": "dc01-tfm",
  "version": "2.0",
  "hmac_required": true,
  "token_configured": true,
  "scripts_dir": "C:\\tfm-scripts"
}
```

`hmac_required`, `token_configured` y `scripts_dir` permiten detectar un agente
arrancado pero inservible sin tener que probar `/run`. En una versión anterior
del agente, `/health` no incluía `token_configured`: durante la validación se
dio el caso de un servicio con `/health` respondiendo `ok` mientras rechazaba
**todas** las peticiones a `/run` porque `AGENT_TOKEN` no estaba definido en el
entorno del servicio (`verify_token()` devuelve `500 AGENT_TOKEN not set` en
ese caso), y no había forma de detectarlo sin probar `/run`. `token_configured`
cierra ese hueco: `false` con `"status": "ok"` es la señal inequívoca de un
servicio arrancado pero inservible, sin necesidad de una petición autenticada.
Comprobar siempre que `scripts_dir` apunta a `C:\tfm-scripts` (no a una ruta
relativa resuelta contra el directorio de arranque del servicio) sigue
formando parte de la validación mínima tras cada despliegue.

La allowlist (`ALLOWED_SCRIPTS` en `agent_dc.py`) son **siete** scripts: los
cinco de acción (`disable_account.ps1`, `enable_account.ps1`,
`collect_logs.ps1`, `isolate_host.ps1`, `reset_password.ps1`) más
`rustdesk_enable.ps1` y `rustdesk_disable.ps1`. Sin estos dos últimos no existe
ningún camino desde el orquestador para activar o revocar el break-glass de
RustDesk — el agente es, para ese flujo, el único ejecutor posible.

## Firma HMAC (Paso 9) — activa

Desde el Paso 9 el agente corre con `AGENT_REQUIRE_HMAC=true`: el orquestador n8n
firma cada petición a `/run` y el agente la rechaza si la firma no valida.

- **Cabeceras exigidas:** `X-Timestamp`, `X-Nonce`, `X-Signature`.
- **Firma:** HMAC-SHA256 sobre la cadena `{timestamp}.{nonce}.{body}` con el
  secreto compartido `AGENT_HMAC_SECRET`.
- **Ventana temporal:** 300 s de tolerancia sobre `X-Timestamp` (`MAX_SKEW`).
- **Anti-replay:** los nonces vistos se retienen en memoria durante la ventana;
  un nonce repetido dentro de esos 300 s se rechaza.

Tabla de validación (misma petición, variando `AGENT_REQUIRE_HMAC`):

| # | Control | `REQUIRE_HMAC=false` | `REQUIRE_HMAC=true` |
|---:|---|:-:|:-:|
| 1 | Petición firmada válida | `200` | `200` |
| 2 | Replay (nonce repetido) | `200` | `409` |
| 3 | Firma inválida | `200` | `403` |
| 4 | Timestamp fuera de ventana | `200` | `400` |
| 5 | Sin cabeceras de firma | `200` | `400` |

La columna izquierda no es ruido: demuestra que **sin el control**, una petición
legítima capturada en tránsito puede reproducirse indefinidamente contra el
Domain Controller. El SIEM discrimina los rechazos: `100605` (firma inválida),
`100606` (replay), frente a `100604` (token inválido) — tres controles que
devuelven códigos HTTP solapados pero alertas distintas.

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

> **Solución provisional.** Lo correcto sería resolver `dc01-tfm` vía MagicDNS
> de Headscale, sin mantener una entrada manual por nodo. MagicDNS no está
> operativo en el despliegue actual porque `base_domain` del `config.yaml` de
> Headscale colisiona con el propio dominio de servicios del enclave
> (`oob.local`, el mismo que sirve `hs.oob.local`, `chat.oob.local`, etc.). La
> configuración endurecida ya corrige esto (`base_domain: tailnet.internal`,
> un espacio de nombres separado — ver la nota de la Fase 4a), pero esa
> configuración está escrita y todavía no aplicada al contenedor en ejecución;
> hasta que se aplique, esta entrada manual sigue siendo necesaria. Seguimiento
> en [`README-fase4-pendientes.md`](README-fase4-pendientes.md).

Para poder usar el nombre `dc01-tfm` desde el orquestador Linux, se ha añadido la entrada correspondiente en `/etc/hosts`:

```bash
sudo nano /etc/hosts
```

Línea añadida:

```
100.64.0.2   dc01-tfm
```

## Despliegue como servicio

El agente no se arranca manualmente en una sesión PowerShell: corre como
servicio de Windows registrado con [NSSM](https://nssm.cc/), en un entorno
virtual propio dentro de `C:\tfm-dc-agent`:

```powershell
# Entorno virtual y dependencias
cd C:\tfm-dc-agent
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt

# Instalación del servicio
nssm install TFM-DC-Agent "C:\tfm-dc-agent\.venv\Scripts\python.exe"
nssm set TFM-DC-Agent AppParameters "-m uvicorn agent_dc:app --host 100.64.0.2 --port 8000"
nssm set TFM-DC-Agent AppDirectory "C:\tfm-dc-agent"
nssm set TFM-DC-Agent DisplayName "TFM DC Agent"
nssm set TFM-DC-Agent Start SERVICE_AUTO_START

# Registro de la actividad del servicio
nssm set TFM-DC-Agent AppStdout C:\tfm-dc-agent\logs\service.log
nssm set TFM-DC-Agent AppStderr C:\tfm-dc-agent\logs\service.log
nssm set TFM-DC-Agent AppRotateFiles 1
nssm set TFM-DC-Agent AppRotateBytes 10485760

# Configuración (los secretos se sustituyen por los valores reales)
nssm set TFM-DC-Agent AppEnvironmentExtra `
  "AGENT_TOKEN=<TOKEN>" `
  "AGENT_HMAC_SECRET=<SECRETO>" `
  "AGENT_REQUIRE_HMAC=true" `
  "TFM_SCRIPTS_DIR=C:\tfm-scripts" `
  "TFM_LOG_PATH=C:\tfm-dc-agent\logs\agent.log" `
  "TFM_HEADSCALE_IP=<IP_TRAEFIK>"

# Dependencia de Tailscale y política de reinicio
nssm set TFM-DC-Agent DependOnService Tailscale
nssm set TFM-DC-Agent AppExit Default Restart
nssm set TFM-DC-Agent AppRestartDelay 15000

Start-Service TFM-DC-Agent
```

Tres decisiones de esta configuración y su motivo:

- **`--host 100.64.0.2` y no `0.0.0.0`.** Con `0.0.0.0` el agente escucharía
  también en la interfaz corporativa del DC, y la única defensa sería la regla
  de firewall de la sección siguiente. Ligar el proceso a la IP de la tailnet
  añade defensa en profundidad: aunque la regla de firewall fallase o se
  desactivara por error, el proceso seguiría sin aceptar conexiones desde la
  red corporativa.
- **`AppEnvironmentExtra` y no variables de entorno de máquina.** `services.exe`
  lee el bloque de entorno del sistema al arrancar Windows y no lo refresca
  después, así que una variable de máquina creada con `setx ... /M` tras el
  arranque no es visible para el servicio hasta un reinicio completo del
  sistema — no basta con reiniciar el servicio. `AppEnvironmentExtra` inyecta
  el entorno directamente en el proceso que NSSM lanza, sin depender de ese
  refresco. **Advertencia operativa:** `AppEnvironmentExtra` **reemplaza el
  conjunto completo** de variables, no lo fusiona — en cada modificación hay que
  reescribir todas las líneas, o las que se omitan desaparecen (un
  `AGENT_TOKEN` que se pierde así produce un `500 AGENT_TOKEN not set`, no un
  fallo evidente al arrancar).
- **`DependOnService Tailscale`.** El binding a `100.64.0.2` falla si el
  servicio arranca antes de que la interfaz de la tailnet exista todavía; la
  dependencia de servicio asegura el orden de arranque.

## Control de acceso al sistema de ficheros

La allowlist de `agent_dc.py` valida el **nombre** del fichero de script, no su
contenido. El servicio corre como `LocalSystem`, que en un controlador de
dominio equivale a la cuenta de máquina del propio DC. Si un principal sin
privilegios pudiera escribir en `C:\tfm-scripts`, podría sustituir el contenido
de cualquier script permitido y obtener ejecución arbitraria como `SYSTEM` en
el controlador de dominio, invocada por el propio agente y superando todos sus
controles de aplicación (allowlist, anclaje de ruta, HMAC). El mismo argumento
aplica a `C:\tfm-dc-agent`: escribir ahí permite sustituir `agent_dc.py`
directamente.

```powershell
icacls C:\tfm-scripts /inheritance:r
icacls C:\tfm-scripts /grant:r "SYSTEM:(OI)(CI)(RX)"
icacls C:\tfm-scripts /grant:r "Administradores:(OI)(CI)(F)"

icacls C:\tfm-dc-agent /inheritance:r
icacls C:\tfm-dc-agent /grant:r "SYSTEM:(OI)(CI)(RX)"
icacls C:\tfm-dc-agent /grant:r "Administradores:(OI)(CI)(F)"

icacls C:\tfm-dc-agent\logs /inheritance:r
icacls C:\tfm-dc-agent\logs /grant:r "SYSTEM:(OI)(CI)(M)"
icacls C:\tfm-dc-agent\logs /grant:r "Administradores:(OI)(CI)(F)"
```

`SYSTEM` recibe únicamente `RX` (lectura + ejecución) sobre el código y los
scripts — nunca escritura — y `M` (modificar) sobre `logs\`, que es el único
directorio en el que el propio agente necesita escribir. `Administradores`
mantiene control total (`F`) sobre los tres, para poder desplegar
actualizaciones y mantenimiento.

## Validación end-to-end

La batería de validación de esta subfase ha crecido de las cuatro pruebas
originales a nueve (allowlist ampliada, binding a la tailnet, servicio NSSM,
ACLs de directorio). Para no duplicar contenido que diverge fácilmente de la
ejecución real, la batería completa con las salidas reales vive en un
documento propio: [`README-fase4-validacion.md`](README-fase4-validacion.md).

## Estado de la tailnet en el momento de la validación

```
100.64.0.1  orchestrator-tfm  tfm-oob  linux    -
100.64.0.2  dc01-tfm          tfm-oob  windows  active; direct 192.168.127.153:41641, tx 860 rx 852
```

La conexión es `direct` (sin pasar por servidor DERP de relay), lo que confirma conectividad WireGuard directa entre los nodos.

## Resultado de la Fase 4c

La Fase 4c queda completada con el agente Python operativo en el DC Windows 2025, accesible desde el orquestador exclusivamente por la red privada Headscale, con autenticación Bearer Token validada, firma HMAC-SHA256 anti-replay activa (Paso 9), allowlist de scripts funcional y logging de cada ejecución.

El flujo de aprobación y ejecución desde Rocket.Chat que consume este agente se
documenta en [`README-fase4d-flujo-aprobacion.md`](README-fase4d-flujo-aprobacion.md).
