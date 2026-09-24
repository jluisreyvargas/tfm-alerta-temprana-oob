# Métricas calculables — tfm-alerta-temprana-oob

- Fecha de extracción: 2026-09-21
- Alcance: las seis métricas encargadas (MTTA, MTTApprove, Agent Precision, Dedup rate,
  False positive rate, Script success rate) más una nota sobre las dos restantes de la
  tabla del README raíz (MTTAccess, MTTCollection), que no estaban en el encargo pero
  aparecen medidas de forma más directa que varias de las seis y se incluyen por
  completitud.
- Método: solo lectura de material ya versionado. No se ha ejecutado ningún comando
  contra Docker ni contra ningún servicio en ejecución. No se han leído ficheros `.env`.
  Se ha descartado deliberadamente `/tmp/censo-wazuh/` (copia local de trabajo de una
  sesión anterior, con los ficheros crudos de alertas de Wazuh): no está versionado, no
  forma parte de "material ya registrado" y usarlo para derivar una cifra nueva excedería
  el encargo de esta tarea, que es evaluar qué es calculable **a partir de lo ya
  documentado**, no producir un análisis original sobre datos crudos no auditados en
  ningún documento del repositorio.

---

## 1. Inventario de fuentes con marcas de tiempo emparejables

| Fuente | Qué registra | Granularidad | Nº de observaciones |
|---|---|---|---|
| `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md` | 45 mediciones (M-1 a M-45) en 6 sesiones (13, 17, 18×2, 20×2 de septiembre de 2026): comandos y salidas reales, casos IRIS numerados, dos duraciones exactas de colección Velociraptor (`started_at`/`ended_at` con segundo) | Mixta: casi todas las entradas son narrativas de causa/efecto sin timestamp; solo dos traen un par de timestamps explícito con el que se puede restar una duración | 45 entradas; de ellas, 2 con par de timestamps explícito (sección 9, Fase 5_4b) |
| `fase3-agentic/README.md`, sección "Resultados" | Banco de rendimiento (30 alertas × 3 modos, 1 repetición) y batería de inyección (11 casos × 3 repeticiones) | Latencia en segundos por ejecución (p50/p95/máx agregados, no por caso individual) | 30 (rendimiento) + 33 (inyección, 11×3) = 63 ejecuciones agregadas en tablas |
| `fase4-breakglass-dc/README.md`, sección "Validación" | Recuento de pruebas superadas: "9/9 pruebas del agente, 5/5 de la firma HMAC, 11/11 del flujo de aprobación 4d" | Solo recuento pasa/falla, sin duración ni timestamp | 25 pruebas funcionales (9+5+11), sin componente temporal |
| `docs/INFORME-AUDITORIA-FASE6.md`, "Control de verificación permanente" | 16 comprobaciones de `scripts/verify-fase6.sh`; 3 acreditadas con prueba negativa (inducir el fallo y comprobar que el script lo detecta) | Pasa/falla por ejecución, sin timestamp ni duración | 16 comprobaciones, 3 con inducción de fallo documentada |
| `fase8-kvm/README.md` + `docs/cierre-mejora1-hook.md` | Latencia del hook de autorización KVM (V10): p50 103 ms, p95 135 ms, máx 151 ms, "contra 3.000" (repeticiones no especificadas con exactitud) | Milisegundos, agregado (p50/p95/máx) | No aplica a las 6 métricas de este encargo: mide autorización de acceso KVM, no aprobación de acción DC ni triage |
| `fase7-observabilidad/README.md` | Definición de los dos únicos tipos de evento indexados en OpenSearch: `triage_decision` y `collection_completed` (este último con campo `duration_ms`) | Por evento, si se consultase el índice | 404 documentos cargados en laboratorio (mezcla de pruebas manuales + 200 sintéticos), no desglosados por tipo en el README |

**Hallazgo que condiciona todo lo demás.** `fase7-observabilidad/README.md`, sección "Próximos pasos", punto 2, dice literalmente: "Instrumentar más hitos del flujo (`war_room_created`, `approval_requested`, `approval_granted`, `remote_access_started`, etc.)" — es decir, **esos tipos de evento no existen todavía en el índice**. Cualquier métrica que dependa de "cuándo se creó el War Room" o "cuándo se aprobó una acción" no es consultable hoy contra OpenSearch, porque el dato no se emite. Esto excluye por diseño (no por falta de acceso) una consulta para MTTA y MTTApprove.

