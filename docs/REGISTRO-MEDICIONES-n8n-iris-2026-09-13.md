# Registro de mediciones n8n→IRIS — 2026-09-13

> Nomenclatura: los identificadores `M-1 … M-n` de este documento son **una
> serie local**, propia de este fichero. No forman parte de la serie global
> P0-*/P1-* del repositorio ni de ninguna otra serie local existente. Cítese
> siempre como `M-n (docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md)`, nunca
> como `M-n` a secas — el repositorio ya arrastra colisiones sin resolver
> entre series locales homónimas (`P1-6`, `P0-3`, `P1-4`, `P1-1`, `F8`,
> documentadas en la sección P4 de `docs/revision-workflow1-caso-iris-warroom.md`)
> y este documento no debe añadir una más.

## 1. Propósito y método

`docs/revision-workflow1-caso-iris-warroom.md` se redactó por la mañana del
2026-09-13 leyendo ficheros de configuración y código fuente vendorizado, y
marcó como `[VERIFICADO]` toda afirmación respaldada por esa lectura. Esa
misma tarde, en una sesión posterior, se sometieron las afirmaciones más
relevantes de esa revisión a **verificación por comportamiento**: ejecutar el
comando real desde donde realmente correría (dentro del contenedor `n8n`,
contra el sistema vivo) y observar la salida, en vez de inferirla de un
fichero de configuración.

Es el mismo estándar que la propia revisión cita como exigencia para
cualquier control nuevo — "cada control que propongas necesita una prueba que
discrimine entre el estado nuevo y el viejo" — aplicado retroactivamente a
las afirmaciones de la revisión misma. El resultado: cinco afirmaciones
`[VERIFICADO]` no resistieron la medición. Ninguna de las cinco era una
afirmación inventada; todas eran lecturas correctas de un fichero que,
tal como estaba, no describía lo que el sistema realmente hace.

Este documento registra las mediciones en el orden en que se hicieron, los
hallazgos nuevos que produjeron, qué afirmaciones de la revisión quedan
refutadas, el cambio aplicado para corregir la causa raíz encontrada, y el
estado resultante de los cuatro bloqueantes que declaraba la revisión.

## 2. Mediciones

Comando ejecutado → salida real observada, en orden cronológico.

**Resolución de nombre de `iris.oob.local` dentro del contenedor n8n:**
```
docker exec n8n node -e "require('dns').lookup('iris.oob.local',(e,a)=>...)"
  → OK 100.64.0.1
```

**Alcance de red del contenedor n8n hacia la tailnet:**
```
docker exec n8n sh -c 'nc -zv -w 5 100.64.0.1 443'
  → 100.64.0.1 (100.64.0.1:443) open

docker exec n8n sh -c 'nc -zv -w 5 100.64.0.1 4833'
  → 100.64.0.1 (100.64.0.1:4833) open
```

**Comportamiento de Authelia ante una petición con `Authorization: Bearer`:**
```
curl -sS -D- -o /dev/null -H "Authorization: Bearer <dummy>" \
  https://iris.oob.local/manage/cases/add
  → HTTP/2 302
    location: https://auth.oob.local/?rd=https%3A%2F%2Firis.oob.local%2Fmanage%2Fcases%2Fadd&rm=GET
    set-cookie: authelia_session=...; domain=oob.local; HttpOnly; secure; SameSite=Lax
```

**Puerto real en el que escucha el nginx de IRIS en la tailnet:**
```
sudo ss -ltnp | grep 4833
  → LISTEN 0 4096 100.64.0.1:4833 0.0.0.0:* users:(("docker-proxy",pid=2941976,fd=8))
```
Contrastado con la configuración declarada:
```
fase6-iris/docker-compose.override.yml:26-27
  → ports: !override
      - "100.64.0.1:${INTERFACE_HTTPS_PORT:-443}:${INTERFACE_HTTPS_PORT:-443}"
  (el .env de fase6 fija INTERFACE_HTTPS_PORT=4833)
```

**Llamada real a la API de IRIS con una clave válida, por la vía de la
tailnet:**
```
curl -sS --cacert fase6-iris/certificates/rootCA/ca-bundle-oob.crt \
  -H "Authorization: Bearer <clave>" https://iris.oob.local:4833/manage/customers/list
  → HTTP/1.1 200 OK
    {"status":"success","data":[{"customer_name":"IrisInitialClient","customer_id":1,...}]}
    Set-Cookie: session=<jwt-like>; Secure; HttpOnly; SameSite=Lax
    (payload del token decodificado: {"permissions": 65535})
    Strict-Transport-Security: max-age=31536000: includeSubDomains
```

**Censo de `oob-network`:**
```
docker network inspect oob-network  → 24 contenedores
```

**Cadena de resolución de nombres real, host y contenedor:**
```
docker exec n8n cat /etc/resolv.conf
  → nameserver 127.0.0.11
    # ExtServers: [host(127.0.0.53)]
/etc/resolv.conf (host) → nameserver 127.0.0.53 (systemd-resolved)
fase4-breakglass-dc/headscale/config/config.yaml:58-66 → extra_records: []
```

**Resolución de los nombres `.oob.local` de servicio desde dentro de n8n:**
```
docker exec n8n node -e "['chat.oob.local','minio.oob.local',
  'velociraptor.oob.local','wazuh.oob.local'].forEach(...)"
  → los cuatro: 127.0.0.1
```

**Origen real del bind de `NODE_EXTRA_CA_CERTS`:**
```
docker inspect n8n → project=n8n, working_dir=fase2-orquestador/n8n,
  volumen con nombre n8n_n8n_data, bind
  fase2-orquestador/n8n/n8n/certs/misp.crt → /usr/local/share/ca-certificates/misp.crt

ls -la fase2-orquestador/n8n/n8n/certs/
  → drwxr-xr-x root root 0  Aug 21 14:44  misp.crt     ← DIRECTORIO, no fichero
docker exec n8n ls -la /usr/local/share/ca-certificates/
  → drwxr-xr-x root root 0  Aug 21 12:44  misp.crt     (hora UTC del contenedor)
```

## 3. Hallazgos nuevos

**M-1 · `NODE_EXTRA_CA_CERTS` inerte durante 23 días.**
El bind `./n8n/certs/misp.crt` del compose de n8n no resuelve desde
`fase2-orquestador/n8n/` — el `working_dir` de ese compose es
`fase2-orquestador/n8n/`, así que la ruta relativa lleva un segmento `n8n/`
de más (compárese con `../../fase4-breakglass-dc/rustdesk/peers.json`, que
sí resuelve correctamente desde ahí). Docker, al no encontrar el origen,
creó `fase2-orquestador/n8n/n8n/certs/misp.crt` como **directorio vacío** el
2026-08-21 a las 12:44 (hora del contenedor). Node, al recibir en
`NODE_EXTRA_CA_CERTS` una ruta que apunta a un directorio y no a un PEM,
**ignora la variable sin emitir ningún error**. Resultado: 23 días
(2026-08-21 → 2026-09-13) sin ninguna CA adicional cargada en el proceso de
n8n, mientras la configuración declaraba lo contrario. Es una instancia más
del patrón de fallo silencioso que el proyecto viene documentando en otras
fases. Corregido — ver sección 5.

**M-2 · La resolución de nombres tiene un tercer sujeto no declarado.**
La cadena real es: `/etc/hosts` del host → `systemd-resolved` (127.0.0.53) →
resolver embebido de Docker (127.0.0.11, `ExtServers: [host(127.0.0.53)]`) →
los 24 contenedores de `oob-network`. Headscale no interviene en ningún
punto de esta cadena (`extra_records: []`). `docs/resolucion-nombres.tsv`
declara dos sujetos de resolución, `ubuntu` y `w11`; los contenedores
heredan el mismo fichero de zona pero con **semántica distinta para la
misma IP**: `127.0.0.1` es correcto y esperado en el host operador (ahí
escucha Traefik), y dentro de un contenedor significa «el propio
contenedor», no el host. Doce de las trece entradas `.oob.local` del TSV
apuntan a loopback; `iris.oob.local` es la única con IP de tailnet
(`100.64.0.1`), y es justamente la que se estaba usando en el diseño del
Workflow 1 — por eso la trampa no se había manifestado hasta ahora.
`verify-hosts.sh` no puede detectar este problema: compara el fichero de
hosts contra el TSV, y ambos coinciden entre sí — el fichero es exactamente
el que el TSV dice que debe ser; el problema es que el TSV no distingue el
sujeto "contenedor" del sujeto "host operador".
Mismo género de problema que P1-1g y que el caso ya conocido del analista
sin acceso al 443. El workflow versionado, en la práctica, **no pisa
ninguna mina**: sus tres nodos de Rocket.Chat usan `http://rocketchat:3000`
— nombre de servicio Docker, no `.oob.local` — así que existe ya una
convención implícita, nunca escrita, de que la comunicación
contenedor→contenedor se hace por nombre de servicio Docker y la
comunicación humano→servicio se hace por nombre `.oob.local`. El nodo 6 del
Workflow 1 (`https://iris.oob.local:4833/...`) rompe esa convención
implícita — con justificación, porque el CN del certificado de IRIS obliga
a usar ese nombre y no el de servicio Docker —, pero la convención en sí
nunca ha estado escrita en ningún sitio, y esta medición es la primera vez
que se hace explícita.

**M-3 · Authelia responde `302`, no `401`, para `iris.oob.local`.**
La medición del `Set-Cookie: authelia_session=...` y el `location:` hacia
`auth.oob.local` confirma una redirección a login, no un rechazo `401`. Esto
es **peor** que un `401` para un cliente automatizado como n8n: el nodo HTTP
Request de n8n sigue redirecciones por defecto, así que la petición
terminaría en **HTTP 200 con el HTML de la página de login de Authelia**, sin
`data.case_id` en ningún sitio del cuerpo. Sería un éxito aparente — el nodo
HTTP no fallaría, "Evaluar Respuesta IRIS" tendría que detectar que el
cuerpo no es JSON de IRIS para no confundirlo con un caso creado. Esta
medición es la justificación más fuerte para no hacer pasar la llamada de
n8n por el 443/Authelia, más sólida que el argumento original de la revisión
("el middleware consume la cabecera `Authorization`"), que no se llegó a
confirmar por medición directa contra IRIS.

**M-4 · Divergencia entre el workflow vivo y el versionado.**
`versionCounter` real de la instancia: 1695, frente a 474 en el fichero
versionado del repositorio. `updatedAt` real: 2026-09-13 11:45, frente a
2026-08-25 en el repo. El diff entre ambos son del orden de 40 hunks, la
mayoría coordenadas de posición de nodos en el canvas, sin efecto funcional.
Tres hunks son sustantivos: el fichero versionado guarda
`"value": "={{ $env.RC_BOT_USER_ID }}"` donde la instancia viva guarda el
valor literal directamente. Medido que ambos estados son **funcionalmente
idénticos**: `docker exec n8n printenv RC_BOT_USER_ID` devuelve exactamente
ese mismo literal. La indirección por `$env` presente en el repo no era, por
tanto, un endurecimiento frente al literal — ambas formas producen el mismo
comportamiento en tiempo de ejecución.

