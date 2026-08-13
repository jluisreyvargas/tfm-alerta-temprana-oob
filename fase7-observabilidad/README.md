# Fase 7 · Observabilidad y métricas en OpenSearch Dashboards

> [!NOTE]
> **Objetivo de la fase**  
> Desplegar un pipeline mínimo de métricas operativas para el sistema de respuesta out-of-band, indexando eventos relevantes en OpenSearch y visualizndolos en un dashboard inicial dentro de OpenSearch Dashboards.

> [!TIP]
> Esta fase queda alineada con las anteriores: mantiene despliegue en Docker, separacin por servicios (`langgraph-agent`, `orchestrator`, `Wazuh/OpenSearch`) y validacin incremental mediante pruebas controladas.

## Estado

- [x] Cliente de métricas compartido (`metrics_client.py`)
- [x] Instrumentacin en `langgraph-agent` (endpoint `/triage`)
- [x] Instrumentacin en `orchestrator` (endpoint `/velociraptor/collect`)
- [x] Carga de datos sintticos (200 eventos)
- [x] Dashboard inicial en OpenSearch Dashboards
- [ ] Métricas avanzadas (MTTA, MTTApprove, Agent Precision)

## Arquitectura de observabilidad

```text
langgraph-agent ──log_event()──► OpenSearch Indexer ──► OpenSearch Dashboards
       │
       └── event_type=triage_decision

orchestrator ─────log_event()──► OpenSearch Indexer ──► OpenSearch Dashboards
       │
       └── event_type=collection_completed
```

> [!IMPORTANT]
> En este despliegue, OpenSearch Dashboards reutiliza el dashboard de Wazuh ya presente en el stack Docker y publicado en el host por el puerto `4443 -> 5601`.

## Cambios aplicados

### 1. Cliente de mtricas compartido

Se creóııı un fichero compartido `metrics_client.py` montado por bind en ambos servicios. Su implementacin se rehizo con `urllib` en lugar de `requests` para evitar dependencias no presentes en las imgenes base.

**Caractersticas principales:**
- Sin dependencias externas.
- Autenticacin bsica contra OpenSearch.
- SSL sin validacin estricta para el laboratorio.
- Fallo no bloqueante: si la indexacin falla, no rompe el flujo principal.

### 2. Instrumentacin en servicios

#### `langgraph-agent`

Se aadióııı el import del cliente compartido y una llamada a `log_event()` al final del endpoint `POST /triage`, registrando:
- `event_type=triage_decision`
- `incident_id`
- `host`
- `profile`
- `decision`
- `source=langgraph-agent`

#### `orchestrator`

Se aadióııı el import del cliente compartido y una llamada a `log_event()` al final del endpoint `POST /velociraptor/collect`, registrando:
- `event_type=collection_completed`
- `incident_id`
- `host`
- `profile`
- `collection_id`
- `minio_path`
- `duration_ms`
- `source=orchestrator`

### 3. Redes, variables y volumen compartido

Ambos `docker-compose.yml` se actualizaron para:
- aadir la red externa `single-node_default`,
- exponer variables `OS_URL`, `OS_USER`, `OS_PASS`, `OS_INDEX`,
- montar el volumen `../fase7-observabilidad/shared:/app/shared`.

## Configuracin aplicada

### `langgraph-agent`

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
      - TZ=Europe/Madrid
      - OS_URL=https://single-node-wazuh.indexer-1:9200
      - OS_USER=admin
      - OS_PASS=SecretPassword
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

### `orchestrator`

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
    environment:
      MINIO_ENDPOINT: minio:9000
      MINIO_ACCESS_KEY: minioadmin
      MINIO_SECRET_KEY: minioadmin123
      MINIO_BUCKET: evidence
      MINIO_SECURE: "false"
      OS_URL: https://single-node-wazuh.indexer-1:9200
      OS_USER: admin
      OS_PASS: SecretPassword
      OS_INDEX: tfm-metrics-events
    volumes:
      - ../fase7-observabilidad/shared:/app/shared

networks:
  oob-network:
    external: true
  single-node_default:
    external: true