---

## 2. Las seis métricas: definición operativa, estado y cálculo

### 2.1 MTTA — Alerta → War Room creada

**Definición en el repositorio:** `README.md:180` y `docs/propuesta_tfm_alerta_temprana_v3.md:570`, idéntica en ambos: "Alerta → War Room creada", objetivo `< 60 segundos`. No hay una definición más precisa (¿desde qué timestamp de la alerta? ¿desde la recepción en n8n o desde el `timestamp` que trae la alerta de Wazuh?).

**Estado: `NO CALCULABLE`.**

Qué falta exactamente: ningún documento registra el par (timestamp de la alerta, timestamp de creación del War Room) para ningún caso concreto. `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md` describe el flujo completo de creación de War Room (M-40, sección 13) con detalle de la lógica de renombrado, pero sin ninguna marca de tiempo de cuándo se creó el canal ni de cuándo llegó la alerta que lo disparó. Tampoco es consultable contra OpenSearch: el evento `war_room_created` no está instrumentado (ver hallazgo de la sección 1). El único dato de latencia relacionado con el pipeline es el de la Fase 2 ("Rendimiento medido", `fase2-orquestador/README.md`): modo `deterministic` ~3 s de principio a fin del pipeline n8n, "dominado por las llamadas CTI" — pero ese número mide la latencia del webhook al veredicto de triage, **no** hasta la creación del War Room, que es un paso posterior del mismo workflow sin medir por separado. No se debe usar esa cifra como sustituto de MTTA sin decirlo explícitamente, porque mide una etapa distinta y anterior.

### 2.2 MTTApprove — Solicitud de aprobación → decisión

**Definición en el repositorio:** `README.md:181`, "Solicitud de aprobación → decisión", objetivo `< 5 minutos`.

**Estado: `NO CALCULABLE`.**

Qué falta exactamente: lo único cuantitativo documentado sobre el flujo de aprobación de Fase 4d es un **límite de política**, no una medición: las solicitudes `REQ-xxxxxxxx` caducan a los 15 minutos (`fase4-breakglass-dc/README.md:57`, `docs/README-fase4d-flujo-aprobacion.md:56,97`). Ese es el techo permitido, no un tiempo medido de aprobación real. La validación de la Fase 4d documentada es "11/11" pruebas superadas (`fase4-breakglass-dc/README.md`, "Validación"), pero el resultado registrado es booleano (pasa/no pasa cada prueba), sin cronometrar ninguna. No es consultable contra OpenSearch por el mismo motivo que MTTA: `approval_requested` y `approval_granted` figuran expresamente como instrumentación pendiente.

### 2.3 Agent Precision — Triage del agente frente a experto humano

**Definición en el repositorio:** `README.md:185`, "Triage del agente frente a experto humano", objetivo `> 80 %`.

**Estado: `NO CALCULABLE` tal como está definida** — y el propio repositorio lo dice explícitamente: `fase3-agentic/README.md`, tabla "Riesgos y limitaciones aceptados", última fila: *"Sin evaluación de precisión frente a triaje manual de un analista | Fuera del alcance del TFM"*. No hay ningún experto humano que haya triado el mismo corpus para comparar. Cualquier cifra de "precisión del agente" que se presente sin esta advertencia estaría respondiendo una pregunta que el propio proyecto ha declarado, por escrito, que no se propuso responder.

**Proxy calculable, con una redefinición explícita que hay que declarar en la presentación:** la Fase 3 sí mide la concordancia del modo `llm`/`hybrid` frente al **motor determinista** (que codifica las reglas del proyecto, no el juicio de un analista humano). Se calcula aquí, dejando constancia de que **no es la misma métrica** que define el README:

| Modo | Coincide con el motor determinista | Escala | Rebaja | n |
|---|---:|---:|---:|---:|
| `hybrid` | 30/30 = **100,0 %** | 0/30 | 0/30 | 30 |
| `llm` | 7/30 = **23,3 %** | 18/30 = 60,0 % | 5/30 = 16,7 % | 30 |

Fuente: `fase3-agentic/README.md`, tabla "Concordancia de severidad frente al motor determinista". n=30 en ambos casos (todo el corpus, 1 repetición por caso). No hay dispersión que reportar porque es un recuento sobre la totalidad del corpus, no una media de sub-muestras.

