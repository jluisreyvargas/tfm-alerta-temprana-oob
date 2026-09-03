# Informe — Fase B del P0-4 (autenticación HMAC del orchestrator)

## Alcance

`POST /velociraptor/collect` del orchestrator (`fase5-orchestrator-api`) no
exigía ninguna credencial. La Fase 2 firma las alertas entrantes y la Fase 4c
firma las órdenes al DC con ventana temporal y anti-replay; este endpoint era la
única desviación del patrón. Esta fase le añade verificación HMAC y valida la
entrada que construye las claves de objeto en MinIO.

No se ha ejecutado `git add`, `git commit`, `git push` ni `git rm`. No se ha
tocado el índice. No se ha tocado Docker. No se ha generado ningún secreto ni se
ha leído `ORCH_HMAC_SECRET` del `.env` de despliegue. No se ha borrado ningún
fichero del árbol de trabajo (el `__pycache__` que dejó `py_compile` durante la
verificación se ha eliminado por ser un artefacto transitorio propio).

## Ficheros

### Modificados

**`fase5-orchestrator-api/main.py`**

- Bloque de configuración nuevo:
  - `ORCH_REQUIRE_HMAC = os.environ.get("ORCH_REQUIRE_HMAC", "true").lower() == "true"`.
    Default `true`, con comentario que explica por qué difiere de la Fase 4c.
  - `ORCH_HMAC_SECRET` se lee con `os.environ["ORCH_HMAC_SECRET"]` (sin default)
    cuando `ORCH_REQUIRE_HMAC` es `true`: si falta, el proceso aborta al arrancar
    con `KeyError`. Con `false` se cae a `.get(..., "")`.
  - `MAX_SKEW = 300` (mismo valor que la Fase 4c).
  - `_seen_nonces: dict[str, float] = {}`.
- `verify_signature(request, body)` asíncrona, equivalente a la de `agent_dc.py`.
  Orden de comprobaciones: cabeceras presentes → timestamp parseable → dentro de
  ventana → purga de nonces anteriores a `MAX_SKEW` → nonce no visto → firma
  correcta. La firma se comprueba **en último lugar**: hacerlo antes que el
  anti-replay permitiría distinguir por temporización si un nonce ya se había
  usado. Firma: `hmac.new(SECRET, f"{ts}.{nonce}.".encode() + body, sha256).hexdigest()`,
  hex sin prefijo, comparada con `hmac.compare_digest`. Cabeceras
  `x-timestamp` / `x-nonce` / `x-signature`. Códigos: `400` faltan cabeceras /
  timestamp inválido o fuera de ventana · `409` replay · `403` firma inválida ·
  `500` secreto no configurado. Rechazos registrados con `logger.warning(...)`.
- El endpoint pasa a recibir `Request` y el cuerpo crudo:
  ```python
  @app.post("/velociraptor/collect")
  async def collect(request: Request):
      body = await request.body()
      await verify_signature(request, body)
      try:
          req = CollectRequest.model_validate_json(body)
      except ValidationError as e:
          raise HTTPException(status_code=422, detail=json.loads(e.json()))
  ```
  La firma se verifica **antes** de validar el modelo, para no exponer la lógica
  de validación a peticiones no autenticadas. Se firma y se valida el mismo byte
  string; no hay reserialización (misma razón documentada en el nodo *Code* de
  `fase2-orquestador/n8n/workflows/wazuh-alert-handler.json`).
- `CollectRequest`: `incidentid` y `host` pasan a
  `Field(pattern=r"^[A-Za-z0-9._-]{1,64}$")`. Comentario en el modelo con el
  motivo: ambos construyen la clave del objeto en MinIO
  (`f"{req.incidentid}/{req.host}/{ts}/manifest.json"`); sin validar permiten
  escribir en rutas arbitrarias del bucket y sobrescribir el manifiesto de otro
  incidente — el usuario `tfm-orchestrator` no puede borrar objetos (política
  `evidence-writer`, sin `s3:DeleteObject`) pero sí sobrescribirlos, comprobado
  en el P0-3.
- `source` pasa a `Field(default=None, pattern=r"^[A-Za-z0-9._-]{1,64}$")`. Ver
  «Decisión sobre `source`» más abajo.
