> ## ⚠ ESTADO: PARCIALMENTE REFUTADO — 2026-09-13
>
> Este documento se redactó por la mañana del 2026-09-13 a partir de la lectura
> de ficheros del repositorio. Esa misma tarde se midió contra el sistema vivo
> y **cinco afirmaciones marcadas `[VERIFICADO]` resultaron falsas**. El texto
> se conserva íntegro y sin correcciones a propósito: la discrepancia entre lo
> que el documento afirma y lo que la máquina hace es material de la memoria
> (véase `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md`, que contiene las
> mediciones, sus comandos y sus salidas).
>
> **Refutado — no usar como base para construir:**
>
> | Afirmación del documento | Medición que la refuta |
> |---|---|
> | Bloqueante 1 / P1: `iris.oob.local` no resuelve dentro del contenedor n8n | Sí resuelve, a `100.64.0.1` |
> | P1: n8n no tiene ninguna vía de red hacia `100.64.0.1` | `100.64.0.1:443` alcanzable desde el contenedor |
> | P1: la única vía físicamente disponible es `oob-network` contra el nginx de IRIS | Había al menos dos; la elegida es una tercera |
> | P1: el `ports: !override` publica el nginx solo en `100.64.0.1:443` | Publica `100.64.0.1:4833`; el `443` del override es solo el valor por defecto de `${INTERFACE_HTTPS_PORT:-443}` |
> | P2 / Bloqueante 2: el `misp.crt` montado existe, 1870 bytes, `CN=localhost` | Se midió el fichero del árbol que **no** se monta. La ruta montada era un **directorio vacío** creado por Docker; el diseño original («directorio vacío»), que esta revisión corrigió, tenía razón |
>
> **Consecuencia:** de los cuatro bloqueantes declarados, **solo uno seguía en
> pie** (el 3, tabla de `severity_id`). El bloqueante 1 era falso; el 2 tenía la
> causa invertida; la premisa del 4 era falsa y el cambio que proponía (alias de
> red Docker en `fase6-iris`) resultó **innecesario**.
>
> **Se mantiene vigente:** la corrección de la tabla `SEV` (sección 3), la
> recomendación de la opción (b) para Velociraptor (P3b), el análisis de
> `/velociraptor/collect` (P3), las colisiones de identificadores (P4) y la
> verificación del saneado de `export-workflow.sh` (P6, con la salvedad
> registrada en el documento de mediciones: el saneado no cubre `parameters`).

# Revisión del diseño «Workflow 1: caso en IRIS desde el War Room»

Fecha de la revisión: 2026-09-13. Modo: análisis y propuesta — ningún fichero
del repositorio salvo este ha sido modificado; no se ha ejecutado `git` de
escritura, ni Docker, ni se ha generado ningún secreto.

El diseño revisado se redactó **antes** de la Fase C del P1-1a (cerrada
2026-09-13), que puso a IRIS detrás de Traefik + Authelia y restringió el
4833 a la tailnet. Esta revisión evalúa si el diseño sigue siendo construible
tal cual, y dónde hay que corregirlo.

---

## 1. Bloqueantes

Lo que impide construir el diseño hoy tal como está redactado, con el cambio
mínimo para cada uno. Detalle y evidencia completa en la sección 2.

1. **`iris.oob.local` no resuelve dentro del contenedor `n8n`.**
   [VERIFICADO] `fase2-orquestador/n8n/docker-compose.yml` no tiene
   `extra_hosts` ni `dns:`. El `/etc/hosts` del host Ubuntu/W11 no aplica
   dentro de un contenedor. La llamada del nodo 6 tal como está escrita en
   el diseño falla en resolución de nombre, antes incluso de negociar TLS.
   **Cambio mínimo:** añadir un alias de red Docker para `iris.oob.local` en
   `oob-network` que resuelva al contenedor `iriswebapp_nginx` (ver P1).

2. **La CA montada en n8n no es la del enclave.** El diseño (F8) afirma que
   `NODE_EXTRA_CA_CERTS` apunta a un directorio vacío; **eso es incorrecto**.
   [VERIFICADO] `fase2-orquestador/n8n/docker-compose.yml:14` fija
   `NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/misp.crt`, y la
   línea `:30` monta `./n8n/certs/misp.crt` ahí — el fichero existe (1870
   bytes) y **no está vacío**, pero es el certificado autofirmado de MISP
   (`CN=localhost`), no la CA raíz del enclave que firma `iris.oob.local`
   (`fase6-iris/certificates/rootCA/ca-bundle-oob.crt`). El hallazgo real no
   es "directorio vacío" sino "CA equivocada". **Cambio mínimo:** fusionar la
   CA del enclave en el mismo fichero que ya se monta en
   `NODE_EXTRA_CA_CERTS` (Node solo admite una ruta).

3. **Los `severity_id` del diseño están mal para MEDIA y BAJA.**
   [VERIFICADO contra `fase6-iris/source/app/post_init.py:694-707` y
   `app/models/alerts.py:69`] La tabla real de IRIS es
   `1=Unspecified, 2=Informational, 3=Low, 4=Medium, 5=High, 6=Critical`. El
   diseño usa `MEDIA:1` (real: Unspecified) y `BAJA:4` (real: Medium), e
   invierte el orden esperado. Esto no es un problema de conectividad: es un
   bug funcional que, sin corregir, generaría casos MEDIA marcados como
   "Unspecified" y casos BAJA marcados como "Medium" (con severidad inflada)
   desde la primera ejecución. **Cambio mínimo:** corregir la tabla `SEV` a
   `{ CRITICA: 6, ALTA: 5, MEDIA: 4, BAJA: 3 }` (ver sección 3).

4. **Decisión de arquitectura pendiente de documentar por escrito, no de
   código:** la única ruta viable para que n8n llegue a IRIS (ver P1)
   consiste en conectar directamente al contenedor `iriswebapp_nginx` dentro
   de `oob-network`, sin pasar por Traefik ni por Authelia. Esto no es un
   bloqueante técnico, pero si no se documenta explícitamente como decisión
   consciente (con su porqué y sus contrapartidas), es indistinguible de un
   atajo no revisado — exactamente lo que el proyecto ya evita en
   `docs/DECISION-velociraptor-fuera-sso.md`. Falta un documento equivalente
   para esta ruta antes de construir.

---

## 2. Respuestas a P1–P6

### P1 — ¿Desde qué endpoint puede n8n llamar a IRIS?