**Lectura correcta para la defensa:** si se presenta esta tabla, debe ir etiquetada como "concordancia con el motor de reglas", nunca como "Agent Precision frente a experto humano" — son cosas distintas y el propio repositorio distingue la una de la otra.

### 2.4 Dedup rate — % de alertas correctamente deduplicadas

**Definición en el repositorio:** `README.md:184`, objetivo `> 95 %`.

**Estado: `NO CALCULABLE`.**

Qué falta exactamente: el mecanismo de deduplicación de Fase 2 (nodo `Dedup` de n8n, clave `rule_id|agent_name|objetivo`, ventana de 15 minutos) **vive en memoria del proceso de n8n y se pierde al reiniciar el contenedor** — así lo dice el propio README de Fase 2, sección "Deuda técnica identificada": *"El estado vive en memoria del proceso y se pierde al reiniciar el contenedor"*. No hay ningún registro persistente de cuántas alertas entraron frente a cuántas se suprimieron por duplicado; la única evidencia documentada es una **prueba funcional cualitativa de un solo caso** ("🔁 Repetición dentro de la ventana | Suprimida en Dedup", tabla "Validación funcional" de `fase2-orquestador/README.md`), que confirma que el mecanismo funciona pero no aporta una tasa. El censo de población real de alertas (`docs/REGISTRO-MEDICIONES...md`, M-24: 52.513 alertas en 4 meses) reporta volumen por regla y por agente, pero no reporta cuántos incidentes únicos resultaron tras deduplicar — esa cifra no está en ningún documento. No es consultable contra OpenSearch: no existe un evento `alert_deduplicated` ni equivalente en la instrumentación de Fase 7.

### 2.5 False positive rate — Alertas que no llegan a aprobación

**Definición en el repositorio:** `README.md:186`, objetivo `< 15 %`.

**Estado: `NO CALCULABLE`, y con una ambigüedad de definición que conviene señalar antes de intentar calcularla.**

El repositorio no aclara en ningún sitio si "no llegar a aprobación" se refiere a (a) alertas de bajo nivel que nunca debieron escalar (el caso normal y esperado, no un fallo), o (b) alertas que escalan a War Room/caso pero se descartan después por no ser un incidente real (falsos positivos en el sentido habitual de un SOC). El episodio más cercano a (b) documentado es el del filtro de postura (`docs/REGISTRO-MEDICIONES...md`, M-23/M-32): antes de la corrección, hallazgos de postura CIS/SCA generaban War Room y caso IRIS como si fueran incidentes; el censo (M-24) cuantifica el volumen de esas reglas por encima del umbral de escalada (rule 19014: 141, rule 19005: 104, rule 19011: 45, rule 23505: 396, rule 23506: 24, en 4 meses, sobre 52.513 alertas totales) pero **no** cuantifica cuántas de ellas efectivamente generaron War Room/caso antes de la corrección del filtro — solo hay un caso documentado con recuento exacto: "nueve casos IRIS creados en un minuto el 2026-09-18 (casos #48 a #56)" (M-32), que es un incidente puntual de una ejecución concreta, no una tasa sobre el volumen total. No hay instrumentación de OpenSearch que permita esta consulta (no hay evento que registre "alerta no escalada" ni "caso descartado por ser falso positivo").

### 2.6 Script success rate — Ejecuciones en DC con resultado correcto

**Definición en el repositorio:** `README.md:187`, objetivo `> 98 %`.

**Estado: `CALCULABLE`, con una salvedad de alcance que hay que declarar: es una tasa de superación de la batería de pruebas funcionales de Fase 4, no una tasa de ejecuciones en producción continua** (el repositorio no registra un histórico de invocaciones reales del agente DC fuera de estas pruebas).

**Cálculo:**

| Batería | Resultado | n |
|---|---:|---:|
| Pruebas del agente DC (allowlist de 7 scripts, ACL, anclaje de ruta) | 9/9 | 9 |
| Pruebas de la firma HMAC-SHA256 + anti-replay | 5/5 | 5 |
| Pruebas del flujo de aprobación 4d (dos personas, caducidad, entrega de credencial) | 11/11 | 11 |
| **Total combinado** | **25/25 = 100,0 %** | **25** |

