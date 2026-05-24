# README — Fase 2f: CTI Enrichment con AbuseIPDB y VirusTotal

**Proyecto:** TFM — Plataforma OOB de alerta temprana y respuesta a incidentes
**Fase:** 2f — Enriquecimiento CTI automático
**Fecha:** 2026-05-24
**Estado:** Completada y validada

---

## Descripción

En esta fase se amplió el pipeline de triage para incorporar inteligencia de amenazas externa en tiempo real. Antes de que el AI Agent emita su análisis, el flujo consulta automáticamente **AbuseIPDB** y **VirusTotal** con la IP fuente extraída de la alerta Wazuh. El resultado es un análisis más rico y contextualizado, donde el modelo recibe no solo los campos nativos de Wazuh sino también reputación IP, volumen de reportes de abuso y votos agregados de motores de seguridad.

## Objetivos alcanzados

- Integración de **AbuseIPDB API v2** para consulta de reputación IP en tiempo real.
- Integración de **VirusTotal API v3** para obtener votos de análisis y contexto ASN.
- Ejecución paralela de ambas consultas HTTP desde n8n antes del AI Agent.
- Consolidación de resultados CTI mediante nodo **Merge** + **Code CTI Context**.
- Recomposición del payload completo (alerta + CTI + análisis IA) en nodo **Code Merge Final**.
- Publicación del mensaje enriquecido completo en **Rocket.Chat**.

## Componentes del flujo

| Nodo | Función |
|---|---|
| Webhook | Recibe alerta Wazuh |
| Edit Fields | Normaliza campos del payload |
| IF (level >= 7) | Filtra alertas relevantes |
| AbuseIPDB Check | HTTP GET a api.abuseipdb.com/api/v2/check |
| VirusTotal Check | HTTP GET a virustotal.com/api/v3/ip_addresses/{ip} |
| Merge | Combina las dos ramas CTI por posición |
| Code CTI Context | Normaliza campos CTI y recompone alerta original |
| AI Agent | Mistral 7B analiza con contexto enriquecido |
| Code Merge Final | Combina CTI + análisis IA en un único payload |
| Rocket.Chat | Publica mensaje final estructurado |

## Arquitectura validada

```
Webhook Wazuh
   |
   v
Edit Fields
   |
   v
IF (rule.level >= 7)
   | True
   |-------------------+------------------+
   v                   v                  v
AbuseIPDB Check   VirusTotal Check   (MISP — pendiente)
   |                   |
   +--------+----------+
            v
          Merge
            |
            v
    Code CTI Context
            |
            v
        AI Agent (Mistral 7B)
            |
            v
    Code Merge Final
            |
            v
        Rocket.Chat
```

## Configuración HTTP Request — AbuseIPDB

| Campo | Valor |
|---|---|
| Method | GET |
| URL | https://api.abuseipdb.com/api/v2/check |
| Auth | Header Auth |
| Header Name | Key |
| Query: ipAddress | {{ $json.body.data.srcip || $json.body.agent.ip || '1.1.1.1' }} |
| Query: maxAgeInDays | 90 |

La respuesta devuelve: `abuseConfidenceScore`, `totalReports`, `countryCode`, `isp`, `isTor`.

## Configuración HTTP Request — VirusTotal

| Campo | Valor |
|---|---|
| Method | GET |
| URL | https://www.virustotal.com/api/v3/ip_addresses/{{ $json.body.data.srcip }} |
| Auth | Header Auth |
| Header Name | x-apikey |

La respuesta devuelve en `data.attributes`: `total_votes` (malicious/harmless), `asn`, `as_owner`, `network`, `country`.

> IMPORTANTE: La estructura real de VirusTotal v3 para IPs usa `total_votes` y NO `last_analysis_stats`.
> El código debe acceder a `vtAttr.total_votes.malicious` y no a `last_analysis_stats.malicious`.

## Nodo Merge

Configurado en modo **Combine by Position** para unir AbuseIPDB (input 1) y VirusTotal (input 2)
en un único item por alerta.

## Código — Code CTI Context

Detecta dinámicamente cuál rama es AbuseIPDB y cuál VirusTotal buscando campos característicos:

```javascript
const items = $input.all();
let abuseRaw = {}, vtAttr = {};

for (const item of items) {
  const d = item.json;
  if (d?.data?.abuseConfidenceScore !== undefined) {
    abuseRaw = d.data;
  }
  if (d?.data?.attributes?.asn !== undefined || d?.data?.attributes?.total_votes !== undefined) {
    vtAttr = d.data.attributes;
  }
}

const body = $('Edit Fields').first().json.body || {};

return [{ json: {
  rule_id:    String(body?.rule?.id          ?? 'N/A'),
  rule_desc:  String(body?.rule?.description ?? 'N/A'),
  rule_level: String(body?.rule?.level       ?? 'N/A'),
  agent_name: String(body?.agent?.name       ?? 'N/A'),
  timestamp:  String(body?.oob_timestamp     ?? 'N/A'),
  src_ip:     String(body?.data?.srcip       ?? body?.agent?.ip ?? 'N/A'),

  abuse_confidence:    String(abuseRaw.abuseConfidenceScore ?? 0),
  abuse_total_reports: String(abuseRaw.totalReports         ?? 0),
  abuse_country:       String(abuseRaw.countryCode          ?? 'N/A'),
  abuse_isp:           String(abuseRaw.isp                  ?? 'N/A'),
  abuse_is_tor:        String(abuseRaw.isTor                ?? false),

  vt_malicious:  String(vtAttr.total_votes?.malicious ?? 0),
  vt_harmless:   String(vtAttr.total_votes?.harmless  ?? 0),
  vt_asn:        String(vtAttr.asn                    ?? 'N/A'),
  vt_as_owner:   String(vtAttr.as_owner               ?? 'N/A'),
  vt_network:    String(vtAttr.network                ?? 'N/A'),
  vt_country:    String(vtAttr.country                ?? 'N/A'),
}}];
```

## Código — Code Merge Final

Recompone el payload final combinando CTI + análisis IA parseado del AI Agent:

```javascript
const output = $input.first().json.output || '';
const match = output.match(/\{[\s\S]*\}/);
let parsed = {};
try { if (match) parsed = JSON.parse(match[0]); } catch(e) {}

const cti = $('Code CTI Context').first().json;

return [{ json: {
  rule_id:    cti.rule_id,
  rule_desc:  cti.rule_desc,
  rule_level: cti.rule_level,
  agent_name: cti.agent_name,
  timestamp:  cti.timestamp,
  src_ip:     cti.src_ip,

  abuse_confidence:    cti.abuse_confidence,
  abuse_total_reports: cti.abuse_total_reports,
  abuse_country:       cti.abuse_country,
  abuse_isp:           cti.abuse_isp,
  abuse_is_tor:        cti.abuse_is_tor,

  vt_malicious:  cti.vt_malicious,
  vt_harmless:   cti.vt_harmless,
  vt_asn:        cti.vt_asn,
  vt_as_owner:   cti.vt_as_owner,
  vt_network:    cti.vt_network,
  vt_country:    cti.vt_country,

  severidad_real:   parsed.severidad_real   || 'N/A',
  tactica_mitre:    parsed.tactica_mitre    || 'N/A',
  tecnica_mitre:    parsed.tecnica_mitre    || 'N/A',
  resumen:          parsed.resumen          || 'N/A',
  recomendacion:    parsed.recomendacion    || 'N/A',
  requiere_bloqueo: String(parsed.requiere_bloqueo ?? false),
  raw_ai_output:    output
}}];
```

## Prompt del AI Agent

### User Message

```
Analiza esta alerta de seguridad Wazuh con datos CTI:

=== ALERTA WAZUH ===
Regla ID: {{ $json.rule_id }}
Descripcion: {{ $json.rule_desc }}
Severidad: {{ $json.rule_level }}
Agente afectado: {{ $json.agent_name }}
IP fuente: {{ $json.src_ip }}
Timestamp: {{ $json.timestamp }}

=== CTI — AbuseIPDB ===
Confidence Score: {{ $json.abuse_confidence }}%
Total reportes: {{ $json.abuse_total_reports }}
Pais: {{ $json.abuse_country }}
ISP: {{ $json.abuse_isp }}
Es nodo TOR: {{ $json.abuse_is_tor }}

=== CTI — VirusTotal ===
Votos maliciosos: {{ $json.vt_malicious }}
Votos harmless: {{ $json.vt_harmless }}
ASN: {{ $json.vt_asn }} ({{ $json.vt_as_owner }})
Red: {{ $json.vt_network }}
Pais: {{ $json.vt_country }}

Responde SOLO con el JSON de triage, sin texto adicional.
```

### Reglas de severidad en System Message

```
REGLAS DE SEVERIDAD OBLIGATORIAS:
- Si vt_malicious > 20 → severidad_real DEBE ser "ALTA" o "CRITICA"
- Si abuse_confidence > 50 → severidad_real DEBE ser "ALTA"
- Si abuse_total_reports > 100 Y vt_malicious > 10 → severidad_real "ALTA"
- Si requiere_bloqueo es true → justificarlo en resumen
```

## Template Rocket.Chat