**Resolución de nombres dentro del contenedor n8n**
[VERIFICADO] `fase2-orquestador/n8n/docker-compose.yml:1-33` — el servicio
`n8n` no declara `extra_hosts` ni `dns:`. Solo `env_file`, `environment`,
`volumes` y `networks: [oob-network]`.
[VERIFICADO] `docs/resolucion-nombres.tsv:1,14-17,29,40` — el control de
resolución de nombres del proyecto cubre explícitamente solo `ubuntu` y `w11`
(sistemas operativos), nunca contenedores. `iris.oob.local` solo se resuelve
a `100.64.0.1` en esos dos hosts.
**Conclusión:** la llamada literal del diseño a
`https://iris.oob.local:4833/manage/cases/add` falla en el paso de DNS
dentro del contenedor n8n.

**Redes compartidas**
[VERIFICADO] `fase2-orquestador/n8n/docker-compose.yml:32-33,51-53` — n8n
está en `oob-network` (external: true).
[VERIFICADO] `fase6-iris/docker-compose.yml:42-50` — el `nginx` de IRIS está
en `iris_frontend` **y** `oob-network`.
[VERIFICADO] `fase6-iris/docker-compose.base.yml:99-100` —
`container_name: iriswebapp_nginx`.
n8n y el nginx de IRIS **comparten `oob-network`**. Cualquier contenedor de
esa red puede alcanzar a `iriswebapp_nginx` en su puerto interno 4833 por la
red Docker interna, con independencia de qué puertos publique
`ports:` hacia el host — esa directiva solo controla la publicación hacia
fuera, no la conectividad interna entre contenedores de la misma red.

**Topología Traefik/Authelia (Fase C), confirmada literal**
[VERIFICADO] `fase6-iris/docker-compose.override.yml:38` —
`traefik.http.routers.iris.middlewares=secure-headers@file,authelia@file`.
[VERIFICADO] `fase6-iris/docker-compose.override.yml:39-40` — backend
`https://172.18.0.23:4833`, `scheme=https`.
[VERIFICADO] `fase6-iris/docker-compose.override.yml:26-27` —
`ports: !override` publica el nginx solo en `100.64.0.1:443`.
[VERIFICADO] `fase1-infraestructura/authelia/configuration.yml:37-39` — la
regla de `access_control` para `iris.oob.local` cubre **todo el dominio**
(sin `resources`), `policy: two_factor`. No hay hoy ninguna excepción de
ruta para IRIS.

**¿Sobrevive un `Authorization: Bearer` a `forwardAuth`?**
No se verificó hoy mismo contra IRIS en esta sesión (eso se hizo contra
Velociraptor), pero el mecanismo de Authelia `forwardAuth` es el mismo
middleware (`authelia@file`) para ambos routers, y ya está documentado que
consume la cabecera `Authorization` y responde `401` sin dejarla pasar
(`docs/DECISION-velociraptor-fuera-sso.md`). [INFERIDO por generalización del
mismo middleware] Sería razonable esperar el mismo fallo con IRIS: un
`Bearer <api-key>` no llegaría nunca al backend de IRIS pasando por el 443.
**[PENDIENTE DE MEDICIÓN]** comando exacto que lo confirmaría sin construir
nada del workflow:
```
curl -sS -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: Bearer <api-key-real-o-dummy>" \
  https://iris.oob.local/manage/cases/add
```
ejecutado desde un host de la tailnet (`ubuntu` o `w11`) con `iris.oob.local`
resuelto a `100.64.0.1`. Un `401` de Authelia (con `Set-Cookie` o redirect a
login) confirmaría el mismo fallo que con Velociraptor; un intento de llegar
al backend (aunque sea un 400/404 de IRIS) lo refutaría.

**Acceso de n8n a la tailnet**
[VERIFICADO] `fase2-orquestador/n8n/docker-compose.yml` no tiene
`network_mode`, `cap_add: NET_ADMIN` ni sidecar tailscale;
`grep -rl tailscale fase2-orquestador/` no da resultados. n8n **no tiene
ninguna vía de red hacia `100.64.0.1`**. Aunque se arreglara la resolución de
nombre apuntando al 443 de Traefik en la tailnet, n8n no podría llegar ahí
por ningún camino de red existente. La única vía físicamente disponible es
`oob-network` contra el nginx de IRIS directamente.

**Alternativas evaluadas**

- *DNS interno de Docker (`https://iriswebapp_nginx:4833`)* — **descartada**,
  tal y como pide el prompt: el certificado de IRIS tiene
  `CN=iris.oob.local`; llamando por el nombre de servicio Docker el hostname
  no coincide con el CN/SAN, y validar TLS exigiría
  `allowUnauthorizedCerts`, el mismo patrón ya abierto como hallazgo en el
  nodo MISP.
- *Excepción de ruta en Authelia para `/manage/cases/add` o para la API* —
  evaluada críticamente y **no recomendada** como primera opción. El propio
  repo ya tiene un precedente de este patrón, pero para el **propio n8n**, no
  para IRIS: [VERIFICADO] `fase2-orquestador/n8n/docker-compose.yml:36-46` —
  el router principal `n8n` (`Host(n8n.oob.local)`) no lleva middleware
  alguno; solo el router `n8n-cred`, acotado por
  `PathPrefix(/webhook/bg-credential)`, lleva `authelia@file`.
  [VERIFICADO] `fase1-infraestructura/authelia/configuration.yml:43-47`
  confirma la regla de `access_control` acotada por `resources` a esa misma
  ruta. Añadir una excepción equivalente en el dominio de IRIS reproduciría
  ese patrón sobre un servicio con datos de casos DFIR, ampliando la
  superficie sin autenticación 2FA de un sistema más sensible que el propio
  n8n.
- *`extra_hosts` (o alias de red Docker) mapeando `iris.oob.local` a
  `iriswebapp_nginx` dentro de `oob-network`* — **es la recomendada**, con
  una precisión: en vez de fijar una IP a mano en `extra_hosts` (frágil si el
  contenedor se recrea), es preferible declarar un **alias de red** para
  `iris.oob.local` en el propio `docker-compose` de `fase6-iris` sobre el
  servicio `nginx`, en su conexión a `oob-network`:
  ```yaml
  services:
    nginx:
      networks:
        oob-network:
          aliases: [iris.oob.local]
  ```
  Esto hace que **cualquier** contenedor de `oob-network` (n8n incluido)
  resuelva `iris.oob.local` vía el DNS embebido de Docker a la IP real y
  actual del contenedor, sin depender de una IP fija.