Fuente: `fase4-breakglass-dc/README.md`, sección "Validación": *"Batería completa con salidas reales y hallazgos... 9/9 pruebas del agente, 5/5 de la firma HMAC, 11/11 del flujo de aprobación 4d, y verificación por captura de tráfico de que el canal break-glass discurre por `tailscale0`"*.

Sin dispersión que reportar (recuento binario agregado, no una media de sub-muestras con varianza). **Advertencia de alcance:** 100,0 % sobre n=25 pruebas de laboratorio no es evidencia de una tasa de éxito del 98 % objetivo en operación sostenida; son universos distintos (batería de validación puntual vs tasa operativa sobre volumen). Presentar ambas cifras juntas sin esta distinción sería engañoso.

---

## 3. Bonus — las otras dos métricas de la tabla del README (no encargadas, incluidas por completitud)

### 3.1 MTTCollection — Disparo → artefactos en MinIO

**Estado: `CALCULABLE` (parcial, n=2) + `CALCULABLE CON CONSULTA` (para ampliar la muestra).**

Dos duraciones exactas medidas y documentadas en `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md`, sección 9 (Fase 5_4b, 2026-09-17):

| Colección | `started_at` | `ended_at` | Duración |
|---|---|---|---|
| VQL directa (`Windows.System.Pslist` sobre el DC) | — | — | **12,0 s** (dado directamente como duración, sin par de timestamps) |
| Endpoint `/velociraptor/collect` (INC-TEST-5B, perfil `ransomware_triage`) | `20260917T115605Z` | `20260917T115614Z` | **9 s** |

**Cálculo:** media de 2 observaciones = **10,5 s**; rango 3 s (9–12 s). n=2 no permite establecer una dispersión estadística fiable (desviación típica de dos puntos no aporta información más allá del rango). Ambas están muy por debajo del objetivo de `< 10 minutos` de `README.md:183`, pero con una muestra de 2 no se puede afirmar que el objetivo se cumple de forma sistemática — son dos ejecuciones de prueba, no una serie en producción.

**Ampliación posible por consulta** (no ejecutada, ver sección 4): el evento `collection_completed` indexado en `tfm-metrics-events` incluye el campo `duration_ms` (`fase7-observabilidad/README.md`, listado de campos del evento). Una agregación `stats` sobre ese campo, filtrando por `event_type=collection_completed`, daría media/mín/máx/n sobre todas las colecciones registradas en el índice desde que la Fase 7 se instrumentó — muestra potencialmente mayor que las 2 que constan en el registro narrativo.

### 3.2 MTTAccess — Aprobación → acceso activo

**Estado: `NO CALCULABLE`.** Mismo motivo que MTTApprove: no hay instrumentación de `approval_granted` ni `remote_access_started`, y no hay ningún par de timestamps narrado en el registro de mediciones para esta transición concreta.

---

## 4. Consultas propuestas (no ejecutadas)

Solo hay una métrica en estado `CALCULABLE CON CONSULTA` con sentido: la ampliación de MTTCollection. Para las demás (MTTA, MTTApprove, Dedup rate, False positive rate, MTTAccess) **no se propone consulta** porque el propio README de Fase 7 confirma que los eventos necesarios no están instrumentados — una consulta contra un campo que no existe no es una consulta pendiente de ejecutar, es una consulta que no puede devolver nada. No tiene sentido redactarla como si solo faltara "ejecutarla".

### 4.1 Distribución de `duration_ms` de las colecciones registradas

```bash
# Sustituir $OS_PASS por la contraseña real del indexador (fase1-infraestructura/wazuh/single-node/.env,
# variable INDEXER_PASSWORD tras su rotación por el P0-3). No transcribir el valor en ningún fichero.
curl -sk -u "admin:${OS_PASS:?exporta OS_PASS antes de ejecutar}" \
  -H 'Content-Type: application/json' \
  "https://localhost:9200/tfm-metrics-events/_search?pretty" \
  -d '{
    "size": 0,
    "query": { "term": { "event_type.keyword": "collection_completed" } },
    "aggs": {
      "duracion": { "stats": { "field": "duration_ms" } }
    }
  }'
```

Qué campo de la respuesta contiene el dato buscado: `aggregations.duracion.count` (n), `.avg`, `.min`, `.max` (en milisegundos; dividir entre 1000 para segundos, comparable con los 9 s / 12,0 s ya documentados).

