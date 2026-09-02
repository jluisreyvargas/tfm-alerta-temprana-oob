# Informe — Fase H del P0-3 (limpieza de documentación y defectos de código)

La remediación técnica del P0-3 (rotación de credenciales root de MinIO, usuario
dedicado `tfm-orchestrator`, eliminación de defaults inseguros) estaba completa y
commiteada en `af08428` antes de esta sesión. Aquí se documenta el cierre: la
limpieza de documentación, la corrección de cuatro defectos de código aparecidos
durante el diagnóstico, y el registro del incidente en el aviso de seguridad.

No se ha ejecutado ningún `git add`, `git commit`, `git rm` ni `git mv`. No se ha
tocado Docker. No se ha borrado ningún fichero del árbol de trabajo. No se ha
generado ningún secreto.

El argumento que atraviesa el incidente: **un control ausente o inefectivo no se
manifiesta como un error, sino como operación normal**. El P0-3 aporta tres
variantes:

1. Un valor por defecto (`${MINIO_ROOT_PASSWORD:-<default publicado>}`) convirtió
   la ausencia de `.env` en un almacén de evidencia con credencial pública, sin
   ningún error.
2. Un aviso correctamente escrito (`print("[metrics_client] WARN: ...")`) no
   llegó durante 21 días por una propiedad del entorno de ejecución ajena a la
   lógica: el buffer de stdout sin `PYTHONUNBUFFERED`.
3. Una verificación de política pasó en verde porque se hizo con `mc`, una
   herramienta distinta del SDK de Python que usa el orchestrator.

---

## 1. Ficheros creados y modificados

### Creados

| Fichero | Justificación |
|---|---|
| `fase5-velociraptor/.env.example` | TAREA 3. Renombrado de `env.example` a `.env.example` para alinear con la convención de `fase5-orchestrator-api/`. Como no se puede tocar el índice, se crea el fichero nuevo y se deja el antiguo; el `git mv` queda como acción pendiente (§3). Contenido: `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` vacíos con comentario, `VELOCIRAPTOR_API` / `VELOCIRAPTOR_GUI` corregidos (faltaba la «O»), `IRIS_URL` actualizado a `https://iris.oob.local:4833` (valor real tras el P0-2). |
| `docs/INFORME-P0-3.md` | Este informe. |

### Modificados

