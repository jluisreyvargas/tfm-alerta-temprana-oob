# Despliegue de `agent_dc.py` en el Domain Controller (W2025)

Este documento describe cómo instalar el agente Python como servicio de Windows en el DC.
No contiene valores reales de secretos: usa siempre los placeholders indicados.

## 1. Requisitos previos

- Python 3.11 instalado en el DC (`winget install -e --id Python.Python.3.11 --scope machine`).
- Nodo `dc01-tfm` ya registrado en la tailnet Headscale (Fase 4b), con el tag `tag:dc`.
- [NSSM](https://nssm.cc/) disponible en el DC para registrar el proceso como servicio Windows
  (Python/uvicorn no ofrece un modo "servicio" nativo).

## 2. Estructura de directorios en el DC

```
C:\tfm-agent\
├── agent_dc.py
├── requirements.txt
└── logs\                  # creado automáticamente por el agente (TFM_LOG_PATH)
C:\tfm-scripts\
├── disable_account.ps1
├── enable_account.ps1
├── collect_logs.ps1
├── isolate_host.ps1
├── reset_password.ps1
├── rustdesk_enable.ps1
└── rustdesk_disable.ps1
```

## 3. ACL de directorios

- `C:\tfm-agent\` y `C:\tfm-scripts\`: escritura restringida a `SYSTEM` y `Administrators`.
  La cuenta de servicio bajo la que corre el agente solo necesita **lectura y ejecución**
  sobre `C:\tfm-scripts\`, nunca escritura — el agente no debe poder modificar su propia
  allowlist de scripts.
- `C:\tfm-agent\logs\`: escritura para la cuenta de servicio, lectura para el equipo de
  respuesta/auditoría. Estos logs son la fuente que consume el agente Wazuh del DC
  (`fase7-observabilidad`).

## 4. Variables de entorno de máquina

Definir como variables de entorno de **máquina** (no de usuario), para que estén
disponibles al servicio NSSM independientemente de qué sesión lo arranque:

| Variable | Obligatoria | Descripción |
|---|---|---|
| `AGENT_TOKEN` | Sí | Bearer token compartido con el orquestador. Placeholder: `REEMPLAZAR` |
| `AGENT_HMAC_SECRET` | Solo si `AGENT_REQUIRE_HMAC=true` | Secreto compartido para la firma HMAC-SHA256 de las peticiones. Placeholder: `REEMPLAZAR` |
| `AGENT_REQUIRE_HMAC` | No (default `false`) | `true` para exigir cabeceras `X-Timestamp`/`X-Nonce`/`X-Signature` en `/run` |
| `TFM_SCRIPTS_DIR` | No (default `C:\tfm-scripts`) | Ruta anclada desde la que se resuelven los scripts de la allowlist |
| `TFM_LOG_PATH` | No (default `C:\tfm-agent\logs\agent.log`) | Ruta del log rotado que consume Wazuh |

Establecerlas con `setx` a nivel de máquina (requiere reiniciar la sesión/servicio para
que surtan efecto):

```powershell
setx AGENT_TOKEN "REEMPLAZAR" /M
setx AGENT_HMAC_SECRET "REEMPLAZAR" /M
setx AGENT_REQUIRE_HMAC "false" /M
```

## 5. Registro como servicio con NSSM

```powershell
nssm install TFM-DCAgent "C:\Python311\python.exe" "-m uvicorn agent_dc:app --host 0.0.0.0 --port 8000"
nssm set TFM-DCAgent AppDirectory "C:\tfm-agent"
nssm set TFM-DCAgent AppStdout "C:\tfm-agent\logs\service-stdout.log"
nssm set TFM-DCAgent AppStderr "C:\tfm-agent\logs\service-stderr.log"
nssm set TFM-DCAgent Start SERVICE_AUTO_START
nssm start TFM-DCAgent
```

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
Get-Service TFM-DCAgent
Invoke-RestMethod http://localhost:8000/health
```

La respuesta de `/health` debe incluir `"hmac_required"` reflejando el valor real de
`AGENT_REQUIRE_HMAC`, `"token_configured": true` confirmando que `AGENT_TOKEN` está
definido en el entorno del servicio, y `"scripts_dir"` apuntando a `C:\tfm-scripts`.
Un `"token_configured": false` con `"status": "ok"` es la señal de un servicio
arrancado pero inservible: acepta el proceso pero rechazará toda petición a `/run`.