**Recomendación (P1): alias de red Docker + llamada directa dentro de
`oob-network`.** Razones:
1. Resuelve el nombre (bloqueante 1) sin depender de IPs fijas.
2. El CN del certificado coincide (`iris.oob.local`) — la verificación TLS
   se mantiene por nombre, sin `allowUnauthorizedCerts`, a diferencia de la
   opción del nombre de servicio Docker.
3. El tráfico contenedor-a-contenedor dentro de `oob-network` **nunca pasa
   por el router de Traefik en el 443**, así que el `forwardAuth` de
   Authelia no interviene — no hace falta tocar
   `fase1-infraestructura/authelia/configuration.yml` en absoluto, evitando
   el patrón de riesgo de "excepción de ruta en el SSO".

Contrapartida que hay que documentar explícitamente (bloqueante 4): esta vía
dejaría a IRIS accesible desde cualquier contenedor de `oob-network` sin
pasar por la protección `two_factor` que Authelia aplica al acceso humano en
el 443/tailnet. Esa protección la sustituye únicamente la API key de IRIS
(credencial Header Auth) y el hecho de que `oob-network` no se expone fuera
del host. Antes de construir, listar qué contenedores están hoy en
`oob-network` (`docker network inspect oob-network` — comando propuesto, no
ejecutado) para acotar esa superficie y dejarlo escrito en un documento de
decisión, igual que se hizo para Velociraptor.

**Prueba que discrimina (antes/después):**
```
# Dentro del contenedor n8n, antes del cambio:
docker exec n8n getent hosts iris.oob.local   # -> vacío / "no encontrado"
docker exec n8n curl -sSv --cacert <bundle> https://iris.oob.local:4833/manage/cases/add
  # -> falla en resolución DNS (curl: (6) Could not resolve host)

# Después del alias de red:
docker exec n8n getent hosts iris.oob.local   # -> IP del contenedor iriswebapp_nginx
docker exec n8n curl -sSv --cacert <bundle-corregido> https://iris.oob.local:4833/manage/cases/add
  # -> handshake TLS válido, respuesta HTTP de IRIS (401 por falta de auth, no error de red/TLS)
```
Control negativo real (falla hoy) vs positivo (falla solo por falta de
credencial, ya no por red/nombre/TLS) — un criterio que hoy también se
cumpliría no serviría; aquí el estado "antes" falla de forma distinta
(DNS) al estado "después" (HTTP de aplicación).

---

### P2 — F8: el montaje de la CA en n8n

[VERIFICADO] `fase2-orquestador/n8n/docker-compose.yml:14` —
`NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/misp.crt`.
[VERIFICADO] `fase2-orquestador/n8n/docker-compose.yml:30` — monta
`./n8n/certs/misp.crt:/usr/local/share/ca-certificates/misp.crt:ro`.
[VERIFICADO] el fichero `fase2-orquestador/n8n/certs/misp.crt` existe, 1870
bytes, `openssl x509 -subject -issuer` → `CN=localhost`, autofirmado —
certificado propio de MISP, sin relación con la CA del enclave.
[VERIFICADO] `fase6-iris/certificates/rootCA/ca-bundle-oob.crt` es un bundle
de ~3729 líneas, contenido completamente distinto al de `misp.crt`.

**El diseño se equivoca en el diagnóstico** ("directorio vacío"): el fichero
existe y tiene contenido, pero es la CA equivocada para validar
`iris.oob.local`. El efecto práctico es el mismo que el diseño teme —fallo
de verificación TLS— pero la causa y la corrección son distintas.

**Cambio mínimo:** Node solo admite una ruta en `NODE_EXTRA_CA_CERTS`, así
que hay que fusionar ambos certificados (MISP + CA del enclave) en un único
fichero versionado igual que hoy se versiona `misp.crt`, y montar ese bundle
combinado en la misma variable. No se toca la confianza existente en MISP.

**`custom-n8n` como precedente de convención, no como código reutilizable**
[VERIFICADO] `fase2-orquestador/wazuh-integration/custom-n8n` es un script
Python que corre en el host Wazuh (fuera de Docker), no dentro del
contenedor n8n. Su función `build_ssl_context()` (líneas 84-93) usa
`CA_BUNDLE=/var/ossec/etc/oob-rootCA.crt` (líneas 22-26) — la CA del enclave
— y **si el bundle no existe, degrada al almacén del sistema con un log de
advertencia explícito**, nunca desactivando verificación (comentario de
justificación en líneas 9-12). Al ser Python sobre el host y no Node dentro
de un contenedor, `build_ssl_context` no es código reutilizable literalmente
para n8n, pero sí es la norma de proyecto a seguir: si la CA no está,
degradar con aviso explícito, jamás con `allowUnauthorizedCerts` — coherente
con que el diseño ya rechaza esa opción para el nodo 6, y con el hallazgo
abierto en MISP y en `serversTransport.insecureSkipVerify` de Traefik.

**Prueba que discrimina:** antes del cambio, una petición TLS desde el
contenedor n8n hacia `iris.oob.local:4833` (una vez resuelto el nombre, ver
P1) falla con error de cadena de confianza (`UNABLE_TO_GET_ISSUER_CERT_LOCALLY`
o equivalente en Node); después, la cadena valida contra la CA del enclave.
No usar `allowUnauthorizedCerts` para "pasar" la prueba — eso haría que el
criterio se cumpliera igual antes y después, y no serviría como control.

---

### P3 — Solapamiento con la Fase 5

**1. El Workflow 1 no depende de `/velociraptor/collect`.** [VERIFICADO]
Ninguno de los nodos del diseño (Preparar Caso IRIS, Crear Caso IRIS,
Evaluar Respuesta IRIS, etc.) referencia ese endpoint ni construye su
payload. El Workflow 1 solo llama a la API de casos de IRIS. Confirmado tal
como el prompt esperaba.

**2. Contenido real de `POST /velociraptor/collect`**
[VERIFICADO] `fase5-orchestrator-api/main.py`:
- Verificación HMAC: función `verify_signature()`, líneas 62-105.
- Construcción del manifiesto: líneas 162-177. `zip_sha256` (línea 163) es
  `sha256(incidentid + host + ts)` — no es el digest de ningún artefacto.
- `zip_path` (línea 173): URL `s3://.../velociraptor_collection.zip`
  construida por interpolación de cadena; no existe ninguna llamada que cree
  ese objeto.
