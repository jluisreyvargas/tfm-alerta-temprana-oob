# Fase 4d — Orquestador ↔ DC Agent ↔ Rocket.Chat

## Objetivo

Integrar el agente Python del Domain Controller (DC Agent) en el flujo de orquestación existente con n8n y Rocket.Chat, de forma que las acciones sobre el DC (p. ej. deshabilitar cuentas) se ejecuten solo tras aprobación explícita y queden notificadas en el canal de incidentes.

Resumen del flujo:

1. n8n recibe una petición HTTP (webhook) con los campos `decision`, `script`, `target`, etc.
2. Si `decision = approved`, n8n llama al DC Agent vía Headscale/Tailscale (`/run`).
3. El DC Agent ejecuta el script PowerShell permitido y devuelve `stdout`, `stderr` y `returncode`.
4. n8n publica el resultado en Rocket.Chat usando la API `chat.postMessage`.

## Alcance

Esta subfase solo cubre la integración lógica entre:

- Webhook de n8n (`/dc-action`).
- DC Agent ya desplegado en Fase 4c.
- Rocket.Chat ya desplegado en la Fase 1 (infraestructura base).

No modifica la lógica de triage o de IA agéntica, sino que añade una pieza de orquestación sobre el DC.

## Prerrequisitos

- Fase 4a: Headscale operativo en Docker.
- Fase 4b: nodos `orchestrator-tfm` (100.64.0.1) y `dc01-tfm` (100.64.0.2) registrados y activos.
- Fase 4c: DC Agent operativo en `http://dc01-tfm:8000` con `AGENT_TOKEN` definido y scripts permitidos.
- Workflow principal de n8n funcionando y accesible como `https://n8n.oob.local`.
- Rocket.Chat accesible desde el contenedor n8n mediante su nombre de servicio Docker (p. ej. `rocketchat:3000`).

## Diseño del workflow en n8n

### Nodo 1 — Webhook (Trigger)

- **Nombre:** `Webhook DC Action`
- **HTTP Method:** `POST`
- **Path:** `dc-action`

URLs generadas por n8n:

- **Test URL:**  
  `https://n8n.oob.local/webhook-test/dc-action`
- **Production URL:**  
  `https://n8n.oob.local/webhook/dc-action`

Para pruebas manuales se usa la Test URL mientras el workflow está en modo `Execute Workflow` / `Listen for test event`. Para integración real se usa la Production URL con el workflow en estado **Active**.

### Payload de entrada esperado

Ejemplo de JSON que llega al Webhook:

```json
{
  "decision": "approved",
  "script": "disable_account.ps1",
  "target": "usuario.prueba",
  "requested_by": "jgarcia",
  "incident_id": "INC-2026-001"
}
```

Estos campos se almacenan en `$json` y se reusan en los nodos posteriores.

### Nodo 2 — IF (filtrar por decisión)

- **Nombre:** `IF decision approved`
- **Condición:**
  - Mode: `Single condition`
  - Value 1: `={{$json["decision"]}}`
  - Operation: `equals`
  - Value 2: `approved`

Solo si la decisión es `approved` se ejecutan los nodos siguientes (llamada al DC Agent y notificación en Rocket.Chat). Si no, el flujo termina sin hacer cambios en el DC.

### Nodo 3 — HTTP Request (DC Agent)

- **Nombre:** `Call DC Agent`
- **Authentication:** `None`
- **Method:** `POST`
- **URL:** `http://100.64.0.2:8000/run`
- **Headers:**
  - `Authorization`: `Bearer tfm-token-secreto-2024`
  - `Content-Type`: `application/json`
- **Body:**
  - `Send Body As`: `JSON`
  - Body Parameters:
    - `script`: `={{$json["script"]}}`
    - `target`: `={{$json["target"]}}`

Ejemplo de petición efectiva que genera este nodo (equivalente al curl probado):

```bash
curl -X POST http://100.64.0.2:8000/run \
  -H "Authorization: Bearer tfm-token-secreto-2024" \
  -H "Content-Type: application/json" \
  -d '{"script":"disable_account.ps1","target":"usuario.prueba"}'
```

Respuesta real obtenida durante las pruebas:

```json
{
  "script": "disable_account.ps1",
  "target": "usuario.prueba",
  "stdout": "TFM-AGENT: Deshabilitando cuenta AD: usuario.prueba\nDRY-RUN OK - Disable-ADAccount -Identity usuario.prueba\n",
  "stderr": "",
  "returncode": 0
}
```

