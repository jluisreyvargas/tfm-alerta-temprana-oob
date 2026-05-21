# README — Fase 2e: Ollama + Mistral 7B + AI Agent en n8n

**Proyecto:** TFM — Plataforma OOB de alerta temprana y respuesta a incidentes  
**Fase:** 2e — Integración de IA local para triage inteligente  
**Fecha:** 2026-05-21  
**Estado:** Completada y validada

## Descripción

En esta fase se integró un modelo de lenguaje local mediante **Ollama** con el workflow de orquestación de **n8n**, sustituyendo la necesidad de una API externa de IA para el triage inicial de alertas. El objetivo fue validar un flujo soberano y autocontenido: **Wazuh → n8n → AI Agent → Rocket.Chat**, con análisis automatizado de incidentes usando un LLM local.[cite:84][cite:130]

La validación confirmó que n8n puede consumir un modelo local a través del nodo **Ollama Model**, y que el agente puede generar una salida estructurada útil para operaciones SOC/SOAR, incluyendo severidad real, táctica MITRE ATT&CK, técnica asociada, resumen y recomendación de respuesta.[cite:84]

## Objetivos alcanzados

- Despliegue del contenedor `ollama` en la red Docker `oob-network`.
- Descarga y carga operativa del modelo `mistral:7b`.
- Verificación de conectividad desde el contenedor `n8n` hacia `http://ollama:11434/api/tags`.[cite:130]
- Creación de credencial funcional de Ollama en n8n usando la URL interna del servicio.[cite:84]
- Integración del nodo **AI Agent** con **Ollama Model** en el workflow de alertas.
- Generación de análisis IA visible en Rocket.Chat para eventos con severidad `>= 7`.

## Componentes desplegados

| Componente | Versión / modelo | Estado |
|---|---|---|
| n8n | 2.20.9 | Operativo |
| Ollama | `ollama/ollama:latest` | Operativo |
| Modelo LLM | `mistral:7b` | Cargado |
| Red Docker | `oob-network` | Operativa |
| Integración IA | `AI Agent` + `Ollama Model` | Validada |

## Arquitectura validada

El flujo funcional validado en esta fase queda así:

```text
Wazuh Alert
   │
   ▼
Webhook n8n
   │
   ▼
Edit Fields
   │
   ▼
IF (rule.level >= 7)
   │ True
   ▼
AI Agent
   └── Chat Model → Ollama Model (mistral:7b)
   │
   ▼
Code in Javascript
   │
   ▼
Rocket.Chat
```

Este diseño permite que cada alerta relevante sea enriquecida semánticamente por un agente local antes de publicarse en el canal de operaciones. El uso del nodo **Ollama Model** de n8n para integrar LLMs locales está documentado oficialmente por n8n.[cite:84]

## Configuración de conectividad

La validación mostró que la URL correcta **dentro de la red Docker** es:

```text
http://ollama:11434
```

La API de Ollama expone el endpoint `/api/tags` para listar modelos disponibles, lo que permitió verificar desde el contenedor `n8n` que `mistral:7b` estaba correctamente cargado.[cite:130]

Comando de prueba correcto desde `n8n`:

```bash
docker exec n8n wget -qO- http://ollama:11434/api/tags
```

El uso de `curl` falló porque el contenedor `n8n` no incluía ese binario en `PATH`; sin embargo, `wget` confirmó conectividad completa entre servicios.

## Configuración en n8n

### Credencial Ollama

En n8n se creó una credencial de tipo **Ollama** con estos parámetros:

| Campo | Valor |
|---|---|
| Base URL | `http://ollama:11434` |
| API Key | vacío |

La documentación de n8n confirma que el nodo **Ollama Model** se usa como modelo de chat dentro de agentes y cadenas LLM.[cite:84]

### Nodo AI Agent

El agente quedó configurado con:

- **Chat Model:** `Ollama Model`
- **Modelo:** `mistral:7b`
- **Memory:** no utilizada en esta validación inicial
- **Output Parser:** desactivado en la validación rápida final

Se optó por no usar memoria en esta fase porque el nodo requería `sessionId`, parámetro normalmente suministrado por `Chat Trigger`; en este proyecto el disparador es un **Webhook** técnico, por lo que se dejó la memoria para fases posteriores.[cite:84]

## Prompt operativo del agente

### System Message

```text
Eres un analista de seguridad SOC/SOAR experto en respuesta a incidentes.
Recibes alertas de Wazuh y debes triarlo inmediatamente.
Responde SIEMPRE con este JSON exacto, sin texto adicional:

{
  "severidad_real": "CRITICA|ALTA|MEDIA|BAJA",
  "tactica_mitre": "nombre de la tactica ATT&CK",
  "tecnica_mitre": "TXXXX - nombre",
  "resumen": "descripcion breve en 2 frases",
  "recomendacion": "accion inmediata recomendada",
  "requiere_bloqueo": true
}
```

### User Message

```text
Analiza esta alerta de seguridad Wazuh:

Regla ID: {{ $json.rule_id }}
Descripcion: {{ $json.rule_desc }}
Severidad: {{ $json.rule_level }}
Agente afectado: {{ $json.agent_name }}
Timestamp: {{ $json.timestamp }}

Responde SOLO con el JSON, sin texto adicional.
```

## Código de parsing posterior al agente

Como validación rápida, en lugar de usar un Output Parser estructurado se añadió un nodo **Code in Javascript** para extraer el JSON generado por Mistral y combinarlo con los datos originales del nodo `Edit Fields`.