- Subida real a MinIO: solo dos `client.put_object` (líneas 187-193 y
  195-201) — `manifest.json` y `sha256.txt`. Ningún ZIP.

**3. "F30" no existe como identificador en el repositorio.**
[VERIFICADO — ausencia] `grep -rn "F30"` sobre todo el repositorio: cero
coincidencias. El hecho subyacente (ausencia del ZIP) **sí está registrado**,
pero sin ese identificador:
`fase5-velociraptor/README.md:194` — tabla de estado —
`Subida de \`velociraptor_collection.zip\` real | 🟡 Pendiente`, y
`docs/INFORME-P0-4-implementacion.md` documenta la misma función centrado en
la HMAC, sin tratar la ausencia del ZIP como hallazgo numerado.
**No son dos hilos con IDs distintos para el mismo hallazgo** en sentido
estricto: es un hallazgo con estado informal (fila de tabla, sin ID) al que
el diseño del Workflow 1 le puso un identificador nuevo ("F30") sin enlazar
con el README de Fase 5 ya existente. El efecto es el mismo problema de
trazabilidad que una colisión de IDs: dos sitios describen el mismo hecho
sin que se pueda saber, sin leer ambos, que es el mismo hecho.

**4. Corrección mínima del manifiesto (honestidad del artefacto, no
funcionalidad)** — sin implementar la recolección:
- No declarar `zip_path` ni `zip_sha256` como si fueran reales. Alternativas
  de coste mínimo:
  - Omitir esos dos campos del manifiesto mientras no exista el objeto, o
  - Renombrarlos explícitamente (`planned_zip_path`,
    `placeholder_sha256_no_evidence`) para que ningún consumidor futuro del
    manifiesto los confunda con evidencia real.
  - Añadir un campo explícito `collection_status: "referencia_sin_artefacto"`.
- `selected_by: forensics_agent_v1` y `operator: orchestrator_v1`: si no hay
  agente ni operador real actuando todavía, marcar como
  `selected_by: null` / `operator: null` en vez de un valor que sugiere
  ejecución real.
- `started_at == ended_at`: o se omiten ambos campos, o se sustituyen por un
  único `manifest_created_at`, ya que no hubo una operación con duración.

Comando para verificar el estado del bucket (bucket `evidence`, confirmado en
`fase5-orchestrator-api/docker-compose.yml:17` y
`fase5-velociraptor/docker-compose.yml:48,79`), sin ejecutarlo:
```
mc alias set tfm http://localhost:9000 "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY"
mc ls --recursive tfm/evidence
```

---

### P3b — ¿Por qué canal se ordena la recolección a Velociraptor?

**Hechos confirmados:**
- [VERIFICADO] `fase5-velociraptor/velociraptor-config/server.config.yaml:236`
  — `api_config: {}` vacío.
- [VERIFICADO — ausencia] no existe `api_client.yaml` en
  `fase5-velociraptor/velociraptor-config/` (`find` sin resultados);
  `fase5-velociraptor/README.md:200-202` documenta que ese fichero, junto con
  `server.config.yaml`/`client.config.yaml` reales, ni siquiera se prevé
  versionar por contener material criptográfico.
- [VERIFICADO] `fase5-orchestrator-api/requirements.txt` completo:
  `fastapi==0.116.1`, `uvicorn[standard]==0.35.0`, `pydantic==2.11.7`,
  `minio==7.2.7`. Sin `pyvelociraptor` ni `grpcio`, y ninguna otra carpeta del
  repo los referencia tampoco.
- [PENDIENTE DE DOCUMENTACIÓN] La prueba del `403` + `_gorilla_csrf` contra
  `/api/v1/CollectArtifact` que motiva esta pregunta (hecha hoy, según el
  contexto de la sesión) **no tiene ningún registro en el repositorio**:
  `grep -rn "gorilla_csrf\|CollectArtifact"` sobre todo el repo no encuentra
  nada. Si se quiere que quede trazable, falta un
  `docs/HALLAZGO-*` o `docs/INFORME-*` equivalente al que ya existe para
  Traefik/Authelia.
- [PENDIENTE — fuera del repo] Si los endpoints `/api/v1/...` de la GUI de
  Velociraptor se consideran API pública o interfaz interna no está escrito
  en ningún sitio del repositorio ni de su documentación vendorizada; exige
  consultar la documentación oficial de Velociraptor sobre su
  Client API/gRPC API (pensada para integraciones) frente a los endpoints
  REST que sirven la GUI (protegidos con CSRF por diseño, no pensados como
  contrato estable para terceros). No se puede resolver leyendo este repo.

**Recomendación: (b) — n8n orquesta, el orchestrator ejecuta.**

Razones, en orden de peso:

1. **El ZIP no debe circular por n8n** (regla explícita del propio prompt):
   la opción (a) igualmente necesitaría que n8n descargue el resultado en
   algún momento si quiere asociarlo al caso; la opción (b) mantiene el
   binario fuera de los nodos HTTP de n8n en todo momento — solo referencias
   (case_id, ruta en MinIO, hash) cruzan el workflow.
2. **Verificabilidad por un tercero:** la lógica de hash y manifiesto en
   Python versionado (`fase5-orchestrator-api/main.py`) es diffable y
   revisable en PR; la misma lógica dentro de un nodo Code de un JSON de n8n
   no lo es de la misma manera — un tribunal o auditor pidiendo "reproduce
   este hash" tiene un comando y un fichero de código que ejecutar, no un
   export de n8n que interpretar.
3. **Los endpoints de la GUI no son la interfaz de programación documentada
   de Velociraptor** ([PENDIENTE de confirmar contra la documentación oficial,
   ver arriba], pero el propio hecho de que estén protegidos por
   `_gorilla_csrf` — un mecanismo anti-CSRF pensado para navegador, no para
   clientes API — es un indicio fuerte de que no lo son). El nombre de la
   cookie, la cabecera esperada y el comportamiento de `SameSite` pueden
   cambiar entre versiones de Velociraptor sin aviso, porque no es un
   contrato de API — es implementación interna de la GUI.
4. **Coste de (b) es conocido y acotado:** habilitar `api_config` en
   `server.config.yaml`, generar `api_client.yaml`, crear un usuario de API
   con permisos, y añadir `pyvelociraptor`/`grpcio` a
   `fase5-orchestrator-api/requirements.txt`. Es trabajo de infraestructura
   explícito, no un truco de scraping de cookies.

