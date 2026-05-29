# Fase 3b — Despliegue del servicio LangGraph en Docker

## Contexto

Tras definir la arquitectura de agentes en la Fase 3a, el siguiente paso es desplegar un servicio independiente que ejecute LangGraph y exponga un endpoint HTTP consumible desde n8n. LangGraph se integra de forma natural en servicios Python con estado y workflows definidos como grafos, lo que encaja con un microservicio dedicado dentro de la red privada del proyecto.

## Objetivo de la fase

- Crear un microservicio Python para ejecutar el flujo agentic.
- Integrarlo en Docker dentro de `oob-network`, junto al resto del stack del TFM.
- Exponer un endpoint `/triage` para que n8n le envíe alertas enriquecidas con CTI.
- Dejar preparado el servicio para consumir Ollama como LLM local.

## Estructura propuesta de carpetas

Dentro del repositorio del TFM se propone crear una carpeta nueva para esta fase:

```text
fase3-agentic/
├── app/
│   ├── main.py
│   ├── graph.py
│   ├── agents.py
│   ├── models.py
│   └── tools.py
├── requirements.txt
├── Dockerfile
└── docker-compose.yml
```

Esta separación mantiene limpio el repositorio y desacopla la lógica agentic del workflow visual de n8n.

## Dependencias mínimas

LangGraph se presenta como framework para orquestación de agentes con estado y suele combinarse con LangChain y adaptadores de modelos de chat. Para este laboratorio se propone una base mínima:

```txt
fastapi
uvicorn[standard]
langgraph
langchain
langchain-community
pydantic
requests
```

Si se utiliza integración específica con Ollama, podrá añadirse el paquete correspondiente en una iteración posterior del servicio.

## `requirements.txt`

```txt
fastapi
uvicorn[standard]
langgraph
langchain
langchain-community
pydantic
requests
```

## `Dockerfile`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

El contenedor expone un servicio simple, reproducible y adecuado para pruebas locales y para la memoria del TFM.

## `docker-compose.yml`

```yaml
services:
  langgraph-agent:
    build: .
    container_name: langgraph-agent
    restart: unless-stopped
    ports:
      - "8000:8000"
    networks:
      - oob-network

networks:
  oob-network:
    external: true
```

De esta forma, n8n podrá conectarse internamente por hostname `langgraph-agent` usando `http://langgraph-agent:8000/triage`.

## Endpoint HTTP propuesto

El servicio expondrá un endpoint POST `/triage` con FastAPI. Ese endpoint recibirá el JSON procedente de n8n, ejecutará el grafo de agentes y devolverá una decisión estructurada.

### `app/main.py`

```python
from fastapi import FastAPI
from pydantic import BaseModel
from app.graph import run_graph

app = FastAPI(title="TFM LangGraph Agent Service")

class TriageRequest(BaseModel):
    wazuh: dict
    cti: dict

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/triage")
def triage(payload: TriageRequest):
    return run_graph(payload.model_dump())
```

El endpoint `/health` facilita validaciones básicas de disponibilidad desde Docker o desde n8n.

## Integración con n8n

En lugar del nodo AI Agent actual, n8n usará un nodo `HTTP Request` con estas propiedades:

- Método: `POST`.
- URL: `http://langgraph-agent:8000/triage`.
- Content-Type: `application/json`.
- Body: salida del nodo `Code CTI Context` empaquetada como `wazuh` + `cti`.

Esto permite conservar el resto del workflow visual: Rocket.Chat, nodos IF, war rooms y playbooks seguirán estando en n8n, pero el razonamiento complejo quedará externalizado.

## Validación de la fase

La Fase 3b se considerará validada cuando se cumplan estos puntos:

- El contenedor `langgraph-agent` arranca correctamente.
- El endpoint `/health` devuelve `{"status":"ok"}`.
- El endpoint `/triage` acepta un payload real de n8n.
- El servicio responde con un JSON estructurado y consumible por Rocket.Chat y por nodos condicionales.

## Resultado de la fase

Al finalizar la Fase 3b se dispone de un microservicio Dockerizado con FastAPI preparado para ejecutar LangGraph dentro de `oob-network`. Esta fase crea la base de ejecución para el sistema multiagente definido en 3a y habilita la implementación detallada de agentes y herramientas de la Fase 3c.