- Imports: `Request` (fastapi); `Field`, `ValidationError` (pydantic); `hmac`.
- **Sin cambios**: lógica de MinIO, `log_event()` protegido, medición de
  `duration_ms`, allowlist de perfiles, endpoint `/health`.

**`fase5-orchestrator-api/.env.example`**

- Añadidos `ORCH_HMAC_SECRET=` (vacío) y `ORCH_REQUIRE_HMAC=true`, con comentario
  que describe el mecanismo (firma sobre `{ts}.{nonce}.` + cuerpo crudo, ventana
  de 300 s, anti-replay por nonce), el motivo del default `true` y la remisión a
  `fase4-breakglass-dc/dcagent/agent_dc.py` como implementación de referencia.

### Creados

**`scripts/collect-signed.sh`** (ejecutable)

Cliente de prueba. `Uso: collect-signed.sh <incidentid> <host> <profile> [source]`.

- Lee `ORCH_HMAC_SECRET` de `fase5-orchestrator-api/.env` (última aparición,
  `cut -d= -f2-` para conservar `=` internos, recorte de comillas y CR). Nunca lo
  imprime ni lo pasa por `argv`: se entrega al proceso Python por entorno.
- El cuerpo JSON se genera **una sola vez** en Python, se escribe a un fichero
  temporal, y ese mismo fichero es el que se firma y el que `curl` envía con
  `--data-binary @fichero`. No hay reserialización posible entre firmar y enviar.
- Firma `HMAC_SHA256(secret, "{ts}.{nonce}." + cuerpo)`, hex sin prefijo. `ts` es
  epoch entero; `nonce` es `secrets.token_hex(16)`.
- Imprime `HTTP <código>` y el cuerpo de la respuesta.
- Variables de entorno, documentadas en la cabecera: `ORCH_URL`
  (default `http://127.0.0.1:8020`), `SIGN_TS` (forzar timestamp), `SIGN_NONCE`
  (forzar nonce → replay), `SIGN_CORRUPT=1` (alterar el último carácter de la
  firma).
- `set -euo pipefail`; comprueba que el `.env` existe y define el secreto no
  vacío; guarda contra fallo silencioso de Python (`${#sig} -ne 64`).

## Diferencias deliberadas respecto a `agent_dc.py`

| # | Diferencia | Motivo |
|---|---|---|
| 1 | `ORCH_REQUIRE_HMAC` default **`true`** (la Fase 4c usa `false`) | La Fase 4c migraba desde Bearer con un parque en producción y necesitaba fase de transición. Aquí no hay consumidores activos; un interruptor cuyo default desactiva el control es la misma clase de fallo que un default inseguro. |
| 2 | Secreto con `os.environ[...]` sin default cuando el HMAC es obligatorio | Fallo ruidoso al arrancar. `agent_dc.py` siempre usa `.get(..., "")` y solo falla al recibir la primera petición. |
| 3 | No hay capa Bearer además del HMAC | `agent_dc.py` mantiene `verify_token` + HMAC porque ya tenía token desplegado. Aquí no había ninguna autenticación previa y el patrón servicio-a-servicio del proyecto es la firma (Fase 2, Fase 4c). Añadir un token estático obligaría a inventar un segundo secreto. |
| 4 | Rechazos con `logger.warning()` sobre el logger de módulo, no un `RotatingFileHandler` | El orchestrator registra a stdout con `PYTHONUNBUFFERED=1` y Docker lo captura; es coherente con el `logger.warning` ya presente para la métrica. `agent_dc.py` corre como servicio Windows y necesita su propio fichero. |
| 5 | Validación de `incidentid` / `host` / `source` con `Field(pattern=...)` | Específico de este endpoint: esos campos construyen la clave del objeto en MinIO. `agent_dc.py` valida `target` con `TARGET_RE`, pero por otro motivo (argument injection en Windows). |
| 6 | Error de validación del modelo → `422` vía `except ValidationError` | Idiomático de FastAPI con un modelo Pydantic. `agent_dc.py` hace `json.loads` + comprobaciones manuales de dict y devuelve `400`. |