**M-5 · El saneado de `export-workflow.sh` no cubre `parameters`.**
El valor de `RC_BOT_USER_ID` coincide con el **ID de credencial** de
`rocketchatApi` en el almacén de n8n, tal como aparece en
`fase2-orquestador/n8n/w.json:130`. `export-workflow.sh` sustituye
`credentials.*.id` por `"REEMPLAZAR"`, y lo hace correctamente — pero este
identificador concreto no entra al workflow por `credentials`, sino por
`parameters` (como valor de un campo de texto), ruta que ningún paso del
script sanea. El fichero versionado en el repo no expone hoy este
identificador, pero **por accidente**: porque guarda la expresión `$env`
resuelta contra la variable de entorno en vez del literal (M-4). Si en algún
momento se exportara con el literal en vez de la expresión, el ID de
credencial quedaría publicado en el repo sin que el saneado actual lo
detecte. El `jq` de verificación que la revisión propone en su sección P6
tampoco lo detectaría, porque solo comprueba el árbol `credentials`, no
`parameters`.
Cuestión abierta, no medida: un ID de credencial de n8n es casi con
seguridad un valor incorrecto como *user ID* de bot de Rocket.Chat; que los
nodos de Rocket.Chat funcionen así sugiere que Rocket.Chat autentica esas
llamadas por cabecera (`X-User-Id`/`X-Auth-Token`) y no valida ese campo del
cuerpo contra nada. Afecta a qué autor queda registrado en los mensajes del
War Room. Queda sin medir.

**M-6 · `staticData` de ejecución dentro del artefacto versionado.**
El fichero versionado contiene una clave de deduplicación con forma
`"550|ubuntuserver|/etc/prueba-1787697629.conf"`, y una exportación nueva de
la instancia viva trae `"19014|DC01-TFM|..."` y `"19005|DC01-TFM|..."` —
hostnames y rutas de ficheros reales, procedentes de ejecuciones de prueba
concretas. Es estado de ejecución mezclado dentro de lo que se pretende que
sea un artefacto de configuración: ensucia cualquier diff futuro del
workflow con datos que no son configuración, y filtra qué hosts y rutas se
han estado procesando en las pruebas.

**M-7 · La API key de IRIS usada en la medición tiene el bitmask completo de
permisos (65535).**
La llamada de la sección 2 funciona con esa clave, pero n8n no necesita
privilegios de administrador de IRIS para crear casos y consultar la lista
de clientes. Un usuario de API de IRIS dedicado, con permisos acotados a lo
que el Workflow 1 realmente necesita, es la diferencia entre "automatización
con credencial propia y auditable" y "automatización operando con la
credencial del administrador".

**M-8 · Riesgo sobre el instrumento de verificación `is_from_api`.**
IRIS calcula `is_from_api` como "la petición no traía cookie de sesión"
(`app/iris_engine/utils/tracker.py:63`, ya citado en
`docs/revision-workflow1-caso-iris-warroom.md`), y la medición de la
sección 2 confirma que IRIS **emite** una cookie `session` en la respuesta a
toda petición autenticada por API key, no solo a los logins de navegador.
Si el nodo HTTP de n8n llegara a conservar y reenviar esa cookie entre
llamadas encadenadas de un mismo workflow (comportamiento por defecto de
algunos clientes HTTP con manejo de cookies activado), `is_from_api` pasaría
a `false` en esa llamada, y el instrumento que el proyecto usa para
demostrar que fue la automatización quien hizo el trabajo (F28 de la
revisión) quedaría invalidado **en silencio**, con el caso creado
correctamente y sin ningún error visible. Comprobable en la primera
ejecución real de extremo a extremo con
`GET /case/activities/list?cid=<id>`. Queda sin medir.

**M-9 · Cabecera HSTS malformada en el nginx de IRIS.**
La respuesta medida en la sección 2 trae
`Strict-Transport-Security: max-age=31536000: includeSubDomains` — con dos
puntos separando la segunda directiva donde la especificación exige punto y
coma (`max-age=31536000; includeSubDomains`). El navegador o cliente HTTP
descarta la directiva `includeSubDomains` sin emitir ningún error visible.
Impacto trivial, pero del mismo género que M-1: una protección declarada que
no está realmente activa, sin que nada lo señale.

**M-10 · `git push` empujaba a los dos remotos por configuración oculta.**
`remote.origin.pushurl` estaba definido **dos veces** en la configuración
git de este repositorio (una entrada para `origin`, otra para el remoto de
respaldo), de modo que un `git push` a secas ya cubría ambos destinos, y el
`git push backup main` que el protocolo del proyecto documenta como segundo
paso era redundante con el primero sin que nada lo advirtiera. Corregido con
`git config --unset-all remote.origin.pushurl`; el protocolo de dos pasos
(`git push` + `git push backup main`) vuelve a corresponder literalmente a
lo que ejecuta. Ambos remotos son HTTPS con autenticación email+token, no
SSH.

**M-11 · Corrección al estado del P1-1a.**
La medición de la sección 2 confirma que `minio.oob.local` y
`velociraptor.oob.local` **sí están** presentes en `/etc/hosts` y en
`docs/resolucion-nombres.tsv` (líneas 33-34 para `ubuntu`, 43-44 para
`w11`). El estado que el hilo del P1-1a daba por bloqueado y sin ejecutar
para esas dos entradas estaba desactualizado respecto al sistema real.
Queda por confirmar, al abordar el P1-6, que las entradas `velociraptor.local`
y `minio.local` que la línea 16 del mismo TSV documenta viven donde deben
(en el DC, no en el host operador): no aparecen en el `/etc/hosts` de
`ubuntu`, medido en esta misma sesión.

## 4. Afirmaciones refutadas del documento de revisión

Las cinco afirmaciones siguientes de `docs/revision-workflow1-caso-iris-warroom.md`
estaban marcadas `[VERIFICADO]` y no resistieron la medición de la sección 2.
En los cinco casos la lectura del fichero de configuración citado era
correcta; lo que fallaba era la suposición implícita de que esa
configuración describe el comportamiento real del sistema.

1. **Bloqueante 1 / P1 — "`iris.oob.local` no resuelve dentro del contenedor
   n8n".** La revisión lo dedujo de la ausencia de `extra_hosts`/`dns:` en
   el compose de n8n y de que `docs/resolucion-nombres.tsv` solo declara
   `ubuntu` y `w11` como sujetos. La medición (`docker exec n8n node -e
   "dns.lookup('iris.oob.local', ...)"`) devuelve `100.64.0.1`: **sí
   resuelve**. La causa es la cadena de tres capas de M-2, que la lectura de
   configuración no podía ver porque no está declarada en ningún fichero.

2. **P1 — "n8n no tiene ninguna vía de red hacia `100.64.0.1`".** Deducido de
   la ausencia de `network_mode`, `NET_ADMIN` o sidecar tailscale en el
   compose de n8n. La medición (`nc -zv 100.64.0.1 443` y `:4833` desde
   dentro del contenedor) confirma **ambos puertos abiertos y alcanzables**.

3. **P1 — "la única vía físicamente disponible es `oob-network` contra el
   nginx de IRIS directamente".** Refutada por las dos anteriores: existía
   también la vía por la tailnet al 4833 publicado. La vía finalmente
   correcta (llamar al 4833 de la tailnet, sin pasar por el 443/Authelia,
   justificada ahora por M-3, no por la imposibilidad de red que se había
   asumido) es una **tercera** opción, distinta tanto de la rechazada
   (nombre de servicio Docker) como de la que la revisión terminó
   recomendando (alias de red en `oob-network`).

4. **P1 / Bloqueante 4 — "el `ports: !override` publica el nginx solo en
   `100.64.0.1:443`".** La revisión citó literalmente
   `${INTERFACE_HTTPS_PORT:-443}` del override y leyó `443` como el puerto
   real. La medición (`ss -ltnp | grep 4833`) confirma que el puerto
   realmente publicado es **4833**: el `.env` de fase 6 fija
   `INTERFACE_HTTPS_PORT=4833`, y `:-443` es solo el valor por defecto de la
   variable cuando no está definida — no lo que efectivamente ocurre en este
   despliegue. Consecuencia directa: la recomendación de la revisión de
   crear un alias de red Docker en `fase6-iris` para llegar por
   `oob-network` resulta **innecesaria** — el 4833 de la tailnet ya es
   alcanzable y resoluble tal como está.

5. **P2 / Bloqueante 2 — "el fichero `misp.crt` montado existe, 1870 bytes,
   `CN=localhost`".** La revisión midió el fichero que existe en el árbol
   del repositorio bajo `fase2-orquestador/n8n/certs/misp.crt`, pero ese no
   es el fichero que el compose monta: el `working_dir` del compose es
   `fase2-orquestador/n8n/`, así que el bind relativo `./n8n/certs/misp.crt`
   apunta a `fase2-orquestador/n8n/n8n/certs/misp.crt` — una ruta con un
   segmento `n8n/` de más, que no existía y que Docker creó como
   **directorio vacío** (M-1). El diseño original del Workflow 1, redactado
   antes de esta revisión, afirmaba "apunta a un directorio vacío" — la
   revisión lo corrigió creyendo que se equivocaba, y en realidad **tenía
   razón**, aunque no supiera por qué.

## 5. Cambio aplicado y verificado