**Contrapartida de (b):** más piezas que mantener (config gRPC, dependencia
nueva), y el orchestrator pasa de "verificador de firma + subida de
manifiesto" a "orquestador con permisos sobre Velociraptor" — aumenta su
superficie y exige revisar sus propios permisos con cuidado.

**Si en algún momento se optase por (a) pese a esta recomendación**, debe
quedar documentado por escrito (documento tipo
`docs/DECISION-*`, igual que para Velociraptor fuera de SSO):
- Qué versión exacta de Velociraptor se probó y con qué nombre de cookie/
  cabecera CSRF.
- Reconocimiento explícito de que se está sorteando una protección
  anti-automatización pensada para navegador, y por qué se considera
  aceptable para este caso de uso.
- Un mecanismo de detección de rotura si el nombre de la cookie o el flujo
  cambian en una actualización de Velociraptor (p. ej. una prueba de humo que
  falle de forma ruidosa, no un fallo silencioso).

---

### P4 — Colisión de identificadores

**El repo mezcla dos series bajo la misma sintaxis:** una serie global de
hitos (P0-1, P0-3, P0-4, P0-6, P1-0, P1-1, P1-1a…P1-1g, todos referenciados
de forma consistente entre documentos) y series **locales** que cada informe
de auditoría reinicia en 1 (`P0-A…E`, `P1-1…P1-11` en
`docs/INFORME-AUDITORIA-FASE6.md`; `P0-1…P0-5`, `P1-1…P1-5` en
`docs/INFORME-AUDITORIA-FASE8.md`; etc.), sin ningún prefijo que las
distinga y sin fichero índice que centralice la numeración
(`ls docs/` no contiene ningún `INDICE*`/`hallazgos.md`).

**P1-6 no es una colisión doble, son cuatro hallazgos distintos con el mismo
identificador:**
1. `docs/cierre-mejora1-hook.md:212` — token GL-RM1 en claro en
   `/home/rttys.conf`.
