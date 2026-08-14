# 🧭 Fase 2 · Orquestador MVP y War Room

> [!NOTE]
> **🎯 Objetivo de la fase**  
> Desarrollar el Orquestador FastAPI con PostgreSQL y Redis, implementando ingesta de alertas Wazuh, correlación y deduplicación básica, creación automática de War Room en Rocket.Chat y registro de aprobaciones.

> [!TIP]
> El Orquestador es el corazón del sistema: correlaciona alertas, gestiona el estado de incidentes y coordina todos los servicios del enclave.

## 📋 Estado

- [x] 🐳 Orquestador FastAPI + PostgreSQL + Redis en Docker
- [x] 📥 POST `/wazuh/alert` para ingesta, correlación y deduplicación básica
- [x] 💬 Creación automática de War Room en Rocket.Chat por incidente
- [x] 📢 Publicación de Incident Card estructurada
- [x] ✅ Comandos `approve` y `reject` en Rocket.Chat
- [x] 📝 Registro de aprobaciones en BD
- [ ] 🔗 Integración con DFIR-IRIS (Fase 6)

## 🏗️ Arquitectura

```text
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Wazuh      │────▶│  Orquestador │────▶│ Rocket.Chat  │
│   Alertas    │     │  FastAPI     │     │   War Room   │
└──────────────┘     └──────────────┘     └──────────────┘
                            │
                     ┌──────┴──────┐
                     │             │
              ┌──────▼──────┐ ┌───▼────┐
              │  PostgreSQL │ │ Redis  │
              │   Estado    │ │  TTL   │
              └─────────────┘ └────────┘
```

## 🔧 Endpoints API

### POST `/wazuh/alert`

Ingesta de alertas JSON normalizadas desde Wazuh.

**Payload:**
```json
{
  "id": "87102",
  "level": 7,
  "agent_name": "HOST-DC01",
  "rule_description": "LSASS access",
  "timestamp": "2026-05-02T20:30:00Z"
}
```

**Respuesta:**
```json
{
  "status": "created",
  "incident_id": "INC-2026-042",
  "war_room_id": "war-room-042"
}
```

### POST `/rocketchat/command`

Aprobaciones `approve` / `reject` desde War Room.

## ⚙️ Configuración Aplicada

### docker-compose.yml

```yaml
services:
  orchestrator:
    build: .
    container_name: orchestrator
    restart: unless-stopped
    ports:
      - "8020:8000"
    environment:
      - DATABASE_URL=postgresql://user:pass@postgres:5432/orchestrator
      - REDIS_URL=redis://redis:6379
      - ROCKETCHAT_WEBHOOK_URL=http://rocketchat:3000/hooks/war-room
    networks:
      - oob-network

  postgres:
    image: postgres:15
    environment:
      - POSTGRES_DB=orchestrator
      - POSTGRES_USER=user
      - POSTGRES_PASSWORD=pass
    volumes:
      - postgres-data:/var/lib/postgresql/data
    networks:
      - oob-network

  redis:
    image: redis:7
    networks:
      - oob-network

networks:
  oob-network:
    external: true

volumes:
  postgres-data:
```

### Variables de Entorno

```bash
# Orquestador
DATABASE_URL=postgresql://user:pass@postgres:5432/orchestrator
REDIS_URL=redis://redis:6379
ROCKETCHAT_WEBHOOK_URL=http://rocketchat:3000/hooks/war-room
```

## ✅ Validación Funcional

### Probar ingesta de alerta

```bash
curl -X POST http://localhost:8020/wazuh/alert \
  -H "Content-Type: application/json" \
  -d '{
    "id": "87102",
    "level": 7,
    "agent_name": "HOST-DC01",
    "rule_description": "LSASS access",
    "timestamp": "2026-05-02T20:30:00Z"
  }'
```

### Verificar War Room

Acceder a Rocket.Chat y buscar el canal creado automáticamente.

### Consultar aprobaciones

```bash
curl http://localhost:8020/approvals?incident_id=INC-2026-042
```

## 🗂️ Modelo de Datos MVP

### Tabla `incidents`

```sql
CREATE TABLE incidents (
  incident_id VARCHAR PRIMARY KEY,
  status VARCHAR,
  severity VARCHAR,
  correlation_key VARCHAR,
  primary_host VARCHAR,
  rocketchat_room_id VARCHAR,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

### Tabla `approvals`

```sql
CREATE TABLE approvals (
  incident_id VARCHAR,
  action_type VARCHAR,
  target_host VARCHAR,
  requested_at TIMESTAMP,
  approved_by VARCHAR,
  decision VARCHAR,
  approved_at TIMESTAMP
);
```

## ⚠️ Consideraciones de Seguridad

- 🔐 **Tokens en variables de entorno:** nunca hardcodeados en el código
- 🔒 **Red privada:** comunicación Orquestador ↔ Rocket.Chat aislada
- 🛡️ **Deduplicación:** evita war rooms duplicados por alertas correlacionadas
- 📝 **Auditoría:** todas las aprobaciones quedan registradas en BD

## 🚀 Próximos Pasos

1. 🤖 Integrar IA Agéntica para triage automático (Fase 3)
2. 🔗 Configurar Cloudflare Tunnels para agentes en DCs (Fase 4)
3. 🦎 Implementar Velociraptor para colección forense (Fase 5)
4. 📊 Integrar DFIR-IRIS para gestión de caso (Fase 6)
5. 📈 Desplegar OpenSearch Dashboards (Fase 7)