| Fichero | Justificación |
|---|---|
| `fase5-orchestrator-api/README.md` | TAREA 1. (a) Retiradas las credenciales por defecto de MinIO de la tabla de variables y del texto: ahora se documentan sin valor, remitiendo a `.env.example`. (b) Bloque `docker-compose.yml` incrustado sustituido por copia literal del fichero real: le faltaban `env_file`, la red `single-node_default`, las variables `OS_*`, el volumen de la Fase 7 y `PYTHONUNBUFFERED`. (c) Eliminada la fila «Estado observado: Up 23 hours» de la tabla de redes y puertos (dato de runtime en documentación). (d) Documentado que el orchestrator usa el usuario `tfm-orchestrator` con la política `evidence-writer` (sin `s3:DeleteObject`), no credenciales root. (e) Aviso `[!CAUTION]` al inicio remitiendo a `fase5-velociraptor/SECURITY-NOTICE.md`. (f) Añadidos a «Limitaciones conocidas» y «Próximos pasos» los riesgos residuales (bucket sin versionado, `incidentid`/`host` sin validar). |
| `fase5-orchestrator-api/.env.example` | TAREA 2. Añadidos `MINIO_ACCESS_KEY` y `MINIO_SECRET_KEY` con valor vacío y comentario que explica el motivo (default publicado, usuario dedicado), en la misma línea argumental que el comentario que ya existía para `OS_PASS`. |
| `fase5-velociraptor/env.example` | TAREA 3. `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` vaciados con comentario; `VELCIRAPTOR_API` → `VELOCIRAPTOR_API`, `VELCIRAPTOR_GUI` → `VELOCIRAPTOR_GUI` (comprobado antes: ningún fichero del repo consume esos nombres, solo el propio `env.example`); `IRIS_URL` de `https://iris.example.local` a `https://iris.oob.local:4833`. Fichero conservado; el `git mv` a `.env.example` queda pendiente. |
| `fase7-observabilidad/shared/metrics_client.py` | TAREA 4. `print()` de la línea 48 sustituido por `logging.warning()`, con `import logging` y `logger = logging.getLogger(__name__)` a nivel de módulo. Motivo: `print` depende del buffer de stdout, que es lo que ocultó este fallo 21 días; `logging` respeta la configuración de la aplicación y añade nivel y marca de tiempo. La lógica del `except` no se toca: capturar la excepción es correcto, la colección forense no debe fallar porque la telemetría esté caída. Fichero compartido por Fase 3 y Fase 5; la Fase 3 ya usa `logger` en su `main.py`, el cambio es compatible. |
| `fase5-orchestrator-api/main.py` | TAREA 5. (5.1) La llamada a `log_event()` posterior a la persistencia en MinIO se envuelve en `try/except` con `logging.warning()`: un fallo de telemetría con la evidencia ya escrita devolvía 500, n8n reintentaba y se generaban duplicados (ocurrió durante la remediación). (5.2) `duration_ms=0` hardcodeado sustituido por medición real con `time.monotonic()` alrededor de las escrituras en MinIO, en milisegundos. Añadidos `import logging`, `import time` y un `logger` de módulo. |
| `fase5-velociraptor/SECURITY-NOTICE.md` | TAREA 7. Nueva sección para el P0-3 tras la del P0-1, mismo tono: naturaleza (credenciales por defecto en repo público, en uso real por ausencia de `.env`), detección dual (auditoría interna + GitGuardian 2026-09-02 17:25 UTC), cadena de impacto (endpoint sin autenticar → `Windows.Memory.Acquisition` sobre el DC → bucket con credenciales publicadas), corrección aplicada y verificaciones, los tres hallazgos del diagnóstico, decisión razonada de no purgar el historial (con el contraste frente al P0-1), y riesgos residuales (sobrescritura, bucket sin versionado, `incidentid`/`host` sin validar, MinIO sin TLS en `0.0.0.0`, `minio/minio:latest` sin fijar). |
| `scripts/verify-no-secrets.sh` | TAREA 6. Añadida la regla `credencial-conocida` mediante una función `scan_all()` nueva (como `scan()` pero con `git grep -a`, recorre binarios; el `.pyc` de `metrics_client` que llevaba la contraseña por defecto del indexador en su tabla de constantes estaba trackeado y el script daba 0 hallazgos por no existir la regla, no por ser binario). La lista de credenciales conocidas y por defecto que reconoce la regla está definida en el propio script (constante de `scan_all` y comentario de cabecera); el patrón está anclado por límites no alfabéticos para evitar un falso positivo de un marcador de posición que aparece como subcadena de una palabra francesa en `fase8-kvm`. Nunca imprime el valor, solo ruta y línea. |

### Presente en el árbol por la remediación técnica (`af08428`), no tocado en esta sesión

| Fichero | Estado |
|---|---|
| `fase5-orchestrator-api/docker-compose.yml` | `env_file: .env`, red `single-node_default`, variables `OS_*`, `PYTHONUNBUFFERED: "1"`, volumen de la Fase 7 en `:ro`. Es la referencia desde la que se ha copiado el bloque incrustado del README. |
| `fase5-velociraptor/docker-compose.yml` | Servicio `minio`: defaults `:-` sustituidos por `:?` (líneas 26-27) en la remediación técnica. El servicio `minio-init` (líneas 48-49) conservó el default `:-` hasta después de la Fase H — ver §4, hallazgo E, **ya resuelto por el usuario** (líneas 26, 27, 48, 49 usan `:?` en ambos servicios). |
| `fase5-velociraptor/.env` (sin trackear, modo 600) | Creado en la remediación con las credenciales rotadas. Excluido por `.gitignore` (`**/.env`). No se ha leído ni impreso. |

---

## 2. Salida literal de `verify-no-secrets.sh`

Ejecutado tras todos los cambios de esta sesión:

```
$ ./scripts/verify-no-secrets.sh
  HALLAZGO  docs/README-fase1d-wazuh.md:216  [credencial-conocida]
  HALLAZGO  docs/README-fase1d-wazuh.md:247  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:113  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:115  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:117  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:120  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:121  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:123  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:125  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:132  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:143  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:153  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:154  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:183  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:257  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:264  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:266  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:268  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:271  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:272  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:274  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:276  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:282  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:292  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:299  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:309  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:310  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/.github/workflows/push.yml:346  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/docs/ref/configuration/environment-variables.md:22  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/docs/ref/configuration/environment-variables.md:61  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/multi-node/docker-compose.yml:21  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/multi-node/docker-compose.yml:59  [credencial-conocida]
  HALLAZGO  fase1-infraestructura/wazuh/single-node/.env.example:4  [credencial-conocida]
  HALLAZGO  fase3-agentic/.env.example:7  [credencial-conocida]
  HALLAZGO  fase5-orchestrator-api/.env.example:4  [credencial-conocida]
  HALLAZGO  fase5-orchestrator-api/.env.example:12  [credencial-conocida]
  HALLAZGO  fase5-orchestrator-api/README.md:232  [credencial-conocida]
  HALLAZGO  fase5-velociraptor/SECURITY-NOTICE.md:139  [credencial-conocida]
  HALLAZGO  fase5-velociraptor/SECURITY-NOTICE.md:146  [credencial-conocida]
  HALLAZGO  fase5-velociraptor/SECURITY-NOTICE.md:167  [credencial-conocida]
  HALLAZGO  fase5-velociraptor/SECURITY-NOTICE.md:174  [credencial-conocida]
  HALLAZGO  fase5-velociraptor/SECURITY-NOTICE.md:186  [credencial-conocida]
  HALLAZGO  fase5-velociraptor/SECURITY-NOTICE.md:187  [credencial-conocida]
  HALLAZGO  fase5-velociraptor/SECURITY-NOTICE.md:192  [credencial-conocida]
  HALLAZGO  fase5-velociraptor/SECURITY-NOTICE.md:219  [credencial-conocida]
  HALLAZGO  fase5-velociraptor/SECURITY-NOTICE.md:250  [credencial-conocida]
  HALLAZGO  fase5-velociraptor/SECURITY-NOTICE.md:253  [credencial-conocida]
  HALLAZGO  fase5-velociraptor/docker-compose.yml:48  [credencial-conocida]
  HALLAZGO  fase5-velociraptor/docker-compose.yml:49  [credencial-conocida]
  HALLAZGO  fase5-velociraptor/env.example:4  [credencial-conocida]
  HALLAZGO  fase5-velociraptor/env.example:13  [credencial-conocida]
  HALLAZGO  fase7-observabilidad/README.md:95  [credencial-conocida]
  HALLAZGO  fase7-observabilidad/README.md:125  [credencial-conocida]
  HALLAZGO  fase7-observabilidad/README.md:126  [credencial-conocida]
  HALLAZGO  fase7-observabilidad/README.md:131  [credencial-conocida]
  HALLAZGO  fase7-observabilidad/README.md:190  [credencial-conocida]

FALLO: 56 hallazgos sobre 1752 ficheros trackeados.
$ echo $?
1
```

Las reglas heredadas del P0-1 (PEM, `private_key`, `password_hash`,
`password_salt`, `obfuscation_nonce`, `nonce`, base64 largo) siguen en **0
hallazgos**. Los 56 son todos de la regla `credencial-conocida` añadida en la
TAREA 6.

Al cierre de la Fase H ninguno se había corregido: la instrucción era
reportarlos y dejar la decisión (reformular la documentación o acotar la regla)
al usuario. Análisis por categorías en §4. **Los 56 se resolvieron en la sesión
siguiente** — ver la nota al inicio de §4 y `docs/INFORME-hallazgos-detector.md`.

---

## 3. Acciones pendientes para el usuario, en orden

1. **Revisar los cambios.** `git diff` sobre los siete ficheros modificados y el
   nuevo `fase5-velociraptor/.env.example`.

