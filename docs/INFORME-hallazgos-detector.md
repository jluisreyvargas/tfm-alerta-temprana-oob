# Informe — Resolución de los hallazgos de `verify-no-secrets.sh` (regla `credencial-conocida`)

En la Fase H del P0-3 se añadió a `scripts/verify-no-secrets.sh` una regla para
credenciales conocidas y por defecto. El detector pasó de 0 a 56 hallazgos. El
usuario corrigió a mano el único que era un fallo real de remediación
(`fase5-velociraptor/docker-compose.yml`, servicio `minio-init`, que conservaba
la forma `:-` con valor por defecto), dejando el árbol en **54 hallazgos** al
empezar esta sesión.

Este informe documenta la resolución de esos 54. Está redactado para **describir**
las credenciales afectadas, no reproducirlas: por eso él mismo pasa el detector.

Criterio aplicado, no negociable:

- **Código y documentación propios:** se corrigen o se reformulan. Nunca se
  excluyen.
- **Código de terceros vendorizado:** se excluye, porque no se puede modificar,
  y la exclusión se documenta con su motivo.
- Cualquier exclusión, lo más estrecha posible, y **solo** sobre la regla
  `credencial-conocida`: PEM, `private_key`, `password_hash`, `password_salt`,
  `obfuscation_nonce`, `nonce` y base64 largo siguen recorriendo todo el árbol.

Resultado: **`exit 0`**, con las cinco pruebas de comportamiento del detector en
verde (§4).

Este informe sustituye a la sección 4 de `docs/INFORME-P0-3.md`, que describía
estos hallazgos como pendientes de decisión.

---

## 1. Hallazgos por categoría y tratamiento

54 hallazgos, todos de la regla `credencial-conocida`. Las reglas heredadas del
P0-1 siguen en 0.

### A · Árbol vendorizado de Wazuh — 31 hallazgos → exclusión acotada

`fase1-infraestructura/wazuh/` es el proyecto oficial `wazuh-docker` vendorizado,
no código de este proyecto. Las cadenas detectadas son las credenciales de demo
que el upstream trae en claro en sus workflows, documentación y composes de
ejemplo. No se pueden reescribir sin divergir del upstream.

| Fichero | Hallazgos | Tratamiento |
|---|---|---|
| `fase1-infraestructura/wazuh/.github/workflows/push.yml` | 26 | Exclusión de la regla `credencial-conocida` acotada al prefijo `fase1-infraestructura/wazuh/` |
| `fase1-infraestructura/wazuh/docs/ref/configuration/environment-variables.md` | 2 | idem |
| `fase1-infraestructura/wazuh/multi-node/docker-compose.yml` | 2 | idem |
| `fase1-infraestructura/wazuh/single-node/.env.example` | 1 | idem |

Las demás reglas (PEM, `private_key`, `nonce`…) **siguen aplicándose** sobre ese
árbol. Verificado en la prueba T3 (§4).

### B · Placeholder en fichero de ejemplo — 1 hallazgo → excepción de valor

| Fichero | Línea | Naturaleza | Tratamiento |
|---|---|---|---|
| `fase5-velociraptor/env.example` | 13 | `IRIS_API_KEY` con un marcador de posición del tipo «sustituir esto» | Excepción acotada: en un `*.env.example` / `env.example`, un marcador de ese tipo se descarta **solo si en esa línea no hay además una credencial real** de la lista. No se excluye el fichero. |

### C · Documentación propia obsoleta — 7 hallazgos → reformulada para apuntar al `.env`

