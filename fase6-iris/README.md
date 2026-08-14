# 📊 Fase 6 · DFIR-IRIS - Case Management

> [!NOTE]
> **🎯 Objetivo de la fase**  
> Implementar gestión completa de caso con trazabilidad total mediante DFIR-IRIS, sincronización bidireccional con Orquestador y timeline automático del incidente.

> [!TIP]
> IRIS centraliza toda la información del incidente: alerta original, decisiones del agente, sesiones de acceso remoto, artefactos forenses y timeline.

## 📋 Estado

- [x] 🐳 DFIR-IRIS en Docker
- [x] 📝 Creación automática de caso al abrir incidente
- [x] 🔗 Sincronización bidireccional webhooks IRIS ↔ Orquestador
- [x] 📦 Añadir evidencias (alerta, decisiones, sesiones, artefactos)
- [x] 📅 Timeline automático del incidente en IRIS
- [x] ✅ Cierre de caso con revocación automática de accesos
- [ ] 📈 Dashboard de métricas operacionales (Fase 7)

## 🏗️ Arquitectura

```text
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Orquestador │◀───▶│  DFIR-IRIS   │◀───▶│  Webhooks    │
│   Incidentes │     │    Casos     │     │  Sincron.    │
└──────────────┘     └──────────────┘     └──────────────┘
                            │
                     ┌──────┴──────┐
                     │             │
              ┌──────▼──────┐ ┌───▼────┐
              │  Evidencias │ │ Timeline│
              │  Artefactos │ │ Evento  │
              └─────────────┘ └────────┘
```

## 🔧 Funcionalidades Clave

### Creación de Caso
- Automática al abrir incidente en Orquestador
- Enlazado a War Room de Rocket.Chat
- Campo `agent_reasoning` con decisión del Triage Agent

### Evidencias
- Alerta original de Wazuh
- Decisiones del agente (triage, forensics)
- Sesiones de acceso remoto (RustDesk, KVM)
- Artefactos forenses (ZIPs de Velociraptor)

### Timeline
- Eventos cronológicos del incidente
- Cada acción registrada con timestamp
- Visualización gráfica en IRIS

### Cierre de Caso
- Revocación automática de accesos (RustDesk, scripts DC)
- Resumen ejecutivo generado
- Exportación de evidencias

## ⚙️ Configuración Aplicada

### docker-compose.yml

```yaml
services:
  iris-webapp:
    image: iris/webapp:latest
    ports:
      - "4833:4833"
    environment:
      - IRIS_API_URL=http://iris-api:8080
      - IRIS_DB_HOST=iris-db
      - IRIS_RABBITMQ_HOST=iris-rabbitmq
    networks:
      - oob-network

  iris-api:
    image: iris/api:latest
    environment:
      - IRIS_DB_HOST=iris-db
      - IRIS_RABBITMQ_HOST=iris-rabbitmq
    networks:
      - oob-network

  iris-db:
    image: postgres:15
    environment:
      - POSTGRES_DB=iris
      - POSTGRES_USER=iris
      - POSTGRES_PASSWORD=iris_pass
    volumes:
      - iris-db-data:/var/lib/postgresql/data
    networks:
      - oob-network

  iris-rabbitmq:
    image: rabbitmq:3-management
    networks:
      - oob-network

networks:
  oob-network:
    external: true

volumes:
  iris-db-data:
```

### Webhooks

```json
{
  "webhook_url": "http://orchestrator:8000/iris/webhook",
  "events": ["case.created", "case.updated", "evidence.added", "timeline.event"]
}
```

## ✅ Validación Funcional

### Crear caso manualmente

Acceder a IRIS Web (`https://<HOST>:4833`) y crear caso de prueba.

### Verificar sincronización

1. Crear incidente en Orquestador
2. Verificar que se crea caso en IRIS automáticamente
3. Modificar caso en IRIS
4. Verificar que Orquestador recibe webhook

### Consultar timeline

```bash
curl http://localhost:8000/iris/case/<CASE_ID>/timeline
```

## ⚠️ Consideraciones de Seguridad

- 🔐 **Credenciales en variables de entorno:** DB, RabbitMQ, API
- 🔒 **Webhooks autenticados:** validación de origen
- 📝 **Auditoría completa:** cada evento registrado en timeline
- 🗂️ **Evidencias inmutables:** solo añadido, nunca modificación

## 🚀 Próximos Pasos

1. 📈 Desplegar OpenSearch Dashboards para métricas (Fase 7)
2. 🎯 Implementar Plan C con KVM (Fase 8)