2. **Completar el renombrado de la TAREA 3.** El fichero nuevo
   `fase5-velociraptor/.env.example` ya existe en el árbol de trabajo; el antiguo
   `fase5-velociraptor/env.example` sigue trackeado con contenido idéntico.
   Consolidar el renombrado en el índice:

   ```
   rm fase5-velociraptor/.env.example        # descartar la copia sin trackear
   git mv fase5-velociraptor/env.example fase5-velociraptor/.env.example
   ```

   (equivalente: `git rm fase5-velociraptor/env.example` + `git add
   fase5-velociraptor/.env.example`).

3. **Preparar el commit de la Fase H.** Añadir a mano los siete modificados, el
   `.env.example` renombrado y `docs/INFORME-P0-3.md`. **No** añadir ningún
   `.env`.

4. **Aplicar el commit** manualmente.

5. **Recrear los contenedores afectados por los cambios de código.** Los cambios
   en `fase7-observabilidad/shared/metrics_client.py` (TAREA 4) y
   `fase5-orchestrator-api/main.py` (TAREA 5) requieren recrear:
   - **Fase 3** (`fase3-agentic/`): monta `shared/` con `metrics_client.py`.
   - **Fase 5** (`fase5-orchestrator-api/`): usa ambos ficheros.

   `docker compose up -d --build` en cada carpeta. Comprobar después con un
   `POST /triage` (Fase 3) y un `POST /velociraptor/collect` (Fase 5) que el
   `logging.warning` aparece en los logs y que `duration_ms` en el evento
   `collection_completed` ya no es 0.

6. **Los 56 hallazgos de `verify-no-secrets.sh`** (§4) se resolvieron en la
   sesión siguiente: reformulación de la documentación propia para describir en
   vez de citar, y dos exclusiones acotadas (árbol vendorizado de Wazuh y
   marcadores de posición en ficheros de ejemplo), solo sobre la regla
   `credencial-conocida`. El detector vuelve a `exit 0`. Detalle en
   `docs/INFORME-hallazgos-detector.md`.

7. **El hallazgo E** (`fase5-velociraptor/docker-compose.yml`, servicio
   `minio-init`) lo resolvió el usuario: los cuatro usos de `MINIO_ROOT_USER` /
   `MINIO_ROOT_PASSWORD` (líneas 26, 27, 48, 49) usan `:?`. Ver §4, hallazgo E.

---

## 4. Apariciones residuales de credenciales por defecto

Los 56 hallazgos, agrupados. Estado al cierre de la Fase H.

> **Nota posterior.** Los 56 se resolvieron en la sesión siguiente
> (`docs/INFORME-hallazgos-detector.md`): las categorías A y C con dos
> exclusiones acotadas de la regla `credencial-conocida`, y B y D reformulando
> la documentación propia para describir en vez de citar. El hallazgo E lo
> corrigió el usuario. Esta sección se conserva como registro del inventario
> tal como se levantó.

### A · Árbol vendorizado de Wazuh — 33 hallazgos

`fase1-infraestructura/wazuh/` es el proyecto upstream `wazuh-docker` completo,
no código del proyecto (ver `CLAUDE.md`). Las apariciones (el usuario y la
contraseña por defecto del propio upstream en `.github/workflows/push.yml`,
`docs/ref/configuration/environment-variables.md`,
`multi-node/docker-compose.yml`, `single-node/.env.example`) son defaults del
propio Wazuh.

**Motivo de conservarlas:** modificarlas divergiría del upstream sin ganancia,
igual que se decidió con las ocho apariciones de `iris.local` en
`fase6-iris/source/` durante el cierre de P0-1/P0-2.
**Resuelto (sesión siguiente):** exclusión acotada a `fase1-infraestructura/wazuh/`
en la regla `credencial-conocida`, y solo en esa regla. Las reglas ancladas
(PEM, `private_key`, `nonce`, base64 largo) siguen recorriendo ese árbol.

### B · Documentación del incidente P0-3 — 15 hallazgos

En la Fase H, estos literales se conservaron como explicación exacta del
incidente.

