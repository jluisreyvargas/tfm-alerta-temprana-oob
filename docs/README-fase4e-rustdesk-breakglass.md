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

> **Nota de endurecimiento posterior:** la primera versión de `rustdesk_enable.ps1`
> tenía el ID de RustDesk hardcodeado en el propio script y nunca revertía el
> `StartupType Disabled` que deja `rustdesk_disable.ps1` — tras el primer ciclo el
> break-glass quedaba muerto. La versión actual (reflejada abajo) lee el ID real
> desde `RustDesk.toml`, revierte el servicio a `Manual` y genera una contraseña de
> un solo uso por sesión. Ver `fase4-breakglass-dc/scripts/` para la versión siempre
> actualizada.

### `C:\tfm-scripts\rustdesk_enable.ps1`

```powershell
param([int]$TTLMinutes = 30)

$ErrorActionPreference = "Stop"

# 1. Revertir el Disabled que dejó rustdesk_disable.ps1
Set-Service -Name RustDesk -StartupType Manual
Start-Service -Name RustDesk
Start-Sleep -Seconds 5

# 2. Leer el ID real del host (nunca hardcodearlo en el repositorio)
$toml = "$env:APPDATA\RustDesk\config\RustDesk.toml"
$rustdeskId = ""
if (Test-Path $toml) {
    $m = Select-String -Path $toml -Pattern "^id\s*=\s*'(.+)'"
    if ($m) { $rustdeskId = $m.Matches.Groups[1].Value }
}

# 3. Contraseña de un solo uso para esta sesión break-glass
$pass = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 16 | ForEach-Object {[char]$_})
& "$env:ProgramFiles\RustDesk\rustdesk.exe" --password $pass

# 4. TTL
$action  = New-ScheduledTaskAction -Execute "PowerShell.exe" `
             -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\tfm-scripts\rustdesk_disable.ps1"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes($TTLMinutes)
Register-ScheduledTask -TaskName "RustDesk-AutoOff" -Action $action `
  -Trigger $trigger -RunLevel Highest -Force | Out-Null

# 5. Salida estructurada para el orquestador
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
  "stdout": "{\"rustdesk_id\":\"<RUSTDESK_ID>\",\"password\":\"<ONE_TIME_PASSWORD>\",\"ttl_minutes\":30}",
  "stderr": "",
  "returncode": 0,
  "truncated": false
}
```

Esta validación confirma que el agente aceptó el script, devolvió el ID de RustDesk real
del host (leído dinámicamente, nunca hardcodeado) junto con una contraseña de un solo
uso, y dejó programada la tarea `RustDesk-AutoOff`.

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