```

## Dataset sinttico de pruebas

Para enriquecer las visualizaciones se generóııı un conjunto sinttico de 200 eventos con secuencias temporales y combinaciones de:
- `triage_decision`
- `collection_completed`
- mltiples hosts,
- varias severidades,
- varios perfiles de coleccin.

> [!TIP]
> El ndice termin alcanzando 404 documentos en la validacin final, combinando las pruebas manuales iniciales y la carga sinttica posterior.

### Script de carga

Se utilizóııı un script Python para importar el CSV sinttico a OpenSearch va HTTPS autenticado.

```bash
python3 import_fase7_metrics.py --csv fase7_metrica_datos_test_200.csv --url https://localhost:9200
```

## Validacin funcional

### Pruebas unitarias de emisin

#### Triage

```bash
docker exec -it langgraph-agent python3 -c "
from app.main import triage
from app.models import TriageRequest
print(triage(TriageRequest(wazuh={'incident_id':'TEST-TRIAGE-01','host':'HOST-01'}, cti={})))
"
```

#### Collection

```bash
docker exec -it orchestrator python3 -c "
from main import collect, CollectRequest
import asyncio
print(asyncio.run(collect(CollectRequest(incidentid='TEST-COLLECT-01', host='HOST-02', profile='generic_high_signal_collection'))))
"
```

### Verificacin en OpenSearch

```bash
curl -sk -u admin:SecretPassword "https://localhost:9200/tfm-metrics-events/_count?pretty"
```

Resultado validado en laboratorio:

```json
{
  "count": 404
}
```

## Dashboard inicial

### Data View

Se creóııı el Data View:

```text
tfm-metrics-events*
```

con campo temporal:

```text
@timestamp
```

### Visualizaciones creadas

| Panel | Tipo | Filtro principal | Propsito |
|---|---|---|---|
| Eventos por tipo | Barras | Sin filtro | Distribucin `triage_decision` vs `collection_completed` |
| Triage por severidad | Barras | `source = langgraph-agent` | Distribucin de decisiones del agente |
| Colecciones por host | Barras | `event_type = collection_completed` | Frecuencia de colecciones por activo |
| Serie temporal de eventos | Lnea/rea | Sin filtro | Evolucin temporal del flujo |
| Tabla resumen | Tabla agregada | Agrupada por `incident_id` | Resumen sinttico por incidente |
| Tabla operativa | Discover guardado | Sin filtro | Inspeccin de documentos individuales |

### Acceso al dashboard

En este entorno, OpenSearch Dashboards est disponible en:

```text
https://<HOST>:4443
```

porque el contenedor `single-node-wazuh.dashboard-1` publica `5601/tcp` en el puerto host `4443`.

## Navegacin visual sugerida

### Tabs lgicos para el README

| Tab | Contenido |
|---|---|
| Overview | Objetivo, arquitectura y componentes |
| Setup | `docker-compose`, variables, volumen compartido |
| Validation | pruebas manuales, curl, recuentos |
| Dashboard | Data View, visualizaciones y layout |
| Synthetic data | CSV de pruebas y script de importacin |

> [!NOTE]
> Aunque Markdown no soporta tabs reales de forma portable en todos los visores, esta estructura deja el contenido preparado para migrarse fcilmente a documentacin tipo MkDocs, Docusaurus o GitHub Pages con componentes visuales.

## Iconografa sugerida

Para mantener coherencia visual con documentacin de fases anteriores, se recomienda usar iconografa estilo producto/infraestructura en la futura versin HTML o wiki:

- 📊 Mtricas y dashboards
- 🤖 LangGraph Agent / IA agentica
- 🧭 Orchestrator
- 🗂️ MinIO / evidencias
- 🔎 OpenSearch / bsquedas
- ✅ Validaciones
- 🧪 Datos sintticos
- ⚠️ Limitaciones o notas de laboratorio

Si se quiere una versin ms cercana a herramientas como Jira/Confluence, la siguiente iteracin puede migrar este README a una pgina HTML o una wiki con bloques visuales, badges y tabs reales.

## Limitaciones observadas

- El campo `incident_id.keyword` no estuvo disponible en todas las consultas, lo que sugiere mapping dinmico mejorable.
- La tabla agregada del dashboard muestra resmenes tiles, pero no sustituye una vista documental completa en Discover.
- Mtricas avanzadas como MTTA, MTTApprove, MTTAccess o precision del agente requerirn instrumentar ms eventos en fases posteriores.

## Prximos pasos

1. Definir un mapping o template explcito para `tfm-metrics-events`.
2. Instrumentar ms hitos del flujo (`war_room_created`, `approval_requested`, `approval_granted`, `remote_access_started`, etc.).
3. Refinar el dashboard con KPIs derivados.
4. Exportar capturas o artefactos del dashboard para anexos del TFM.
5. Evolucionar la documentacin a una versin visual enriquecida si se quiere uniformidad completa con el resto de fases.