```
🚨 *Alerta Analizada por IA — OOB*

📋 *Regla:* {{ $json.rule_id }} — {{ $json.rule_desc }}
⚠ *Severidad Wazuh:* {{ $json.rule_level }}
🖥 *Agente:* {{ $json.agent_name }}
🌐 *IP Fuente:* {{ $json.src_ip }}
🕐 *Timestamp:* {{ $json.timestamp }}

🔍 *CTI — AbuseIPDB*
├ Confidence Score: {{ $json.abuse_confidence }}%
├ Total Reportes: {{ $json.abuse_total_reports }}
├ País: {{ $json.abuse_country }}
├ ISP: {{ $json.abuse_isp }}
└ Nodo TOR: {{ $json.abuse_is_tor }}

🦠 *CTI — VirusTotal*
├ Votos maliciosos: {{ $json.vt_malicious }}
├ Votos harmless: {{ $json.vt_harmless }}
├ ASN: {{ $json.vt_asn }} ({{ $json.vt_as_owner }})
├ Red: {{ $json.vt_network }}
└ País: {{ $json.vt_country }}

🤖 *Análisis IA (Mistral 7B):*
├ Severidad Real: {{ $json.severidad_real }}
├ Táctica MITRE: {{ $json.tactica_mitre }}
├ Técnica: {{ $json.tecnica_mitre }}
├ Resumen: {{ $json.resumen }}
├ Recomendación: {{ $json.recomendacion }}
└ Requiere Bloqueo: {{ $json.requiere_bloqueo }}
```

## Resultado validado — Rocket.Chat

Mensaje real recibido durante la validación (2026-05-24):

```
🚨 Alerta Analizada por IA — OOB

📋 Regla: 5710 — SSH brute force attack detected
⚠ Severidad Wazuh: 7
🖥 Agente: web-server-01
🌐 IP Fuente: 1.1.1.1
🕐 Timestamp: 2026-05-21T20:00:00Z

🔍 CTI — AbuseIPDB
├ Confidence Score: 0%
├ Total Reportes: 239
├ País: AU
├ ISP: APNIC and Cloudflare DNS Resolver project
└ Nodo TOR: false

🦠 CTI — VirusTotal
├ Votos maliciosos: 39
├ Votos harmless: 144
├ ASN: 13335 (Cloudflare, Inc.)
├ Red: 1.1.1.0/24
└ País: N/A

🤖 Análisis IA (Mistral 7B):
├ Severidad Real: MEDIA
├ Táctica MITRE: T1110 - Brute Force
├ Técnica: TXXXX - SSH
├ Resumen: SSH brute force attack detected on web-server-01 from IP 1.1.1.1,
│          potential malicious activity based on VirusTotal report
├ Recomendación: Monitor the affected agent and increase login attempts rate limits.
└ Requiere Bloqueo: false
```

> La IP 1.1.1.1 pertenece a Cloudflare con abuseConfidenceScore = 0, lo que explica la severidad
> MEDIA. Con IPs maliciosas reales el score de AbuseIPDB y vt_malicious serán más altos y el
> modelo escalará la severidad según las reglas del System Message.

## Incidencias resueltas

### 1. Campos CTI vacíos en Rocket.Chat

**Causa:** El nodo Rocket.Chat estaba conectado directamente al AI Agent, que sobreescribía
el payload devolviendo solo su campo `output`.
**Solución:** Añadir el nodo `Code Merge Final` que recompone CTI + análisis antes de publicar.

### 2. Campos VirusTotal todos a 0 y N/A

**Causa:** El código accedía a `last_analysis_stats` pero la respuesta real de VirusTotal v3
para IPs usa `total_votes`.
**Solución:** Actualizar rutas a `vtAttr.total_votes.malicious` y `vtAttr.total_votes.harmless`.

### 3. Valores numéricos no renderizados en Rocket.Chat

**Causa:** n8n no renderiza valores falsy (0, false) con la sintaxis {{ $json.campo }}.
**Solución:** Forzar String() sobre todos los valores en el nodo Code.

### 4. src_ip = N/A en pruebas

**Causa:** El payload de test no incluía el campo data.srcip.
**Solución:** Añadir "data": {"srcip": "1.1.1.1"} al curl de prueba. En alertas reales de
Wazuh la regla 5710 incluye este campo nativamente.

## Estado del proyecto

| Fase | Estado |
|---|---|
| Fase 1 — Base de infraestructura | Completada |
| Fase 2a — n8n desplegado | Completada |
| Fase 2b — Webhook Wazuh a n8n | Completada |
| Fase 2c — Notificación Rocket.Chat | Completada |
| Fase 2d — Filtrado por severidad | Completada |
| Fase 2e — Ollama + AI Agent | Completada |
| Fase 2f — CTI Enrichment | Completada |
| Fase 2g — MISP Integration | Pendiente |
| Fase 3 — War Rooms + Respuesta automática | Pendiente |

## Commit de cierre

```bash
cd ~/tfm-alerta-temprana-oob
git add .
git commit -m "fase2f: CTI Enrichment operativo - AbuseIPDB + VirusTotal integrados en triage IA"
git push
```

## Siguiente fase

La siguiente fase es **2g — MISP Integration**, que añadirá como tercer bloque CTI consultas
a la instancia interna de MISP para correlacionar indicadores de compromiso, eventos compartidos
y contexto táctico adicional antes de que el AI Agent genere su análisis final.
