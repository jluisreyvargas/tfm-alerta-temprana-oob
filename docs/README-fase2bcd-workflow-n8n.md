# Fase 2b/2c/2d — Integración Wazuh → n8n → Rocket.Chat

**Proyecto:** alerta-temprana-oob  
**Fases:** 2b, 2c, 2d  
**Fecha:** 2026-05-17  
**Estado:** ✅ Operativo  

> [!NOTE]
> Las validaciones de este documento se realizaron con payloads sintéticos enviados por `curl` desde el host, no sobre tráfico real de Wazuh: `wazuh-integratord` no estaba corriendo y `n8n.oob.local` resolvía a `127.0.0.1` dentro del contenedor del manager. La validación de extremo a extremo sobre tráfico real está documentada en `fase2-orquestador/README.md`.

---

## Descripción

Implementación del flujo completo de orquestación de alertas de seguridad:
- **Fase 2b:** Script de integración custom en Wazuh Manager
- **Fase 2c:** Workflow n8n con recepción, extracción y filtrado de alertas
- **Fase 2d:** Notificación automática a Rocket.Chat

---

## Flujo implementado
Wazuh Manager
│ /var/ossec/integrations/custom-n8n
│ HTTP POST (JSON alert)
▼
n8n Webhook Node (POST /webhook/wazuh-alerts)
│
▼
Set Node (extrae campos: rule_id, rule_level, rule_desc, agent_name, timestamp)
│
▼
IF Node (rule_level >= 7)
│
├── True ──▶ Rocket.Chat Node → canal: general
└── False ──▶ (ignorado)

---

## Fase 2b — Script custom-n8n en Wazuh

### Ubicación
/var/ossec/integrations/custom-n8n


### Contenido del script

```python
#!/usr/bin/env python3

import sys
import json
import urllib.request
import urllib.error
import ssl
from datetime import datetime

WEBHOOK_URL = "https://n8n.oob.local/webhook/wazuh-alerts"

def send_alert(alert_json):
    payload = json.dumps(alert_json).encode("utf-8")
    req = urllib.request.Request(
        WEBHOOK_URL,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=10) as resp:
            return resp.status
    except urllib.error.URLError as e:
        sys.stderr.write(f"[custom-n8n] Error enviando alerta: {e}\n")
        return None

def main():
    alert_file = sys.argv[1]
    with open(alert_file, "r") as f:
        alert_data = json.load(f)
    alert_data["oob_timestamp"] = datetime.utcnow().isoformat() + "Z"
    status = send_alert(alert_data)
    if status:
        sys.stdout.write(f"[custom-n8n] Alerta enviada OK (HTTP {status})\n")

if __name__ == "__main__":
    main()
```

> [!NOTE]
> **Estado actual.** `ssl.CERT_NONE` desactiva la verificación TLS por completo. La versión actual del script verifica contra la CA propia del enclave en lugar de omitir la verificación. Ver `fase2-orquestador/CAMBIOS-WORKFLOW-N8N.md` y la sección "PKI del enclave" de `fase2-orquestador/README.md`.

### Permisos

```bash
chmod 750 /var/ossec/integrations/custom-n8n
chown root:wazuh /var/ossec/integrations/custom-n8n
```

### Configuración en ossec.conf

```xml
<ossec_config>
  <integration>
    <name>custom-n8n</name>
    <hook_url>https://n8n.oob.local/webhook/wazuh-alerts</hook_url>
    <level>7</level>
    <alert_format>json</alert_format>
  </integration>
</ossec_config>
```

> [!CAUTION]
> El bloque `<integration>` debe ir dentro de `<ossec_config>`. Si `wazuh-integratord` no encuentra ningún bloque `<integration>` válido, no arranca: registra `Remote integrations not configured. Clean exit.` y termina sin error visible. Comprobar siempre que el demonio está activo tras un reinicio o recreación del contenedor:
> ```bash
> docker exec single-node-wazuh.manager-1 /var/ossec/bin/wazuh-control status | grep integrator
> ```

---

## Fase 2c — Workflow n8n

### Nombre del workflow
`Wazuh Alert Handler`

### Versión n8n
`2.20.9 (Self Hosted)`

### Nodos implementados

#### 1. Webhook Node
| Parámetro | Valor |
|-----------|-------|
| HTTP Method | `POST` |
| Path | `wazuh-alerts` |
| Authentication | `None` |
| Respond | `Immediately` |
| URL producción | `https://n8n.oob.local/webhook/wazuh-alerts` |

> [!NOTE]
> **Estado actual.** El webhook aceptaba originalmente cualquier petición sin autenticación. La versión actual verifica una firma HMAC-SHA256 (cabecera `X-OOB-Signature`) antes de procesar la alerta. Ver `fase2-orquestador/CAMBIOS-WORKFLOW-N8N.md` y la sección "Seguridad del canal de ingesta" de `fase2-orquestador/README.md`.

#### 2. Set Node (Edit Fields)
| Campo de salida | Expresión |
|----------------|-----------|
| `rule_id` | `{{ $json.body.rule.id }}` |
| `rule_level` | `{{ $json.body.rule.level }}` |
| `rule_desc` | `{{ $json.body.rule.description }}` |
| `agent_name` | `{{ $json.body.agent.name }}` |
| `timestamp` | `{{ $json.body.oob_timestamp }}` |

