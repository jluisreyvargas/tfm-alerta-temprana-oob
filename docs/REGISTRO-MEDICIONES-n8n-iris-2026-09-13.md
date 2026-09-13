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