### 4.2 Recuento total de eventos por tipo (para contextualizar cualquier cifra anterior)

```bash
curl -sk -u "admin:${OS_PASS:?exporta OS_PASS antes de ejecutar}" \
  -H 'Content-Type: application/json' \
  "https://localhost:9200/tfm-metrics-events/_search?pretty" \
  -d '{
    "size": 0,
    "aggs": {
      "por_tipo": { "terms": { "field": "event_type.keyword" } }
    }
  }'
```

Qué campo de la respuesta contiene el dato buscado: `aggregations.por_tipo.buckets[].key` (el tipo de evento) y `.doc_count` (cuántos hay de cada uno) — permite saber si los 404 documentos citados en `fase7-observabilidad/README.md` incluyen colecciones suficientes para que la consulta 4.1 tenga un n mayor que 2.

---

## 5. Resumen de estado

| Métrica | Estado | n (si aplica) |
|---|---|---|
| MTTA | `NO CALCULABLE` | — |
| MTTApprove | `NO CALCULABLE` | — |
| Agent Precision (según definición del README) | `NO CALCULABLE` — declarado fuera de alcance por el propio proyecto | — |
| Agent Precision (proxy: concordancia con el motor determinista) | `CALCULABLE` (no es la misma métrica) | 30 |
| Dedup rate | `NO CALCULABLE` | — |
| False positive rate | `NO CALCULABLE` | — |
| Script success rate | `CALCULABLE` (tasa de superación de la batería de Fase 4, no tasa operativa) | 25 |
| MTTCollection (bonus) | `CALCULABLE` parcial + `CALCULABLE CON CONSULTA` para ampliar | 2 |
| MTTAccess (bonus) | `NO CALCULABLE` | — |

**De las seis métricas encargadas: dos son calculables** (Agent Precision solo como proxy redefinido y con advertencia explícita de que no es la métrica que el README nombra; Script success rate como tasa de superación de una batería de pruebas de laboratorio, no como tasa operativa). **Las otras cuatro no lo son**, por dos motivos distintos que conviene no mezclar en la presentación: (a) el dato no se emite porque la instrumentación necesaria está declarada como trabajo futuro (MTTA, MTTApprove), o (b) el mecanismo es deliberadamente efímero y no deja registro (Dedup rate), o (c) la propia definición operativa de la métrica es ambigua en el repositorio y no hay ningún documento que la resuelva (False positive rate).

## 6. Limitaciones metodológicas

- **Tamaño muestral.** Ninguna de las cifras calculadas supera n=30. Agent Precision (proxy) y el banco de rendimiento de Fase 3 usan un corpus sintético de 30 alertas diseñado para cubrir el rango de severidad, no una muestra representativa de tráfico real. Script success rate (25/25) es el resultado de una batería de validación puntual, no una serie temporal.
- **Laboratorio no permanente.** Aplica a cualquier intento futuro de calcular Dedup rate o False positive rate con datos reales: `docs/REGISTRO-MEDICIONES...md` (M-24) ya advierte que el laboratorio no está encendido de forma continua, así que cualquier recuento sobre el histórico de Wazuh sería "cuántas veces ocurrió mientras el laboratorio estuvo vivo", no una tasa por unidad de tiempo.
- **Mezcla de datos reales y sintéticos.** El índice `tfm-metrics-events` combina pruebas manuales con una carga sintética de 200 eventos (`fase7-observabilidad/README.md`). Cualquier consulta de la sección 4 devolvería una mezcla de ambos sin forma de separarlos por el esquema documentado, salvo que exista un campo adicional no descrito en el README (a comprobar si se ejecuta la consulta).
- **La batería de inyección de Fase 3 usa un único modelo (Mistral 7B).** Cualquier cifra de la sección 2.3 que se generalice a "los LLM" en vez de a "este modelo en esta configuración" excede lo que los datos permiten afirmar — el propio README lo señala como pregunta abierta.
- **No se ha intentado calcular nada a partir de datos crudos no versionados** (por ejemplo, los ficheros de alertas de Wazuh que pudieran existir fuera del repositorio en el sistema anfitrión). Esta decisión es deliberada: el encargo pide evaluar qué es calculable a partir del material ya registrado en el repositorio, no producir análisis nuevos sobre datos operativos en vivo.
