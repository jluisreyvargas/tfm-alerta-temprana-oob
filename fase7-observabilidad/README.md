# 📊 Fase 7 · Observabilidad y métricas en OpenSearch Dashboards

> [!NOTE]
> **🎯 Objetivo de la fase**  
> Desplegar un pipeline mínimo de métricas operativas para el sistema de respuesta out-of-band, indexando eventos relevantes en OpenSearch y visualizándolos en un dashboard inicial dentro de OpenSearch Dashboards.

> [!TIP]
> Esta fase queda alineada con las anteriores: mantiene despliegue en Docker, separación por servicios (`langgraph-agent`, `orchestrator`, `Wazuh/OpenSearch`) y validación incremental mediante pruebas controladas.

## 📋 Estado

- [x] 🧩 Cliente de métricas compartido (`metrics_client.py`)
- [x] 🤖 Instrumentación en `langgraph-agent` (endpoint `/triage`)
- [x] 🧭 Instrumentación en `orchestrator` (endpoint `/velociraptor/collect`)
- [x] 🧪 Carga de datos sintéticos (200 eventos)
- [x] 📈 Dashboard inicial en OpenSearch Dashboards
- [ ] 📊 Métricas avanzadas (MTTA, MTTApprove, Agent Precision)

## 🏗️ Arquitectura de observabilidad

```text
🤖 langgraph-agent ──log_event()──► 🔎 OpenSearch Indexer ──► 📊 OpenSearch Dashboards
       │
       └── event_type=triage_decision

🧭 orchestrator ─────log_event()──► 🔎 OpenSearch Indexer ──► 📊 OpenSearch Dashboards
       │
       └── event_type=collection_completed
```

> [!IMPORTANT]
> En este despliegue, OpenSearch Dashboards reutiliza el dashboard de Wazuh ya presente en el stack Docker y publicado en el host por el puerto `4443 -> 5601`.

## 🔧 Cambios aplicados

### 1. 🧩 Cliente de métricas compartido

Se creó un fichero compartido `metrics_client.py` montado por bind en ambos servicios. Su implementación se rehizo con `urllib` en lugar de `requests` para evitar dependencias no presentes en las imágenes base.

**Características principales:**
- ✅ Sin dependencias externas.
- 🔐 Autenticación básica contra OpenSearch.
- 🔒 SSL sin validación estricta para el laboratorio.
- ⚠️ Fallo no bloqueante: si la indexación falla, no rompe el flujo principal.

### 2. 🤖 Instrumentación en servicios

#### `langgraph-agent`

Se añadió el import del cliente compartido y una llamada a `log_event()` al final del endpoint `POST /triage`, registrando:
- `event_type=triage_decision`
- `incident_id`
- `host`
- `profile`
- `decision`
- `source=langgraph-agent`

#### `orchestrator`

Se añadió el import del cliente compartido y una llamada a `log_event()` al final del endpoint `POST /velociraptor/collect`, registrando:
- `event_type=collection_completed`
- `incident_id`
- `host`
- `profile`
- `collection_id`
- `minio_path`
- `duration_ms`
- `source=orchestrator`

### 3. 🌐 Redes, variables y volumen compartido

Ambos `docker-compose.yml` se actualizaron para:
- ➕ añadir la red externa `single-node_default`,
- 📦 exponer variables `OS_URL`, `OS_USER`, `OS_PASS`, `OS_INDEX`,
- 📁 montar el volumen `../fase7-observabilidad/shared:/app/shared`.

## ⚙️ Configuración aplicada

### 🤖 `langgraph-agent`

> Extracto ilustrativo. El fichero autoritativo es
> `fase3-agentic/docker-compose.yml`. `OS_USER` y `OS_PASS` se cargan desde
> `.env` (`env_file`), nunca en el compose: `OS_PASS` debe coincidir con
> `INDEXER_PASSWORD` de `fase1-infraestructura/wazuh/single-node/.env`, que se
> rotó (ver `fase5-velociraptor/SECURITY-NOTICE.md`, P0-3).

```yaml
services:
  langgraph-agent:
    build: .
    container_name: langgraph-agent
    restart: unless-stopped
    ports:
      - "8000:8000"
    env_file:
      - .env                       # OS_USER, OS_PASS
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - OLLAMA_MODEL=mistral:7b
      - TZ=Europe/Madrid
      - OS_URL=https://single-node-wazuh.indexer-1:9200
      - OS_INDEX=tfm-metrics-events
    volumes:
      - ../fase7-observabilidad/shared:/app/shared
    networks:
      - oob-network
      - single-node_default

networks:
  oob-network:
    external: true
  single-node_default:
    external: true
```

### 🧭 `orchestrator`

> Extracto ilustrativo. El fichero autoritativo es
> `fase5-orchestrator-api/docker-compose.yml`. Las credenciales de MinIO
> (`MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY`, del usuario `tfm-orchestrator`) y
> `OS_PASS` se cargan desde `.env` (`env_file`), nunca en el compose (P0-3, ver
> `fase5-velociraptor/SECURITY-NOTICE.md`).