| Fichero | Líneas | Contenido |
|---|---|---|
| `fase5-velociraptor/SECURITY-NOTICE.md` | 139, 146, 167, 174, 186, 187, 192, 219, 250, 253 | Sección P0-3: ubicaciones afectadas, el default del compose, el hallazgo 1 (contraseña por defecto del indexador arrastrada), el `.pyc`, la decisión de no purgar. |
| `fase5-orchestrator-api/README.md` | 232 | Aviso `[!IMPORTANT]` de variables de entorno: cita el default publicado como causa del P0-3. |
| `fase5-orchestrator-api/.env.example` | 4, 12 | Comentarios que describían la contraseña por defecto del indexador y el default del compose como causa. |
| `fase3-agentic/.env.example` | 7 | Comentario equivalente sobre la contraseña por defecto del indexador (preexistente). |
| `fase5-velociraptor/env.example` | 4 | Comentario sobre el default de MinIO (añadido en TAREA 3). |

**Resuelto (sesión siguiente):** reformulados para describir en vez de citar
—«las credenciales por defecto de MinIO», «el valor por defecto del compose»—.
Un aviso de seguridad no necesita reproducir la credencial para explicar qué
pasó. Este mismo informe se reformuló con el mismo criterio.

### C · Placeholder de configuración — 1 hallazgo

`fase5-velociraptor/env.example:13` → `IRIS_API_KEY` con un marcador de
posición. No es un secreto real, pero encajaba en la regla nueva. Fuera del
alcance de la TAREA 3 (que solo enumera `MINIO_ROOT_*`, `VELOCIRAPTOR_*` e
`IRIS_URL`).
**Resuelto (sesión siguiente):** excepción acotada en la regla: en un
`*.env.example` / `env.example`, un marcador de ese tipo se descarta solo si en
la línea no hay además una credencial real. No se excluye el fichero.

### D · Documentación propia del proyecto con referencias obsoletas — 7 hallazgos

| Fichero | Líneas | Contenido |
|---|---|---|
| `fase7-observabilidad/README.md` | 95, 125, 126, 131, 190 | Mostraba las credenciales por defecto de MinIO y la contraseña por defecto del indexador (en bloques de compose incrustados y en un `curl`) como configuración vigente. |
| `docs/README-fase1d-wazuh.md` | 216, 247 | Un `curl` con la contraseña por defecto embebida y una tabla que la documentaba como credencial de emergencia de OpenSearch. |

**Motivo (Fase H):** el diagnóstico del P0-3 indicaba que la contraseña del
indexador se rotó en un momento anterior (el orchestrator la arrastraba «desde
antes de que se rotara»), por lo que estas referencias estaban obsoletas.
**Resuelto (sesión siguiente):** reescritas para remitir a `.env`
(`${OS_PASS}`, `${API_PASSWORD}`, `INDEXER_PASSWORD` / `DASHBOARD_PASSWORD`) con
nota de rotación, como hacen ya `fase3-agentic/.env.example` y
`fase5-orchestrator-api/.env.example`.

### E · Remediación incompleta — 2 hallazgos → RESUELTO

`fase5-velociraptor/docker-compose.yml`, servicio `minio-init`. Conservaba la
forma `:-` con valor por defecto en `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`
cuando el servicio `minio` (mismas variables, líneas 26-27) ya se había
corregido a `:?` en la remediación técnica. El punto 1 de «Corrección aplicada»
del `SECURITY-NOTICE.md` afirmaba que *todos* los defaults `:-` del compose se
habían sustituido; estas dos líneas lo contradecían.

Dos revisiones manuales del compose durante la remediación dieron el fichero
por bueno. Lo encontró la regla `credencial-conocida` del detector, añadida
después.

**Estado: resuelto.** El usuario aplicó `:?` a los cuatro usos de
`MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` (líneas 26, 27, 48, 49; servicios
`minio` y `minio-init`). Verificado apartando el `.env`: Compose aborta el
arranque con el mensaje explícito, citando ambos servicios. El registro se
conserva porque el patrón —una corrección parcial que pasa dos revisiones
manuales y la detecta una regla automática— es material para la memoria.

---

## 5. Estado del árbol

```
$ git status --porcelain
 M fase5-orchestrator-api/.env.example
 M fase5-orchestrator-api/README.md
 M fase5-orchestrator-api/main.py
 M fase5-velociraptor/SECURITY-NOTICE.md
 M fase5-velociraptor/env.example
 M fase7-observabilidad/shared/metrics_client.py
 M scripts/verify-no-secrets.sh
?? fase5-velociraptor/.env.example
```