2. `docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:322` (§5) —
   `server_urls`/`public_url` de las plantillas de Velociraptor, **cerrado
   2026-09-13** (confirmado en el commit `744aa11`: "P1-6 cerrado tambien en
   client.config.yaml del host").
3. `docs/api-reconocimiento-fase8.md:234` — `/api/script-info` filtra
   `RTTYS_TOKEN`/`WEBRTC_PASSWORD` sin `middleware.Require`.
4. `docs/INFORME-AUDITORIA-FASE6.md:81` (tabla) — CA del enclave fuera de los
   almacenes de confianza de IRIS, corregido.

**La colisión entre (1) y (2) ya estaba detectada por el propio proyecto**,
no es un hallazgo nuevo de esta revisión: `docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:230-234`
(§3.5.1, "Colisión de identificadores en el P1-6") la registra explícitamente,
y `docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:359` (§6, paso 5) dejó
pendiente "renumerar uno de los dos P1-6" — **acción nunca ejecutada**. (3) y
(4) no estaban registrados como parte de esa colisión por nadie hasta ahora.

**Otras colisiones del mismo patrón** (no auditadas línea a línea por
completo, marcar como screening, no verificación exhaustiva):
- `P0-3`: serie global (rotación de credenciales root MinIO,
  `docs/credenciales-de-arranque.md:138`, `docs/INFORME-P0-3.md:1,3`) vs.
  usos locales en `docs/INFORME-AUDITORIA-FASE8.md:118`,
  `docs/mejora6-endurecimiento-dispositivo.md:96,110`,
  `docs/README-fase1d-wazuh.md:258`.
- `P1-4`: `docs/INVENTARIO-artefactos-huerfanos.md:3` vs.
  `docs/mejora3-trazabilidad-operador.md:6` vs. series locales de FASE6/FASE8
  vs. `docs/api-reconocimiento-fase8.md:256`.
- `P1-1`: uso global (`docs/README-resolucion-nombres.md:284`) vs. local
  (`docs/INFORME-AUDITORIA-FASE6.md:76,636,638`,
  `docs/INFORME-AUDITORIA-FASE8.md:138`).

**Los `F<n>` del diseño del Workflow 1 (F2, F8, F14, F20, F21, F23, F27, F28,
F30) no colisionan por identidad hoy** (ninguno de esos números tiene, en
`docs/`, el significado de "hallazgo del Workflow 1", porque el diseño aún
no está incorporado). Pero **"F8" ya está tomado con otro significado**:
[VERIFICADO] `docs/diseno-hook-autorizacion.md:49-55` usa "F8-D4"…"F8-D8"
donde "F8" significa **"Fase 8"**, no "hallazgo número 8" — y el propio
documento ya advierte de esta ambigüedad en sus líneas 41-44 ("con las
decisiones de P1-1a, que usan la misma serie con otro significado"). Es
decir, el repo ya tiene un precedente explícito de que la sigla "F" es
propensa a colisionar semánticamente. Además hay una referencia cruzada rota
de tipo similar: `docs/DECISION-p0-6-pospuesto.md:63` cita "F4, sección de
Excepciones del README de resolución de nombres", pero
`docs/README-resolucion-nombres.md` no tiene ninguna etiqueta "F4" (la
sección "Excepciones", línea 111, no numera sus entradas).

**Renumeración mínima propuesta (sugerencia, no aplicada):**
1. Dejar **P1-6 (GL-RM1, `cierre-mejora1-hook.md`)** como está — es el uso
   más antiguo.
2. Renombrar **P1-6 (Velociraptor, cerrado)** a **P1-1h**, continuando la
   serie `P1-1a…P1-1g` ya usada para sub-hallazgos de esa misma fase, en
   cualquier documento futuro que lo cite (el registro histórico y el
   mensaje de commit ya existentes no se tocan).
3. Para **P1-6 (`/api/script-info`, Fase 8)** y **P1-6 (CA fuera de
   almacenes, Fase 6)**: coste mínimo es añadir una nota de desambiguación
   como la que ya existe en `diseno-hook-autorizacion.md:41-44`, en vez de
   renumerar informes de auditoría potencialmente cerrados.
4. Antes de incorporar el diseño del Workflow 1 a `docs/`, renombrar su serie
   interna de **`F<n>` a `H<n>`** ("Hallazgo n") para no colisionar con el
   uso ya establecido de "F8 = Fase 8".
5. Estructural (no aplicada, fuera de alcance de esta revisión): crear
   `docs/INDICE-HALLAZGOS.md` con la serie global P0-*/P1-*, dejando
   explícito que los `P[0-2]-N` dentro de `INFORME-AUDITORIA-FASE*.md` son
   locales a ese informe y deben citarse siempre junto al nombre del
   fichero.

---

### P5 — Revisión técnica del diseño

**`case_customer: 1`**
[VERIFICADO] `fase6-iris/source/app/post_init.py:935-946` —
`create_safe_client()` crea un único cliente (`name="IrisInitialClient"`) en
el arranque inicial, antes de `create_safe_case`. `Client.client_id`
(`app/models/models.py:130-141`) es `BigInteger` autoincremental sin valor
forzado. En una instalación nueva con tabla vacía, el primer y único insert
produce `client_id=1`. El supuesto del diseño es correcto para instalación
nueva. **[PENDIENTE DE MEDICIÓN]** si esta instancia de IRIS ha tenido
clientes borrados/recreados: `GET /manage/customers/list` con la API key y
confirmar que el id=1 sigue siendo el cliente esperado.

**`severity_id` — mismatch confirmado (ver bloqueante 3)**
[VERIFICADO] `fase6-iris/source/app/post_init.py:694-707` (orden de
`create_safe_severities()`, autoincremento sobre
`Severity.severity_id: Integer primary_key`, `app/models/alerts.py:69`):
```
1=Unspecified, 2=Informational, 3=Low, 4=Medium, 5=High, 6=Critical
```
Comparado con el diseño (`CRITICA:6, ALTA:5, MEDIA:1, BAJA:4, defecto:2`):
CRITICA y ALTA son correctos; **MEDIA=1 es incorrecto** (real: Unspecified,
el valor real de Medium es 4); **BAJA=4 es incorrecto** (real: Medium, el
valor real de Low es 3); el **defecto=2 es cuestionable** (Informational, no
Unspecified, que sería 1). Además, `create()` en
`app/business/cases.py:81` tiene su propio fallback:
`if not case.severity_id: case.severity_id = 4` — si el payload omitiera
`severity_id` del todo, IRIS lo pondría en **Medium**, no en el "por
defecto" que el diseño cree. Esto refuerza que el payload debe enviar
siempre `severity_id` explícito (el diseño ya lo hace), pero con la tabla
corregida.

**`classification_id` — coincide, pero es una dependencia frágil no
declarada**
[VERIFICADO] `fase6-iris/source/app/post_init.py:638-660` —
`create_safe_classifications()` carga
`app/resources/misp.classification.taxonomy.json` y crea
`CaseClassification` en el orden de iteración del JSON, autoincremental, sin
ID declarado en ningún sitio como constante. Orden real verificado:
`10 = malicious-code:rootkit`, `14 = intrusion-attempts:exploit-known-vuln`,
`15 = intrusion-attempts:login-attempts`. Los tres coinciden con el diseño
(15 y 10 con buena correspondencia semántica; 14 es una aproximación —no hay
entrada específica de "web"/"sql injection" en esa taxonomía MISP de 36
entradas). **Riesgo:** estos IDs no son constantes garantizadas por el
código, son consecuencia del orden de un fichero JSON de terceros cargado
una sola vez en el primer arranque; una reinstalación con una versión
distinta de esa taxonomía desplazaría los IDs sin aviso. Recomendación: no
tratarlos como mágicos fijos en el Code de n8n sin, al menos, un comentario
explícito de esta fragilidad y una verificación puntual contra la instancia
antes de cada uso en producción real (no solo en pruebas).

**`cases/add`: los tres supuestos no confirmados, verificados en código**
- `data.case_id` en la respuesta: [VERIFICADO]
  `fase6-iris/source/app/blueprints/manage/manage_cases_routes.py:346-354`
  devuelve `response_success(msg, data=case_schema.dump(case))`; `CaseSchema`
  (`app/schema/marshables.py:1527-1552`) no excluye `case_id` de la
  serialización. **Confirmado: sí viene.**
- `case_soc_id` como string pese a la anotación `int`: [VERIFICADO]
  `app/schema/marshables.py:1537` —
  `case_soc_id: int = auto_field('soc_id', required=True)`; la anotación
  `: int` es cosmética de Python, el campo marshmallow real deriva de la
  columna `soc_id = Column(String(256))`
  (`app/models/cases.py:53`). **Confirmado: el campo real es string, sin
  coerción especial** — el diseño acierta al enviarlo como cadena.
- Forma del 400 cuando `ValidationError` escapa del `except
  BusinessProcessingError`: [VERIFICADO] esto en realidad **no puede
  ocurrir tal como el diseño lo plantea** — `_load()`
  (`app/business/cases.py:64-68`) ya envuelve cualquier `ValidationError` de
  marshmallow en un `BusinessProcessingError('Data error', e.messages)`
  antes de que `create()` lo vea; y el `except Exception` genérico de
  `create()` (líneas ~116-118) relanza como
  `BusinessProcessingError('Error creating case - check server logs')`
  **sin el detalle de campo original** (el propio código tiene un
  `# TODO maybe remove validationerror (because unnecessary)` en la línea
  111, delatando que el camino de `ValidationError` explícito ya se
  considera vestigial). **Consecuencia práctica para el nodo 7:** la mayoría
  de errores de validación de negocio (incluido un `case_customer` inválido)
  llegan como HTTP 400 con mensaje genérico "Error creating case - check
  server logs", **sin `body.data`** con detalle de campo. El Code de
  "Evaluar Respuesta IRIS" no debe asumir que `body?.data` traerá
  información útil de qué campo falló — el mensaje genérico es lo único
  fiable para mostrar en el aviso.

**`is_from_api`** [VERIFICADO] `app/iris_engine/utils/tracker.py:63` —
`ua.is_from_api = (request.cookies.get('session') is None if request else False)`:
lo fija el servidor según si la petición trae o no cookie de sesión de
navegador (True cuando llega autenticada por API key), no algo que el
llamante pueda inyectar. `GET /case/activities/list`
(`app/blueprints/case/case_routes.py:218-234`) proyecta ese campo en la
respuesta (línea 225). El plan de verificación F28 del diseño es correcto
tal como está.

**Rama de error del nodo 7 (If vs Switch)**
Recomendación: **`If`**, no `Switch` — la salida de "Evaluar Respuesta IRIS"
es un booleano (`iris_ok`), no una enumeración con más de dos casos; un
`Switch` sobre un booleano añade una rama por defecto sin uso claro y un
punto más donde un camino podría quedar sin nodo terminal. Con `If`: rama
`true` → Referencia en War Room, rama `false` → Aviso Fallo IRIS, ambas
confluyendo en Anuncio en General, tal como ya dibuja el cableado del
diseño. **Comprobación pendiente sobre el propio diseño, no del código de
IRIS:** el nodo "Evaluar Respuesta IRIS" es un Code; si lanza una excepción
no capturada (por ejemplo, `$input.first()` vacío en un escenario no
previsto) y no tiene `onError: continueErrorOutput` configurado, cae en el
comportamiento de n8n de responder `200` internamente sin ejecutar el resto
del flujo — el mismo "aprobación silenciosa" que el proyecto ya tiene
documentado. El diseño no especifica la política de error de este Code node;
debe llevar la misma `onError: continueErrorOutput` (con el error dirigido a
Aviso Fallo IRIS) que ya llevan los nodos 1 y 6, no dejarlo en su valor por
defecto.

---

### P6 — Estado del workflow versionado

**Nodos y estado `active`** [VERIFICADO]
`fase2-orquestador/n8n/workflows/wazuh-alert-handler.json` tiene
**19 nodos** (contados sobre el array `nodes`, no con un grep sobre la clave
`"type"`, que cuenta 44 apariciones porque también cuenta tipos de parámetro
anidados) y `active: false` (línea 6). El fichero interno declara
`updatedAt: 2026-08-25T22:38:55.984Z`, `versionCounter: 474`.

**`export-workflow.sh`** [VERIFICADO, fichero completo leído]
- Elimina `id`, `versionId`, `webhookId`, `meta.instanceId` y `shared`
  (este último contiene el email del propietario en esa instancia de n8n).
- Sustituye `credentials.*.id` por `"REEMPLAZAR"` de forma **genérica**, para
  cualquier tipo de credencial (`.credentials | with_entries(.value.id =
  "REEMPLAZAR")`) — **sí cubre credenciales de tipo Header Auth**: verificado
  en el propio fichero versionado, los 7 nodos con credenciales
  (`rocketchatApi`, `httpHeaderAuth` ×4, `virusTotalApi`, `mispApi`) tienen
  todos `"id": "REEMPLAZAR"` (líneas 88-89, 161-162, 188-189, 279-280,
  375-376, 410-411, 446-447 del fichero versionado). El saneado se aplica
  correctamente y de forma verificable hoy — **este punto ya está resuelto,
  no hace falta ninguna acción**.
- **No hay ningún paso de verificación posterior** dentro del script que
  confirme por sí solo, tras escribir el fichero, que no quedó ningún ID
  real. Propuesta de coste mínimo (no aplicada): añadir al final del script
  un `jq` que falle si queda algún `credentials.*.id` distinto de
  `"REEMPLAZAR"`, por ejemplo:
  ```
  jq -e '[.. | objects | select(has("credentials")) | .credentials[] | .id] | all(. == "REEMPLAZAR")' "$OUTPUT" >/dev/null \
    || { echo "ERROR: quedó un id de credencial real sin sanear" >&2; exit 1; }
  ```

**Sincronización con la instancia viva** [PENDIENTE DE MEDICIÓN]
No es determinable desde el repositorio si hay cambios hechos solo en la UI
de n8n posteriores a la última exportación. `git log` muestra el último
commit sobre el fichero el 2026-09-01 (`22ed2f5`), y `git status`/`git diff`
confirman working tree limpio (sin cambios locales pendientes) pese a que el
`mtime` en disco es de hoy (2026-09-13 00:20) — ese `mtime` no es señal fiable
de edición de contenido (un `checkout` o `stash` puede tocarlo sin cambiar
bytes). El campo interno `versionCounter: 474` sugiere una instancia con
mucho historial de ediciones en vivo, pero no hay una snapshot anterior con
la que comparar ese contador desde el repo. Comando exacto que lo
confirmaría, sin ejecutarlo:
```
./fase2-orquestador/n8n/export-workflow.sh TUzKK9OBP39SYILa /tmp/export-check.json
diff fase2-orquestador/n8n/workflows/wazuh-alert-handler.json /tmp/export-check.json
```
Un diff no vacío (más allá de `updatedAt`/`versionCounter`, que cambian
siempre) confirmaría edición en la UI no exportada aún.

**Ficheros sueltos en `fase2-orquestador/n8n/`** [VERIFICADO]
`ls -la` confirma: `backup-workflows.json`, `w.json`,
`w-backup-2026-08-23-2249.json`, `wf-antes-rotacion-2026-08-23.json`,
`wf-antes-tarea5-2026-08-23-2232.json`, `wf-backup-2026-08-21.json`,
`wf-FUNCIONANDO-2026-08-21.json`, `wf-FUNCIONANDO-2026-08-23.json`.

- **Cobertura por `.gitignore`:** `.gitignore:37-38` —
  `fase2-orquestador/n8n/*.json` con excepción
  `!fase2-orquestador/n8n/workflows/*.json` — cubre **todos** los ficheros
  sueltos anteriores, no solo los que además coinciden con los patrones más
  específicos de `.gitignore:8-10`
  (`wf-backup-*.json`, `cred-inventory.json`, `wf-FUNCIONANDO*.json`).
- **Contenido:** `w.json` (24582 bytes) contiene IDs de credencial reales de
  la instancia de n8n en claro, por ejemplo
  `"rocketchatApi": {"id": "kScBxrDSCtRDxZmnm", ...}`,
  `"httpHeaderAuth": {"id": "Ikt2xj6YgAI7ClXt", ...}`,
  `"virusTotalApi": {"id": "HWGw41rV55NVvKNV", ...}`,
  `"mispApi": {"id": "qyGYEZWarbeNZKBi", ...}` (líneas 130, 243, 265, 361).
  Son identificadores internos del almacén de credenciales de esa instancia
  de n8n (no las API keys en sí), pero identifican de forma persistente qué
  credencial usa cada nodo — exactamente lo que el saneado de
  `export-workflow.sh` existe para evitar publicar.
- **Historial de git:** `git log --all --full-history -- <fichero>` da
  **salida vacía para los 8 ficheros** — ninguno ha llegado nunca al
  historial de git, ni siquiera en un commit posteriormente revertido. El
  `.gitignore` ha funcionado correctamente desde que estos ficheros
  aparecieron.

---

## 3. Diseño corregido

Solo lo que cambia respecto al diseño adjunto. Todo lo no mencionado aquí se
mantiene igual.

**Infraestructura (fuera del JSON de n8n, requisito previo a construir):**
- Añadir alias de red Docker `iris.oob.local` al servicio `nginx` de
  `fase6-iris` en su conexión a `oob-network` (ver P1). Sin esto, el nodo 6
  no puede ni resolver el nombre.
- Fusionar la CA del enclave (`fase6-iris/certificates/rootCA/ca-bundle-oob.crt`)
  con `misp.crt` en un único fichero, y mantener `NODE_EXTRA_CA_CERTS`
  apuntando a ese bundle combinado (ver P2). Sin esto, el nodo 6 falla en
  la validación TLS aunque resuelva el nombre.
- Documento de decisión explícito (tipo `docs/DECISION-*`) registrando que
  la llamada de n8n a IRIS va directa por `oob-network`, sin pasar por
  Traefik/Authelia, y por qué eso es aceptable (protegido por API key +
  red interna no expuesta), listando qué otros contenedores comparten esa
  red.

**Nodo 5 — Preparar Caso IRIS (Code):** corregir la tabla `SEV`:
```js
// Antes (incorrecto, ver P5):
const SEV = { CRITICA: 6, ALTA: 5, MEDIA: 1, BAJA: 4 };
const severity_id = SEV[norm(d.severity_real)] ?? 2;

// Corregido, contra el modelo real de IRIS
// (app/post_init.py:694-707: 1=Unspecified,2=Informational,3=Low,4=Medium,5=High,6=Critical):
const SEV = { CRITICA: 6, ALTA: 5, MEDIA: 4, BAJA: 3 };
const severity_id = SEV[norm(d.severity_real)] ?? 1; // 1 = Unspecified (severidad no reconocida)
```
Nota sobre el valor por defecto: se cambia de `2` (Informational) a `1`
(Unspecified) porque semánticamente una severidad no reconocida por la
tabla es "no determinada", no "informativa". Si el equipo prefiere otro
criterio, es una decisión de negocio, no técnica — pero debe tomarse de
forma explícita, no heredar el `2` original sin motivo declarado.

Añadir un comentario explícito sobre la fragilidad de `classification_id`:
```js
// F14-bis: estos IDs vienen del orden de carga de una taxonomia MISP de
// terceros en el primer arranque de IRIS (post_init.py), no son constantes
// declaradas. Verificar contra la instancia antes de cada uso en produccion
// real: GET /manage/case-classifications/list (o equivalente).
```

**Nodo 6 — Crear Caso IRIS (HTTP Request):** sin cambio en la URL visible
del nodo (sigue siendo `https://iris.oob.local:4833/manage/cases/add`); el
cambio vive en la infraestructura (alias de red + CA), no en el JSON del
nodo. Añadir una nota/comentario en el propio nodo n8n indicando que esta
llamada resuelve dentro de `oob-network` y no pasa por Traefik/Authelia,
para que quien mantenga el workflow no asuma erróneamente que hereda la
protección 2FA del dominio.

**Nodo 7 — Evaluar Respuesta IRIS (Code):**
- Confirmado: usar **`If`** (no `Switch`) sobre `iris_ok` para el
  enrutamiento de nodo 7 a 8/9.
- Añadir política de error explícita al Code node (no dejarlo en el valor
  por defecto de n8n):
```json
{
  "onError": "continueErrorOutput"
}
```
con la salida de error dirigida también a "Aviso Fallo IRIS", para que una
excepción interna del propio Code (no solo un `iris_ok: false` calculado)
no termine en un `200` silencioso.
- No asumir que `body?.data` traerá detalle de campo en un 400 de
  validación (ver P5): la mayoría de errores de negocio de IRIS colapsan a
  un mensaje genérico "Error creating case - check server logs" sin `data`.
  El texto de `motivo` debe apoyarse solo en `body?.message`, no en
  `body?.data`.

**Fuera del Workflow 1 (para cuando se aborde el "Workflow 2" de
evidencia):** en `fase5-orchestrator-api/main.py`, corregir el manifiesto
para no declarar `zip_path`/`zip_sha256`/`selected_by`/`operator` como si
fueran reales mientras no exista el ZIP (ver P3, punto 4). Esto es
independiente del Workflow 1 pero condiciona cualquier diseño futuro que
enlace casos de IRIS con evidencia de Velociraptor.

---

## 4. Duplicidades detectadas

- **"F30" (diseño Workflow 1) vs. fila sin ID en
  `fase5-velociraptor/README.md:194`**: mismo hecho (ZIP nunca generado),
  dos formas de registrarlo, sin enlace cruzado entre ambas. Ver P3.
- **P1-6 usado cuatro veces con significados distintos**, colisión ya
  detectada por el propio proyecto para dos de los cuatro casos
  (`docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:230-234`) y con acción
  de renumeración pendiente desde entonces, nunca ejecutada. Esta revisión
  añade dos apariciones más no detectadas antes. Ver P4.
- **La sigla "F8" ya significa "Fase 8"** en
  `docs/diseno-hook-autorizacion.md:49-55`, con advertencia de ambigüedad ya
  escrita por el propio proyecto en ese mismo documento (líneas 41-44). El
  diseño del Workflow 1 reutiliza "F8" con un tercer significado
  ("hallazgo 8 de este documento"). Ver P4.
- **El patrón de "excepción de ruta en el SSO" ya existe en el repo**, pero
  para n8n, no para IRIS: `fase2-orquestador/n8n/docker-compose.yml:36-46` +
  `fase1-infraestructura/authelia/configuration.yml:43-47`. No es una
  duplicidad de implementación (la vía recomendada para IRIS —P1— no toca
  Authelia en absoluto), pero es el mismo patrón de riesgo que ya vive en el
  proyecto y que esta revisión evita repetir para un servicio más sensible.
- **La norma "nunca degradar en silencio la validación TLS, nunca
  `allowUnauthorizedCerts`"** ya tiene un precedente de implementación en
  `custom-n8n:84-93` (`build_ssl_context`). No es código reutilizable para
  n8n (Python en el host vs. Node en contenedor), pero la corrección de P2
  debe seguir la misma norma, no inventar una nueva.
- El montaje de CA en n8n (`NODE_EXTRA_CA_CERTS`) **ya resuelve el mismo
  problema para MISP** (`fase2-orquestador/n8n/certs/misp.crt`,
  versionado en el repo) — la corrección de P2 es extender ese mecanismo ya
  construido, no crear uno nuevo.
