# 🤖 Fase 3 · IA Agéntica - Triage y Enrichment

> [!NOTE]
> **🎯 Objetivo de la fase**  
> Incorporar inteligencia agéntica al flujo de triage mediante LangGraph con Ollama (modelo local), enriquecimiento CTI automático y campo `agentreasoning` en IRIS para auditoría.

> [!TIP]
> El Triage Agent analiza alertas, consulta CTI, busca incidentes históricos y genera recomendaciones de acción de forma autónoma.

## 📋 Estado

- [x] 🐳 Ollama con Mistral-7B o Qwen2.5-7B en Docker
- [x] 🧠 ChromaDB para memoria vectorial del agente
- [x] 🤖 Triage Agent con LangGraph implementado
- [x] 🔍 Enrichment CTI automático (AbuseIPDB, VirusTotal)
- [x] 📊 Integración MISP self-hosted
- [x] 🔎 Búsqueda en histórico IRIS
- [x] 📝 Campo `agentreasoning` en IRIS
- [ ] 📈 Evaluación de precisión del agente vs. triaje manual

## 🏗️ Arquitectura

```text
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Orquestador │────▶│ LangGraph    │────▶│  Ollama      │
│   Alerta     │     │  Agentes     │     │  Mistral-7B  │
└──────────────┘     └──────────────┘     └──────────────┘
                            │
                     ┌──────┴──────┐
                     │             │
              ┌──────▼──────┐ ┌───▼────┐
              │   ChromaDB  │ │  MISP  │
              │  Memoria    │ │  CTI   │
              └─────────────┘ └────────┘
```

## 🔧 Agentes Especializados

### 🤖 Triage Agent
- Consulta CTI (MISP, AbuseIPDB, VirusTotal API)
- Busca incidentes históricos similares en IRIS
- Genera resumen enriquecido con contexto
- Reevalúa severidad
- Decide perfil de colección Velociraptor

### 📝 Communication Agent
- Redacta Incident Card enriquecida para War Room
- Genera resumen ejecutivo para IRIS
- Propone acciones de contención con justificación

## ⚙️ Configuración Aplicada

### docker-compose.yml

```yaml
services:
  langgraph-agent:
    build: .
    container_name: langgraph-agent
    restart: unless-stopped
    ports:
      - "8000:8000"
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - OLLAMA_MODEL=mistral:7b
      - CHROMADB_URL=http://chromadb:8000
      - MISP_URL=https://misp.tudominio.com
      - MISP_KEY=<API_KEY>
    networks:
      - oob-network

  ollama:
    image: ollama/ollama
    volumes:
      - ollama-data:/root/.ollama
    networks:
      - oob-network

  chromadb:
    image: chromadb/chroma
    networks:
      - oob-network

networks:
  oob-network:
    external: true

volumes:
  ollama-data:
```

### Endpoints API

#### POST `/triage`

Dispara triage agéntico sobre incidente.

**Payload:**
```json
{
  "wazuh": {
    "incident_id": "INC-2026-042",
    "host": "HOST-DC01",
    "rule_id": "87102",
    "description": "LSASS access"
  },
  "cti": {
    "ip": "192.168.1.50",
    "hash": "abc123..."
  }
}
```

**Respuesta:**
```json
{
  "decision": {
    "severity_real": "CRITICAL",
    "mitre_tactic": "TA0005 - Defense Evasion",
    "mitre_technique": "T1078 - Valid Accounts",
    "recommendation": "credential_dump_collection",
    "agent_reasoning": "Hash detected as known credential dumper. Similar incident INC-2025-003 resolved with memory dump."
  }
}
```

## ✅ Validación Funcional

### Probar triage

```bash
curl -X POST http://localhost:8000/triage \
  -H "Content-Type: application/json" \
  -d '{
    "wazuh": {"incident_id":"TEST-001","host":"HOST-01","rule_id":"87102"},
    "cti": {"ip":"192.168.1.50"}
  }'
```

### Verificar agentreasoning en IRIS

Consultar campo `agent_reasoning` en el caso creado.

## ⚠️ Consideraciones de Seguridad

- 🧠 **LLM local:** datos de incidentes nunca salen del enclave
- 🔐 **API keys en variables de entorno:** MISP, VirusTotal, AbuseIPDB
- 📝 **Auditoría completa:** cada decisión del agente queda documentada
- 🔒 **Red privada:** comunicación agente ↔ servicios aislada

## 🚀 Próximos Pasos

1. 🔗 Configurar Cloudflare Tunnels para agentes en DCs (Fase 4)
2. 🦎 Implementar Velociraptor para colección forense (Fase 5)
3. 📊 Integrar DFIR-IRIS para gestión de caso (Fase 6)
4. 📈 Desplegar OpenSearch Dashboards (Fase 7)