Esta salida queda disponible en `$json` para el siguiente nodo.

### Nodo 4 — HTTP Request (Rocket.Chat)

- **Nombre:** `Notify Rocket.Chat`
- **Authentication:** `None` (se usan headers manuales con las credenciales de API)
- **Method:** `POST`
- **URL:** `http://rocketchat:3000/api/v1/chat.postMessage`
- **Headers:**
  - `X-Auth-Token`: `<TOKEN_API_ROCKETCHAT>`
  - `X-User-Id`: `<USER_ID_ROCKETCHAT>`
  - `Content-Type`: `application/json`
- **Body:**
  - `Send Body As`: `JSON`
  - Body Parameters:
    - `channel`: `general`
    - `text` (Expression):

      ```n8n
      =
      "✅ Acción DC completada\n" +
      "Script: " + $json["script"] + "\n" +
      "Target: " + $json["target"] + "\n" +
      "Return code: " + $json["returncode"]
      ```

Ejemplo del JSON que envía este nodo a Rocket.Chat:

```json
{
  "channel": "general",
  "text": "✅ Acción DC completada\nScript: disable_account.ps1\nTarget: usuario.prueba\nReturn code: 0"
}
```

## Pruebas realizadas

### 1. Prueba completa en modo test (Webhook Test URL)

1. En n8n se abrió el workflow y se pulsó `Execute Workflow` para poner el nodo Webhook en modo escucha.
2. Desde el host Ubuntu se lanzó:

   ```bash
   curl -k -X POST "https://n8n.oob.local/webhook-test/dc-action" \
     -H "Content-Type: application/json" \
     -d '{
       "decision": "approved",
       "script": "disable_account.ps1",
       "target": "usuario.prueba",
       "requested_by": "jgarcia",
       "incident_id": "INC-2026-001"
     }'
   ```

3. El nodo `Call DC Agent` envió la petición al DC y recibió `returncode: 0`.
4. El nodo `Notify Rocket.Chat` publicó el mensaje en el canal `#general`.

Mensaje observado en Rocket.Chat:

```text
orchestrator-bot
✅ Acción DC completada
Script: disable_account.ps1
Target: usuario.prueba
Return code: 0
```

### 2. Prueba con token incorrecto (seguridad del DC Agent)

Se probó directamente contra el DC Agent para verificar rechazo por token erróneo:

```bash
curl -s -X POST http://dc01-tfm:8000/run \
  -H "Authorization: Bearer token-incorrecto" \
  -H "Content-Type: application/json" \
  -d '{"script":"disable_account.ps1","target":"test"}'
```

Respuesta:

```json
{"detail":"Forbidden"}
```

Lo que confirma que el DC Agent solo acepta el token configurado en `AGENT_TOKEN`.

### 3. Prueba con script fuera del allowlist

Petición directa al DC Agent con un script no permitido:

```bash
curl -s -X POST http://dc01-tfm:8000/run \
  -H "Authorization: Bearer tfm-token-secreto-2024" \
  -H "Content-Type: application/json" \
  -d '{"script":"malicioso.ps1","target":"x"}'
```

Respuesta:

```json
{"detail":"Script no permitido: malicioso.ps1"}
```

Esto demuestra que la allowlist definida en `ALLOWED_SCRIPTS` funciona correctamente.

## Resultado de la Fase 4d

La Fase 4d queda completada con:

- Webhook de n8n recibiendo decisiones y parámetros de acción para el DC.
- Condición explícita `decision = approved` antes de ejecutar cualquier script.
- Llamada al DC Agent protegida por Bearer Token, sobre la red privada Headscale.
- Publicación de resultados en Rocket.Chat con el contexto de script, target y código de retorno.

El sistema está preparado para que, en fases posteriores, este flujo se conecte tanto con la IA agéntica (que recomienda acciones) como con DFIR-IRIS (que registrará las acciones en el caso de incidente).

## Comandos de commit

Una vez revisados el workflow y este README, los comandos sugeridos para guardar el avance en el repositorio son:

```bash
cd /home/jose/tfm-alerta-temprana-oob

git add fase4-breakglass-dc/
git add docs/README-fase4d-orquestador-dc.md   # si se copia este README a docs/

git commit -m "fase4d: integracion n8n ↔ dc agent ↔ rocketchat"

git push origin main
```

En caso de trabajar en una rama específica para la Fase 4, sustituir `main` por el nombre real de la rama.