## Decisión sobre `source`

`source` llega del payload, se guarda en `manifest.json` y está previsto que
llegue al índice de métricas (hoy `log_event(...)` pasa `source="orchestrator"`
fijo; el valor del payload solo entra en el manifiesto). **No** construye la
clave del objeto, así que no es vector de path traversal. Aun así es texto libre
de un payload que hasta ahora entraba sin autenticar: sin cota permite
documentos sobredimensionados en el manifiesto y en el índice, y caracteres de
control en un campo que viaja a un almacén y a un motor de triaje.

Decisión: acotarlo a la misma forma que `incidentid` / `host`
(`^[A-Za-z0-9._-]{1,64}$`). Sin consumidores activos, el coste de restringirlo
ahora es nulo y evita tener que relajar un formato ya asumido más adelante.
**A revisar**: si algún consumidor legítimo necesita enviar `source` con
espacios o texto descriptivo, habrá que ampliar el patrón (p. ej. permitir
espacio y `:`), no eliminarlo.

## Verificación estática

```
$ python3 -m py_compile main.py   → sintaxis OK: main.py
$ bash -n scripts/collect-signed.sh → script OK: collect-signed.sh
```

### Prueba de coherencia de firma

`py_compile` no ejecuta el módulo, así que el `os.environ[...]` de MinIO no
aborta. El servicio real corre en Docker con `fastapi`/`pydantic`/`minio`, que no
están en el Python del host; para ejercitar el **bytecode real** de
`verify_signature()` se inyectaron stubs mínimos de esas dependencias en
`sys.modules` (`HTTPException` como excepción real; el resto no-ops). El HMAC, la
ventana y el anti-replay son código puro de la biblioteca estándar y se ejecutan
tal cual están en `main.py`.

El arnés (`scratchpad/sigtest.py`, fuera del repo) levanta un servidor de captura
local, ejecuta `collect-signed.sh` contra él con un secreto **ficticio** y un
árbol de directorios de usar y tirar, y coteja lo enviado con
`verify_signature()`:

```
OK  firma script == recalculo manual
OK  verify_signature() acepta la firma del script
OK  el script no imprime el secreto
OK  firma alterada -> 403
OK  primer envio con nonce fijo aceptado
OK  replay -> 409
OK  timestamp viejo -> 400
OK  patron acepta INC-2026-042
OK  patron acepta HOST-DC01
OK  patron acepta TEST-COLLECT-01
OK  patron acepta HOST-02
OK  patron rechaza '../evil'
OK  patron rechaza 'INC 2026'
OK  patron rechaza 'aaa…' (65 caracteres)
OK  patron rechaza 'INC/2026'

TODAS LAS COMPROBACIONES OK
```

El HMAC calculado por `collect-signed.sh` y el recalculado sobre los bytes
recibidos coinciden, y `verify_signature()` de `main.py` acepta esa firma. Los
cuatro identificadores del histórico pasan el patrón.

## Pruebas que debe ejecutar el usuario

Requisito previo: desplegar el orchestrator con el código nuevo y con
`ORCH_HMAC_SECRET` definido en `fase5-orchestrator-api/.env` (ya está). MinIO
debe estar accesible para que el caso 2 llegue a `200`; si no, devolverá
`500 MinIO error` aunque la firma sea válida.

Desde `~/tfm-alerta-temprana-oob`:

| # | Caso | Comando | HTTP esperado |
|---|---|---|---|
| 1 | Sin firma | `curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8020/velociraptor/collect -H 'Content-Type: application/json' -d '{"incidentid":"INC-2026-042","host":"HOST-DC01","profile":"credential_dump_collection"}'` | `400` (Missing signature headers) |
| 2 | Firma válida | `scripts/collect-signed.sh INC-2026-042 HOST-DC01 credential_dump_collection` | `200`, cuerpo `{"status":"queued",...}` |
| 3 | Replay | `SIGN_NONCE=fijo-01 scripts/collect-signed.sh INC-2026-042 HOST-DC01 credential_dump_collection` dos veces seguidas | 1ª: `200` · 2ª: `409` (Replay detected) |
| 4 | Timestamp fuera de ventana | `SIGN_TS=1000000000 scripts/collect-signed.sh INC-2026-042 HOST-DC01 credential_dump_collection` | `400` (Timestamp outside window) |
| 5 | Firma alterada | `SIGN_CORRUPT=1 scripts/collect-signed.sh INC-2026-042 HOST-DC01 credential_dump_collection` | `403` (Bad signature) |
| 6 | `incidentid` inválido | `scripts/collect-signed.sh 'INC/2026' HOST-DC01 credential_dump_collection` | `422` (error de patrón; la firma es válida, el rechazo es del modelo) |
| 7 | `incidentid` demasiado largo | `scripts/collect-signed.sh "$(python3 -c 'print("A"*65)')" HOST-DC01 credential_dump_collection` | `422` |

Casos adicionales que conviene pasar una vez:

| # | Caso | Comando | HTTP esperado |
|---|---|---|---|
| 8 | Perfil no permitido (firma válida) | `scripts/collect-signed.sh INC-2026-042 HOST-DC01 perfil_inexistente` | `400` (Profile not allowed) |
| 9 | `source` inválido | `scripts/collect-signed.sh INC-2026-042 HOST-DC01 credential_dump_collection 'origen con espacios'` | `422` |
| 10 | Cabeceras incompletas | `curl` del caso 1 añadiendo solo `-H 'x-timestamp: 123'` | `400` (Missing signature headers) |

Tras el caso 2, comprobar en MinIO que existe
`s3://evidence/INC-2026-042/HOST-DC01/<timestamp>/manifest.json` y que su campo
`source` es `null` (o el valor pasado, si se usó el argumento opcional).

## Decisiones que conviene revisar

1. **`source`**: acotado al patrón de `incidentid`/`host`. Si un consumidor
   necesita texto descriptivo, ampliar el patrón, no quitarlo (ver sección
   dedicada).
2. **`_seen_nonces` en memoria de proceso**: el anti-replay es por proceso. El
   `docker-compose.yml` arranca un único contenedor con el `uvicorn` por
   defecto (un worker), así que hoy es efectivo. Si se escala a varios workers o
   réplicas, una petición reenviada a otro worker dentro de la ventana de 300 s
   no se detectaría. Misma propiedad que `agent_dc.py`. Si se escala, mover el
   registro de nonces a un almacén compartido.
3. **Sin cota de tamaño de `_seen_nonces`**: solo hay purga temporal. Un flujo de
   nonces distintos dentro de la ventana hace crecer el diccionario hasta la
   siguiente purga. Aceptable para el volumen previsto (una colección por
   incidente); misma propiedad que la Fase 4c.
4. **Rama `500` «HMAC secret not set» parcialmente inalcanzable**: con
   `ORCH_REQUIRE_HMAC=true` el arranque ya falla si la variable no existe. La
   rama sigue cubriendo el caso de variable presente pero vacía
   (`ORCH_HMAC_SECRET=`) y se mantiene por paridad con la referencia y como
   defensa en profundidad.
5. **`json.loads(e.json())` en el `422`**: expone la estructura de errores de
   Pydantic (nombres de campo, tipo de restricción) en la respuesta. Es
   consistente con el comportamiento por defecto de FastAPI para `RequestValidationError`
   y solo se alcanza tras verificar la firma, así que el consumidor ya está
   autenticado. Si se prefiere no revelar el detalle, sustituir por un `detail`
   genérico.

## `git status --porcelain`

```
 M .gitignore
 M fase5-orchestrator-api/.env.example
 M fase5-orchestrator-api/main.py
?? docs/evidencias/
?? fase6-iris/docker-compose.override.yml
?? scripts/collect-signed.sh
```

De esas entradas, esta fase ha tocado tres: `fase5-orchestrator-api/main.py`,
`fase5-orchestrator-api/.env.example` y `scripts/collect-signed.sh` (nuevo). El
informe `docs/INFORME-P0-4-implementacion.md` es también nuevo y aparecerá al
refrescar el estado. El resto (`.gitignore`, `docs/evidencias/`,
`fase6-iris/docker-compose.override.yml`) es previo y ajeno.