Aplicado en el commit `4a97225` ("fix(n8n): NODE_EXTRA_CA_CERTS apuntaba a un
directorio vacío"), posterior a esta sesión de medición:

- Corregido el bind de `fase2-orquestador/n8n/docker-compose.yml` de
  `./n8n/certs/misp.crt` a `./certs/misp.crt`, para que resuelva realmente
  desde `fase2-orquestador/n8n/`.
- Sustituido el contenido confiado: en vez de `misp.crt`
  (`CN=localhost`, que en cualquier caso nunca podría validar el hostname
  `misp` del nodo MISP), se añadió la CA del enclave dedicada,
  `fase2-orquestador/n8n/certs/oob-rootCA.crt`
  (`CN=OOB Enclave Root CA`, autofirmado, `notAfter=2036-08-21`, SHA256
  `AB:11:4F:F8:A6:08:F2:9F:FB:C5:59:5F:54:B3:AC:6C:4E:65:4D:FB:C4:9B:0F:0E:68:21:28:14:19:EC:82:5C`,
  sin clave privada, un único certificado), y `NODE_EXTRA_CA_CERTS`
  apuntando a ella.
- Se descartó incluir `misp.crt` en el nuevo bundle de confianza: como
  `CN=localhost` nunca podría validar el hostname `misp` del nodo MISP, ese
  nodo sigue dependiendo de `allowUnauthorizedCerts` — hallazgo ya abierto
  en el proyecto, ahora con la causa entendida — y añadir ese certificado al
  almacén de confianza de n8n no habría cambiado nada al respecto.

**Control discriminante**, desde dentro del contenedor n8n contra
`iris.oob.local:4833`:
```
antes:    FAIL UNABLE_TO_VERIFY_LEAF_SIGNATURE
después:  HTTP 401   (cadena válida; falla por credencial, no por red ni TLS)
```
Los dos estados fallan de forma distinta — antes por cadena de confianza,
después por autenticación —, que es lo que hace útil el control: el mismo
resultado antes y después no habría demostrado nada.

Verificado además tras el cambio: el fichero montado en
`/usr/local/share/ca-certificates/` es un fichero regular de 1992 bytes, no
un directorio; `NODE_EXTRA_CA_CERTS` apunta a él; las credenciales
configuradas en n8n y el workflow importado sobrevivieron a la recreación
del contenedor; la interfaz de n8n sigue accesible.

## 6. Estado de los cuatro bloqueantes de la revisión

| # | Bloqueante declarado en la revisión | Estado tras medición |
|---|---|---|
| 1 | `iris.oob.local` no resuelve en el contenedor n8n | **Falso** — resuelve a `100.64.0.1` (sección 4.1) |
| 2 | La CA montada en n8n es la equivocada (MISP en vez de la del enclave) | **Causa invertida** — no era la CA equivocada, era un directorio vacío por un bind mal resuelto (sección 4.5). Corregido en `4a97225` |
| 3 | Tabla `severity_id` incorrecta para MEDIA y BAJA | **En pie** — es el único de los cuatro bloqueantes originales que la medición no toca; sigue pendiente de corregir en el diseño |
| 4 | Falta documentar la decisión de arquitectura de la ruta n8n→IRIS | **Premisa falsa** — el cambio que la revisión proponía para resolverlo (alias de red Docker en `fase6-iris`) es innecesario (sección 4.4); la necesidad de documentar la decisión sigue vigente, pero con un contenido distinto (sección 7) |

## 7. Pendiente

- Corregir en el diseño del Workflow 1 la tabla `SEV` a
  `{ CRITICA: 6, ALTA: 5, MEDIA: 4, BAJA: 3 }`, con valor por defecto `1`
  (Unspecified) — bloqueante 3, sigue en pie, no depende de nada de lo
  medido en esta sesión.
- Redactar el documento de decisión de la ruta n8n→IRIS con el contenido
  correcto que esta medición establece: la llamada va al puerto 4833
  realmente publicado por el override de fase 6 en la tailnet (no al 443);
  Authelia no interviene en esa ruta **porque no está en el camino de red**,
  no porque se le esquive deliberadamente; la dependencia frágil real no es
  ninguna excepción de SSO, sino la cadena de resolución de nombres de tres
  capas descrita en M-2.
- Declarar en `docs/resolucion-nombres.tsv` (o en un documento asociado) el
  tercer sujeto de resolución identificado en M-2 (contenedores de
  `oob-network`, vía el resolver embebido de Docker) y la convención
  implícita, hasta ahora nunca escrita, de que la comunicación
  contenedor→contenedor usa nombre de servicio Docker y la comunicación
  humano→servicio usa nombre `.oob.local`.
- Verificar que el nodo de MISP del workflow sigue funcionando tras la
  retirada de `misp.crt` del almacén de confianza de n8n (predicción: sí,
  porque ese nodo depende de `allowUnauthorizedCerts`, no de
  `NODE_EXTRA_CA_CERTS`; sin medir).
- Medir M-8 (persistencia de la cookie `session` de IRIS entre llamadas
  encadenadas de un mismo workflow de n8n, y su efecto sobre `is_from_api`)
  en la primera ejecución real de extremo a extremo.
- Medir la cuestión abierta de M-5 (si Rocket.Chat valida o ignora el campo
  del cuerpo que hoy contiene, por accidente, un ID de credencial de n8n).
- Sanear `export-workflow.sh` para cubrir también valores sensibles que
  entren por `parameters`, no solo por `credentials` (M-5); el `jq` de
  verificación que propone la sección P6 de la revisión necesita la misma
  ampliación.
- Corregir el bind en `fase2-orquestador/n8n/n8n/certs/` (el directorio
  vacío que dejó M-1) y limpiar el `staticData` de ejecución del workflow
  versionado (M-6) antes de la próxima exportación.
- La Fase 5_4b (evidencia de Velociraptor) **no se aborda** hasta que exista
  una recolección real: escribir un `file_hash` en IRIS a partir del
  manifiesto actual convertiría un hueco de almacenamiento en un registro
  falso de cadena de custodia — ya señalado en la sección P3 de la revisión,
  y esta sesión de medición no cambia esa conclusión.

## 8. Adenda — cierre de la Fase 5_4a

Sesión de cierre, 2026-09-13 tarde/noche. Las secciones 1-7 se conservan tal
como se redactaron; esta adenda cierra dos de los puntos que quedaban
abiertos allí (M-5, M-8) sin reescribir sus entradas originales, y registra
lo que apareció al ejercitar el flujo completo con alertas reales.

### Cierre parcial de M-5

El valor `kScBxrDSCtRDxZmnm` **sí es** el user ID real del bot de
Rocket.Chat: confirmado en la salida del nodo `Crear War Room`, donde
`group.u._id` es exactamente ese valor, con `username: orchestrator-bot`.
Que coincida en formato con un ID de credencial de n8n es casualidad — ambos
son `ObjectId` de Mongo, de la misma forma pero de dos almacenes distintos.
La cuestión abierta que M-5 dejaba sin medir —si Rocket.Chat valida ese
campo del cuerpo o lo ignora— queda resuelta: **era correcto**, no una
coincidencia inofensiva sobre un dato erróneo.

Lo que de M-5 sigue en pie es el hueco de saneado ya descrito allí: ese
mismo valor viaja en `parameters`, y `export-workflow.sh` no lo cubre.

### Cierre de M-8

`GET /case/activities/list?cid=4` devolvió `is_from_api: true` para el caso
creado por n8n. El instrumento funciona tal como F28 de la revisión lo
preveía. Matiz que queda abierto: se verificó con **una sola** llamada al
caso. El riesgo de reutilización de cookie que M-8 planteaba se manifestaría
con llamadas encadenadas sobre el mismo caso — que es justo lo que hará el
Workflow 2 al añadir una nota y un evento de timeline después de crear el
caso. Sin medir ese escenario todavía.

### M-12 · `$env` no resuelve en expresiones de nodos HTTP

La cabecera `X-User-Id` con valor `={{ $env.RC_BOT_USER_ID }}` produjo
«authorization failed» en Rocket.Chat; con el literal en su lugar, funciona.
`printenv RC_BOT_USER_ID` dentro del contenedor devuelve el valor correcto,
así que la variable existe y está accesible al proceso — lo que falla es su
resolución dentro de la expresión de un nodo HTTP Request, que termina
enviando la cabecera vacía. `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` está fijado
en el compose, pero esa variable gobierna el acceso a `$env` desde nodos
Code, no desde expresiones de parámetros de otros tipos de nodo.

Lo relevante no es el fallo en sí, sino su mensaje: «authorization failed»
apunta al token, no a la variable no resuelta — es el tipo de mensaje que
casi lleva a regenerar una credencial que estaba sana. Es un error de
diagnóstico inducido por el mensaje, no causado por el fallo real.

Estado: el nodo `Referencia en War Room` usa el literal como solución
temporal. El valor no es secreto en sí mismo — es el user ID público del
bot, visible en cualquier respuesta de la API de Rocket.Chat —, pero al ir
como literal acabará en el JSON versionado del workflow porque el saneado de
`export-workflow.sh` no cubre `parameters` (mismo hueco que M-5). Pendiente
de investigar por qué `$env` no resuelve ahí.

### M-13 · Carrera entre las ramas paralelas de Rocket.Chat e IRIS

Con `Preparar Caso IRIS` colgando de `Abrir War Room` en paralelo con
`Crear War Room`, la rama de IRIS llegaba antes de que el canal existiera, y
`$('Crear War Room').first()` lanzaba `Node 'Crear War Room' hasn't been
executed`. El encadenamiento opcional entre ramas paralelas no protege
contra esto, tal como ya advierte el comentario de `Code Merge Final`.

El nodo afectado por esta carrera era, en concreto, `Aviso Fallo IRIS` — el
nodo que precisamente debe avisar cuando algo falla —, y al llevar
`continueErrorOutput`, el fallo no quedaba visible en ningún sitio: se
perdía en silencio.

Resuelto serializando el cableado (`Contexto en War Room → Preparar Caso
IRIS`, en vez de dos ramas paralelas desde `Abrir War Room`) y resolviendo
`room_id` una sola vez dentro del Code, con la convención `salidaDe()` para
no volver a depender de referencias cruzadas a nodos que podrían no haberse
ejecutado todavía.

### M-14 · AbuseIPDB devuelve 0 para una IP maliciosa conocida

En las pruebas con `185.220.101.5` (nodo de salida Tor conocido), AbuseIPDB
devolvió `abuse_confidence: 0`, `abuse_total_reports: 0`,
`abuse_country: N/A` y `abuse_is_tor: false`, mientras que en la misma
alerta VirusTotal marcó 12 motores como maliciosos y MISP aportó 5
atributos.

`Code CTI Context` no distingue «sin reputación registrada» de «no se pudo
consultar la fuente»: los `?? 0` que usa convierten cualquier fallo de la
consulta en un cero legítimo, indistinguible de una IP realmente limpia. El
score consolidado de esa alerta fue 14 (CRITICA) pese a perder una de las
tres fuentes de CTI, así que el resultado final fue correcto — pero por la
robustez del cálculo de score frente a una fuente ausente, no porque
AbuseIPDB hubiera funcionado. Sin medir la causa concreta del cero (clave
agotada, error de la API, formato de respuesta inesperado). Es el mismo
patrón que M-1: la ausencia de señal es indistinguible de la señal cero, y
nada en el flujo actual lo señala.

### M-15 · Tres campos que el triaje envía vacíos desde siempre

El cuerpo que n8n manda a `langgraph-agent` interpola
`{{$json.wazuh.timestamp}}`, pero `Normalize Alert` produce el campo
`event_timestamp`, no `timestamp` — ese campo no existe en el objeto que se
interpola. El mismo cuerpo pide también `cti.misp_threat_level` y
`cti.misp_attributes_summary`, que `Code CTI Context` nunca produce (solo
genera `misp_total`). Los tres llegan al agente como cadena vacía, dentro de
un JSON por lo demás válido, sin que nada emita un error. El triaje lleva
funcionando sin marca de tiempo de evento y sin contexto MISP resumido desde
que existe, sin que esto hubiera sido detectado hasta ejercitar el flujo
completo con alertas reales en esta sesión.

### Estado final de la Fase 5_4a

El bloqueante 3 de la revisión (tabla de `severity_id`) se verificó por
comportamiento, no solo por lectura de código: una alerta CRITICA produjo un
caso real en IRIS con severidad Critical (caso #4, `severity_id: 6`). Los
dos caminos del flujo del Workflow 1 —éxito y fallo— se ejercitaron con
alertas reales, no como supuestos de diseño. El camino de fallo se probó
forzando una URL inválida en el nodo de creación del caso, y el War Room y
el aviso de fallo se comportaron como el diseño corregido preveía.

La corrección de la tabla `SEV` está **aplicada y commiteada** (`7d20797`),
no pendiente: la sección 7 se redactó antes de aplicarla. Lo que sigue
abierto es su verificación. Esta prueba cubre únicamente CRITICA, que es el
valor que la tabla vieja ya mapeaba bien (`CRITICA: 6` en ambas); **MEDIA y
BAJA, que eran precisamente los dos valores mal mapeados, no se han
ejercitado todavía**. Una alerta de nivel bajo y sin grupos de
autenticación produciría BAJA y permitiría confirmar que llega a IRIS como
Low (3) y no como Medium (4). Hasta entonces el bloqueante 3 está corregido
con verificación parcial.

## 9. Fase 5_4b — la recolección de Velociraptor deja de ser simulada (2026-09-17)

### Estado de partida (lo que se corrige)

`/velociraptor/collect` no recolectaba nada:

- `zip_sha256` era `sha256(incidentid + host + ts)` — el hash de tres
  identificadores concatenados, sin relación con ningún fichero.
- El `zip_path` del manifiesto apuntaba a un objeto que **nunca se subía**:
  solo había `put_object` para `manifest.json` y `sha256.txt`.
- `started_at == ended_at` en todos los manifiestos.
- `sha256.txt` contenía el hash inventado, así que no verificaba nada.

El endpoint tenía ya la envoltura de seguridad completa —HMAC con anti-replay
ordenado para no filtrar nonces, `ORCH_REQUIRE_HMAC` con default `true`, lista
blanca de perfiles, identificadores acotados contra traversal— alrededor de
un hueco donde debía estar la recolección. El diagnóstico correcto no era "el
endpoint está mal diseñado" sino "los controles están bien y falta lo que
protegen".

### Mediciones de la sesión (comando → resultado)

```
acl show orchestrator            → {"roles":["investigator"]}
VQL SELECT … FROM clients()      → 3 clientes activos: W11, DC01-TFM, ubuntuserver
collect_client Windows.System.Pslist sobre el DC
                                 → FINISHED, 138 filas, 12.0 s
create_flow_download(wait=TRUE)  → fs:/downloads/C.…/F.…/DC01-TFM-….zip
read_file(accessor='fs') por gRPC → 0 bytes, sha256 e3b0c442… (fichero vacío)
sha256sum del ZIP en el filestore → 08d6dee6…61583 (hash de referencia)
```

Prueba end to end del endpoint ya reescrito, con petición firmada:

```
POST /velociraptor/collect  {"incidentid":"INC-TEST-5B","host":"DC01-TFM",
                             "profile":"ransomware_triage"}
→ HTTP 200, status "completed"
  flow_id F.DALTALD2Q52JO, client_os windows, 131 filas
  started_at 20260917T115605Z  /  ended_at 20260917T115614Z   (9 s, distintos)
  zip_size_bytes 29374
  zip_sha256 967541d6cb0e6a1d2f9363ff3d997006545a0b53412f7c6f1063f3fcc1bea235
```

Verificación de la cadena de custodia — **el mismo hash en tres puntos
independientes**:

```
filestore de Velociraptor (sha256sum)  → 967541d6…bea235
manifest.json en MinIO                 → 967541d6…bea235
objeto descargado de MinIO (29374 B)   → 967541d6…bea235
sha256.txt                             → "967541d6…bea235  velociraptor_collection.zip"
```

El `sha256.txt` pasa a formato compatible con `sha256sum -c`: un tercero
puede descargar el ZIP y ese fichero a un directorio y verificar la
integridad con un comando estándar, fuera del workflow. Era el criterio
fijado al abrir la fase.

### Hallazgos nuevos

**M-16 · `api_config: {}` no era la causa.**
Una medición anterior identificó ese campo como el motivo de que la API gRPC
estuviera deshabilitada. Es un campo distinto: el servidor API lo define el
bloque `API:`, que ya existía con `bind_address: 127.0.0.1`. No estaba
deshabilitado, estaba escuchando donde ningún otro contenedor podía
alcanzarlo.

**M-17 · Leer el ZIP por gRPC devuelve 0 bytes sin error.**
`read_file` con accessor `fs` sobre la ruta del filestore no falló: devolvió
una respuesta vacía, y el hash resultante fue `e3b0c442…`, el del fichero
vacío. De no haberse comparado contra un `sha256sum` de referencia, se habría
subido a MinIO un ZIP vacío con un hash consistente consigo mismo. Mismo
patrón que M-1 y M-14: la ausencia de señal es indistinguible de la señal
cero si no se contrasta con una referencia externa.

**M-18 · `COPY main.py .` en el Dockerfile.**
El módulo nuevo `velociraptor_client.py` no entraba en la imagen porque el
Dockerfile copiaba un solo fichero por nombre. Aquí falló ruidosamente (el
import es obligatorio y el contenedor reiniciaba en bucle), pero un módulo
opcional habría dejado la imagen corriendo con código desincronizado del
repositorio sin aviso.

**M-19 · El orchestrator corre como root** (`uid=0`), y va a manejar
evidencia forense. No se cambia en esta fase; queda anotado como superficie
mayor de la necesaria.

**M-20 · Los artefactos de `ALLOWED` son todos de Windows**
(`Windows.System.Pslist`, `Windows.Network.Netstat`,
`Windows.Memory.Acquisition`) y hay un cliente Linux registrado
(`ubuntuserver`). Una petición con ese host lanzaría artefactos Windows
contra un agente Linux. El manifiesto registra ahora
`velociraptor_client_os`, de modo que la incoherencia quedaría documentada
si ocurriera, pero no se impide.

### Pendiente tras esta fase

- **Etapa D**: enlazar la evidencia al caso IRIS vía `/case/evidences/add`.
  Ya no está bloqueada — el `file_hash` corresponde a un fichero que existe.
- Usuario no-root para el orchestrator (M-19).
- Validar el SO del cliente contra el perfil pedido (M-20).
- `COPY . .` con `.dockerignore` en vez de copiar ficheros por nombre (M-18).

## 10. Sesión 2026-09-18

### M-21 · El rechazo de firma HMAC no deja rastro observable

Cuando el nodo de verificación HMAC del Workflow 1 rechazó una firma
inválida, el flujo murió sin ejecución visible en n8n, sin mensaje en ningún
canal de Rocket.Chat y sin entrada en los logs del contenedor. El control
funcionó —rechazó lo que debía rechazar—, pero desde fuera el resultado es
indistinguible de «el webhook no recibió nada». Con una alerta real de
Wazuh sería una alerta perdida en silencio.

Encuadrado frente al hallazgo de *fail-open* de n8n ya registrado en el
proyecto (un error interno cerraba la petición con HTTP 200 y rttys lo leía
como aprobación): allí el control falla abierto, aquí falla cerrado —que es
lo correcto— pero sin dejar constancia. Son las dos caras del mismo
defecto: el resultado del control no se distingue del no-evento. Lo que
pide no es cambiar el control, sino un observable donde el rechazo quede
registrado. Nótese que el instrumento de verificación está por definir: un
rechazo que solo se apunte en el log de n8n no sería verificable, porque en
esta ocasión no dejó rastro ni ahí.

### M-22 · El defecto de la cadena de clasificación era específico, no genérico

La entrada original de esta sesión afirmaba que el nodo `Preparar Caso
IRIS` fija `classification_id: 15` en todos los casos, y que el caso #44 lo
llevaba. Ninguna de las dos cosas era cierta. La medición posterior
estableció lo que sigue, y esta entrada la sustituye por completo.

**Lo que hay realmente en el nodo.** `Preparar Caso IRIS` (tipo Code)
contiene una cadena de mapeo de tres ramas sobre `rule_groups`, no un valor
fijo:

- valor inicial `14` (`intrusion-attempts:exploit-known-vuln`);
- si los grupos incluyen `authentication_failed`, `authentication_failures`,
  `sshd` o `win_authentication_failed` → `15`
  (`intrusion-attempts:login-attempts`);
- si incluyen `rootcheck`, `rootkit` o `malware` → `10`
  (`malicious-code:rootkit`).

**El defecto.** El valor inicial de la cadena es una clasificación
específica. Todo lo que no casa con las dos ramas conocidas —es decir, todo
lo que el código no ha clasificado— queda registrado en IRIS como
«explotación de vulnerabilidad conocida». El caso #44 (alerta SCA real,
`rule.groups` medido como `['sca']`) no está mal clasificado por un error
de mapeo: está mal clasificado porque el «no sé» del código afirma un hecho
concreto. Verificado que IRIS guarda exactamente lo que recibe
(`classification_id: 14`, `classification:
intrusion-attempts:exploit-known-vuln` en `/manage/cases/list`), de modo
que no hay desajuste entre lo enviado y lo almacenado.

**Encuadre.** Es la misma familia que el resto del documento: la ausencia
de señal produce una señal positiva indistinguible de una medición real.
Un analista que abra el caso no ve «sin clasificar», ve una clasificación
concreta y falsa. A diferencia del ruido de canales de Rocket.Chat, esto no
se limpia borrando: queda en el histórico de casos de IRIS, que es el
artefacto que el proyecto presenta como cadena de custodia.

**La corrección aplicada** (commit `cb9a8dd`): el valor inicial pasa a `36`
(`other:other`), con un comentario en el código que explica por qué el
defecto debe seguir siendo genérico. Las dos ramas `15` y `10` no se
tocan: son mapeos correctos y medidos.

**La taxonomía, medida.** El comentario del propio nodo advertía que estos
IDs vienen del orden de carga de una taxonomía MISP de terceros en el
primer arranque de IRIS (`post_init.py:638-660`) y no son constantes
declaradas, y pedía verificarlos contra la instancia. Esa verificación se
hizo con `GET /manage/case-classifications/list`: la instancia devuelve 36
clasificaciones, y los tres IDs que el nodo usa son correctos en ella.
Quedan registrados, como mínimo, los relevantes para el enclave:

| id | nombre | uso |
| --- | --- | --- |
| 10 | `malicious-code:rootkit` | rama `rootcheck`/`rootkit`/`malware` |
| 14 | `intrusion-attempts:exploit-known-vuln` | antiguo defecto, retirado |
| 15 | `intrusion-attempts:login-attempts` | rama de autenticación |
| 31 | `vulnerable:vulnerable-service` | candidato para CVE, sin implementar |
| 33 | `conformity:standard` | candidato para hallazgos SCA, sin implementar |
| 36 | `other:other` | defecto actual |

31 y 33 son candidatos para una ampliación futura del mapeo, no decisiones
tomadas: la ampliación depende del censo de grupos, y el genérico 36 es el
paso honesto mientras tanto, no el destino.

**Error de diagnóstico que merece quedar escrito.** La afirmación falsa de
partida («`classification_id: 15` fijo para todos los casos») salió de leer
el valor esperado que documenta `PROCEDIMIENTO-prueba-manual-webhook.md`
para una alerta de SSH —donde 15 es correcto— y generalizarlo al
comportamiento del nodo sin abrirlo. Es la misma clase de error que este
documento atribuye a la revisión de la mañana del 2026-09-13: una lectura
correcta de un artefacto, falsa sobre el sistema.

Anotar también, como defecto menor del mismo origen: la recomendación que
el triaje emitió para el caso #44 fue «Abrir War Room y determinar el
vector: sin IP publica sobre la que actuar» — una plantilla redactada para
incidentes con IP de origen, aplicada a una alerta que no puede tener
vector.

### M-23 · La supresión de escalada está atada a un grupo, no a una categoría

El filtro añadido el 2026-09-17 en `tool_generate_response_flags` suprime
la escalada cuando `rule_groups` contiene `vulnerability-detector`. Medido
en la alerta del caso #44: `rule.groups` es `['sca']`, un único grupo sin
ningún token en común con el anterior, por lo que el filtro no podía
alcanzarla.

**Decisión tomada (Jose, 2026-09-18): el filtro no se amplía a `sca`.** Un
hallazgo con severidad que no sea un CVE del inventario sigue escalando
como incidente para que se investigue. La duda que queda abierta no es de
criterio sino de volumen: se desconoce cuántos tipos distintos de alerta
generan los endpoints, y por tanto si alguna otra familia puede desbordar
como lo hizo el detector de vulnerabilidades. Esa pregunta se responde con
el censo de `scripts/censo-grupos-alertas.py` (tarea 1 de este mismo
prompt), no estimándola.

Criterio de diseño que se fija para cualquier ampliación futura del
filtro: **lista de supresión, nunca lista de escalada**. Si el criterio
fuese «escalan solo estos grupos», un grupo nuevo correspondiente a una
regla de ataque real dejaría de escalar sin que nada lo señalara. Con lista
de supresión, un grupo de postura no contemplado se cuela como incidente:
ruido visible y corregible. Es el mismo criterio que `ORCH_REQUIRE_HMAC`
con valor por defecto `true` en el orchestrator — el defecto no desactiva
el control.

### M-24 · Censo de la población real de alertas

Medido con `scripts/censo-grupos-alertas.py` sobre `alerts.json` y los 52
rotados de `/var/ossec/logs/alerts/2026/`: **52.513 alertas parseadas, 53
ficheros, cero líneas ilegibles**, ventana del 2026-05-16 al 2026-09-18.

Reparto por agente: `ubuntuserver` 41.163, `DC01-TFM` 6.052, `W11` 5.025,
`wazuh.manager` 273.

Hallazgos:

1. **El 71% del volumen es el enclave vigilándose a sí mismo.** Las cuatro
   reglas más frecuentes son eventos de Docker en `ubuntuserver` —volúmenes
   montados y desmontados, redes conectadas y desconectadas—, más de 37.000
   eventos del grupo `docker`, una de ellas nombrando literalmente el
   volumen de n8n. Nivel bajo, así que no escalan, pero inundan el índice y
   las métricas. No es hallazgo de seguridad; sí lo es sobre la relación
   señal/ruido de un SIEM que monitoriza su propia infraestructura.
2. **`vulnerability-detector` no era el único candidato a desbordar.** Son
   1.843 alertas con nivel máximo 13, y por eso se filtró. Pero por encima o
   cerca del umbral de escalada hay más: `ossec` 5.419 (nivel máx. 11,
   eventos del propio Wazuh), `windows` 2.999 (máx. 10), `sca` 1.962 (máx.
   9), `windows_system` 636 (máx. 10), `windows_application` 2.140 y
   `system_error` 228 (máx. 9). El nivel máximo no dice cuántas alertas de
   cada grupo lo alcanzan, así que esto acota candidatos, no decide nada.
3. **El camino más ejercitado es el más raro en la población real.**
   `authentication_failed` son 25 alertas en cuatro meses y `sshd` aparece
   **una sola vez** — con toda probabilidad la inyección manual de hoy. El
   laboratorio no recibe ataques reales, lo cual es esperable, pero debe
   quedar escrito al interpretar cualquier métrica de detección del TFM.

Limitación de lectura que hay que dejar explícita: el laboratorio no está
encendido de forma continua, así que los recuentos son «cuántas veces
apareció cada tipo mientras el laboratorio estuvo vivo», no una tasa
diaria, y no se extrapolan. Misma limitación que el proyecto ya aplica a
las métricas de disponibilidad.

### M-25 · La representación de «no aplica» está resuelta por separado en cada plantilla

Una alerta sin IP de origen (SCA, y cualquier otra sin `src_ip`) se
representa de forma distinta en cada sitio que la escribe, porque cada
plantilla resuelve el caso por su cuenta:

- `Preparar Caso IRIS` — correcto: el helper `md()` rinde `N/D`.
- `Anuncio en General` — producía `desde .`, con la IP vacía y el punto
  suelto. Corregido en `cb9a8dd` con un ternario local.
- `Contexto en War Room` — sigue emitiendo `🌐 IP origen:` con el valor
  vacío. Sin corregir.
- Plantilla de `#alertas-cve` — mismo `🌐 IP Fuente:` vacío, y además repite
  MITRE tres veces (táctica, técnica y combinado) con los tres «no
  determinado». Sin corregir.

A esto se suma el motor determinista de `fase3-agentic`, que emite
«determinar el vector: sin IP publica sobre la que actuar» para alertas que
no pueden tener vector — una plantilla escrita para el caso con IP aplicada
al caso sin ella.

El defecto no es cosmético en su origen: son cinco consumidores repitiendo
una lógica que debería estar resuelta una sola vez en `Code Merge Final`,
donde ya existe el helper. Registrado como deuda; no bloquea, porque un
campo vacío no afirma nada falso —a diferencia del `classification_id` de
M-22, que sí lo hacía—. Esa es la razón por la que uno se corrigió de
inmediato y el otro no.

### Nota sobre M-14 · el 0 de AbuseIPDB ya es persistente, no incidental

M-14 (sección 8) registró que AbuseIPDB devolvió `0` para
`185.220.101.5` el 2026-09-13, sin medir la causa. El 2026-09-18, la misma
IP en el caso #46 vuelve a dar `abuse_confidence: 0`, `abuse_total_reports:
0`, país `N/A`, mientras VirusTotal marca 13 motores maliciosos y 3
sospechosos y MISP aporta 5 atributos.

Ya no es un resultado aislado, sino un estado persistente a lo largo de
cinco días. La causa concreta sigue sin medir (clave agotada, error de la
API, formato de respuesta inesperado). Los `?? 0` de `Code CTI Context`
siguen haciendo indistinguible «sin reputación registrada» de «no se pudo
consultar la fuente» — el mismo patrón que M-1 y M-17. El score consolidado
absorbió la pérdida de esta fuente en las dos ocasiones, así que el
veredicto final fue correcto por robustez del cálculo, no porque la fuente
funcionara.

### Correcciones a entradas previas de este registro

Subsección aparte, sin tocar el texto original de las entradas corregidas.
Tres entradas quedan refutadas, las tres por el mismo mecanismo: una
lectura correcta que nunca se cruzó con otra medición del propio
documento.

- **M-4** concluyó que el fichero con `={{ $env.RC_BOT_USER_ID }}` y la
  instancia viva con el literal eran «funcionalmente idénticos», apoyándose
  en que `printenv RC_BOT_USER_ID` devuelve el valor dentro del contenedor.
  Eso es una medición sobre la variable, no sobre la expresión. Medido el
  2026-09-18: los cuatro nodos que llevan ese valor (`Contexto en War
  Room`, `Anuncio en General`, `Crear War Room`, `Referencia en War Room`)
  son todos de tipo `n8n-nodes-base.httpRequest`, que es el ámbito exacto
  donde M-12 midió que `$env` no resuelve y termina enviando la cabecera
  vacía. Consecuencia: entre `22ed2f5` y `7d20797` **el fichero versionado
  era el estado roto**; quien lo hubiera reimportado tendría los cuatro
  nodos enviando `X-User-Id` vacío. La instancia viva nunca estuvo mal.
  `7d20797` no deshizo un endurecimiento: puso la única forma que funciona.
  El endurecimiento de `22ed2f5` existió solo en el artefacto, nunca en el
  sistema.
- **M-5** dio por hecho que el valor `kScBxrDSCtRDxZmnm` coincide con el ID
  de credencial de `rocketchatApi` en `fase2-orquestador/n8n/w.json:130`.
  La cadena sí está en esa línea, pero medido el inventario completo de IDs
  de credencial del repositorio: todos los demás tienen 16 caracteres, sin
  una excepción, y este tiene 17. Es decir, ese campo
  `credentials.rocketchatApi.id` de `w.json` no contiene un ID de
  credencial de n8n: contiene el user ID del bot de Rocket.Chat colocado en
  un hueco etiquetado como ID de credencial. No hay dos almacenes que
  generaran la misma cadena. Consecuencia: la preocupación de exposición de
  M-5 se reduce a que el literal publicado es el user ID público del bot,
  que no es secreto. El hueco de saneado de `export-workflow.sh` sobre
  `parameters` sigue en pie como deuda de limpieza, no como riesgo.
- **La adenda que cerraba M-5** atribuía la coincidencia a que ambos
  valores son `ObjectId` de Mongo, «de la misma forma pero de dos
  almacenes distintos». Un `ObjectId` son 24 caracteres hexadecimales; este
  valor son 17 alfanuméricos de caja mixta. La conclusión de la adenda (el
  valor es correcto como user ID del bot) es acertada; el mecanismo que
  propone para explicarla, no.

Cerrar la subsección con el patrón de segundo orden, que es la aportación
de esta sesión: **el propio registro acumula entradas que se contradicen
entre sí sin que nada lo señale**, porque cada una se verificó contra el
sistema y ninguna contra las demás. Es la misma familia de defecto que el
documento documenta en el sistema —una afirmación correcta sobre su objeto
y falsa sobre el conjunto— aplicada al instrumento de verificación. Tres de
veintitrés entradas, encontradas por accidente al preparar un `grep` para
otra cosa.

### Verificación adicional que queda registrada como no hecha

Estado tras la sesión del 2026-09-18: lo que cerró por comportamiento y lo
que sigue abierto.

**Cerrado por comportamiento el 2026-09-18:**

- Defecto de clasificación: caso #45 (`sca`) → 36, caso #46
  (`sshd`/`authentication_failed`) → 15, caso #47 (`sca` sin IP) → 36,
  frente a los casos #43 y #44 con 14 como estado previo. La prueba de
  no-regresión (#46 sigue dando 15) es la que da valor a la otra: sin ella,
  un cambio que rompiera el mapeo sería indistinguible de uno que
  corrigiera el defecto.
- CRÍTICA con IP pública escala: caso #46, score 14, War Room
  `#inc-5710-1789721608-1660` y caso creado.
- `Fuente ATT&CK` deja de ser `unmapped`: el caso #46 da
  `T1110 - Brute Force / TA0006 - Credential Access`, fuente `heuristic`.
  El `unmapped` del caso #44 no lo contradice: la regla 19005 es un resumen
  SCA y su grupo no está en la tabla de mapeo, así que ahí `unmapped` es el
  resultado correcto.
- Supresión de CVE, **las dos ramas**: la rama falsa con tres alertas (#45,
  #46, #47) y la rama verdadera con una inyección de grupo
  `vulnerability-detector`, que produjo aviso en `#alertas-cve`,
  `create_war_room: false`, `requires_block: false`, severidad ALTA
  conservada y la recomendación de parcheo — sin War Room y sin caso IRIS.
  Hasta esa inyección, la rama verdadera del `If` nunca se había ejecutado:
  los veinte canales de ayer se crearon antes del arreglo.
- `CRITICA → 6` reconfirmada; primer tercio de M-15 cerrado (el
  `timestamp` corregido llega al triaje, verificado en el campo Evento del
  caso #46).

**Sigue abierto:**

- `MEDIA` y `BAJA` de la tabla `SEV`, que eran los dos valores mal
  mapeados. `ALTA → 5` quedó sin confirmar: se creó el caso #45 con
  severidad ALTA pero no se consultó su `severity_id`.
- Los otros dos tercios de M-15: `misp_threat_level` y
  `misp_attributes_summary` siguen sin producirse en `Code CTI Context` y
  viajan vacíos al triaje.
- **El síntoma que abrió la sesión quedó sin causa identificada.** Se
  partía de que tres alertas «acabaron en `#general`», y se sospechó del
  nodo de CVE recién añadido. La sesión demuestra que el enrutado funciona
  y que el aviso en `#general` es un nodo por diseño que publica el enlace
  al War Room, no un destino final. No se ha determinado si aquellas tres
  alertas crearon o no su War Room; si el comportamiento reaparece no
  habrá pista previa. Anotarlo como no explicado, no como resuelto.
- `rule_desc` se interpola cruda dentro de la cadena JSON del cuerpo de
  `Anuncio en General`. Una descripción de regla con una comilla doble
  rompería el cuerpo y el nodo fallaría. Es el mismo texto que `Preparar
  Caso IRIS` sí neutraliza con `md()` antes de mandarlo a IRIS, y viene
  parcialmente de datos que un atacante influye.

## 11. Sesión 2026-09-18 (tarde) — Etapa D

### M-26 · Esquema de `/case/evidences/add`, medido

`CaseEvidenceSchema` declara **un único campo obligatorio**: `filename`
(`Length(min=2)`). Todo lo demás lo hereda del modelo `CaseReceivedFile` por
`SQLAlchemyAutoSchema`, y en ese modelo **ninguna columna es
`nullable=False`** salvo `file_uuid`, que se autogenera.

Nombres reales de campo: `filename`, `file_hash`, `file_size`, `type_id`,
`file_description`, `acquisition_date`, `start_date`, `end_date`. `case_id`
y `user_id` los pone IRIS: el primero desde el query string `?cid=N`, el
segundo desde el usuario de la API key.

Tipo de evidencia **39 = «Collection - Velociraptor»**, que IRIS trae de
serie.

Fechas: se acepta `YYYY-MM-DDTHH:MM:SS` **sin zona horaria** y se devuelve
intacto. Distinto de `EventSchema` del timeline, que exige microsegundos y
`event_tz`.

`chain_of_custody` queda `null`: IRIS **no escribe nada ahí por su cuenta**.
Si el proyecto presenta cadena de custodia, la sostienen el manifiesto y el
`sha256.txt` de MinIO, no ese campo.

### M-27 · Un nombre de campo erróneo produce una evidencia sin hash, con HTTP 200

Prueba negativa medida: `POST /case/evidences/add?cid=56` con el hash bajo
la clave `file_sha256` en lugar de `file_hash` devuelve `status: success` y
crea una evidencia con `file_hash: null`.

Causa: `unknown = EXCLUDE` en el esquema sobre una columna nullable. El
campo desconocido se descarta en silencio y nada en la cadena lo detiene.

Es la instancia más grave del patrón que documenta este registro. En
`AlertSchema` el resultado era una alerta vacía; aquí es **una evidencia
forense registrada en el caso, visible en el listado, que no acredita
integridad alguna**. Un perito que la viera daría por hecho que hay hash
verificado.

Consecuencia de diseño, aplicada en el workflow: `Comparar Hash` lee la
evidencia de vuelta y **busca por hash** en el listado —no toma la última—,
y publica un aviso explícito si no la encuentra. El 200 del alta no
acredita el efecto.

### M-28 · `cid` vacío en IRIS devuelve 401, no 400

Un `GET /case/evidences/list?cid=` (parámetro presente pero vacío) devuelve
`401 {"status":"error","message":"Authentication required"}`. La
credencial era correcta; el defecto estaba en la petición. Diagnóstico
desviado hacia las credenciales durante el cableado.

### M-29 · Un `case_id` inexistente devuelve 500, no 404

`GET /case/evidences/list?cid=<caso borrado>` devuelve `500 Internal
Server Error`. En el log de `iriswebapp_app`: `KeyError: 'permissions'` en
`ac_current_user_has_permission`
(`app/iris_engine/access_control/utils.py:1142`), que lee
`session['permissions']` donde una petición por API key no tiene sesión de
navegador.

Desde fuera, «este caso no existe» y «el servidor está roto» son
indistinguibles. Costó un diagnóstico equivocado el 2026-09-18: se atribuyó
a falta de acceso efectivo del usuario de API a los casos creados por la
automatización, hipótesis que se construyó sobre casos que estaban siendo
borrados en paralelo. La refutó un `200` sobre un caso vivo (#56).

Es código vendorizado de IRIS: se registra, no se parchea.

### M-30 · La dirección del orchestrator tiene semántica doble

El orchestrator arranca con `uvicorn --host 0.0.0.0 --port 8000` y el
contenedor publica `8000/tcp -> 127.0.0.1:8020`. Comprobado desde dentro
del contenedor: el 8000 está abierto y el 8020 cerrado.

Por tanto `http://127.0.0.1:8020`, que es lo que figura en la tabla de
datos de entorno, es **la vista del host**. Desde n8n —mismo
`oob-network`, alias `orchestrator`— la URL es `http://orchestrator:8000`.
Usar el puerto del host desde un contenedor produce `ECONNREFUSED`.

Misma familia que M-2: una dirección correcta para un sujeto y engañosa
para otro, sin que ningún fichero lo declare.

### M-31 · Etapa D verificada de extremo a extremo

Caso IRIS **#62**, 2026-09-18. Alerta inyectada (regla 5714, `sshd` /
`authentication_failed`, IP 185.220.101.5, agente DC01-TFM) → triaje
CRITICA score 14 → caso IRIS con `severity_id` 6 y `classification_id` 15
→ War Room → recolección real por gRPC → ZIP en MinIO → evidencia
enlazada al caso.

Colección: flow `F.DAMLV9PKLOBUU`, cliente `C.c7302a34a17948ec`
(DC01-TFM, windows), perfil `generic_high_signal_collection`, 127 filas,
29025 bytes. Objeto en
`s3://evidence/INC-62/DC01-TFM/20260918T155828Z/velociraptor_collection.zip`.

**sha256 `04a4fe554a2b707c4ba9125c65571d8d6f12b2a5875fb684670a00942ad657dc`
idéntico en cuatro puntos independientes:** el registro de evidencia de
IRIS, el `sha256.txt` del bucket, el `manifest.json`, y el recálculo sobre
los bytes del objeto descargado de MinIO. `file_size` 29025 coincide en
IRIS y en el objeto.

Registrar como **no verificado todavía**: la prueba negativa de `Comparar
Hash` —forzar un nombre de campo erróneo en `Preparar Evidencia` y
comprobar que el aviso sale como fallo— está pendiente. El nodo está
ejercitado solo en el camino correcto.

### Incidencias de cableado, para no repetirlas

Los cuatro fallos que costaron una inyección cada uno durante el montaje
de los seis nodos:

1. Marcador `<nombre-medido>` pegado literalmente en la URL del nodo →
   `ERR_INVALID_URL`.
2. `case_id` leído de `Crear Caso IRIS`, cuya salida es
   `{statusCode, body:{...}}` por estar configurado con full response. El
   valor ya normalizado vive en `Evaluar Respuesta IRIS` como
   `iris_case_id`.
3. `{{ $json.case_id }}` en un nodo cuya entrada es la respuesta de IRIS y
   no el objeto propio → `cid` vacío. Se resuelve referenciando el nodo por
   nombre: `{{ $('Preparar Evidencia').first().json.case_id }}`.
4. Un nodo HTTP nuevo **no hereda la credencial**: `Verificar Evidencia`
   salió sin `Authorization` y devolvió 401.

Nota positiva que merece constar: la salida de error de `Lanzar
Recolección` estaba cableada a un aviso, y por eso el primer fallo se vio
de inmediato en lugar de morir en silencio. Es el remedio directo del
patrón de M-21.

## 12. Sesión 2026-09-18 (noche) — Filtro de postura

### M-32 · El filtro de supresión estaba atado a un grupo, no a una categoría — resuelto

El filtro del 2026-09-17 suprimía la escalada solo para
`vulnerability-detector`. Los hallazgos SCA no quedaban cubiertos: nueve
casos IRIS creados en un minuto el 2026-09-18 (casos #48 a #56, `soc_id` de
1789725832 a 1789725893), todos resúmenes o controles del benchmark CIS,
ninguno describiendo actividad.

**La medición que decidió.** Censo sobre cuatro meses de alertas
(`scripts/censo-grupos-alertas.py`, 52.513 alertas, 53 ficheros, cero
líneas ilegibles). Por encima del umbral de escalada (nivel ≥ 9):

| regla | nivel | alertas | descripción |
| --- | --- | --- | --- |
| 23505 | 10 | 396 | CVE-2026-50449 en Windows Server 2025 |
| 19014 | 9 | 141 | Control CIS incumplido (Windows Server 2025) |
| 19005 | 9 | 104 | Resumen SCA, puntuación baja |
| 19011 | 9 | 45 | Control CIS incumplido (Ubuntu 24.04) |
| 23506 | 13 | 24 | CVE-2026-50447 |
| **521** | **11** | **7** | **Possible kernel level rootkit** |

**La solución aplicada** (`7808ac1`): `GRUPOS_POSTURA =
{"vulnerability-detector", "sca"}` en `tool_generate_response_flags`, y el
flag pasa de `is_vulnerability` a `is_posture_finding`, que es lo que de
verdad describe. Un flag llamado «vulnerability» que marca hallazgos SCA es
la misma clase de afirmación falsa que el `classification_id` por defecto
de M-22.

**Criterio de diseño, fijado y aplicado: lista de supresión, nunca lista de
escalada.** Si el criterio fuera «escalan solo estos grupos», un grupo
nuevo de una regla de ataque real dejaría de escalar sin que nada lo
señalara. Con lista de supresión, un grupo de postura no contemplado se
cuela como incidente: ruido visible y corregible.

**`rootcheck` queda deliberadamente fuera**, pese a parecer de la misma
familia. La regla 521 («Possible kernel level rootkit», nivel 11, 7 alertas
en la población real) vive en ese grupo y sí describe actividad. La
cautela de no ampliar el filtro a grupos sin medir dejó de ser una
precaución teórica: la medición muestra exactamente el caso que se habría
silenciado.

Verificado por comportamiento: `sca` y `vulnerability-detector` al canal de
postura sin War Room ni caso; `sshd`/`authentication_failed` abre War Room,
caso #63 y evidencia de Velociraptor.

### M-33 · La supresión funcionaba a medias: la cadena forense seguía ejecutándose

Durante la verificación del filtro, una alerta de postura —suprimida
correctamente en cuanto a War Room y caso— **continuó hasta los nodos de la
etapa D**, lanzando la cadena de recolección y fallando al registrar
evidencia en un caso que no existía.

El síntoma que lo delató fue un `401` en `Verificar Evidencia`, no un error
que mencionara la supresión. Sin ese fallo, una alerta suprimida habría
seguido disparando recolecciones forenses de forma invisible: el control
impedía el registro del incidente pero no el consumo de recursos ni la
actividad sobre el endpoint.

Registrar como lección de método: **verificar que una rama suprimida
termina donde debe, no solo que no produce el efecto observable que se
estaba buscando.** Comprobar que no se crea el caso no es comprobar que la
alerta deja de recorrer el flujo.

### M-34 · El nodo `Anuncio en General` se perdió al recablear, sin aviso

Al montar los seis nodos de la etapa D, la configuración de `Anuncio en
General` quedó incompleta y el aviso dejó de publicarse. No hubo error
visible: el mensaje simplemente no aparecía, y se detectó por comparación
con ejecuciones anteriores de la misma tarde, no por ninguna señal del
sistema.

Mismo género que M-21: una función que deja de operar sin que nada lo
distinga de «no había nada que publicar». La diferencia aquí es que el
nodo llevaba funcionando ese mismo día, lo que permitió detectarlo; sin ese
contraste habría pasado por comportamiento normal.

### M-35 · Medir mientras se borra invalida la medición

Dos diagnósticos equivocados en la misma jornada, ambos por el mismo
motivo: se midió contra un sistema del que se estaban borrando objetos en
paralelo.

1. **El `500` del caso #47** se atribuyó a que el usuario de la API no
   tenía acceso efectivo a los casos creados por la automatización, con una
   hipótesis construida sobre `user_case_effective_access`. La refutó un
   `200` sobre un caso vivo (#56): el caso #47 estaba siendo borrado
   durante la consulta. Ver M-29 sobre por qué un caso inexistente devuelve
   500 y no 404.
2. **El Workflow 2 se dio por roto.** Una consulta a `cases_events` mostró
   cuatro eventos, todos en el caso 1, ninguno en casos de la
   automatización, lo que llevó a concluir que el enriquecimiento nunca
   había escrito nada. Falso: los casos con eventos se habían borrado en la
   limpieza. Comprobado después de la sesión de la noche: `cases_events`
   tiene eventos en los casos 63 y 67 además del 1. **El Workflow 2
   funciona.**

Lección de método, aplicable a todo el proyecto: no limpiar mientras se
mide, y ante un resultado anómalo, comprobar primero que el objeto medido
sigue existiendo. Desde fuera, un objeto borrado y un defecto real son
indistinguibles.

### M-36 · El vaciado manual de `staticData` se olvidó dos veces en una tarde

`export-workflow.sh` sanea `credentials.*.id` pero no `staticData` ni
`parameters`. El vaciado manual del bloque `staticData` se olvidó en dos de
los tres commits del día que tocaban el workflow (`cb3454e` y `7808ac1`), y
hubo que corregirlo después en cada caso.

Un paso manual que se olvida dos veces en una tarde no es un paso manual:
es un defecto pendiente de automatizar. Registrar como argumento directo
para ampliar `export-workflow.sh` a `staticData` y `parameters`, con su
prueba negativa — exportar y que ambos greps devuelvan cero.

### M-37 · Un campo en modo *fixed* envía la plantilla como literal, sin fallar

El campo URL del nodo `Verificar Evidencia` quedó en modo *fixed* en lugar de
*expression*. n8n no avisa de eso: envía
`?cid={{ $('Preparar Evidencia').first().json.case_id }}` tal cual, como texto.

IRIS tampoco rechaza la petición. Devuelve **HTTP 200 con la lista de
evidencias de otro caso** —el que resuelve por defecto—, vacía. Dos capas
encadenadas que convierten un error de configuración en una respuesta plausible
y falsa: ni n8n ni IRIS emiten señal alguna.

El síntoma que lo delató no fue un error sino un detalle del contenido:
`object_last_update: 2026-06-26T16:07:45` —la fecha de instalación de IRIS— en
una respuesta que decía describir un caso creado minutos antes.

Distinto de M-28, donde un `cid` **vacío** devuelve 401. Aquí el `cid` no está
vacío: contiene basura, y eso IRIS lo resuelve en silencio.

### M-38 · Un control que siempre responde lo mismo no distingue nada, aunque acierte

Durante tres inyecciones consecutivas, `Comparar Hash` publicó «La evidencia no
acredita integridad». El mensaje era prudente, sonaba correcto, y coincidía con
lo que se esperaba ver en la prueba negativa. Se dio por acreditado el control.

No lo estaba: leía el caso equivocado (M-37), así que respondía exactamente lo
mismo con el hash bien puesto y con el hash manipulado. **La prueba negativa fue
un falso positivo** — el resultado correcto por el motivo equivocado.

Lo que lo destapó fue comprobar por fuera que la evidencia sí existía en IRIS
con el hash correcto, contradiciendo el mensaje que publicaba el control.

**Regla que queda establecida para el proyecto:** un control solo está
verificado cuando se ha comprobado que responde de forma **distinta** ante
entradas distintas. Ver que avisa en el caso malo no basta si no se ha visto
callar en el caso bueno. Un veredicto conservador —«no acredita»— es
especialmente engañoso, porque el sesgo natural es aceptarlo sin examinarlo.

Verificación definitiva, ya con el campo en modo expresión:

- caso **#76** → «✅ Hash verificado contra el registro de IRIS»,
  sha256 `5ab864c086fc0097a6c8611f9b6e48b7527f32dff803d24902c926dfe6a4b575`,
  flow `F.DANQNRAF0GFHU`, 129 filas.
- caso **#77**, con el hash enviado como `file_sha256` en lugar de `file_hash`
  → «ninguna de las 1 evidencias del caso casa con el hash del manifiesto.
  Presentes: **(sin hash)**».

Dos mensajes distintos ante dos entradas distintas. Ese `(sin hash)` es M-27
visto desde el otro extremo: IRIS aceptó el alta con `success`, creó la
evidencia, y el campo del hash quedó vacío.

Recurrencia. Esta entrada repite el patrón que M-35 acababa de nombrar como
lección de método: aceptar un resultado plausible sin cruzarlo con otra
fuente. Entre una y otra median menos de dos horas. Tener la lección escrita
en el propio documento no impidió volver a cometerla, lo que sugiere que
estas lecciones no operan como recordatorio sino solo como explicación a
posteriori — salvo que se conviertan en un paso obligatorio del
procedimiento.

### M-39 · `Comparar Hash` no estaba conectado a nada

El nodo calculaba el veredicto correctamente y su salida no iba a ningún sitio:
el aviso moría dentro de la ejecución, sin publicarse en ningún canal.

Un control que detecta y no comunica es, operativamente, un control que no
detecta. Mismo patrón que M-21, esta vez en el control que sostiene la cadena de
custodia. Resuelto con un nodo que publica el veredicto en el War Room del
incidente —no en `#general`: es información del caso concreto, y su sitio es el
canal donde se trabaja ese caso.

La revisión de cableado de la sección 11 recorrió los nodos uno a uno sin
detectar que `Comparar Hash` carecía de conexión de salida.

## 13. Sesión 2026-09-20 — Renombrado del canal con el case_id

### M-40 · El `case_id` en el nombre del canal elimina la resolución por consulta

El War Room se crea **antes** que el caso IRIS, así que el `case_id` no puede
incluirse al crear el canal. Se resuelve renombrando con `groups.rename` en la
rama de éxito, justo después de publicar la referencia al caso.

Formato: `inc-<case_id>-<rule_id>-<alert_id saneado>`. Verificado:
`inc-78-5703-1789899607-6039`.

Medido antes de implementarlo, contra un canal de prueba: `groups.rename`
devuelve `200` con el bot como propietario del canal, y el nombre objetivo se
acepta tal cual. Rocket.Chat además deja constancia del cambio dentro del propio
canal («changed room name to …»), lo que da trazabilidad sin coste.

El nombre nuevo se compone recortando el prefijo del nombre actual
(`replace(/^inc-\d+-/, '')`) en lugar de volver a sanear el `alert_id`: así no
hay dos implementaciones del saneado que puedan divergir.

**Lo que esto elimina.** El Workflow 2 resolvía canal → caso consultando
`/manage/cases/list` y comparando `case_soc_id` saneado, filtrando cerrados y
quedándose con el más reciente. Esa lógica estaba **duplicada**: una cadena para
el comando de timeline (`Resolver Caso IRIS` → `Listar Casos IRIS` →
`Buscar Caso`) y otra idéntica para la auditoría de accesos (`Auditar: resolver
caso` → `Listar Casos IRIS1` → `Buscar Caso1`), con los dos nodos `Buscar Caso`
byte a byte iguales salvo el nodo del que leían. El sufijo `1` delataba el
duplicado por copia.

Resultado: cuatro nodos eliminados, dos consultas HTTP menos por ejecución, y
una sola lógica de resolución donde había dos copias que podían divergir —el
mismo defecto ya anotado para los miembros del War Room frente a
`IR_APPROVER_IDS`. El commit tiene 220 inserciones frente a 334 borrados: menos
código con más funcionalidad.

**Lo que se pierde a conciencia.** La resolución directa ya no filtra casos
cerrados. Si el caso se cerrara con el War Room aún activo, el Workflow 2
escribiría en un caso cerrado. Se acepta: un War Room activo con su caso cerrado
es en sí una anomalía, y reintroducir la consulta para cubrir ese supuesto
devolvería la complejidad que este cambio elimina.

Verificado por comportamiento en los tres caminos: el comando de timeline
registra en el caso 78; la auditoría de una aprobación de break-glass registra
en el mismo caso (eventos 13, 14 y 15 en `cases_events`, comprobados
directamente en la base de datos); y desde un canal que no es War Room el bot
responde que el canal no tiene formato de War Room, en vez de callar.

### M-41 · El hueco de saneado de `parameters` contenía un secreto real

M-5 describió que `export-workflow.sh` sanea `credentials.*.id` pero no
`parameters`, y evaluó el riesgo con el único caso conocido entonces: el
`X-User-Id` del bot, que es un identificador público. Esa evaluación resultó
incompleta.

El workflow de break-glass (`fase4d-breakglass.json`) construía sus llamadas a
Rocket.Chat con las dos cabeceras a mano —`X-User-Id` y **`X-Auth-Token`**— en
lugar de usar la credencial Header Auth. Medido el 2026-09-20: **ocho nodos**
con el token del bot en claro dentro de `parameters`, y el fichero commiteado y
publicado en los dos remotos.

No era un nodo despistado de una prueba: era el patrón por defecto con el que se
construyó ese workflow. Los nodos afectados cubrían casi toda su interacción
(verificación de autoría de mensajes, publicación de respuestas, avisos de
solicitud pendiente, resultado del agente, confirmaciones y avisos de fallo).

**Gravedad.** El token gobierna el bot que concede accesos de emergencia al
controlador de dominio. Un identificador público expuesto es deuda de limpieza;
un token operativo expuesto es un incidente, aunque los repositorios sean
privados y los servicios solo se alcancen por la tailnet.

**Cómo se llegó a la decisión correcta.** Una primera lectura concluyó que el
token no estaba commiteado (`git grep` sobre HEAD no devolvió nada) y se acordó
aplazar la rotación. La comprobación posterior con `git show HEAD:<fichero>`
mostró ocho apariciones con el valor real. La premisa sobre la que se había
aplazado era falsa, y al caer, la decisión cambió.

Se descartó reescribir la historia: borrar el commit exige force-push a los dos
remotos, el objeto sigue siendo accesible por su hash durante un tiempo y
persiste en cualquier clon, y el token seguiría siendo válido. **Limpiar el
fichero no invalida un secreto; rotarlo sí.**

**Resuelto:** los ocho nodos migrados a la credencial Header Auth, el token
rotado en Rocket.Chat y actualizada la credencial en n8n. El export posterior
devuelve cero apariciones de `X-Auth-Token`. El orden importó: se rotó primero,
de modo que los nodos que aún llevaran la cabecera vieja fallaran de forma
visible en lugar de seguir funcionando con un secreto publicado.

**Consecuencia para M-5:** el hueco de `parameters` deja de ser deuda de
limpieza y pasa a ser riesgo de fuga de secretos. Refuerza la ampliación
pendiente de `export-workflow.sh`, que debe cubrir `parameters` y `staticData`.

**Relación con entradas previas.** M-5 y su adenda cerraron este hueco como
deuda de limpieza tras comprobar que el único valor conocido en `parameters`
era público. La medición era correcta; la conclusión excedió su alcance: «no
he visto un secreto ahí» no equivale a «no puede haberlo». M-36 planteaba la
ampliación de `export-workflow.sh` como argumento de higiene, y esta entrada
le cambia el peso retroactivamente: es una medida de seguridad. Y el push a
los dos remotos (M-10) propagó el secreto a ambos automáticamente — la misma
configuración que protege el trabajo multiplicó el alcance de la fuga.

### M-42 · `export-workflow.sh` ya admite ID y ruta como argumentos

El script acepta `./export-workflow.sh [WORKFLOW_ID] [RUTA_SALIDA]` y por
defecto exporta el de Fase 2. El workflow de break-glass no tenía script propio
y se exportó con el mismo, pasando su ID y la ruta de destino.

Eso importa porque el saneado de `credentials.*.id` a `REEMPLAZAR` solo ocurre
por esa vía: una exportación cruda dejaría los IDs reales en el fichero
versionado. Conviene documentarlo en el README de Fase 4 para que no haya que
redescubrirlo, y para que nadie exporte ese workflow por otro camino.

## 14. Sesión 2026-09-20 (tarde) — Saneado del export y cierre de M-14

### M-43 · El `staticData` del break-glass guardaba credenciales de acceso, no solo estado

`export-workflow.sh` se amplió para vaciar `staticData` automáticamente, porque
el vaciado manual se había olvidado en tres commits de una semana (M-36). El
argumento era de higiene. Al ejecutarlo por primera vez sobre el workflow de
break-glass, el diff mostró qué contenía realmente ese bloque:

- `staticData.global.requests` — las solicitudes de acceso, con solicitante,
  aprobador, canal de origen y marcas de tiempo.
- `staticData.global.credentials` — **la contraseña temporal de RustDesk en
  claro**, junto con el `rustdesk_id`, su `expires_at` y el flag `consumed`.

Medido sobre la historia del fichero: cuatro commits contienen bloques de
credenciales, y dos de ellos (`39c186f` y `d244e09`, tres entradas en total)
con `password` presente y `consumed: false`. Las contraseñas son efímeras,
únicas por solicitud y con TTL, y todos esos TTL habían expirado, así que no
hubo credencial viva publicada.

**Pero la ventana existía.** Entre que una solicitud se aprueba y su TTL
caduca median minutos. Un export hecho dentro de esa ventana habría publicado
en los dos remotos una contraseña **válida** de acceso de emergencia al
controlador de dominio. El vaciado automático deja de ser higiene y pasa a ser
una medida de seguridad con nombre propio.

Registrar también la asimetría que esto revela: el detector de secretos del
propio script **no lo habría visto**. Solo inspecciona `parameters` y solo
cadenas de 32 caracteres o más; la contraseña de RustDesk vive en `staticData`
y tiene 20. Lo que la atrapó fue el vaciado, no la detección. Ese punto ciego
no es un fallo del detector construido a raíz de M-41: es el límite propio de
un control con umbral, y conviene saberlo antes de apoyarse en él para lo que
no cubre.

### M-44 · Sanear por patrón sin excepción para expresiones borra lógica legítima

El saneado nuevo sustituye por `REEMPLAZAR` el valor de las cabeceras de
autenticación conocidas dentro de `parameters` (lista de supresión:
`x-auth-token`, `authorization`, `x-api-key`, `apikey`, `key`, `token`,
`x-token`). En su primera versión se llevó por delante un valor que no era un
secreto: `Authorization: =Bearer {{ $env.AGENT_TOKEN }}`, la llamada al agente
del DC.

Eso no es un secreto: es una expresión de n8n que lee una variable de entorno
en tiempo de ejecución. Sustituirla deja el fichero versionado sin servir para
restaurar —el mismo defecto de M-4, un artefacto endurecido que no corresponde
al sistema, pero esta vez provocado a propósito por la herramienta. Es el
mismo defecto reproducido por la vía contraria: la herramienta que existe
para proteger fue, en su primera versión, la que lo causó.

Corregido con una excepción por forma, no por lista: **no se sanean los valores
que empiezan por `=`**, porque un secreto literal nunca empieza así y toda
expresión de n8n sí. Verificado: tras el arreglo, `AGENT_TOKEN` vuelve a
aparecer en el fichero exportado y el diff queda reducido a `staticData`.

Lo que el episodio enseña: un filtro de saneado tiene dos formas de fallar, y
la segunda es menos visible. Dejar pasar un secreto se descubre tarde y duele;
borrar lógica legítima no duele hasta que alguien intenta restaurar desde el
fichero, probablemente meses después. Por eso la prueba del filtro se hizo en
los dos sentidos: que atrape el token sobre el fichero que lo contenía, y que
el `X-User-Id` y las expresiones sobrevivan intactos.

### M-45 · Cierre de M-14 — AbuseIPDB usaba la credencial de Rocket.Chat

M-14 registró el 2026-09-13 que AbuseIPDB devolvía `0` para una IP que
VirusTotal y MISP sí marcaban, sin medir la causa. El 2026-09-18 se comprobó
que el mismo resultado persistía con la misma IP, cinco días después, y se
elevó de incidente a estado persistente. Ahora tiene causa.

**Medición.** Consulta directa a la API con `curl`, con la clave cargada en la
shell: `HTTP 200` con `abuseConfidenceScore: 100`, `totalReports: 301`,
`isTor: true`, nodo de salida Tor en Berlín. La API funciona y la clave es
válida, así que el cero no era «sin reputación».

**Causa.** El nodo `AbuseIPDB` tenía asignada la credencial `Header Auth
account`, que es la de Rocket.Chat y envía la cabecera `X-Auth-Token`. La API
de AbuseIPDB exige la cabecera `Key`. Le llegaba una cabecera que no entiende y
ninguna de las que necesita, así que respondía 401. Esa credencial la comparten
cinco nodos más, todos de Rocket.Chat, donde sí es la correcta: una sola
credencial genérica no puede servir a APIs que esperan cabeceras con nombres
distintos.

**Por qué no se vio antes.** El nodo tiene `onError: continueRegularOutput` y
`alwaysOutputData: true`, así que el 401 salía por la salida normal como item
vacío. En `Code CTI Context`, cada `?? 0` convertía la ausencia en un cero
idéntico al de una IP sin reportes. Es el mismo patrón que este registro
documenta en otros sitios: la ausencia de señal produce una señal positiva
indistinguible de una medición real.

**No era cosmético.** `tool_score_incident` suma 2 puntos si
`abuse_confidence > 50`. Todos los casos anteriores se puntuaron con una fuente
caída y perdieron esos 2 puntos. Esto se verificó por predicción: antes de
tocar nada se anunció que, corregida la credencial, el mismo payload pasaría de
score 14 a 16. Tras asignar una credencial propia con la cabecera `Key`, el
mismo payload dio **score 16**. Las alertas de prueba acababan en CRITICA de
todos modos gracias a VirusTotal y MISP, pero una alerta con score 9 podría
haber salido ALTA en lugar de CRITICA.

**Corrección.** Credencial propia para AbuseIPDB con la cabecera `Key`;
`Code CTI Context` expone `abuse_disponible` para distinguir «la fuente dice
cero» de «la fuente no contestó»; y las plantillas publican «AbuseIPDB no
disponible» en ese caso, en lugar de «0%».

Verificado en los dos caminos, según la regla que fija M-38: con la credencial
errónea el mensaje dice «AbuseIPDB no disponible»; con la correcta, «AbuseIPDB
100%» y score 16. Dos entradas distintas, dos salidas distintas.

**Queda abierto:** el payload que n8n envía al triaje reconstruye el objeto
`cti` campo a campo, y `abuse_disponible` no está entre ellos. El motor
determinista sigue sin saber si una fuente estaba caída al calcular el score, y
el resumen que publica no lo refleja. El síntoma está resuelto; el mecanismo
que lo hacía invisible al veredicto, no.

**Asimetría de diagnóstico, no señalada en su momento.** M-14 y su
seguimiento del 18 atribuyeron el cero a la fuente externa —clave agotada,
cuota, formato de respuesta— sin considerar la hipótesis más barata y más
próxima: la configuración local del nodo. Cinco días de estado persistente
que se resolvieron mirando a qué credencial apuntaba el nodo, algo
comprobable en segundos. Es la imagen especular de M-28, donde un fallo de la
petición se leyó como problema de credencial. En ambos casos el diagnóstico
se fue hacia el componente lejano antes de agotar el cercano, y hasta ahora
el registro no había cruzado las dos entradas.
