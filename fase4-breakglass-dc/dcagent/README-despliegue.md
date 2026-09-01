# Despliegue de `agent_dc.py` en el Domain Controller (W2025)

Este documento describe cómo instalar el agente Python como servicio de Windows en el DC.
No contiene valores reales de secretos: usa siempre los placeholders indicados.

El reflejo del código del agente y la explicación de cada control está en
[`docs/README-fase4c-dcagent.md`](../../docs/README-fase4c-dcagent.md); aquí solo
se cubre el despliegue operativo.

## 1. Requisitos previos

- Python 3.11 instalado en el DC (`winget install -e --id Python.Python.3.11 --scope machine`).
- Nodo `dc01-tfm` ya registrado en la tailnet Headscale (Fase 4b), con el tag `tag:dc`.
- Interfaz de la tailnet activa: el agente hace binding a `100.64.0.2` y falla si
  `tailscale0` no existe todavía cuando arranca.
- [NSSM](https://nssm.cc/) disponible en el DC para registrar el proceso como servicio Windows
  (Python/uvicorn no ofrece un modo "servicio" nativo).

## 2. Estructura de directorios en el DC

```
C:\tfm-dc-agent\
├── .venv\                 # entorno virtual Python
├── agent_dc.py
├── requirements.txt
└── logs\                  # creado automáticamente por el agente (TFM_LOG_PATH)
    ├── agent.log          # auditoría de ejecuciones (consumido por Wazuh)
    └── service.log        # stdout/stderr del servicio NSSM
C:\tfm-scripts\
├── disable_account.ps1
├── enable_account.ps1
├── collect_logs.ps1
├── isolate_host.ps1
├── reset_password.ps1
├── rustdesk_enable.ps1
└── rustdesk_disable.ps1
```

La allowlist de `agent_dc.py` (`ALLOWED_SCRIPTS`) son estos **siete** scripts.

## 3. ACL de directorios

- `C:\tfm-dc-agent\` y `C:\tfm-scripts\`: escritura restringida a `SYSTEM` y `Administrators`.
  La cuenta de servicio bajo la que corre el agente solo necesita **lectura y ejecución**
  sobre ambos, nunca escritura — el agente no debe poder modificar su propio código
  ni su allowlist de scripts.
- `C:\tfm-dc-agent\logs\`: escritura para la cuenta de servicio, lectura para el equipo de
  respuesta/auditoría. Estos logs son la fuente que consume el agente Wazuh del DC
  (`fase7-observabilidad`).

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

## 4. Variables de entorno del servicio

Se inyectan con `AppEnvironmentExtra` de NSSM (ver Paso 5), **no** con variables de
máquina: `services.exe` lee el bloque de entorno del sistema al arrancar Windows y
no lo refresca, así que un `setx ... /M` posterior no es visible para el servicio
hasta un reinicio completo del sistema.

| Variable | Obligatoria | Descripción |
|---|---|---|
| `AGENT_TOKEN` | Sí | Bearer token compartido con el orquestador. Placeholder: `<TOKEN>` |
| `AGENT_HMAC_SECRET` | Sí (HMAC activa) | Secreto compartido para la firma HMAC-SHA256. Placeholder: `<SECRETO>` |
| `AGENT_REQUIRE_HMAC` | — | `true` desde el Paso 9: exige `X-Timestamp`/`X-Nonce`/`X-Signature` en `/run` |
| `TFM_SCRIPTS_DIR` | No (default `C:\tfm-scripts`) | Ruta anclada desde la que se resuelven los scripts de la allowlist |
| `TFM_LOG_PATH` | No (default `C:\tfm-dc-agent\logs\agent.log`) | Ruta del log rotado que consume Wazuh |
| `TFM_HEADSCALE_IP` | Solo `isolate_host.ps1` | IP del host Traefik/Headscale a preservar en el aislamiento |

## 5. Registro como servicio con NSSM

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

nssm set TFM-DC-Agent AppStdout C:\tfm-dc-agent\logs\service.log
nssm set TFM-DC-Agent AppStderr C:\tfm-dc-agent\logs\service.log
nssm set TFM-DC-Agent AppRotateFiles 1
nssm set TFM-DC-Agent AppRotateBytes 10485760

# Entorno: AppEnvironmentExtra REEMPLAZA el conjunto completo; hay que reescribir
# TODAS las líneas en cada modificación o las omitidas desaparecen.
nssm set TFM-DC-Agent AppEnvironmentExtra `
  "AGENT_TOKEN=<TOKEN>" `
  "AGENT_HMAC_SECRET=<SECRETO>" `
  "AGENT_REQUIRE_HMAC=true" `
  "TFM_SCRIPTS_DIR=C:\tfm-scripts" `
  "TFM_LOG_PATH=C:\tfm-dc-agent\logs\agent.log" `
  "TFM_HEADSCALE_IP=<IP_TRAEFIK>"

nssm set TFM-DC-Agent DependOnService Tailscale
nssm set TFM-DC-Agent AppExit Default Restart
nssm set TFM-DC-Agent AppRestartDelay 15000

Start-Service TFM-DC-Agent
```

- **`--host 100.64.0.2` y no `0.0.0.0`:** defensa en profundidad. Aunque la regla
  de firewall fallase, el proceso no aceptaría conexiones desde la red corporativa.
- **`DependOnService Tailscale`:** el binding falla si el servicio arranca antes
  de que exista la interfaz de la tailnet.

## 6. Regla de firewall

El puerto `8000` solo debe ser alcanzable desde la tailnet Headscale (ver `acl.hujson` en
`fase4-breakglass-dc/headscale/config/`, que ya restringe el tráfico a `tag:orchestrator`):

```powershell
New-NetFirewallRule `
  -DisplayName "TFM DC Agent - Solo Tailscale" `
  -Direction Inbound -Protocol TCP -LocalPort 8000 `
  -RemoteAddress 100.64.0.0/10 -Action Allow
```

## 7. Validación

```powershell
Get-Service TFM-DC-Agent
Invoke-RestMethod http://localhost:8000/health
```

La respuesta de `/health` debe incluir `"hmac_required": true` (Paso 9 activo),
`"token_configured": true` confirmando que `AGENT_TOKEN` está definido en el
entorno del servicio, y `"scripts_dir": "C:\\tfm-scripts"`. Un
`"token_configured": false` con `"status": "ok"` es la señal de un servicio
arrancado pero inservible: acepta el proceso pero rechazará toda petición a `/run`.
