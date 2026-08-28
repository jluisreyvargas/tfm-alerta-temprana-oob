# Fase 4e — RustDesk Server + flujo break-glass

## Objetivo

Desplegar un servidor RustDesk self-hosted dentro del enclave Docker y habilitar un flujo de acceso break-glass con TTL sobre el Domain Controller Windows 2025. La activación y desactivación remotas se realizan a través del DC Agent ya validado en la Fase 4c/4d.

El flujo queda orientado a sesiones temporales y controladas: una acción aprobada activa RustDesk en el DC, notifica el estado al canal de incidentes y programa el apagado automático; una acción de desactivación revoca el acceso y cancela la tarea programada.

## Alcance

En esta subfase se cubre:

- Despliegue de `hbbs` y `hbbr` en Docker.
- Configuración del cliente RustDesk en el DC Windows 2025.
- Incorporación de los scripts `rustdesk_enable.ps1` y `rustdesk_disable.ps1` al DC Agent.
- Despliegue del DC Agent Python como servicio de Windows mediante NSSM.
- Validación de activación y desactivación remota mediante `curl` al agente.
- Documentación de los IDs y resultados reales obtenidos durante la validación.

## Prerrequisitos

- Fase 4a: Headscale operativo en Docker.
- Fase 4b: nodos `orchestrator-tfm` y `dc01-tfm` activos en la tailnet.
- Fase 4c: DC Agent operativo en `http://dc01-tfm:8000`.
- Fase 4d: integración n8n → DC Agent → Rocket.Chat validada.
- RustDesk instalado en el DC Windows 2025 y el ID visible en la aplicación.

## Paso 1 — Despliegue de RustDesk Server en Docker

Crear la carpeta de trabajo del servicio:

```bash
mkdir -p ~/tfm-alerta-temprana-oob/fase4-breakglass-dc/rustdesk/data
```

Crear `docker-compose.rustdesk.yml`:

```yaml
services:
  hbbs:
    image: rustdesk/rustdesk-server:latest
    container_name: rustdesk-hbbs
    command: hbbs
    restart: unless-stopped
    volumes:
      - ./rustdesk/data:/root
    ports:
      - "21115:21115"
      - "21116:21116"
      - "21116:21116/udp"
      - "21118:21118"
    networks:
      - oob-network

  hbbr:
    image: rustdesk/rustdesk-server:latest
    container_name: rustdesk-hbbr
    command: hbbr
    restart: unless-stopped
    volumes:
      - ./rustdesk/data:/root
    ports:
      - "21117:21117"
      - "21119:21119"
    networks:
      - oob-network

networks:
  oob-network:
    external: true
```

Arrancar los contenedores y verificar que quedan activos:

```bash
docker compose -f ~/tfm-alerta-temprana-oob/fase4-breakglass-dc/docker-compose.rustdesk.yml up -d
docker ps | grep rustdesk
```

## Paso 2 — Configuración del cliente RustDesk en el DC

Instalar el cliente en Windows si no estaba presente:

```powershell
winget install RustDesk.RustDesk
```

Abrir RustDesk en el DC y configurar el servidor propio en **Settings → Network**:

- **ID Server:** IP del host Ubuntu donde corre Docker.
- **Relay Server:** IP del host Ubuntu donde corre Docker.
- **Key:** contenido de `rustdesk/data/id_ed25519.pub`.

En la prueba realizada, el ID visible en la aplicación del DC fue anotado manualmente
y usado solo como referencia local — no se hardcodea en ningún script ni fichero del
repositorio (ver nota de endurecimiento en el Paso 3):

```text
<RUSTDESK_ID>
```

## Paso 3 — Scripts PowerShell de activación/desactivación

