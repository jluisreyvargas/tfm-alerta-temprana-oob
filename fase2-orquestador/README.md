# 🛡️ Fase 2 — Orquestación de Alertas Tempranas con Inteligencia Artificial

**Proyecto:** TFM — Plataforma OOB de alerta temprana y respuesta a incidentes  
**Fase:** 2 — Orquestación, IA y CTI Enrichment  
**Fecha:** 2026-05-17 / 2026-06-07  
**Estado:** ✅ Completada y validada  

[![TFM](https://img.shields.io/badge/TFM-Alerta%20Temprana%20OOB-blue)]()
[![Fase](https://img.shields.io/badge/Fase-2-orange)]()
[![Estado](https://img.shields.io/badge/Estado-Completado-success)]()
[![Docker](https://img.shields.io/badge/Docker-Compose-black)]()
[![n8n](https://img.shields.io/badge/n8n-2.20.9-red)]()
[![Ollama](https://img.shields.io/badge/Ollama-Mistral_7B-purple)]()

---

## 📋 Tabla de Contenidos

- [Resumen del Objetivo](#-resumen-del-objetivo)
- [Objetivos Específicos](#-objetivos-específicos)
- [Arquitectura del Pipeline](#-arquitectura-del-pipeline)
- [Stack Tecnológico](#-stack-tecnológico)
- [Subfases](#-subfases)
- [Flujo del Workflow n8n](#-flujo-del-workflow-n8n)
- [Instalación y Configuración](#-instalación-y-configuración)
- [Validación y Pruebas](#-validación-y-pruebas)
- [Resultados Alcanzados](#-resultados-alcanzados)
- [Incidencias Resueltas](#-incidencias-resueltas)
- [Estado del Proyecto](#-estado-del-proyecto)
- [Próximos Pasos](#-próximos-pasos)

---

## 🎯 Resumen del Objetivo

La **Fase 2** del TFM de **Alerta Temprana Out-of-Band (OOB)** desarrolla e implementa un sistema de orquestación automatizada de alertas de seguridad que integra **Wazuh**, **n8n**, **Inteligencia de Amenazas (CTI)** y un **Agente de IA local (Mistral 7B vía Ollama)**.

El pipeline captura alertas desde Wazuh, las enriquece en tiempo real con fuentes CTI externas (AbuseIPDB y VirusTotal) e internas (MISP), genera un análisis de triage automatizado usando un LLM local soberano y publica el resultado en Rocket.Chat para el equipo SOC.

El enfoque es completamente autocontenido: **sin dependencias de APIs de IA externas**, con soberanía del dato y orientado a operar en entornos con restricciones de privacidad o compliance.

---

## 🎯 Objetivos Específicos

1. **Fase 2a — Orquestador n8n:** Desplegar n8n como motor central de integración y automatización de workflows.
2. **Fase 2b — Script Wazuh:** Implementar el script `custom-n8n` en Wazuh Manager para reenviar alertas por HTTP POST.
3. **Fase 2c — Workflow n8n:** Desarrollar el workflow `Wazuh Alert Handler` con recepción, extracción y filtrado por severidad.
4. **Fase 2d — Rocket.Chat:** Implementar notificaciones automáticas al canal SOC mediante `orchestrator-bot`.
5. **Fase 2e — Agente de IA:** Integrar Ollama con Mistral 7B para análisis de triage estructurado con MITRE ATT&CK.
6. **Fase 2f — CTI Enrichment:** Añadir AbuseIPDB y VirusTotal al pipeline para enriquecimiento de IOCs antes del análisis IA.
7. **Fase 2g — MISP:** Integrar la instancia interna de MISP como tercera fuente CTI para correlación de IOCs internos.

---

## 🏗️ Arquitectura del Pipeline

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    PIPELINE DE TRIAGE OOB — FASE 2                         │
└─────────────────────────────────────────────────────────────────────────────┘

Wazuh Manager
  │  /var/ossec/integrations/custom-n8n
  │  HTTP POST (JSON alert + oob_timestamp)
  ▼
n8n Webhook  (POST /webhook/wazuh-alerts)
  │
  ▼
Edit Fields  (normaliza: rule_id, rule_level, rule_desc, agent_name, timestamp, src_ip)
  │
  ▼
IF Node  (rule.level >= 7)
  │ True
  ├─────────────────────┬──────────────────────┐
  ▼                     ▼                      ▼
AbuseIPDB Check    VirusTotal Check       MISP Search
(HTTP GET)         (HTTP GET)             (HTTP POST restSearch)
  │                     │                      │
  └──────────┬──────────┘                      │
             ▼                                 │
           Merge (Combine by Position)         │
             │                                 │
             └──────────────┬──────────────────┘
                            ▼
                   Code CTI Context
                   (normaliza campos CTI + alerta)
                            │
                            ▼
                       AI Agent
                   (Ollama → Mistral 7B)
                            │
                            ▼
                   Code Merge Final
                   (CTI + análisis IA → payload único)
                            │
                            ▼
                       Rocket.Chat
                   (orchestrator-bot → canal #general)
```

---

## 🛠️ Stack Tecnológico

| Componente | Versión | Imagen Docker | Propósito |
|---|---|---|---|
| **n8n** | 2.20.9 | `docker.n8n.io/n8nio/n8n:latest` | Orquestador de workflows |
| **Ollama** | latest | `ollama/ollama:latest` | Motor de LLM local |
| **Mistral 7B** | mistral:7b | — (cargado en Ollama) | LLM para triage IA |
| **Wazuh** | 4.14.0 | Single-Node | SIEM, detección y alertas |
| **AbuseIPDB** | API v2 | — (externo) | Reputación IP y reportes de abuso |
| **VirusTotal** | API v3 | — (externo) | Votos de análisis y contexto ASN |
| **MISP** | 2.4.x | `misp-docker` | IOCs internos y correlación de eventos |
| **Rocket.Chat** | 8.4.3 | `registry.rocket.chat/...` | Notificaciones SOC |
| **MongoDB** | 8.0 | `mongo:8.0` | Base de datos de Rocket.Chat |
| **Traefik** | v3.3 | `traefik:v3.3` | Reverse proxy y TLS |
| **Portainer** | CE | `portainer/portainer-ce:latest` | Gestión de contenedores |
| **Authelia** | latest | `authelia/authelia:latest` | SSO y MFA con Traefik |

---

## 🔗 Subfases

Cada subfase tiene su propio README detallado en la carpeta `/docs` de la rama principal:

| Subfase | Descripción | Fecha | Estado | README |
|---------|-------------|-------|--------|--------|
| **2a** | Despliegue de n8n como orquestador | 2026-05-17 | ✅ Completada | [📄 README-fase2a-n8n.md](../docs/README-fase2a-n8n.md) |
| **2b/2c/2d** | Integración Wazuh → n8n → Rocket.Chat | 2026-05-17 | ✅ Completada | [📄 README-fase2bcd-workflow-n8n.md](../docs/README-fase2bcd-workflow-n8n.md) |
| **2e** | Ollama + Mistral 7B + AI Agent | 2026-05-21 | ✅ Completada | [📄 README-fase2e-ollama-ai-agent.md](../docs/README-fase2e-ollama-ai-agent.md) |
| **2f** | CTI Enrichment (AbuseIPDB + VirusTotal) | 2026-05-24 | ✅ Completada | [📄 README-fase2f-cti-enrichment.md](../docs/README-fase2f-cti-enrichment.md) |
| **2g** | MISP Integration (IOCs internos) | 2026-06-07 | ⏳ En progreso | [📄 Pendiente de cierre documental](../docs/) |

> Los enlaces apuntan a la carpeta `/docs` de la rama `main` del repositorio TFM.

---

## 🔄 Flujo del Workflow n8n

### Nodos implementados

| Nodo | Tipo | Función |
|------|------|---------|
| `Webhook` | Webhook | Recibe alerta Wazuh en `POST /webhook/wazuh-alerts` |
| `Edit Fields` | Set | Normaliza campos del payload (`$json.body.*`) |
| `IF (level >= 7)` | IF | Filtra alertas por severidad ≥ 7 |
| `AbuseIPDB Check` | HTTP Request | `GET api.abuseipdb.com/api/v2/check` |
| `VirusTotal Check` | HTTP Request | `GET virustotal.com/api/v3/ip_addresses/{ip}` |
| `MISP Search` | HTTP Request | `POST misp/attributes/restSearch` |
| `Merge` | Merge | Combina ramas CTI por posición |
| `Code CTI Context` | Code | Normaliza campos CTI + alerta en un JSON único |
| `AI Agent` | AI Agent | Mistral 7B analiza alerta con contexto enriquecido |
| `Code Merge Final` | Code | Combina CTI + análisis IA en payload final |
| `Rocket.Chat` | Rocket.Chat | Publica mensaje en canal `general` |

### Script Wazuh — `custom-n8n`

El script se despliega en `/var/ossec/integrations/custom-n8n` con estos permisos:

```bash
chmod 750 /var/ossec/integrations/custom-n8n
chown root:wazuh /var/ossec/integrations/custom-n8n
```

Configuración en `ossec.conf`:

```xml
<integration>
  <name>custom-n8n</name>
  <hook_url>https://n8n.oob.local/webhook/wazuh-alerts</hook_url>
  <level>7</level>
  <alert_format>json</alert_format>
</integration>
```

---

## 🚀 Instalación y Configuración

### Prerrequisitos

```bash
docker --version        # >= 24.0.0
docker compose version  # >= 2.24.0
```

### Red Docker compartida

```bash
docker network create oob-network
```

### Despliegue de n8n

```yaml
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    environment:
      - N8N_HOST=n8n.oob.local
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://n8n.oob.local/
      - N8N_ENCRYPTION_KEY=cambia_esta_clave_segura_32chars
      - GENERIC_TIMEZONE=Europe/Madrid
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - oob-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(`n8n.oob.local`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls=true"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"
      - "traefik.docker.network=oob-network"
```

### Credenciales n8n necesarias

| Servicio | Tipo | Campo clave |
|---|---|---|
| Rocket.Chat | Rocket.Chat API | Server URL interno: `http://rocketchat:3000` |
| AbuseIPDB | Header Auth | Header: `Key`, valor: tu API key |
| VirusTotal | Header Auth | Header: `x-apikey`, valor: tu API key |
| MISP | Header Auth | Header: `Authorization`, valor: tu API key |
| Ollama | Ollama | Base URL: `http://ollama:11434` |

> **Nota:** Usar siempre URLs internas Docker para servicios en la misma red. Rocket.Chat debe usarse como `http://rocketchat:3000` y nunca como `https://chat.oob.local` desde dentro de n8n.

---

## ✅ Validación y Pruebas

### Curl de prueba completo

```bash
curl -k -X POST https://n8n.oob.local/webhook-test/wazuh-alerts \
  -H "Content-Type: application/json" \
  -d '{
    "rule": {"id": "5710", "level": 7, "description": "SSH brute force attack detected"},
    "agent": {"id": "001", "name": "web-server-01"},
    "data": {"srcip": "185.220.101.4"},
    "oob_timestamp": "2026-05-21T20:00:00Z"
  }'
```

### Mensaje esperado en Rocket.Chat

```
🚨 Alerta Analizada por IA — OOB

📋 Regla: 5710 — SSH brute force attack detected
⚠ Severidad Wazuh: 7
🖥 Agente: web-server-01
🌐 IP Fuente: 185.220.101.4
🕐 Timestamp: 2026-05-21T20:00:00Z

🔍 CTI — AbuseIPDB
├ Confidence Score: 100%
├ Total Reportes: 231
├ País: DE
├ ISP: Artikel10 e.V.
└ Nodo TOR: true

🦠 CTI — VirusTotal
├ Votos maliciosos: 39
├ Votos harmless: 144
├ ASN: 13335 (Cloudflare, Inc.)
├ Red: 1.1.1.0/24
└ País: AU

🧠 CTI — MISP
├ Coincidencias: 0
└ Contexto: IP no presente en MISP

🤖 Análisis IA (Mistral 7B):
├ Severidad Real: ALTA
├ Táctica MITRE: T1110 - Brute Force
├ Técnica: T1110.004 - SSH
├ Resumen: SSH brute force desde nodo TOR con score máximo en AbuseIPDB
├ Recomendación: Bloquear IP en firewall e investigar cuentas atacadas
└ Requiere Bloqueo: true
```

### Checklist de validación

- ✅ n8n accesible en `https://n8n.oob.local`
- ✅ Workflow `Wazuh Alert Handler` publicado y activo
- ✅ Script `custom-n8n` instalado en Wazuh Manager con permisos correctos
- ✅ Integración registrada en `ossec.conf` con `level >= 7`
- ✅ AbuseIPDB devuelve datos de reputación correctamente
- ✅ VirusTotal devuelve `total_votes` y contexto ASN
- ✅ MISP retorna coincidencias si la IP está en feeds activos
- ✅ AI Agent genera JSON de triage estructurado con MITRE ATT&CK
- ✅ Code Merge Final combina CTI + análisis IA en un único payload
- ✅ Mensaje completo recibido en Rocket.Chat

---

## ✅ Resultados Alcanzados

| Indicador | Resultado |
|-----------|-----------|
| Tiempo de procesamiento por alerta | < 30 segundos end-to-end |
| Fuentes CTI integradas | 3 (AbuseIPDB, VirusTotal, MISP) |
| Modelo IA | Mistral 7B local vía Ollama |
| Dependencias externas de IA | 0 (soberanía del dato) |
| Formato de salida IA | JSON estructurado (severidad, MITRE, resumen, recomendación, bloqueo) |
| Notificación | Rocket.Chat con formato visual completo |
| Filtrado por severidad | ≥ 7 (configurable en nodo IF) |

---

## 🐛 Incidencias Resueltas

| Incidencia | Causa | Solución |
|---|---|---|
| Webhook 404 en producción | Workflow no publicado | Pulsar **Publish** en n8n |
| `$json.rule.*` vacío | n8n envuelve payload en `body` | Usar `$json.body.rule.*` en Edit Fields |
| `error-not-allowed` en Rocket.Chat | Canal con `#general` | Usar `general` sin almohadilla |
| Conexión rechazada a `chat.oob.local` | Hostname no resuelto dentro de Docker | Usar URL interna `http://rocketchat:3000` |
| `curl` no disponible en n8n | Binario ausente en imagen n8n | Usar `wget` para pruebas internas |
| Campos CTI vacíos en Rocket.Chat | AI Agent sobreescribía el payload | Añadir `Code Merge Final` que recompone CTI + IA |
| `vt_malicious` siempre a 0 | Ruta errónea `last_analysis_stats` | Corregir a `total_votes.malicious` |
| Valores `0` no renderizados | n8n no renderiza falsy | Forzar `String()` en todos los valores del nodo Code |
| `src_ip = N/A` en pruebas | Falta campo `data.srcip` en curl | Añadir `"data": {"srcip": "1.1.1.1"}` al payload |
| MISP healthcheck `unhealthy` | `curl` ausente en imagen MISP + timeout de 1s | Reemplazar por check PHP con `cake Admin getSetting` |
| MISP `data` como string HTML-encoded | MISP devuelve JSON serializado con `&quot;` | Decodificar entidades HTML antes de `JSON.parse()` |

---

## 📊 Estado del Proyecto

| Fase | Descripción | Estado |
|------|-------------|--------|
| 1a | Traefik v3.3 + Portainer | ✅ Completada |
| 1b | Authelia v4.39.19 MFA/IdP | ✅ Completada |
| 1c | MongoDB 8.0 + Rocket.Chat 8.4.3 | ✅ Completada |
| 1d | Wazuh 4.14.0 Single-Node | ✅ Completada |
| 1e | Validación final Fase 1 | ✅ Completada |
| **2a** | **n8n Orquestador desplegado** | ✅ **Completada** |
| **2b** | **Script `custom-n8n` en Wazuh Manager** | ✅ **Completada** |
| **2c** | **Workflow n8n: recepción y filtrado** | ✅ **Completada** |
| **2d** | **Notificación Rocket.Chat** | ✅ **Completada** |
| **2e** | **Ollama + Mistral 7B + AI Agent** | ✅ **Completada** |
| **2f** | **CTI Enrichment: AbuseIPDB + VirusTotal** | ✅ **Completada** |
| **2g** | **MISP Integration** | ⏳ En progreso |
| 3 | War Rooms + Respuesta automática | 🔜 Pendiente |

---

## 🔜 Próximos Pasos

1. **Fase 2g — MISP completo:** cerrar la integración documental y funcional de MISP como tercera fuente CTI, dejando claramente validadas la búsqueda de IOCs internos y la persistencia de sus campos en Rocket.Chat.
2. **Fase 3 — Respuesta activa:** bloqueo automático de IPs en firewall, playbooks de contención y war rooms en Rocket.Chat.
3. **Mejoras de pipeline:** añadir caché de consultas CTI para IPs repetidas, alertas por severidad `CRITICA` a canal dedicado, y métricas de tiempo de respuesta.

---

## 📚 Referencias

- [Wazuh Documentation](https://documentation.wazuh.com/)
- [n8n Documentation](https://docs.n8n.io/)
- [Ollama — n8n Model Node](https://docs.n8n.io/integrations/builtin/cluster-nodes/sub-nodes/n8n-nodes-langchain.lmollama/)
- [AbuseIPDB API v2](https://docs.abuseipdb.com/)
- [VirusTotal API v3](https://docs.virustotal.com/reference/overview)
- [MISP restSearch API](https://www.misp-project.org/openapi/)
- [Rocket.Chat Docs](https://docs.rocket.chat/)
- [MITRE ATT&CK Framework](https://attack.mitre.org/)

---

**Última actualización:** 2026-06-07  
**Versión del documento:** 2.2.0  
**Estado:** ✅ Fase 2a–2f completadas | ⏳ Fase 2g en progreso