| Fichero | Líneas | Qué documentaba | Tratamiento |
|---|---|---|---|
| `fase7-observabilidad/README.md` | 95 (bloque `langgraph-agent`) | La contraseña por defecto del indexador escrita en `environment` | Bloque marcado como «extracto ilustrativo»; `env_file: [.env]` añadido; `OS_USER` / `OS_PASS` retirados del literal (se cargan de `.env`); nota de que `OS_PASS` corresponde a `INDEXER_PASSWORD` de la Fase 1, rotada |
| `fase7-observabilidad/README.md` | 125, 126, 131 (bloque `orchestrator`) | Usuario y contraseña por defecto de MinIO y contraseña por defecto del indexador, en `environment` | `env_file: [.env]` añadido; literales retirados; nota de que MinIO usa el usuario `tfm-orchestrator` vía `.env`; volumen de `shared` a `:ro` |
| `fase7-observabilidad/README.md` | 190 (verificación OpenSearch) | `curl` con usuario y contraseña por defecto embebidos | `curl` con la contraseña tomada de la variable de entorno (`${OS_PASS:?…}`) + nota de origen y rotación |
| `docs/README-fase1d-wazuh.md` | 216 (API del manager) | `curl` con contraseña por defecto embebida | `curl` con `${API_PASSWORD:?…}` + nota de que está en `wazuh/single-node/.env`, rotada respecto al valor por defecto público de la imagen |
| `docs/README-fase1d-wazuh.md` | 247 (tabla de credenciales) | Contraseñas por defecto de la imagen de Wazuh en tres filas (`admin`, `kibanaserver`, `wazuh-wui`) | Celdas sustituidas por «ver `INDEXER_PASSWORD` / `DASHBOARD_PASSWORD` / `API_PASSWORD` en `wazuh/single-node/.env`» + nota de rotación. Ajustada además la narración del «Problema 2» (línea ~79), que afirmaba que `admin` conservaba la contraseña por defecto |

**Determinación del estado actual** (regla: no inventarlo). Los composes reales
`fase3-agentic/docker-compose.yml` y `fase5-orchestrator-api/docker-compose.yml`
ya cargan estas credenciales desde `.env` (`env_file`);
`fase1-infraestructura/wazuh/single-node/.env.example` documenta
`INDEXER_PASSWORD` / `API_PASSWORD` / `DASHBOARD_PASSWORD` como los valores que
sustituyen a los defaults públicos de la imagen; y el diagnóstico del P0-3
recoge que la contraseña del indexador se rotó (la telemetría cayó 21 días por
arrastrar el valor viejo). Con eso, los literales de estos dos READMEs son
inequívocamente obsoletos.

### D · Documentación del incidente — 15 hallazgos → reformulada para describir, no citar

| Fichero | Líneas | Tratamiento |
|---|---|---|
| `fase5-velociraptor/SECURITY-NOTICE.md` | 139, 146, 167, 174, 186-187, 192, 219, 250, 253 | Las credenciales por defecto de MinIO → «las credenciales por defecto de MinIO» / «la contraseña por defecto»; la forma `${VAR:-valor}` del compose → «el valor por defecto definido en el propio compose»; los `os.getenv("…", "<valor>")` → `os.getenv("…", <contraseña por defecto>)`; la contraseña por defecto del indexador en `OS_PASS` → descrita; usuario y contraseña por defecto en el `.pyc` → descritos. La nota sobre `verify-no-secrets.sh` se actualiza para remitir a este informe |
| `fase5-orchestrator-api/README.md` | 232 | La forma `${VAR:-valor}` → «el valor por defecto definido en el propio compose» |
| `fase5-orchestrator-api/.env.example` | 4, 12 | Contraseña por defecto del indexador → descrita; forma `${VAR:-valor}` → descrita |
| `fase3-agentic/.env.example` | 7 | Contraseña por defecto del indexador → descrita |
| `fase5-velociraptor/env.example` | 4 | Forma `${VAR:-valor}` → descrita |

`fase5-velociraptor/.env.example` (copia sin trackear creada en la Fase H,
pendiente de `git mv`) se mantiene idéntico a `env.example`.

Ninguna reformulación necesitó conservar el valor concreto ni su hash: son
credenciales triviales y públicas; la descripción basta para la trazabilidad.

---

## 2. Exclusiones añadidas a `scripts/verify-no-secrets.sh`

Ambas afectan **solo** a la regla `credencial-conocida` (función `scan_all`).
Están documentadas en la cabecera del script (líneas 34-53) y junto al código.

### 2.1 · Árbol vendorizado de Wazuh

Se añade el prefijo `fase1-infraestructura/wazuh/` como `":(exclude)…"` en el
`pathspec` del `git grep` de `scan_all`, de forma que esos ficheros ni entran en
el bucle. La constante es `VENDOR_WAZUH`.