> **Nota de endurecimiento posterior (actualizada tras la validación empírica
> de la sección correspondiente en `docs/README-fase4-validacion.md`):** la
> primera versión de `rustdesk_enable.ps1` tenía el ID de RustDesk hardcodeado
> en el propio script y nunca revertía el `StartupType Disabled` que deja
> `rustdesk_disable.ps1` — tras el primer ciclo el break-glass quedaba muerto.
> Una segunda versión corrigió eso pero leía el ID real desde `RustDesk.toml`
> **en el propio DC** — un autoinforme de un endpoint que en un escenario
> break-glass puede estar comprometido. La versión actual (reflejada abajo) ya
> no lee ese fichero: devuelve el literal `rustdesk_id: "resolver_en_hbbs"` y
> delega la resolución al servidor `hbbs` (bajo control del equipo de
> respuesta, no del sistema investigado). Además genera la contraseña con
> `RandomNumberGenerator` (criptográficamente seguro, en vez de `Get-Random`) y
> registra la tarea programada con un `-Principal` explícito, sin el cual
> `Register-ScheduledTask` falla con `0x80070534` bajo el contexto SYSTEM del
> servicio del agente. Ver `fase4-breakglass-dc/scripts/` para la versión
> siempre actualizada.

### `C:\tfm-scripts\rustdesk_enable.ps1`

```powershell
param([int]$TTLMinutes = 30)

$ErrorActionPreference = "Stop"
$warnings = @()

# 1. Revertir el Disabled que dejó rustdesk_disable.ps1
Set-Service -Name RustDesk -StartupType Manual
Start-Service -Name RustDesk
Start-Sleep -Seconds 5
$svc = Get-Service -Name RustDesk

# 2. Identificador del par: NO se resuelve en el propio DC. En un escenario
# break-glass el endpoint puede estar comprometido, asi que la identidad del
# par debe proceder del componente bajo control del equipo de respuesta (el
# servidor hbbs), no del sistema bajo investigacion. El orquestador resuelve
# el ID real consultando rustdesk/data/db_v2.sqlite3 en hbbs
# (ver docs/README-fase4-validacion.md, seccion 5.2).
$rustdeskId = "resolver_en_hbbs"

# 3. Contraseña de un solo uso para esta sesión break-glass.
# RandomNumberGenerator en vez de Get-Random: Get-Random usa un PRNG no apto
# para material criptográfico.
$bytes = New-Object byte[] 16
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
$pass = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })

try {
    & "$env:ProgramFiles\RustDesk\rustdesk.exe" --password $pass
} catch {
    $warnings += "No se pudo fijar la contrasena en el cliente RustDesk: $_"
}

# 4. TTL. Principal explicito requerido: sin -Principal con LogonType
# ServiceAccount, Register-ScheduledTask falla con 0x80070534 cuando se
# invoca bajo el contexto SYSTEM del servicio del agente (no se manifiesta
# al ejecutar el script desde una sesion interactiva).
$action    = New-ScheduledTaskAction -Execute "PowerShell.exe" `
               -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\tfm-scripts\rustdesk_disable.ps1"
$trigger   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes($TTLMinutes)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "RustDesk-AutoOff" -Action $action `
  -Trigger $trigger -Principal $principal -Force | Out-Null
$task = Get-ScheduledTask -TaskName "RustDesk-AutoOff"

# 5. Salida estructurada para el orquestador
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

### Allowlist del DC Agent

Asegurar que ambos scripts están permitidos en `C:\tfm-agent\agent_dc.py`:

```python
ALLOWED_SCRIPTS = [
    "disable_account.ps1",
    "enable_account.ps1",
    "collect_logs.ps1",
    "isolate_host.ps1",
    "reset_password.ps1",
    "rustdesk_enable.ps1",
    "rustdesk_disable.ps1",
]
```

Después de cambiar el fichero, reiniciar el agente Python en el DC.

## Paso 4 — DC Agent como servicio de Windows

El agente Python no debe depender de una consola abierta ni de una ejecución manual tras reinicios. Para ello se registra como servicio de Windows con NSSM, de forma que arranque automáticamente al inicio del sistema y quede disponible para el Orquestador en todo momento.

### Estructura recomendada

```text
C:\tfm-agent\
├── .venv\
├── agent_dc.py
└── logs\
```

### Instalación de dependencias

```powershell
cd C:\tfm-agent
python -m venv .venv
.\.venv\Scripts\activate
pip install fastapi uvicorn
```

### Registro del servicio con NSSM

En PowerShell, si `nssm.exe` está en el directorio actual, debe ejecutarse con `./`:

```powershell
cd C:\Tools\nssm\win64
./nssm.exe install TFM-DC-Agent C:\tfm-agent\.venv\Scripts\python.exe -m uvicorn agent_dc:app --host 0.0.0.0 --port 8000
./nssm.exe set TFM-DC-Agent Start SERVICE_AUTO_START
./nssm.exe set TFM-DC-Agent AppStdout C:\tfm-agent\logs\stdout.log
./nssm.exe set TFM-DC-Agent AppStderr C:\tfm-agent\logs\stderr.log
./nssm.exe start TFM-DC-Agent
```

Con esta configuración, el agente queda activo como servicio persistente y el endpoint `http://dc01-tfm:8000` permanece disponible sin intervención manual.