```yaml
services:
  orchestrator:
    build: .
    container_name: orchestrator
    restart: unless-stopped
    ports:
      - "8020:8000"
    networks:
      - oob-network
      - single-node_default
    env_file:
      - .env                       # MINIO_ACCESS_KEY, MINIO_SECRET_KEY, OS_PASS
    environment:
      MINIO_ENDPOINT: minio:9000
      MINIO_BUCKET: evidence
      MINIO_SECURE: "false"
      OS_URL: https://single-node-wazuh.indexer-1:9200
      OS_USER: admin
      OS_INDEX: tfm-metrics-events
    volumes:
      - ../fase7-observabilidad/shared:/app/shared:ro

networks:
  oob-network:
    external: true
  single-node_default:
    external: true
```

## 🧪 Dataset sintético de pruebas

Para enriquecer las visualizaciones se generó un conjunto sintético de 200 eventos con secuencias temporales y combinaciones de:
- `triage_decision`
- `collection_completed`
- múltiples hosts,
- varias severidades,
- varios perfiles de colección.

> [!TIP]
> El índice terminó alcanzando 404 documentos en la validación final, combinando las pruebas manuales iniciales y la carga sintética posterior.

### 📥 Script de carga

Se utilizó un script Python para importar el CSV sintético a OpenSearch vía HTTPS autenticado.

```bash
python3 import_fase7_metrics.py --csv fase7_metrica_datos_test_200.csv --url https://localhost:9200
```

## ✅ Validación funcional

### 🧪 Pruebas unitarias de emisión

#### 🤖 Triage

```bash
docker exec -it langgraph-agent python3 -c "
from app.main import triage
from app.models import TriageRequest
print(triage(TriageRequest(wazuh={'incident_id':'TEST-TRIAGE-01','host':'HOST-01'}, cti={})))
"
```

#### 🧭 Collection

```bash
docker exec -it orchestrator python3 -c "
from main import collect, CollectRequest
import asyncio
print(asyncio.run(collect(CollectRequest(incidentid='TEST-COLLECT-01', host='HOST-02', profile='generic_high_signal_collection'))))
"
```

### 🔎 Verificación en OpenSearch

`$OS_PASS` es la contraseña del indexador (`INDEXER_PASSWORD` en
`fase1-infraestructura/wazuh/single-node/.env`, rotada — ver
`fase5-velociraptor/SECURITY-NOTICE.md`, P0-3). Cárgala del `.env` de la fase,
no la escribas en el comando:

```bash
curl -sk -u "admin:${OS_PASS:?exporta OS_PASS antes de ejecutar}" \
  "https://localhost:9200/tfm-metrics-events/_count?pretty"
```

Resultado validado en laboratorio:

```json
{
  "count": 404
}
```

## 📊 Dashboard inicial

### 📁 Data View

Se creó el Data View:

```text
tfm-metrics-events*
```

con campo temporal:

```text
@timestamp
```

### 📈 Visualizaciones creadas

| Panel | Tipo | Filtro principal | 🎯 Propósito |
|---|---|---|---|
| 📊 Eventos por tipo | Barras | Sin filtro | Distribución `triage_decision` vs `collection_completed` |
| 🤖 Triage por severidad | Barras | `source = langgraph-agent` | Distribución de decisiones del agente |
| 🧭 Colecciones por host | Barras | `event_type = collection_completed` | Frecuencia de colecciones por activo |
| 📈 Serie temporal de eventos | Línea/Área | Sin filtro | Evolución temporal del flujo |
| 📋 Tabla resumen | Tabla agregada | Agrupada por `incident_id` | Resumen sintético por incidente |
| 🔍 Tabla operativa | Discover guardado | Sin filtro | Inspección de documentos individuales |

### 🔗 Acceso al dashboard

En este entorno, OpenSearch Dashboards está disponible en:

```text
https://<HOST>:4443
```

porque el contenedor `single-node-wazuh.dashboard-1` publica `5601/tcp` en el puerto host `4443`.

## ⚠️ Limitaciones observadas

- 🔍 El campo `incident_id.keyword` no estuvo disponible en todas las consultas, lo que sugiere mapping dinámico mejorable.
- 📋 La tabla agregada del dashboard muestra resúmenes útiles, pero no sustituye una vista documental completa en Discover.
- 📊 Métricas avanzadas como MTTA, MTTApprove, MTTAccess o precisión del agente requerirán instrumentar más eventos en fases posteriores.

## 🚀 Próximos pasos

1. 🔧 Definir un mapping o template explícito para `tfm-metrics-events`.
2. 📝 Instrumentar más hitos del flujo (`war_room_created`, `approval_requested`, `approval_granted`, `remote_access_started`, etc.).
3. 📈 Refinar el dashboard con KPIs derivados.
4. 📸 Exportar capturas o artefactos del dashboard para anexos del TFM.
5. 📚 Evolucionar la documentación a una versión visual enriquecida si se quiere uniformidad completa con el resto de fases.