Justificación textual (cabecera): árbol vendorizado del proyecto oficial
`wazuh-docker`, no código de este proyecto; las cadenas que contiene son las
credenciales de demo que el upstream trae en claro; no se pueden reescribir sin
divergir del upstream; el despliegue real toma los secretos de
`fase1-infraestructura/wazuh/single-node/.env` (`INDEXER_PASSWORD` /
`API_PASSWORD` / `DASHBOARD_PASSWORD`), fuera del control de versiones.

**No** se toca `scan()`, que ejecuta las reglas ancladas (PEM, `private_key`,
`password_hash`, `password_salt`, `obfuscation_nonce`, `nonce`) y la de base64
largo: esas siguen recorriendo `fase1-infraestructura/wazuh/`.

### 2.2 · Placeholders en ficheros de ejemplo

Para un fichero cuyo nombre encaja en `EXAMPLE_PATH_RE`
(`(^|/)(\.env\.example|env\.example)$`), el hallazgo se descarta **solo si** la
línea no contiene además una credencial de `HARD_CRED_RE` — que es la lista de
`credencial-conocida` **sin** los dos marcadores de posición. Es decir: un
marcador «sustituir esto» en un `.env.example` no salta; una contraseña real por
defecto en un `.env.example` sí sigue saltando. No se excluye ningún fichero
entero. La comprobación se hace con `sed -n "${line}p" | grep -qE`, sin imprimir
el contenido, igual que el carve-out de plantillas que ya existía.

---

## 3. Clasificación previa (TAREA 1) — sin hallazgos fuera de categoría

Los 54 hallazgos encajaron en las cuatro categorías. Ninguno quedó sin
clasificar. Reparto por fichero antes de actuar:

```
     26 fase1-infraestructura/wazuh/.github/workflows/push.yml                        (A)
     10 fase5-velociraptor/SECURITY-NOTICE.md                                         (D)
      5 fase7-observabilidad/README.md                                                (C)
      2 fase5-velociraptor/env.example                              (D: línea 4) + (B: línea 13)
      2 fase5-orchestrator-api/.env.example                                           (D)
      2 fase1-infraestructura/wazuh/multi-node/docker-compose.yml                     (A)
      2 fase1-infraestructura/wazuh/docs/ref/configuration/environment-variables.md   (A)
      2 docs/README-fase1d-wazuh.md                                                   (C)
      1 fase5-orchestrator-api/README.md                                              (D)
      1 fase3-agentic/.env.example                                                    (D)
      1 fase1-infraestructura/wazuh/single-node/.env.example                          (A)
```

---

## 4. Pruebas de comportamiento del detector (TAREA 6)

Método: `verify-no-secrets.sh` recorre el árbol de trabajo de los ficheros
**trackeados** (`git grep` sin `--cached`). Se añadieron líneas de prueba a dos
ficheros trackeados, se ejecutó el script real y se restauró el contenido exacto
previo con una copia de seguridad (no `git restore`, para no perder las
reformulaciones de esta sesión). Verificado después que el árbol vuelve a `exit
0` y que `git status` no conserva ninguna línea de prueba.

| # | Caso | Línea de prueba añadida | Esperado | Resultado |
|---|---|---|---|---|
| T1 | Credencial conocida en fichero propio | En `fase3-agentic/.env.example`, una asignación con la contraseña por defecto de MinIO | **salta** `[credencial-conocida]` | ✅ `fase3-agentic/.env.example:11 [credencial-conocida]` |
| T2 | Credencial conocida bajo árbol vendorizado | En `fase1-infraestructura/wazuh/single-node/.env.example`, una asignación con otra credencial por defecto de la lista | **no salta** | ✅ sin hallazgo |
| T3 | Bloque PEM bajo árbol vendorizado | En el mismo fichero, una cabecera PEM de clave privada | **salta** `[PEM PRIVATE KEY]` | ✅ `fase1-infraestructura/wazuh/single-node/.env.example:16 [PEM PRIVATE KEY]` |
| T4 | Marcador de posición en un `.env.example` | En `fase3-agentic/.env.example`, una asignación con un marcador «sustituir esto» | **no salta** | ✅ sin hallazgo |
| T5 | Credencial por defecto real en un `.env.example` | La misma línea de T1 (es un `.env.example`) | **salta** | ✅ (mismo hallazgo que T1) |

Salida literal de la ejecución con las líneas de prueba presentes:

```
  HALLAZGO  fase1-infraestructura/wazuh/single-node/.env.example:16  [PEM PRIVATE KEY]
  HALLAZGO  fase3-agentic/.env.example:11  [credencial-conocida]

FALLO: 2 hallazgos sobre 1752 ficheros trackeados.
exit=1
```

T3 confirma que la exclusión del árbol de Wazuh es específica de
`credencial-conocida` y **no** desactiva el resto de reglas sobre ese árbol.
T2 frente a T5 confirma que la excepción de placeholders discrimina por valor,
no por fichero.

---

## 5. Salida literal final del script

```
$ ./scripts/verify-no-secrets.sh

OK: 0 hallazgos sobre 1752 ficheros trackeados.
$ echo $?
0
```

---

## 6. Hallazgos y literales que NO se han tocado, y por qué

- **`docs/README-fase1d-wazuh.md` — usuario `wazuh-admin`.** En la sesión
  anterior quedó anotado como pendiente de decisión (no se podía verificar si
  seguía en uso). **Resuelto en esta sesión** (ver §9): verificado contra el
  sistema en ejecución que el usuario **no existe**. Las cuatro zonas del
  documento que lo describían como control implementado se han reescrito;
  también dos referencias en `docs/README-fase1e-validacion.md`.

- **`fase7-observabilidad/README.md` — bloques de compose incrustados.** Se han
  reformulado las credenciales (categoría C), pero los bloques siguen difiriendo
  de los ficheros reales en cosas no relacionadas con secretos: el bloque
  `langgraph-agent` muestra `ports: "8000:8000"` cuando el compose real usa
  `expose` (el puerto dejó de publicarse al host por seguridad) y ninguno
  incluye `healthcheck`. Fuera del alcance de esta tarea (no son hallazgos).
  Mitigado con la nota «el fichero autoritativo es …» al inicio de cada bloque.
  **Recomendación:** sincronizar ambos extractos con los composes reales o
  reducirlos a las líneas relevantes.

- **`docs/INFORME-P0-3.md`, sección 4.** En la sesión anterior contenía los
  literales en claro y describía los hallazgos como pendientes de decisión.
  **Resuelto en esta sesión** (ver §9): sus 17 apariciones de literales se han
  reformulado con el mismo criterio, y el hallazgo E de esa sección se ha
  marcado como resuelto conservando el registro. El fichero ya pasa el detector.

---

## 7. Acciones pendientes para el usuario, en orden

1. **Revisar los cambios.** `git diff` sobre los ocho ficheros modificados en
   esta sesión y el nuevo `docs/INFORME-hallazgos-detector.md`.

2. **Completar el renombrado pendiente de la Fase H** (si no se hizo ya):
   `fase5-velociraptor/.env.example` existe sin trackear y `env.example` sigue
   trackeado con contenido idéntico.
   ```
   rm fase5-velociraptor/.env.example
   git mv fase5-velociraptor/env.example fase5-velociraptor/.env.example
   ```

3. **Preparar el commit.** Añadir a mano los ficheros modificados,
   `docs/INFORME-hallazgos-detector.md` y `docs/INFORME-P0-3.md` (ya reformulado,
   pasa el detector). No añadir ningún `.env`.

4. **Sincronizar los extractos de compose de `fase7-observabilidad/README.md`**
   con los ficheros reales (ver §6).

5. **Ejecutar `./scripts/verify-no-secrets.sh` en CI o como hook de
   pre-commit**, si aún no lo está. El valor de esta regla se demostró
   encontrando un `.pyc` trackeado que dos revisiones manuales pasaron por alto
   y un fallo de remediación real. Debe correr sola.

---

## 8. Estado del árbol (tras la resolución de los hallazgos)

```
$ git status --porcelain
 M docs/README-fase1d-wazuh.md
 M fase3-agentic/.env.example
 M fase5-orchestrator-api/.env.example
 M fase5-orchestrator-api/README.md
 M fase5-orchestrator-api/main.py
 M fase5-velociraptor/SECURITY-NOTICE.md
 M fase5-velociraptor/docker-compose.yml
 M fase5-velociraptor/env.example
 M fase7-observabilidad/README.md
 M fase7-observabilidad/shared/metrics_client.py
 M scripts/verify-no-secrets.sh
?? docs/INFORME-P0-3.md
?? docs/INFORME-hallazgos-detector.md
?? fase5-velociraptor/.env.example
```