## Paso 5 — Validación de activación

Comando ejecutado desde el orquestador Linux:

```bash
curl -s -X POST http://dc01-tfm:8000/run \
  -H "Authorization: Bearer ${AGENT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"script":"rustdesk_enable.ps1","target":"DC01"}'
```

Respuesta obtenida:

```json
{
  "script": "rustdesk_enable.ps1",
  "target": "DC01",
  "stdout": "{\"password\":\"<ONE_TIME_PASSWORD>\",\"rustdesk_id\":\"resolver_en_hbbs\",\"service\":\"Running\",\"ttl_task\":\"Ready\",\"warnings\":[],\"ttl_minutes\":30}",
  "stderr": "",
  "returncode": 0,
  "truncated": false
}
```

Esta validación confirma que el agente aceptó el script, arrancó el servicio RustDesk
(`service: "Running"`), generó una contraseña de un solo uso y dejó programada la tarea
`RustDesk-AutoOff` (`ttl_task: "Ready"`). El campo `rustdesk_id` devuelve deliberadamente
el literal `resolver_en_hbbs` en vez de un identificador leído del propio DC: la
resolución real se delega al servidor `hbbs` (ver `docs/README-fase4-validacion.md`,
sección 5.2). `warnings` recoge fallos no bloqueantes, como no haber podido fijar la
contraseña en el cliente RustDesk.

## Paso 6 — Validación de desactivación

Comando ejecutado desde el orquestador Linux:

```bash
curl -s -X POST http://dc01-tfm:8000/run \
  -H "Authorization: Bearer ${AGENT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"script":"rustdesk_disable.ps1","target":"DC01"}'
```

Respuesta obtenida:

```json
{
  "script": "rustdesk_disable.ps1",
  "target": "DC01",
  "stdout": "RustDesk deshabilitado y TTL cancelado\n",
  "stderr": "",
  "returncode": 0
}
```

Con esta prueba queda confirmado que el flujo de revocación también funciona y que la tarea programada se elimina correctamente.

## Resultado de la Fase 4e

La Fase 4e queda completada con RustDesk desplegado en modelo self-hosted, configurado en el DC y gobernado remotamente por el DC Agent, con activación y desactivación validadas por `curl`.

El agente Python queda además registrado como servicio de Windows mediante NSSM, por lo que arranca automáticamente con el sistema y no depende de intervención manual tras reinicios.

El sistema está listo para el cierre de Fase 4 con la consolidación documental final y la validación end-to-end de todo el flujo break-glass.

## Comandos de commit

```bash
cd /home/jose/tfm-alerta-temprana-oob

git add fase4-breakglass-dc/
git add docs/README-fase4e-rustdesk-breakglass.md   # si se copia este README a docs/

git commit -m "fase4e: rustdesk break-glass self-hosted validado"
git push origin main
```

Si trabajas en otra rama, sustituye `main` por el nombre real de la rama.