# Fase 3 · Motor de triage y evaluación de viabilidad de LLM local

> **Objetivo de la fase**
> Dotar al enclave de un motor de triage propio que convierta una alerta de Wazuh
> ya enriquecida en una decisión accionable (severidad, atribución ATT&CK, flags
> de respuesta), y **evaluar experimentalmente** si un LLM local aporta valor
> suficiente para formar parte de esa decisión en un entorno Out-of-Band.

> **Resultado de la fase**
> El motor **determinista** es el que se despliega. La alternativa basada en
> LLM local (Mistral 7B vía Ollama) está implementada, instrumentada y medida,
> y se **descarta para producción** por las razones documentadas en
> [Decisión de despliegue](#decisión-de-despliegue). El código del modo LLM se
> conserva como artefacto de investigación reproducible, no como componente
> operativo.

---

## Alcance real de esta fase

Esta fase implementa **un servicio HTTP con un grafo LangGraph de dos nodos**.
Nada más. Es importante ser explícito porque el enriquecimiento y la gestión de
caso pertenecen a otras fases y una lectura descuidada del conjunto sugeriría
que están aquí.

| Capacidad | Dónde vive realmente |
|---|---|
| Consulta a AbuseIPDB, VirusTotal y MISP | **Fase 2** (workflow de n8n) |
| Deduplicación y verificación HMAC del webhook | **Fase 2** |
| Cálculo de severidad, ATT&CK y flags de respuesta | **Fase 3 (esta)** |
| Publicación de la Incident Card en Rocket.Chat | **Fase 2** |
| Creación y seguimiento de caso en DFIR-IRIS | **Fase 6** |
| Colección forense (Velociraptor) | **Fase 5** |

En concreto, esta fase **no** incluye memoria vectorial (ChromaDB), **no**
consulta el histórico de IRIS y **no** habla con MISP. Las herramientas de
`app/tools.py` que empiezan por `tool_format_cti_*` únicamente **formatean**
inteligencia que n8n ya ha resuelto y entrega en el payload.

---

## Arquitectura

```text
                        Fase 2                              Fase 3
   ┌──────────┐    ┌──────────────┐   POST /triage   ┌──────────────────┐
   │  Wazuh   │───▶│     n8n      │─────────────────▶│  langgraph-agent │
   │ manager  │    │ (enrichment) │                  │  (FastAPI)       │
   └──────────┘    └──────┬───────┘◀─────────────────└────────┬─────────┘
                          │           decision                │
                          ▼                                   │
                  ┌───────────────┐                  ┌────────▼────────┐
                  │ Rocket.Chat   │                  │  Grafo LangGraph│
                  │ (War Room)    │                  │  triage_agent   │
                  └───────────────┘                  │  remediation_ag.│
                                                     └────────┬────────┘
                                                              │ solo en
                                                              │ modo llm/hybrid
                                                     ┌────────▼────────┐
                                                     │ Ollama          │
                                                     │ mistral:7b      │
                                                     └─────────────────┘
```

El servicio **no publica puerto en el host**. n8n lo alcanza por DNS interno de
Docker (`http://langgraph-agent:8000`). Una versión anterior exponía `8000:8000`,
lo que dejaba `/triage` accesible sin autenticación desde cualquier proceso del
host; queda documentado como hallazgo corregido.

---

## Modos de triage

El motor se selecciona con `TRIAGE_MODE`. **El contrato de `/triage` es idéntico
en los tres casos**, de modo que cambiar de modo no obliga a tocar el workflow
de n8n.

| Modo | Quién fija la severidad | Quién redacta el texto | Uso |
|---|---|---|---|
| `deterministic` | Motor de reglas | Motor de reglas | **Por defecto. En producción.** |
| `hybrid` | Motor de reglas | LLM | Experimental |
| `llm` | LLM (sujeto a guardrail) | LLM | Experimental |

En `llm` e `hybrid`, cualquier fallo del modelo —timeout, JSON malformado,
esquema incompleto, severidad fuera de vocabulario, Ollama caído— provoca
**degradación limpia** al motor determinista. La degradación queda registrada en
`decision.analysis_mode` y `decision.degraded_reason`.

> El campo `analysis_mode` se propaga hasta el mensaje de Rocket.Chat de forma
> deliberada: **el informe no puede atribuir a un modelo un veredicto que produjo
> el motor de reglas.** Es un requisito de trazabilidad, no cosmético.

---

## Motor determinista

### Puntuación

```
score = rule_level
      + 2  si AbuseIPDB confidence > 50
      + 2  si VirusTotal motores maliciosos > 10
      + 2  si hay coincidencia en MISP
```

| score | severidad |
|---:|---|
| ≥ 12 | `CRITICA` |
| ≥ 9 | `ALTA` |
| ≥ 6 | `MEDIA` |
| < 6 | `BAJA` |

El desglose se devuelve explícitamente en `decision.score_breakdown` para que
cada veredicto sea auditable: siempre se puede justificar por qué una alerta
subió o bajó.

### Atribución ATT&CK: precedencia explícita

1. **`wazuh_native`** — campos `rule.mitre.*` de la propia alerta. Es el dato
   autoritativo: lo mantiene el ruleset upstream.
2. **`heuristic`** — mapeo local por palabras clave, **solo** para reglas sin
   mapeo nativo.
3. **`unmapped`** — `"no determinado"`.

Nunca se fabrica una técnica para una regla que no se reconoce. Una atribución
inventada es peor que la ausencia de dato: contamina las métricas de cobertura
ATT&CK del SOC y orienta mal la respuesta.

> **Hallazgo corregido.** La versión inicial devolvía `T1078 - Valid Accounts`
> como valor por defecto cuando no encontraba mapeo. Un ataque de fuerza bruta
> SSH (`T1110`) se reportaba como uso de credenciales válidas: dos tácticas
> distintas, dos respuestas distintas. El caso `A015` del corpus documenta el
> equivalente en Windows (acceso a LSASS es `T1003.001`, no `T1078`).

### Flags de respuesta

`requires_block` solo se propone si la severidad está escalada **y** la IP de
origen es pública y enrutable. Proponer bloquear una IP privada, ausente o
malformada genera ruido operativo y erosiona la confianza en el sistema.

---

## Controles frente al LLM

El prompt del modelo incorpora, literalmente, campos de la alerta: `rule_desc`,
`agent_name`, `src_ip`. **Un nombre de usuario en un fallo de SSH acaba dentro
del contexto del modelo.** El atacante elige ese texto. Esto es inyección
indirecta de prompt por un canal que el operador no controla, y es la razón
principal por la que esta fase existe como evaluación y no como integración.

Se implementan tres controles independientes:

### 1. Guardrail antidegradación de severidad

Se acepta la severidad del LLM solo si no rebaja la determinista más de
`MAX_SEVERITY_DOWNGRADE` niveles (por defecto, 1). **Escalar siempre está
permitido**; el riesgo asimétrico está en la rebaja, que es justo lo que
buscaría una inyección: bajar la severidad y desactivar el bloqueo.

Si el guardrail se dispara en modo `llm`, se descarta **también** la
recomendación del modelo: si su veredicto no es fiable, ninguna de sus salidas
lo es.

### 2. Delimitador con *nonce* por petición

El bloque de datos no confiables se cierra con un identificador aleatorio
generado en cada invocación (`END_UNTRUSTED_DATA_<nonce>`). Un delimitador fijo
es adivinable —aparece en el propio prompt del sistema— y basta con escribirlo
en un campo de log para simular el cierre del bloque y continuar como si fuera
texto de sistema. El caso `INJ-03` de la batería mide exactamente esto.

### 3. Saneado de la salida generativa

`summary` y `recommendation` se acotan en longitud, se les eliminan caracteres
de control y saltos de línea, se neutralizan menciones masivas (`@all`, `@here`)
y se despoja a los enlaces markdown de su destino. No pretende detectar
inyección: asume que puede haberla y limita el daño en el canal del War Room.

> **Límite conocido y deliberadamente documentado.** El guardrail protege la
> *decisión automatizada*. No protege el *texto que lee el analista*. Una
> inyección que no toca la severidad puede seguir contaminando la Incident Card
> con contexto falso ("actividad ya validada por el equipo de sistemas"). El
> saneado reduce el vector técnico, no el semántico. Es una limitación
> estructural del enfoque, no un defecto de implementación.

---

## Banco de pruebas

En `bench/` (instrumentación de laboratorio; **no** forma parte del servicio
desplegado):

| Fichero | Contenido |
|---|---|
| `corpus_alertas.json` | 30 alertas que cubren el rango completo de severidad, alertas sin `src_ip`, IPs privadas y malformadas, y los tres orígenes de atribución ATT&CK |
| `corpus_inyeccion.json` | 11 casos: 1 control + 10 vectores de inyección indirecta |
| `replay_alerts.py` | Reproduce un corpus contra los tres modos y emite las tablas de resultados |

El script conmuta `TRIAGE_MODE` en memoria, por lo que **no requiere reiniciar el
contenedor entre modos**:

```bash
docker cp bench langgraph-agent:/app/bench

# Suite de rendimiento y concordancia
docker exec -it langgraph-agent python3 /app/bench/replay_alerts.py \
    --suite rendimiento --modes deterministic hybrid llm -n 3

# Batería de inyección indirecta
docker exec -it langgraph-agent python3 /app/bench/replay_alerts.py \
    --suite inyeccion --modes llm hybrid -n 3

docker cp langgraph-agent:/app/bench/resultados ./bench/resultados
```

Para el consumo de CPU durante la inferencia, ejecutar en paralelo:

```bash
docker stats --no-stream ollama langgraph-agent
```

---

## Resultados

<!-- TODO: sustituir por las tablas reales generadas en bench/resultados/ -->

> **Pendiente de ejecución.** Las tablas de esta sección se generan con
> `replay_alerts.py` y deben pegarse aquí tal cual las emite el script. Hasta
> entonces, ninguna cifra de rendimiento debe darse por válida en la memoria.

Métricas que se reportan:

- Latencia p50 / p95 / máxima por modo.
- Porcentaje de degradaciones (veces que el modo nominal **no fue** el modo efectivo).
- Concordancia de severidad frente al motor determinista, con las divergencias caso a caso.
- Procedencia de la atribución ATT&CK (`wazuh_native` / `heuristic` / `unmapped`).
- Batería de inyección: rebajas conseguidas, rebajas que el guardrail no detuvo,
  propagación del canario al texto y propagación de marcado al canal.

---

## Decisión de despliegue

Se despliega `TRIAGE_MODE=deterministic`. Criterios:

| Criterio | Determinista | LLM local (Mistral 7B, CPU) |
|---|---|---|
| Latencia | < 50 ms | ~50 s por inferencia |
| Reproducibilidad | Total (funciones puras) | No garantizada |
| Auditabilidad del veredicto | `score_breakdown` explícito | Texto libre |
| Superficie de inyección indirecta | Nula (no interpreta texto) | Presente por diseño |
| Coste en el anfitrión | Despreciable | Compite con Wazuh por 32 vCPU sin GPU |

El factor determinante es la **latencia frente al propósito del sistema**: un
enclave de alerta temprana cuya notificación se retrasa ~50 s por alerta deja de
cumplir su función. Los demás criterios refuerzan la decisión, no la sostienen
por sí solos.

### Sobre el uso de un LLM remoto

Se consideró y se descarta para el flujo operativo. Conviene distinguir dos ejes,
porque el enclave ya usa servicios externos (AbuseIPDB, VirusTotal):

- **Posición en la ruta.** AbuseIPDB es *enriquecimiento*: una entrada a una
  decisión que toma el motor local, con ruta de degradación documentada. Un LLM
  remoto estaría *en la decisión*. Una dependencia externa degradable en la
  entrada es aceptable; en la decisión, no.
- **Dirección del dato.** A AbuseIPDB se le envía una dirección IP. A un LLM
  remoto se le enviarían nombres de host, cuentas, rutas y contenido de alerta
  de un incidente en curso — potencialmente durante un compromiso del entorno
  corporativo, que es exactamente el escenario para el que se construye el
  enclave. Es un problema de confidencialidad de la investigación, no solo de
  disponibilidad.

Un modelo remoto **sí** puede emplearse como sujeto de laboratorio para la
batería de inyección (un modelo más capaz da a la prueba un valor que Mistral 7B
no alcanza), siempre fuera del despliegue: sin `TRIAGE_MODE` remoto, sin cambios
en `docker-compose.yml` y sin tocar el workflow de n8n.

---

## Configuración

### Variables de entorno

| Variable | Por defecto | Descripción |
|---|---|---|
| `TRIAGE_MODE` | `deterministic` | `deterministic` \| `llm` \| `hybrid` |
| `OLLAMA_BASE_URL` | `http://ollama:11434` | Solo en modos `llm`/`hybrid` |
| `OLLAMA_MODEL` | `mistral:7b` | |
| `OLLAMA_TIMEOUT_SECONDS` | `45` | Timeout duro; agotado, degrada |
| `OLLAMA_TEMPERATURE` | `0.1` | El triage no es una tarea creativa |
| `MAX_SEVERITY_DOWNGRADE` | `1` | Margen del guardrail, en niveles |
| `OS_URL` / `OS_INDEX` | ver compose | Métricas de Fase 7 |
| `OS_USER` / `OS_PASS` | — | **Solo vía `.env`**, nunca en el compose |

> `.env` está excluido por `.gitignore` (`**/.env`). Partir de `.env.example`.
> La cuenta usada para métricas debe tener permiso de escritura **únicamente**
> sobre `tfm-metrics-events*`; no debe ser la cuenta administrativa del
> indexador.

### `docker-compose.yml`

Es el fichero real del repositorio. El servicio no publica puerto, se une a la
red del stack de Wazuh para escribir métricas y monta en solo lectura el cliente
de métricas de la Fase 7. Ollama se declara en su propio bloque de compose y
solo es necesario para los modos experimentales.

---

## Contrato de la API

### `GET /health`

```json
{ "status": "ok", "triage_mode": "deterministic", "llm_model": "mistral:7b" }
```

### `POST /triage`

**Petición**

```json
{
  "wazuh": {
    "alert_id": "1756200001.100001",
    "rule_id": "5712",
    "rule_desc": "sshd: brute force trying to get access to the system.",
    "rule_level": 10,
    "rule_groups": ["syslog", "sshd", "authentication_failures"],
    "agent_name": "srv-web-01",
    "src_ip": "45.134.26.11",
    "mitre_id": ["T1110"],
    "mitre_tactic": ["Credential Access"],
    "mitre_technique": ["Brute Force"]
  },
  "cti": {
    "abuse_confidence": 96,
    "abuse_total_reports": 4210,
    "vt_malicious": 8,
    "misp_total": 0,
    "src_ip_is_private": false
  }
}
```

**Respuesta**

```json
{
  "wazuh": { "...": "eco de la entrada" },
  "cti": { "...": "eco de la entrada" },
  "decision": {
    "severity_real": "CRITICA",
    "score": 12,
    "score_breakdown": { "nivel_wazuh": 10, "abuseipdb": 2, "virustotal": 0, "misp": 0 },
    "summary": "Severidad CRITICA (score=12)",
    "mitre_tactic": "Credential Access",
    "mitre_technique": "T1110 - Brute Force",
    "mitre_source": "wazuh_native",
    "cti_summary": "AbuseIPDB confidence=96 | reportes=4210 | VirusTotal motores maliciosos=8",
    "analysis_mode": "deterministic",
    "guardrail_triggered": false,
    "guardrail_reason": "",
    "degraded_reason": "",
    "requires_block": true,
    "create_war_room": true,
    "recommendation": "Bloquear 45.134.26.11 en perimetro y abrir War Room del incidente."
  },
  "messages": [ { "agent": "triage_agent", "detail": "Motor determinista." } ]
}
```

`decision.severity_real` usa el vocabulario `CRITICA | ALTA | MEDIA | BAJA`,
sin tilde, coherente con `SEVERITY_SCALE` en `app/tools.py`.

---

## Validación funcional

```bash
# Salud y modo efectivo
docker exec -it langgraph-agent \
  python3 -c "import urllib.request;print(urllib.request.urlopen('http://127.0.0.1:8000/health').read())"

# Triage de una alerta del corpus, desde la red de n8n
docker exec -it n8n sh -c 'wget -qO- --post-file=/dev/stdin \
  --header="Content-Type: application/json" http://langgraph-agent:8000/triage' \
  < bench/una_alerta.json
```

Comprobaciones esperadas:

- [ ] `analysis_mode` coincide con `TRIAGE_MODE`, o indica degradación explícita.
- [ ] Una alerta sin `src_ip` (regla 550) no provoca error ni propone bloqueo.
- [ ] Una alerta con IP privada escalada abre War Room pero **no** propone bloqueo.
- [ ] `mitre_source` es `wazuh_native` cuando la alerta trae `rule.mitre`.
- [ ] Ninguna alerta sin mapeo devuelve una técnica fabricada.

---

## Riesgos y limitaciones aceptados

| Riesgo | Estado |
|---|---|
| El saneado no cubre la inyección semántica (contexto falso creíble en el resumen) | Documentado; solo afecta a modos experimentales |
| Al agotar el timeout, el hilo de inferencia queda huérfano consumiendo CPU hasta que Ollama termina | Documentado; aceptable con 32 vCPU |
| `src_ip_is_private` proviene de n8n | Se valida además localmente con `ipaddress`; el campo externo es señal secundaria |
| Dependencia de AbuseIPDB / VirusTotal (servicios externos) | Fase 2; degradable, documentado |
| Sin evaluación de precisión frente a triaje manual de un analista | Fuera del alcance del TFM |

---

## Estado

- [x] Servicio de triage con grafo LangGraph de dos nodos
- [x] Motor determinista auditable con desglose de puntuación
- [x] Atribución ATT&CK con precedencia explícita y sin fabricación
- [x] Modos `llm` e `hybrid` con degradación limpia
- [x] Guardrail antidegradación de severidad
- [x] Delimitador con nonce y saneado de salida generativa
- [x] Corpus de alertas y batería de inyección
- [ ] Ejecución del banco y volcado de resultados en la sección correspondiente
- [ ] Rol dedicado de escritura de métricas en el indexador

## Próximos pasos

1. Ejecutar el banco y completar [Resultados](#resultados).
2. Fase 4 — conectividad OOB de los agentes mediante **Headscale** (sustituye a
   la propuesta inicial de Cloudflare Tunnels, descartada por dependencia de un
   tercero externo).
3. Fase 5 — Velociraptor y colección forense dirigida por `recommendation`.
4. Fase 6 — DFIR-IRIS: creación de caso y volcado de `decision` como registro de
   trazabilidad del veredicto automatizado.