`fase5-orchestrator-api/main.py`,
`fase7-observabilidad/shared/metrics_client.py` y
`fase5-velociraptor/docker-compose.yml` cargan cambios de la Fase H o del
usuario, no de esta sesión.

---

## 9. Corrección final antes del commit — `INFORME-P0-3.md` y el usuario `wazuh-admin`

Dos casos de la misma clase de deriva que el resto de la sesión, ahora en la
documentación: un control descrito, defendido en una sección de decisiones de
diseño, y nunca implementado.

### 9.1 · `docs/INFORME-P0-3.md` — reformulación de literales y cierre del hallazgo E

El fichero estaba sin trackear, así que no había disparado el detector; al
añadirlo al índice habría fallado (17 líneas con literales de credenciales
conocidas). Reformulado con el mismo criterio que los `SECURITY-NOTICE.md`:
describir en vez de citar, conservando la forma sintáctica `${VAR:-…}` donde
ilustra el mecanismo del valor por defecto.

| Zona | Antes | Después |
|---|---|---|
| Intro, variante 1 del patrón | `${MINIO_ROOT_PASSWORD:-<literal>}` | `${MINIO_ROOT_PASSWORD:-<default publicado>}` (se conserva la construcción, se sustituye solo la cadena) |
| §1, fila `fase5-orchestrator-api/README.md` | «Retirados `<usuario>` / `<contraseña>`…» | «Retiradas las credenciales por defecto de MinIO…» |
| §1, fila `verify-no-secrets.sh` | Reproducía la lista completa del patrón de la regla | Remite al propio script (constante de `scan_all` y comentario de cabecera); describe el anclaje sin nombrar el marcador |
| §1, fila `fase5-velociraptor/docker-compose.yml` | Citaba los dos `${VAR:-<literal>}` del servicio `minio-init` como pendientes | Describe el estado y remite al hallazgo E, ya resuelto |
| §3, acciones 6 y 7 | «Decidir sobre los 56 hallazgos», «Resolver el hallazgo E» | Marcadas como resueltas, con puntero a este informe |
| §4, intro y A–E | Inventario con literales y «motivo de conservarlas» | Literales descritos; cada categoría con su línea «Resuelto (sesión siguiente)»; E reescrito como RESUELTO |
| §4.E | `${MINIO_ROOT_USER:-<literal>}` / `${MINIO_ROOT_PASSWORD:-<literal>}` en bloque YAML | `${MINIO_ROOT_USER:-<default publicado>}` / idem; se conserva el bloque porque explica el fallo |

**Hallazgo E marcado como resuelto sin borrarlo.** Queda el registro de que
existió (el servicio `minio-init` conservaba la forma `:-` con valor por defecto
mientras el servicio `minio` ya usaba `:?`), de que dos revisiones manuales del
compose lo dieron por bueno, y de que lo encontró la regla `credencial-conocida`
del detector. El usuario aplicó `:?` a los cuatro usos de `MINIO_ROOT_USER` /
`MINIO_ROOT_PASSWORD` (líneas 26, 27, 48, 49; servicios `minio` y `minio-init`)
y verificó, apartando el `.env`, que Compose aborta el arranque con el mensaje
explícito citando ambos servicios.

Comprobación (el fichero está sin trackear; se aplica la regla directamente).
Un `grep -c` sobre el par usuario/contraseña por defecto de MinIO devuelve `0`
líneas, y un `grep -nE` con la expresión completa de la regla `credencial-conocida`
sobre `docs/INFORME-P0-3.md` no produce salida.

### 9.2 · `docs/README-fase1d-wazuh.md` y `docs/README-fase1e-validacion.md` — usuario `wazuh-admin` inexistente

El documento describía un usuario `wazuh-admin` con rol `all_access` como la
solución adoptada al problema del usuario reservado de OpenSearch, lo defendía
en «Decisiones de diseño» y listaba su contraseña en claro. **Ese usuario no
existe.**