Código funcional validado:

```javascript
const output = $input.first().json.output || '';
const match = output.match(/\{[\s\S]*\}/);
let parsed = {};
try { if (match) parsed = JSON.parse(match[0]); } catch(e) {}

const body = $('Edit Fields').first().json.body || {};

return [{ json: {
  rule_id:    String(body?.rule?.id          ?? 'N/A'),
  rule_desc:  String(body?.rule?.description ?? 'N/A'),
  rule_level: String(body?.rule?.level       ?? 'N/A'),
  agent_name: String(body?.agent?.name       ?? 'N/A'),
  timestamp:  String(body?.oob_timestamp     ?? 'N/A'),

  severidad_real:   parsed.severidad_real   || 'N/A',
  tactica_mitre:    parsed.tactica_mitre    || 'N/A',
  tecnica_mitre:    parsed.tecnica_mitre    || 'N/A',
  resumen:          parsed.resumen          || 'N/A',
  recomendacion:    parsed.recomendacion    || 'N/A',
  requiere_bloqueo: parsed.requiere_bloqueo ?? false,
  raw_ai_output:    output
}}];
```

## Ejemplo de prueba ejecutada

Prueba manual de webhook en modo test:

```bash
curl -k -X POST https://n8n.oob.local/webhook-test/wazuh-alerts \
  -H "Content-Type: application/json" \
  -d '{
    "rule": {"id": "5710", "level": 7, "description": "SSH brute force attack detected"},
    "agent": {"id": "001", "name": "web-server-01"},
    "oob_timestamp": "2026-05-21T20:00:00Z"
  }'
```

El uso de URL de test para webhooks es coherente con la práctica habitual de n8n durante la fase de desarrollo, antes de activar el workflow en producción.[cite:131][cite:136]

## Resultado funcional observado

Mensaje final publicado en Rocket.Chat tras el procesamiento completo:

```text
🚨 Alerta Analizada por IA — OOB

📋 Regla: 5710 — SSH brute force attack detected
⚠ Severidad Wazuh: 7
🖥 Agente: web-server-01
🕐 Timestamp: 2026-05-21T20:00:00Z

🤖 Análisis IA (Mistral 7B):
├ Severidad Real: ALTA
├ Táctica MITRE: Persistence
├ Técnica: T1547 - Process Hollowing
├ Resumen: Procesado de huecos en ejecuciones paralelas
├ Recomendación: Investigar proceso malicioso y tomar medidas para eliminarlo
└ Requiere Bloqueo: true
```

Este resultado demuestra que el flujo completo **captura, filtra, analiza y comunica** una alerta con apoyo de IA local, validando el enfoque arquitectónico planteado para el TFM.

## Incidencias resueltas

### 1. Error con `curl` en el contenedor `n8n`

Se detectó que `curl` no estaba disponible en el contenedor, lo que provocaba un parseo fallido en pruebas iniciales. La conectividad real se comprobó usando `wget`, que sí estaba presente.

### 2. Error de memoria del agente

El nodo de memoria requería un `sessionId`, esperado normalmente desde `Chat Trigger`. Como el flujo utiliza un webhook técnico, la memoria se desconectó temporalmente para simplificar la validación inicial del agente.

### 3. Pérdida de campos originales tras el AI Agent

El nodo `AI Agent` reenviaba esencialmente su `output`, por lo que se añadió un nodo `Code in Javascript` para recomponer el payload final usando el contenido original del nodo `Edit Fields`.

### 4. Parser estructurado demasiado costoso para la validación rápida

Se descartó temporalmente el uso de `Structured Output Parser` porque requería otra conexión de modelo, lo que aumentaba complejidad y latencia. Para esta fase de validación resultó más eficiente parsear el JSON en un nodo de código.

## Valor técnico para el TFM

Esta fase demuestra que un enfoque con **n8n + Ollama + modelo local** es viable para IA Agéntica aplicada a triage de incidentes. La decisión evita depender de una FastAPI adicional y mantiene toda la lógica de orquestación en una interfaz visual y extensible. El enfoque encaja especialmente bien con fases posteriores de **CTI Enrichment**, War Rooms y respuesta automatizada.[cite:84][cite:122]

Además, la integración local refuerza la soberanía del dato y reduce dependencia de proveedores externos, aspecto especialmente relevante en entornos de ciberseguridad con restricciones de privacidad o compliance.

## Estado del proyecto

| Fase | Estado |
|---|---|
| Fase 1 — Base de infraestructura | Completada |
| Fase 2a — n8n desplegado y validado | Completada |
| Fase 2b — integración webhook Wazuh → n8n | Completada |
| Fase 2c — notificación Rocket.Chat | Completada |
| Fase 2d — filtrado por severidad | Completada |
| **Fase 2e — Ollama + AI Agent** | **Completada** |
| Fase 2f — CTI Enrichment | Pendiente |
| Fase 3 — IA Agéntica extendida | Pendiente |

## Commit recomendado

```bash
cd ~/tfm-alerta-temprana-oob
git add .
git commit -m "fase2e: integrar Ollama y AI Agent en n8n para triage inteligente local"
git push
```

## Siguiente fase

La siguiente fase lógica es **Fase 2f — CTI Enrichment**, incorporando consultas automáticas a **AbuseIPDB**, **VirusTotal** y posteriormente **MISP** como fuentes de contexto para el agente. Esto permitirá que el triage no se base solo en los campos de Wazuh, sino también en reputación IP, análisis de hashes e indicadores de compromiso externos.
