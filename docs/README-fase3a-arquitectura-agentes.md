# Fase 3a — Diseño de arquitectura de agentes (LangGraph + LLM local)

## Contexto

En las fases 2e, 2f y 2g se construyó un pipeline de triage automático que integra Wazuh, n8n, un modelo local en Ollama y enriquecimiento CTI con AbuseIPDB, VirusTotal y MISP. El flujo actual realiza una única llamada a un agente de IA dentro de n8n, que recibe el contexto CTI normalizado y devuelve un análisis estructurado para Rocket.Chat.

En esta fase se define la arquitectura de un sistema de agentes especializado basado en LangGraph, manteniendo n8n como orquestador principal y Ollama como LLM local.

## Objetivo de la fase

- Diseñar el contrato JSON entre n8n y un servicio de agentes basado en LangGraph.
- Definir el estado del grafo que modela un incidente de seguridad y su triage.
- Especificar los agentes especializados, sus responsabilidades y el flujo de control.
- Dejar preparada la base conceptual para las fases 3b y 3c.

## Contrato n8n ↔ servicio de agentes

El orquestador n8n seguirá siendo el punto de entrada del pipeline del TFM. Recibirá alertas desde Wazuh, ejecutará consultas CTI a AbuseIPDB, VirusTotal y MISP, y normalizará el contexto en un nodo `Code CTI Context`, igual que en la fase anterior.

A partir de esta fase, en lugar de llamar al AI Agent interno de n8n, se llamará a un servicio HTTP desplegado en Docker dentro de la red `oob-network`, implementado en Python con LangGraph. El contrato propuesto se divide en dos bloques principales: `wazuh` y `cti`.

### Ejemplo de entrada JSON

```json
{
  "wazuh": {
    "rule_id": "5710",
    "rule_desc": "SSH brute force attack detected",
    "rule_level": 7,
    "agent_name": "web-server-01",
    "timestamp": "2026-05-21T20:00:00Z",
    "src_ip": "185.220.101.4"
  },
  "cti": {
    "abuse_confidence": 85,
    "abuse_total_reports": 239,
    "abuse_country": "DE",
    "abuse_isp": "Example ISP",
    "abuse_is_tor": true,
    "vt_malicious": 39,
    "vt_harmless": 144,
    "vt_asn": "13335",
    "vt_as_owner": "Cloudflare, Inc.",
    "vt_network": "1.1.1.0/24",
    "vt_country": "AU",
    "misp_total": 3,
    "misp_threat_level": "high",
    "misp_tags": ["APT28", "Bruteforce", "SSH"],
    "misp_attributes_summary": "3 eventos en MISP con esta IP, asociados a campañas brute-force SSH."
  }
}
```

Este diseño reutiliza la normalización CTI ya validada en Fase 2, pero separa claramente el plano de datos (`wazuh`, `cti`) del plano de decisión inteligente.

### Ejemplo de salida JSON

```json
{
  "decision": {
    "severity_real": "CRITICA",
    "mitre_tactic": "TA0006 - Credential Access",
    "mitre_technique": "T1110 - Brute Force",
    "summary": "Ataque de fuerza bruta SSH con alta probabilidad de éxito y fuerte respaldo CTI.",
    "recommendation": "Bloquear la IP a nivel de firewall, revisar accesos fallidos y forzar rotación de credenciales.",
    "requires_block": true,
    "create_war_room": true
  },
  "explanation": {
    "reasoning_steps": [
      "Regla Wazuh 5710 indica brute force SSH con severidad 7.",
      "AbuseIPDB muestra alta confianza y múltiples reportes recientes.",
      "MISP asocia la IP a campañas conocidas de brute force.",
      "Se eleva severidad a CRITICA y se recomienda bloqueo inmediato."
    ]
  }
}
```

La salida está pensada para que n8n pueda seguir usando una lógica similar a la actual: publicar en Rocket.Chat, activar nodos condicionales y disparar playbooks cuando `requires_block` sea verdadero.

## Estado del grafo

LangGraph está orientado a flujos con estado, donde cada nodo lee y modifica un `StateGraph` compartido. Para este proyecto se propone un estado tipado `IncidentState` con cuatro áreas principales:

- `wazuh`: campos de la alerta original.
- `cti`: resumen CTI ya normalizado.
- `decision`: resultados producidos por los agentes.
- `messages`: historial de mensajes internos del sistema multiagente.

### Esquema lógico del estado

```python
class IncidentState(TypedDict):
    wazuh: dict
    cti: dict
    decision: dict
    messages: list
```

Este patrón encaja con la filosofía de LangGraph: estado explícito, nodos especializados y transiciones controladas por edges.

## Agentes definidos

La arquitectura adoptará un patrón de supervisor con agentes especializados, recomendado para sistemas multiagente con flujo controlado y trazabilidad.

### `triage_agent`

- Entrada: `wazuh` y `cti`.
- Salida: `severity_real`, `mitre_tactic`, `mitre_technique`, `summary`.
- Rol: evaluar la criticidad real del incidente combinando señal Wazuh y contexto CTI.

### `remediation_agent`

- Entrada: `wazuh`, `cti` y resultados parciales del triage.
- Salida: `recommendation`, `requires_block`, `create_war_room`.
- Rol: traducir el análisis técnico en acciones concretas de respuesta y coordinación.

### `supervisor_agent`

- Entrada: estado completo del incidente.
- Salida: decide qué nodo ejecutar a continuación y cuándo finalizar el flujo.
- Rol: implementar la lógica de control del grafo y permitir futuras ampliaciones del sistema.

## Flujo de control del grafo

El flujo lógico propuesto es el siguiente:

1. `START` → `load_incident`.
2. `supervisor_agent` envía el control a `triage_agent`.
3. `triage_agent` calcula la severidad real y el mapeo MITRE.
4. El control vuelve al `supervisor_agent`.
5. `supervisor_agent` invoca `remediation_agent`.
6. `remediation_agent` decide acciones, bloqueo y creación de War Room.
7. `finalizer` construye el JSON final.
8. `END` devuelve la respuesta HTTP a n8n.

Este diseño mantiene n8n como plano de orquestación visible y LangGraph como plano de razonamiento agéntico, lo que mejora la trazabilidad y el valor académico del TFM.

## Resultado de la fase

Al finalizar la Fase 3a se dispone de un diseño formal del contrato n8n ↔ servicio de agentes, la definición del estado del grafo, la lista de agentes y el flujo de control general. Esto deja preparada la implementación de la Fase 3b y la definición técnica de herramientas de la Fase 3c.