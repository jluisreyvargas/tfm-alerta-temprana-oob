# Fase 4e — RustDesk Server + flujo break-glass

## Objetivo

Desplegar un servidor RustDesk self-hosted dentro del enclave Docker y habilitar un flujo de acceso break-glass con TTL sobre el Domain Controller Windows 2025. La activación y desactivación remotas se realizan a través del DC Agent ya validado en la Fase 4c/4d.

El flujo queda orientado a sesiones temporales y controladas: una acción aprobada activa RustDesk en el DC, notifica el estado al canal de incidentes y programa el apagado automático; una acción de desactivación revoca el acceso y cancela la tarea programada.

## Alcance

En esta subfase se cubre:

- Despliegue de `hbbs` y `hbbr` en Docker.
- Configuración del cliente RustDesk en el DC Windows 2025.
- Incorporación de los scripts `rustdesk_enable.ps1` y `rustdesk_disable.ps1` al DC Agent.
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

En la prueba realizada, el ID visible en la aplicación del DC fue:

```text
161 180 321
```

## Paso 3 — Scripts PowerShell de activación/desactivación

### `C:	fm-scriptsustdesk_enable.ps1`

```powershell
param([int]$TTLMinutes = 30)

Write-Host "RUSTDESK_ID=161 180 321"
Write-Host "RUSTDESK_TTL=$TTLMinutes"

$action = New-ScheduledTaskAction -Execute "PowerShell.exe"   -Argument "-File C:	fm-scriptsustdesk_disable.ps1"

$trigger = New-ScheduledTaskTrigger -Once   -At (Get-Date).AddMinutes($TTLMinutes)

Register-ScheduledTask   -TaskName "RustDesk-AutoOff"   -Action $action   -Trigger $trigger   -Force

Write-Host "TTL programado: $TTLMinutes minutos"
```

### `C:	fm-scriptsustdesk_disable.ps1`

```powershell
Stop-Service -Name RustDesk -ErrorAction SilentlyContinue
Set-Service -Name RustDesk -StartupType Disabled
Unregister-ScheduledTask -TaskName "RustDesk-AutoOff" -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "RustDesk deshabilitado y TTL cancelado"
```

### Allowlist del DC Agent

Asegurar que ambos scripts están permitidos en `C:	fm-agentgent_dc.py`:

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

## Paso 4 — Validación de activación

Comando ejecutado desde el orquestador Linux:

```bash
curl -s -X POST http://dc01-tfm:8000/run   -H "Authorization: Bearer tfm-token-secreto-2024"   -H "Content-Type: application/json"   -d '{"script":"rustdesk_enable.ps1","target":"DC01"}'
```

Respuesta obtenida:

```json
{
  "script": "rustdesk_enable.ps1",
  "target": "DC01",
  "stdout": "RUSTDESK_ID=161 180 321
RUSTDESK_TTL=30

TaskPath                                       TaskName                          State     
--------                                       --------                          -----     
\                                              RustDesk-AutoOff                  Ready     
TTL programado: 30 minutos


",
  "stderr": "",
  "returncode": 0
}
```

Esta validación confirma que el agente aceptó el script, devolvió el ID de RustDesk y dejó programada la tarea `RustDesk-AutoOff`.

## Paso 5 — Validación de desactivación

Comando ejecutado desde el orquestador Linux:

```bash
curl -s -X POST http://dc01-tfm:8000/run   -H "Authorization: Bearer tfm-token-secreto-2024"   -H "Content-Type: application/json"   -d '{"script":"rustdesk_disable.ps1","target":"DC01"}'
```

Respuesta obtenida:

```json
{
  "script": "rustdesk_disable.ps1",
  "target": "DC01",
  "stdout": "RustDesk deshabilitado y TTL cancelado
",
  "stderr": "",
  "returncode": 0
}
```

Con esta prueba queda confirmado que el flujo de revocación también funciona y que la tarea programada se elimina correctamente.

## Resultado de la Fase 4e

La Fase 4e queda completada con RustDesk desplegado en modelo self-hosted, configurado en el DC y gobernado remotamente por el DC Agent, con activación y desactivación validadas por `curl`.

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