**Verificación aportada (sistema en ejecución).** La API de seguridad de
OpenSearch devuelve únicamente `admin` y `kibanaserver`. La credencial de
`wazuh-admin` documentada en la tabla devuelve **HTTP 401**. Es decir, la
documentación describía un control (separación de privilegios mediante un
usuario operativo dedicado) que nunca llegó a implementarse; quien reconstruyera
el entorno siguiendo el documento crearía un usuario que el sistema real no
tiene y creería tener una separación que no existe.

Zonas reescritas para reflejar el estado verificado:

| Fichero | Zona | Cambio |
|---|---|---|
| `README-fase1d-wazuh.md` | «Problema 2», solución (~L79) | «Crear un usuario dedicado `wazuh-admin`…» → «El acceso operativo se hace con `admin` y la contraseña de `INDEXER_PASSWORD` en `.env`… La creación de un usuario dedicado se evaluó y no llegó a implementarse» |
| `README-fase1d-wazuh.md` | Tabla de credenciales (~L251) | Eliminada la fila `wazuh-admin` y su contraseña en claro. `admin` pasa a «acceso operativo y de emergencia» |
| `README-fase1d-wazuh.md` | Nota bajo la tabla (~L261) | Eliminado el párrafo sobre `wazuh-admin` «pendiente de decisión», que queda sin objeto |
| `README-fase1d-wazuh.md` | «Decisiones de diseño» (~L274) | El bullet que afirmaba el usuario separado como práctica implementada pasa a subsección «evaluado, no implementado», con el formato de `README-fase4-pendientes.md` (Control evaluado / Amenaza que cubriría / Control equivalente actual / Decisión) |
| `README-fase1e-validacion.md` | Inventario de credenciales (~L173) | Fila `Wazuh Dashboard \| wazuh-admin` → `Wazuh Dashboard \| admin`, con nota de que el usuario dedicado se evaluó y no se implementó |
| `README-fase1e-validacion.md` | «Decisiones de diseño documentadas» (~L183) | El bullet `wazuh-admin en lugar de admin` pasa a «evaluado pero no implementado», remitiendo a `README-fase1d-wazuh.md` |

Motivo del control equivalente registrado en la decisión: el usuario `admin` de
OpenSearch Security es reservado y no modificable desde la UI, de modo que un
usuario operativo dedicado sigue siendo la práctica correcta —pero no se ha
creado—. El acceso actual es con `admin` y la contraseña de `INDEXER_PASSWORD`
(`fase1-infraestructura/wazuh/single-node/.env`, fuera del control de versiones,
rotada respecto al valor por defecto público de la imagen, restringida a red
local).

No se han encontrado más referencias a `wazuh-admin` en `docs/` ni en
`fase1-infraestructura/` fuera de las zonas listadas.

### 9.3 · Salida literal del detector

```
$ ./scripts/verify-no-secrets.sh

OK: 0 hallazgos sobre 1752 ficheros trackeados.
$ echo $?
0
```

`docs/INFORME-P0-3.md` y `docs/INFORME-hallazgos-detector.md` siguen sin
trackear, por lo que `git grep` aún no los recorre. Comprobados directamente con
la expresión de la regla `credencial-conocida`: **ninguno contiene literales**.
Al añadirlos al índice, el detector seguirá en `exit 0`.

### 9.4 · Acciones pendientes para el usuario

1. **Revisar los cambios.** `git diff` sobre los doce ficheros modificados y los
   dos informes sin trackear.
2. **Completar el renombrado pendiente de la Fase H** (si no se hizo ya):
   ```
   rm fase5-velociraptor/.env.example
   git mv fase5-velociraptor/env.example fase5-velociraptor/.env.example
   ```
3. **Preparar el commit.** Añadir a mano los ficheros modificados,
   `docs/INFORME-P0-3.md` y `docs/INFORME-hallazgos-detector.md`. No añadir
   ningún `.env`.
4. **Recrear los contenedores de Fase 3 y Fase 5** por los cambios de código de
   la Fase H (`metrics_client.py`, `main.py`), si aún no se hizo.
5. **Sincronizar los extractos de compose de `fase7-observabilidad/README.md`**
   con los ficheros reales (§6), pendiente de la sesión anterior.
6. **Si en algún momento se implementa el usuario operativo dedicado de Wazuh**,
   actualizar la subsección «evaluado, no implementado» de
   `README-fase1d-wazuh.md` y la entrada equivalente de `README-fase1e-validacion.md`.