> **Nota:** n8n envuelve el payload del webhook dentro de `body`,
> por eso las expresiones usan `$json.body.*`

> [!NOTE]
> **Estado actual.** El nodo `Edit Fields` fue sustituido por `Normalize Alert`, que además maneja alertas sin `data.srcip` (las de integridad, regla 550), separa `event_timestamp` de `ingest_timestamp` y propaga `rule.mitre` nativo de Wazuh. Ver `fase2-orquestador/CAMBIOS-WORKFLOW-N8N.md` y la sección "Normalización y deduplicación" de `fase2-orquestador/README.md`.

#### 3. IF Node
| Parámetro | Valor |
|-----------|-------|
| Value 1 | `{{ $json.rule_level }}` |
| Operator | `>= (Number)` |
| Value 2 | `7` |

---

## Fase 2d — Integración Rocket.Chat

### Credenciales n8n (Rocket.Chat)

| Campo | Valor |
|-------|-------|
| Server URL | `http://rocketchat:3000` |
| User ID | ID del usuario `orchestrator` |
| Auth Token | Token generado en Fase 1c |

> **Importante:** Se usa la URL interna Docker (`http://rocketchat:3000`)
> ya que el contenedor n8n no resuelve hostnames de `/etc/hosts` del host.
> No usar `https://chat.oob.local` desde dentro de n8n.

### Nodo Rocket.Chat
| Parámetro | Valor |
|-----------|-------|
| Resource | `Message` |
| Operation | `Post` |
| Channel | `general` (sin `#`) |

### Mensaje de alerta
🚨 Alerta de Seguridad OOB
📋 Regla: {{ $json.body.rule_id }} — {{ $json.body.rule_desc }}
⚠️ Severidad: {{ $json.body.rule_level }}
🖥️ Agente: {{ $json.body.agent_name }}
🕐 Timestamp: {{ $json.body.timestamp }}


> **Nota:** El campo Channel debe ir **sin almohadilla** (`general`, no `#general`).
> Con `#general` Rocket.Chat devuelve `error-not-allowed` (HTTP 400).

> [!NOTE]
> **Sin reproducir.** `error-not-allowed` es el error real de Rocket.Chat cuando el bot carece del permiso `create-c`/`create-p` para crear canales o grupos — no está confirmado que un `#` de más en el campo `Channel` de este nodo lo dispare. En esta instalación el bot siempre tuvo permisos suficientes, así que este caso concreto nunca se llegó a ver; queda documentado como previsto, no como observado. El error que sí se observó y confirmó por un `#`/`roomId` mal usado en `chat.postMessage` es `[invalid-channel]`, en el flujo de War Room posterior — ver `fase2-orquestador/CAMBIOS-WORKFLOW-N8N.md`.

---

## Problemas encontrados y soluciones

| Problema | Causa | Solución |
|----------|-------|----------|
| Webhook 404 con `/webhook/` | Workflow no publicado | Pulsar **Publish** en n8n |
| Expresiones `$json.rule.*` vacías | n8n envuelve payload en `body` | Usar `$json.body.rule.*` en nodo Set |
| `error-not-allowed` Rocket.Chat (previsto, no observado — ver nota arriba) | Canal con `#` en el nombre | Usar `general` sin `#` |
| Conexión rechazada a `chat.oob.local` | Hostname no resuelto dentro del contenedor n8n | Usar URL interna Docker `http://rocketchat:3000` |

---

## Validación

```bash
# Test del flujo completo (URL producción)
curl -k -X POST https://n8n.oob.local/webhook/wazuh-alerts \
  -H "Content-Type: application/json" \
  -d '{
    "rule": {"id": "5710", "level": 7, "description": "Test alert OOB"},
    "agent": {"id": "000", "name": "wazuh-manager"},
    "oob_timestamp": "2026-05-17T21:00:00Z"
  }'
```

### Checklist de validación

- ✅ Script `custom-n8n` instalado con permisos correctos en Wazuh Manager
- ✅ Integración registrada en `ossec.conf` con `level >= 7`
- ✅ Workflow `Wazuh Alert Handler` publicado en n8n
- ✅ Nodos `Webhook → Set → IF → Rocket.Chat` operativos
- ✅ Mensaje de alerta recibido en canal `general` de Rocket.Chat
- ✅ URL de producción `/webhook/wazuh-alerts` activa y respondiendo

---

## Estado del proyecto

| Fase | Descripción | Estado |
|------|-------------|--------|
| 1a | Traefik v3.3 + Portainer | ✅ Completada |
| 1b | Authelia v4.39.19 MFA/IdP | ✅ Completada |
| 1c | MongoDB 8.0 + Rocket.Chat 8.4.1 | ✅ Completada |
| 1d | Wazuh 4.14.0 Single-Node | ✅ Completada |
| 1e | Validación final + tag fase1-base | ✅ Completada |
| 2a | n8n Orquestador desplegado | ✅ Completada |
| **2b** | **Script integración Wazuh → n8n** | ✅ **Completada** |
| **2c** | **Workflow n8n: recepción y filtrado** | ✅ **Completada** |
| **2d** | **Notificación Rocket.Chat** | ✅ **Completada** |
| 2e | Playbooks respuesta activa + tag fase2 | ⏳ Siguiente |

