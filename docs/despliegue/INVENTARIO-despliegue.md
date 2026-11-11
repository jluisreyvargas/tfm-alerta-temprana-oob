# Inventario de despliegue desde cero · paso 1 de 2 (reconocimiento)

- **Commit leído:** `c233bbe` (rama `claude/cool-mendel-arfp9t`, árbol limpio).
- **Método:** solo lectura del repositorio. No se ha ejecutado ninguna operación Docker, ni `git commit`, ni `git push`. El único fichero creado es este.
- **Estado del clon:** no existe ningún `.env`, `*.key`, `api_client.yaml`, `users_database.yml` ni `peers.json` (comprobado con `find`). Todo lo que se dice de esos ficheros procede de sus plantillas, de los compose que los consumen y de los documentos, no de su contenido.
- **Convención:** cada afirmación lleva `ruta:línea`. Lo que es inferencia se marca **(inferencia)** y se repite en la sección «No verificado». De ningún secreto se anota el valor: solo nombre y ubicación.
- **Interfaces del host actual** (para leer las IP): `192.168.0.70` es `ens33`, LAN del KVM; `192.168.127.138` es `ens34`, red del laboratorio donde escucha Traefik; son el mismo host (`fase8-kvm/README.md:138-143`). `100.64.0.1` es la IP del tailnet (`fase4-breakglass-dc/.env.example:3`).

Categorías de origen: **G** generable · **C** cosechable · **E** externo · **D** derivado.

---

## 1. Matriz de secretos

### 1.1 Fase 1 · núcleo (`fase1-infraestructura/.env`)

| Variable | Se define en | La consumen | Origen | Restricciones |
|---|---|---|---|---|
| `AUTHELIA_JWT_SECRET` | `.env.example:14` | `docker-compose.yml:61` | G | `openssl rand -hex 32` (`.env.example:11`). Vacío impide que Authelia levante (`.env.example:12-13`) |
| `AUTHELIA_SESSION_SECRET` | `.env.example:15` | `docker-compose.yml:62` | G | ídem |
| `AUTHELIA_STORAGE_ENCRYPTION_KEY` | `.env.example:16` | `docker-compose.yml:63` | G | ídem. Cifra `authelia/db.sqlite3` (`authelia/configuration.yml:60-62`) |
| `MONGO_INITDB_ROOT_PASSWORD` | `.env.example:9` | `docker-compose.yml:91` (healthcheck), `:107-108` (URI de Rocket.Chat); `mongodb/init-mongo.sh:15` | G | **Solo alfanumérica**: va dentro de una URI (`docs/HALLAZGO-credencial-mongodb-2026-09-23.md:102-105`). Referencia: `openssl rand -hex 24` |
| `MONGO_INITDB_ROOT_USERNAME` | `.env.example:8` | `docker-compose.yml:107-108`; `init-mongo.sh:14` | fijo (`rcuser`) | El healthcheck lleva `rcuser` literal (`docker-compose.yml:91`): cambiar la variable sin tocar el compose deja el contenedor `unhealthy` |
| Hash de contraseña de cada usuario de Authelia | `authelia/users_database.yml` (no existe en git) | `authelia/configuration.yml:13-15` | D | argon2id, generado con `authelia crypto hash generate argon2` (`docs/README-fase1b-authelia.md:222-223`). La contraseña en claro es G |
| Secreto TOTP de cada usuario | `authelia/db.sqlite3` (runtime) | Authelia | C · **manual** | Alta desde el navegador; el enlace se escribe en `authelia/notification.txt` (`fase1-infraestructura/README.md:201`). Sin vía no interactiva documentada |
| Contenido de `mongodb/mongo-keyfile` | fichero, no variable | `docker-compose.yml:81,85` | G | `openssl rand -base64 756` (`mongodb/mongo-keyfile.example:1`) |

Desajustes de la plantilla de fase 1:

- **Consumida y no definida:** `ROOT_URL` (`docker-compose.yml:109`) no está en `.env.example`. Solo aparece en el README (`fase1-infraestructura/README.md:132`). Con la plantilla tal cual, Rocket.Chat arranca con `ROOT_URL` vacío.
- **Definidas e inertes** (ningún compose las lee): `ROCKETCHAT_ADMIN_USER`, `ROCKETCHAT_ADMIN_PASS`, `ROCKETCHAT_ADMIN_EMAIL` (`.env.example:5-7`; el motivo está en `docs/README-fase1c-mongodb-rocketchat.md:119-121`), `ACME_EMAIL` (`.env.example:2`; Let's Encrypt nunca se desplegó, `docs/README-fase1a-traefik-portainer.md:18`) y `PORTAINER_VERSION` (`.env.example:18`; la imagen lleva `latest` literal, `docker-compose.yml:31`).

### 1.2 Wazuh (`fase1-infraestructura/wazuh/single-node/.env`)

| Variable | Se define en | La consumen | Origen | Restricciones |
|---|---|---|---|---|
| `INDEXER_PASSWORD` | `.env.example:12` | `docker-compose.yml:22,84`; y como `OS_PASS` en fase 3 y fase 5-api (ver 1.4 y 1.6) | G | Debe coincidir con el hash de `admin` en `internal_users.yml` |
| `API_PASSWORD` | `.env.example:13` | `docker-compose.yml:28,89`; `config/wazuh_dashboard/wazuh.yml:6` | G | **Política de la API de Wazuh:** 8–64 caracteres con mayúscula, minúscula, número y símbolo de `.*+?-`. Si no la cumple, el manager entero no arranca y no hay mensaje salvo en los logs (`fase2-orquestador/README.md:546`) |
| `DASHBOARD_PASSWORD` | `.env.example:14` | `docker-compose.yml:87` | G | Debe coincidir con el hash de `kibanaserver` |
| Hash de `admin` | `config/wazuh_indexer/internal_users.yml:14` | montado en el indexador (`docker-compose.yml:72`) | D de `INDEXER_PASSWORD` | bcrypt, con `plugins/opensearch-security/tools/hash.sh` dentro de la imagen del indexador (`internal_users.yml:11-12`) |
| Hash de `kibanaserver` | `internal_users.yml:23` | ídem | D de `DASHBOARD_PASSWORD` | ídem (`internal_users.yml:20-21`) |
| Contraseña literal en `wazuh.yml` | `config/wazuh_dashboard/wazuh.yml:6` | montado en el dashboard (`docker-compose.yml:95`) | D de `API_PASSWORD` | El fichero «no admite sustitución de variables» (`fase2-orquestador/README.md:545`): hay que reescribirlo |
| Clave de clúster del manager | `config/wazuh_cluster/wazuh_manager.conf:293` | `docker-compose.yml:44` | fijo (valor del upstream) | No es un secreto del despliegue: es la constante que trae wazuh-docker. Se anota por si se quiere rotar |

Hallazgos sobre ficheros versionados de Wazuh:

- `internal_users.yml` y `wazuh.yml` **están versionados con valores del laboratorio actual** (hashes en `internal_users.yml:14,23`; contraseña literal en `wazuh.yml:6`). Una instalación limpia los reescribe y deja el árbol de trabajo modificado, igual que la CA.
- `fase2-orquestador/README.md:545` afirma que `wazuh.yml` está «excluido del control de versiones, con `.example` en su lugar». No es así: `git ls-files` lo lista y no existe ningún `.example`. Lo declarado no es lo desplegado.
- `scripts/verify-no-secrets.sh` no tiene regla para un campo `password:` suelto (`scripts/verify-no-secrets.sh:7-27`), así que no señala `wazuh.yml:6`.

### 1.3 n8n (`fase2-orquestador/n8n/.env`) — **sin `.env.example`**

Confirmado: no existe plantilla (`fase2-orquestador/README.md:452-455`; `fase2-orquestador/n8n/README.md:31-33`). El compose carga `.env` con `env_file` (`docker-compose.yml:6-7`).

| Variable | Se define en | La consumen | Origen | Restricciones |
|---|---|---|---|---|
| `N8N_ENCRYPTION_KEY` | solo nombrada en `fase2-orquestador/README.md:435` y `n8n/README.md:51` | n8n, vía `env_file` (no figura en `environment`) | G | `openssl rand -hex 32` (`n8n/README.md:27`). Si falta, n8n genera una en el volumen; rotarla después exige exportar credenciales en claro (`fase2-orquestador/README.md:533`) |
| `OOB_WEBHOOK_SECRET` | solo nombrada en `fase2-orquestador/README.md:435` | `workflows/wazuh-alert-handler.json:270` (`$env`); debe ser igual a `WEBHOOK_SECRET` de `n8n-integration.conf` (`wazuh-integration/custom-n8n:25,98-100`) | G | `openssl rand -hex 32` (`custom-n8n:25`). Llega al contenedor solo por `env_file`: **no está en el bloque `environment`** |
| `ORCH_HMAC_SECRET` | — | `docker-compose.yml:29` (aborta con `:?` si falta); `wazuh-alert-handler.json:689`; `fase5-orchestrator-api/main.py:55` | G | Mismo valor en `fase5-orchestrator-api/.env` (`fase5-orchestrator-api/.env.example:32`) |
| `AGENT_TOKEN` | — | `docker-compose.yml:25`; `fase4d-breakglass.json:355,375`; agente del DC (`dcagent/agent_dc.py:33`); `scripts/dc-signed.env.example:14` | G | Mismo valor en el NSSM del DC (`dcagent/README-despliegue.md:104`) |
| `AGENT_HMAC_SECRET` | — | `docker-compose.yml:26`; `fase4d-breakglass.json:355`; `agent_dc.py:34`; `scripts/dc-signed.env.example:18` | G | Mismo valor en el DC (`README-despliegue.md:105`) |
| `RC_BOT_USER_ID` | — | `docker-compose.yml:20`; `wazuh-alert-handler.json:580` | C | Identificador del usuario `orchestrator-bot` en Rocket.Chat. Ver nota de literales abajo |
| `RC_BOT_TOKEN` | — | `docker-compose.yml:21`. Ningún workflow versionado lo lee por `$env` (el token viaja en la credencial `rocketchatApi`) | C | Token de acceso personal generado con omisión de 2FA (`fase1-infraestructura/README.md:214`) |
| `RC_OUTGOING_TOKEN` | — | `docker-compose.yml:22`; `fase4d-breakglass.json:26` | C (o G, ver «No verificado») | Token del webhook saliente de Rocket.Chat (`docs/README-fase4d-flujo-aprobacion.md:86`) |
| `IR_APPROVER_IDS` | — | `docker-compose.yml:23`; `fase4d-breakglass.json:92` | C | Lista de identificadores de Rocket.Chat de los aprobadores (`docs/README-fase4d-flujo-aprobacion.md:78`). Formato de la lista: no documentado, hay que leerlo del nodo en `fase4d-breakglass.json:92` |

**Cómo se cosechan (los cuatro `RC_*`/`IR_*`):** el repositorio no documenta ninguna vía por CLI ni por API. Los documentos describen el resultado (cuenta `orchestrator-bot`, token con omisión de 2FA, webhook saliente con token), no el procedimiento. **Hoy es un paso manual por interfaz.** La API REST de Rocket.Chat es alcanzable sin Authelia en `http://rocketchat:3000` desde la red Docker (`docs/README-fase4d-flujo-aprobacion.md:105-107`), lo que abre una vía no interactiva, pero no está escrita ni probada en el repo (ver «No verificado»).

**Identificador del bot incrustado como literal.** Además de `$env.RC_BOT_USER_ID`, el identificador del bot del laboratorio actual está escrito como valor de la cabecera `X-User-Id` en 6 nodos de `wazuh-alert-handler.json` (líneas `339, 378, 417, 541, 868, 903`) y 8 de `fase4d-breakglass.json` (`69, 329, 437, 482, 517, 787, 906, 1075`). Es deliberado: `$env` no resuelve en las expresiones de los nodos HTTP Request (`n8n/export-workflow.sh:19-22`). En una instalación limpia el bot tendrá otro identificador, así que **los 14 literales hay que reescribirlos en el JSON antes de importar**.

**Consumidas sin definición en ninguna plantilla:** las nueve variables de la tabla. **Definidas en el compose con valor fijo:** `RC_URL`, `DC_AGENT_URL`, `CREDENTIAL_BASE_URL` (`docker-compose.yml:19,24,27`), que los workflows leen por `$env` (`fase4d-breakglass.json:52,355,369,415`).

### 1.4 Fase 3 · triage (`fase3-agentic/.env`)

| Variable | Se define en | La consumen | Origen | Restricciones |
|---|---|---|---|---|
| `OS_PASS` | `.env.example:10` | `fase7-observabilidad/shared/metrics_client.py:13` (`os.environ[...]`: sin ella no arranca) | D | Igual a `INDEXER_PASSWORD` (`fase5-orchestrator-api/.env.example:5-6`) |
| `OS_USER` | `.env.example:9` | `metrics_client.py:12` | fijo (`admin`) | — |
| `TRIAGE_MODE` | `.env.example:4` | `docker-compose.yml:17` | fijo | `deterministic` \| `llm` \| `hybrid` (`app/config.py:19-37`) |

### 1.5 Fase 4 · tailnet y break-glass

| Variable / material | Se define en | La consumen | Origen | Restricciones |
|---|---|---|---|---|
| `TAILNET_IP` | `fase4-breakglass-dc/.env.example:3` | `docker-compose.rustdesk.yml:10-13,25-26`; `systemd/tfm-fase4-rustdesk.service:18` | C | `tailscale ip -4` (`.env.example:2`). No existe hasta que el host se une al tailnet |
| Clave de preautorización (una por nodo) | Headscale, runtime | `tailscale up --authkey` | C | `docker exec headscale headscale preauthkeys create --user tfm-oob --expiration 1h --tags tag:<rol>` (`docs/README-fase4b-tailnet.md:60-61,89-90`). De un solo uso, etiquetada y de vida corta por decisión (`docs/README-fase4b-tailnet.md:41-47`; `docs/credenciales-de-arranque.md:45-48`) |
| Usuario de Headscale `tfm-oob` | Headscale, runtime | `headscale/config/acl.hujson:8-11` | C | `docker exec headscale headscale users create tfm-oob` (`docs/README-fase4b-tailnet.md:33`) |
| Clave de API de Headscale (para la UI) | Headscale, runtime | navegador del analista; **nunca** en `headscale-ui/container-config/config.yaml:11` | C · pegado manual | `docker exec -it headscale headscale apikeys create --expiration 90d` (`docs/README-fase4a-headscale-ui.md:103`). Se pega en la UI (`config.yaml:8-10`) |
| `noise_private.key`, `derp_server_private.key`, `db.sqlite` | `fase4-breakglass-dc/headscale/lib/` (ignorado, `.gitignore:1`) | `headscale/config/config.yaml:16,32,45` | G por el propio servicio | Los crea Headscale en el primer arranque **(inferencia)** |
| Par de claves de RustDesk (`id_ed25519`, `.pub`) | `fase4-breakglass-dc/rustdesk/data/` (ignorado, `.gitignore:2`) | `docker-compose.rustdesk.yml:5,8,20,23` (`-k _`) | G por el propio servicio; la pública es C para el DC | La pública se copia a mano al cliente del DC (`docs/README-fase4e-rustdesk-breakglass.md:100`) |

### 1.6 Fase 5 · Velociraptor, MinIO y orchestrator

| Variable / material | Se define en | La consumen | Origen | Restricciones |
|---|---|---|---|---|
| `MINIO_ROOT_USER` | `fase5-velociraptor/.env.example:7` | `fase5-velociraptor/docker-compose.yml:46,77` (`:?`) | G | — |
| `MINIO_ROOT_PASSWORD` | `.env.example:8` | `docker-compose.yml:47,78` (`:?`); `init-minio-bucket.sh:3` | G | Longitud mínima de MinIO: no documentada en el repo |
| `MINIO_ACCESS_KEY` | `fase5-orchestrator-api/.env.example:17` | `fase5-orchestrator-api/main.py:25` | G + alta manual | Es el usuario dedicado `tfm-orchestrator`, **no** el root (`.env.example:14-15`). El usuario y su política `evidence-writer` hay que crearlos en MinIO: ni el comando ni el JSON de la política están en el repo (ver sección 5) |
| `MINIO_SECRET_KEY` | `.env.example:18` | `main.py:26` | G + alta manual | ídem |
| `ORCH_HMAC_SECRET` | `fase5-orchestrator-api/.env.example:32` | `main.py:55`; `scripts/collect-signed.sh:26` | G | Igual al de n8n (1.3). Con `ORCH_REQUIRE_HMAC=true` el proceso falla al arrancar si está vacío (`.env.example:27-29`) |
| `OS_PASS` | `.env.example:8` | `docker-compose.yml:28`; `metrics_client.py:13` | D | Igual a `INDEXER_PASSWORD` (`.env.example:5-6`) |
| `server.config.yaml` (CA, claves de frontend y gateway, `obfuscation_nonce`) | `fase5-velociraptor/velociraptor-config/` (ignorado) | `velociraptor-image/Dockerfile:18`; `docker-compose.yml:20` | G con la imagen | `docker run --rm velociraptor-oob:0.76.6 --nobanner config generate` (`fase5-velociraptor/README.md:275-276`), más alineación **a mano** con la plantilla (`README.md:279-281`) y cambio de `API.bind_address` a `0.0.0.0` (`README.md:316-322`) |
| `api_client.yaml` (certificado y clave del cliente gRPC) | `velociraptor-config/api_client.yaml` (ignorado) | `fase5-orchestrator-api/docker-compose.yml:22,35`; `velociraptor_client.py:18` | C | `docker exec velociraptor … config api_client --name orchestrator --role investigator /velociraptor/api_client.yaml` (`fase5-velociraptor/README.md:343-349`), y después editar `api_connection_string` a `velociraptor:8888` (`README.md:364-370`) |
| Usuario de la GUI de Velociraptor | dentro de `server.config.yaml` / datastore | GUI (Basic Auth, `config-templates/server.config.template.yaml:62-67`) | G + alta | El repo no documenta el comando de alta (ver «No verificado») |

**Definidas e inertes** en `fase5-velociraptor/.env.example`: `VELOCIRAPTOR_API`, `VELOCIRAPTOR_GUI`, `IRIS_URL`, `IRIS_API_KEY` (`.env.example:10-13`). El compose de esa fase no las lee (`fase5-velociraptor/docker-compose.yml`, completo) y ningún otro compose carga ese `.env`. `IRIS_API_KEY` trae además un marcador de relleno en lugar de vacío (`.env.example:13`), contra el criterio del resto de plantillas.

### 1.7 Fase 6 · DFIR-IRIS (`fase6-iris/.env`)

| Variable | Se define en | La consumen | Origen | Restricciones |
|---|---|---|---|---|
| `POSTGRES_PASSWORD` | `.env.example:22` | `docker-compose.base.yml:31,58,88` | G | — |
| `POSTGRES_ADMIN_PASSWORD` | `.env.example:24` | `docker-compose.base.yml:33,60,90` | G | — |
| `IRIS_SECRET_KEY` | `.env.example:34` | `docker-compose.base.yml:63,93` | G | `openssl rand -base64 48 \| tr -d '\n'` (`.env.example:33`). `verify-fase6.sh` comprueba que no es la constante del upstream (`scripts/verify-fase6.sh:51-57`) |
| `IRIS_SECURITY_PASSWORD_SALT` | `.env.example:37` | `docker-compose.base.yml:64,94` | G | `openssl rand -base64 32 \| tr -d '\n'`. Residual: se carga y no se consume (`.env.example:35-36`) |
| `IRIS_ADM_PASSWORD` | `.env.example:49` (comentada) | `source/app/post_init.py:1040` | G | Solo se aplica con la BD vacía (`.env.example:48`). Si falta, IRIS genera una aleatoria y la escribe en el log (`post_init.py:1041-1042,1069`) |
| `IRIS_ADM_API_KEY` | **no está en `.env.example`** | `source/app/post_init.py:1056-1058`; `source/app/configuration.py:290` | **G** (o C si no se fija) | Si se define antes del primer arranque con BD vacía, el administrador nace con esa clave; si no, IRIS genera una y hay que cosecharla. La clave es la credencial `dfirIrisApi` de n8n. Ver «No verificado»: el código leído es el vendorizado, no el de la imagen `v2.4.27` |

### 1.8 Fase 8 · KVM (`fase8-kvm/glkvm-cloud/docker-compose/.env`)

| Variable | Se define en | La consumen | Origen | Restricciones |
|---|---|---|---|---|
| `RTTYS_TOKEN` | `.env.arm64.example:87` | `docker-compose.yml:10`; `templates/rttys.conf.template:2`; el GL-RM1 (`fase8-kvm/README.md:195`) | G | Idéntico en el dispositivo |
| `RTTYS_PASS` | `.env.arm64.example:88` | `docker-compose.yml:11`; `rttys.conf.template:5` | G | Contraseña del administrador de rttys |
| `RTTYS_ADMIN_NAME` | `.env.arm64.example:91` | `docker-compose.yml:12` | fijo | Solo letras y dígitos (`.env.arm64.example:90`) |
| `TURN_PASS` | `.env.arm64.example:99` | `docker-compose.yml:20,100`; el GL-RM1 como `WEBRTC_PASSWORD` (`README.md:199`) | G | coturn está desactivado (`docker-compose.override.yml:17-23`), pero rttys sigue recibiendo el valor |
| `GLKVM_ACCESS_IP` | `.env.arm64.example:84` | `docker-compose.yml:8` | parámetro (IP de LAN) | **No dejar vacío**: con vacío el entrypoint consulta servicios de Internet y cae a `127.0.0.1` (`README.md:232-237`) |
| `REVERSE_PROXY_ENABLED` | `.env.arm64.example:23` | `docker-compose.yml:51` | fijo (`true`) | Ver aviso abajo |

**La plantilla no sirve tal cual.** `.env.arm64.example` es el fichero del upstream, no una plantilla del proyecto:

- trae imágenes `arm64` (`.env.arm64.example:2-3`), cuando el host es `amd64` (`fase5-velociraptor/velociraptor-image/Dockerfile:9`);
- trae `REVERSE_PROXY_ENABLED=false` y `RTTYS_WEBUI_PORT=443` (`:23,93`), cuando las etiquetas de Traefik esperan el `8180` en claro (`docker-compose.yml:81`) y el despliegue real usa `true` (`docs/credenciales-de-arranque.md:92`);
- trae `RTTYS_TOKEN`, `RTTYS_PASS` y `TURN_PASS` con **valores públicos de ejemplo** en vez de vacíos (`:87-88,99`);
- y si el `.env` falta, el compose no aborta: cae a esas mismas constantes públicas (`docker-compose.yml:10-11,20`). Es el patrón del P0-3: arranca y funciona con credencial conocida.

### 1.9 MISP (`misp/misp-docker/.env`, a partir de `template.env`)

| Variable | Se define en | La consumen | Origen | Restricciones |
|---|---|---|---|---|
| `ADMIN_PASSWORD` | `template.env:54` | `docker-compose.yml:169` | G | — |
| `ADMIN_KEY` | `template.env:52` | `docker-compose.yml:170`; `core/files/configure_misp.sh:460-466` | **G** | Si se define, MISP fija esa clave al administrador en el arranque; si no, la autogenera (`configure_misp.sh:467-471`; `template.env:168-169`). Es la credencial `mispApi` de n8n. Formato exigido por MISP: no comprobado |
| `ENCRYPTION_KEY` | `template.env:71` | `docker-compose.yml:160` | G | — |
| `GPG_PASSPHRASE` | `template.env:59` | compose de MISP | G | — |
| `MYSQL_PASSWORD` | `template.env:132` (comentada) | `docker-compose.yml:67,298` | G | **Si falta, cae a un valor público** (`docker-compose.yml:67`) |
| `MYSQL_ROOT_PASSWORD` | `template.env:133` (comentada) | `docker-compose.yml:68` | G | ídem (`docker-compose.yml:68`) |
| `REDIS_PASSWORD` | `template.env:146` (comentada) | `docker-compose.yml:34,41,308` | G | ídem (`docker-compose.yml:41`) |
| `BASE_URL` | `template.env:64` | `docker-compose.yml:152` | parámetro | `https://misp.<dominio>` |
| `CORE_HTTP_PORT` / `CORE_HTTPS_PORT` | no definidas | `docker-compose.override.yml:4-5` | fijo | Por defecto `1280`/`12443` en loopback |

### 1.10 Integración Wazuh → n8n (`/var/ossec/etc/n8n-integration.conf`, dentro del manager)

| Variable | Se define en | La consumen | Origen | Restricciones |
|---|---|---|---|---|
| `WEBHOOK_SECRET` | `fase2-orquestador/wazuh-integration/n8n-integration.conf.example:8` | `custom-n8n:77-80,98-100` | D | Igual a `OOB_WEBHOOK_SECRET` (`fase2-orquestador/README.md:441`) |
| `WEBHOOK_URL` | `n8n-integration.conf.example:7` | `custom-n8n:103` | parámetro | `https://n8n.<dominio>/webhook/wazuh-alerts` (`custom-n8n:24`) |
| `CA_BUNDLE` | `n8n-integration.conf.example:9` | `custom-n8n:84-93` | fijo | `/var/ossec/etc/oob-rootCA.crt` (`custom-n8n:26`) |

### 1.11 Credenciales de n8n (viven cifradas en el volumen `n8n_data`)

| Credencial (tipo · nombre) | Referencias | Secreto que contiene | Origen del secreto |
|---|---|---|---|
| `rocketchatApi` · «Rocket account» | 9 en `wazuh-alert-handler.json`, 8 en `fase4d-breakglass.json` | identificador y token del bot | C (1.3) |
| `httpHeaderAuth` · «Header Auth account» | 5 + 2 | cabecera de autenticación (por los nodos, la de la API de Rocket.Chat) | C |
| `httpHeaderAuth` · «AbuseIPDB» | 1 | clave de API de AbuseIPDB | **E** |
| `virusTotalApi` · «VirusTotal account» | 1 | clave de API de VirusTotal | **E** |
| `mispApi` · «MISP account» | 1 | `ADMIN_KEY` de MISP | G (1.9) |
| `dfirIrisApi` · «DFIR-IRIS account» | 3 + 2 | clave de API de IRIS | G o C (1.7) |
| Identificador interno de cada credencial | 32 marcadores `"id": "REEMPLAZAR"` (20 + 12) | — | **C**: lo asigna n8n al crear la credencial |

El repo no documenta ninguna vía no interactiva para crear credenciales ni para reasignarlas: dice que hay que hacerlo «a mano» (`fase2-orquestador/README.md:459,532`). La CLI de n8n se usa ya para workflows (`fase2-orquestador/README.md:447`; `n8n/export-workflow.sh:39`), pero `import:credentials` no aparece en ningún fichero.

### 1.12 Otros

| Variable | Se define en | La consumen | Origen |
|---|---|---|---|
| `AGENT_URL`, `AGENT_TOKEN`, `AGENT_HMAC_SECRET` | `scripts/dc-signed.env.example:10,14,18` | `scripts/dc-signed.sh:71` | D (copia de 1.3) |
| `ROCKETCHAT_WEBHOOK` | entorno del cron | `fase8-kvm/scripts/check-kvm-lastseen.sh:22` | C (webhook entrante de Rocket.Chat). Sin plantilla; opcional |

---

## 2. Ficheros que el despliegue debe crear

Ninguno está en git. «Falla» indica qué ocurre si falta.

### 2.1 PKI del enclave

| Ruta | Quién lo genera hoy | Propietario / permisos | Si falta |
|---|---|---|---|
| `fase1-infraestructura/traefik/certs/oob-rootCA.key` | `traefik/generate-oob-ca.sh:44` | usuario, `600` (`generate-oob-ca.sh:95`) | No se puede firmar nada más |
| `…/certs/oob-rootCA.crt` | `generate-oob-ca.sh:45-47` | `644` | **Versionado**: lo sustituye la CA nueva |
| `…/certs/oob-wildcard.{key,crt}` | `generate-oob-ca.sh:50,87-90` | `600` / `644` | Traefik **no falla**: sirve `TRAEFIK DEFAULT CERT` (`traefik/dynamic/tls.yml:3-6`) |
| `…/certs/glkvm-cloud.{key,crt}` | **a mano**, con `openssl` y `certs/glkvm-cloud.cnf` (el `.cnf` está versionado; el comando no) | — | Paso previo de `glkvm.cer`/`glkvm.key` |
| `…/certs/glkvm-device.{key,crt}` | **a mano**, con `certs/glkvm-device.cnf`; clave EC `prime256v1` (`fase8-kvm/README.md:254-256`) | — | Va al paquete del GL-RM1 |
| `…/certs/iris.{key,crt}` | **a mano**, con `certs/iris.cnf` | — | Paso previo de los certificados web de IRIS |
| `fase6-iris/certificates/web_certificates/iris_oob_cert.pem` y `iris_oob_key.pem` | a mano (nombres en `fase6-iris/.env.example:15-16`) | legible por el nginx del contenedor | El directorio no existe: Docker lo crea vacío y de `root` (`fase6-iris/README.md:257-262`); nginx no encuentra el certificado (`docker/nginx/nginx.conf:84-85`) |
| `fase6-iris/certificates/ldap/` | a mano; vacío | usuario | Docker lo crea como `root` (`fase6-iris/README.md:255`) |
| `fase6-iris/certificates/rootCA/irisRootCACert.pem` | copia de la CA (`fase6-iris/README.md:253`) | `644` | **Versionado.** Hoy es idéntico byte a byte a `oob-rootCA.crt` (comprobado con `cmp`) |
| `fase6-iris/certificates/rootCA/ca-bundle-oob.crt` | a mano: CAs públicas + CA del enclave (`fase6-iris/README.md:254`) | `644` | **Versionado.** 151 certificados hoy. Hay que regenerarlo con la CA nueva; `verify-fase6.sh` exige ≥151 (`scripts/verify-fase6.sh:46-48`) |
| `fase2-orquestador/n8n/certs/oob-rootCA.crt` | copia de la CA | `644` | **Versionado.** Montado en n8n (`n8n/docker-compose.yml:14,32`) |
| `fase8-kvm/glkvm-cloud/docker-compose/certificate/glkvm.cer` y `glkvm.key` | copia de `glkvm-cloud.{crt,key}` (`docs/credenciales-de-arranque.md:83-86`) | — | Montaje de fichero inexistente (`docker-compose.yml:58-59`): Docker crea un directorio con ese nombre |
| CA en el almacén de confianza del host | **sin procedimiento escrito** | root | `tailscale up` falla con `x509: certificate signed by unknown authority`; además hay que reiniciar `tailscaled` tras instalarla (`docs/README-fase4b-tailnet.md:179-183`) |
| `oob-rootCA.crt` dentro del manager de Wazuh (`/var/ossec/etc/`) | `docker cp` (`fase2-orquestador/README.md:440`) | — | `custom-n8n` **no falla al arrancar**: usa el almacén del sistema y falla en cada entrega (`custom-n8n:88-93`) |

**Aviso para el script.** `glkvm.key` **no** puede ser la clave de la CA. Ya ocurrió: la clave raíz estuvo montada en el contenedor del fabricante del KVM (`docs/credenciales-de-arranque.md:63-76`).

`generate-oob-ca.sh` cubre solo la CA y el comodín; se niega a ejecutarse si ya existe `oob-rootCA.key` (`generate-oob-ca.sh:34-39`), lo que es correcto en una instalación limpia. Los SAN del comodín están escritos dentro del script (`generate-oob-ca.sh:73-81`).

### 2.2 Resto de ficheros

| Ruta | Quién lo genera hoy | Propietario / permisos | Si falta |
|---|---|---|---|
| Los nueve `.env` (fase1, wazuh, n8n, fase3, fase4, fase5-api, fase5-velociraptor, fase6, fase8) y `misp/misp-docker/.env` | a mano, desde las plantillas (n8n: sin plantilla) | usuario, `600` recomendado | Varía: `:?` aborta (n8n `ORCH_HMAC_SECRET`, MinIO); el resto arranca con vacío o con valor público (fase8, MISP) |
| `fase1-infraestructura/mongodb/mongo-keyfile` | a mano (`fase1-infraestructura/README.md:151-152`) | El entrypoint lo copia y le pone `400 mongodb` dentro del contenedor (`mongodb/docker-entrypoint-keyfile.sh:3-5`); en el host basta que sea legible (`docs/README-fase1c-mongodb-rocketchat.md:139`) | Docker crea un directorio; `cp` falla y mongod no arranca **(inferencia)** |
| `fase1-infraestructura/traefik/acme.json` | a mano: `touch` + `chmod 600` (`docs/README-fase1a-traefik-portainer.md:288-289`) | `600` | Montaje de fichero (`docker-compose.yml:24`): Docker crea un directorio. Traefik no usa ACME (`traefik/traefik.yml:33`), así que **no falla** |
| `fase1-infraestructura/authelia/users_database.yml` | a mano (`docs/README-fase1b-authelia.md:100-109,218`) | usuario | Authelia no tiene backend de usuarios (`authelia/configuration.yml:13-15`). No existe `.example`, aunque `docs/README-fase1b-authelia.md:113,116` lo dan por existente (`fase1-infraestructura/README.md:323` confirma que no existe) |
| `fase1-infraestructura/wazuh/single-node/config/wazuh_indexer_ssl_certs/*` (10 ficheros distintos montados) | `docker compose -f generate-indexer-certs.yml run --rm generator` (`wazuh/single-node/README.md:11`), desde `wazuh/single-node/` | los crea el contenedor | Once montajes de fichero (`docker-compose.yml:41-43,66-70,91-93`): Docker crea directorios y los tres servicios fallan |
| `config/wazuh_indexer/internal_users.yml` reescrito | a mano con `hash.sh` | — | **Arranca**, pero con los hashes del laboratorio actual: las contraseñas nuevas del `.env` no autentican |
| `config/wazuh_dashboard/wazuh.yml` reescrito | a mano | — | **Arranca**, pero el dashboard usa la contraseña antigua contra la API |
| `/var/ossec/etc/n8n-integration.conf` (dentro del manager) | a mano, desde `n8n-integration.conf.example` | `640 root:wazuh` (`n8n-integration.conf.example:2`) | `custom-n8n` sale con error en cada alerta (`custom-n8n:73-75`) |
| Bloque `<integration>` en `/var/ossec/etc/ossec.conf` | a mano, desde `wazuh-integration/ossec-integration.xml:5-10` | — | **No falla:** `wazuh-integratord` termina con «Clean exit» y ninguna alerta sale (`fase2-orquestador/README.md:117`). El `wazuh_manager.conf` versionado **no** contiene el bloque (leído completo: 311 líneas, sin `<integration>`) |
| Reglas propias `100600`–`100609` en `local_rules.xml` del manager | a mano; solo descritas en `docs/README-fase4-validacion.md:343-357` | — | **No falla:** las ejecuciones del agente del DC no generan alerta. No hay fichero de reglas versionado |
| `fase4-breakglass-dc/.env` | a mano | — | Compose interpola `TAILNET_IP` vacío y publica en todas las interfaces **(inferencia)**; la unidad systemd no encuentra la IP y agota 300 s (`tfm-fase4-rustdesk.service:18`) |
| `fase4-breakglass-dc/rustdesk/peers.json` | `rustdesk/export-peers.sh:15-16`, por cron cada 30 min | usuario | Montaje de fichero en n8n (`n8n/docker-compose.yml:33`): **Docker crea un directorio**; el nodo que lo lee devuelve `no_resuelto` (`fase4d-breakglass.json:595`). Hay que crearlo (aunque sea `[]`) **antes** de arrancar n8n |
| `fase4-breakglass-dc/rustdesk/data/` | lo crea hbbs | — | Sin `db_v2.sqlite3`, `export-peers.sh` falla (`export-peers.sh:15`) |
| `fase4-breakglass-dc/headscale/lib/` | lo crea Headscale | `db.sqlite` no debe quedar en `644` (`docs/revision-credenciales-fases1-8.md:27`) | — |
| `fase5-velociraptor/velociraptor-config/` | a mano; el directorio **no existe en el clon** (`.gitignore:68` y `SECURITY-NOTICE.md:129` mencionan un `.gitkeep` que no está versionado) | usuario | Docker lo crea de `root` y vacío; Velociraptor no encuentra `server.config.yaml` (`velociraptor-image/Dockerfile:18`) |
| `velociraptor-config/server.config.yaml` | `config generate` + edición manual (`fase5-velociraptor/README.md:272-281,316-322`) | — | No arranca |
| `velociraptor-config/api_client.yaml` | `config api_client` + edición (`README.md:343-349,364-370`) | `:ro` en el orchestrator | Montaje de fichero (`fase5-orchestrator-api/docker-compose.yml:35`): Docker crea un directorio |
| `velociraptor-config/downloads/` | lo crea Velociraptor | — | Montaje `:ro` (`fase5-orchestrator-api/docker-compose.yml:40`) |
| `client.config.yaml` y MSI de cliente | `config client` y `config repack --msi` (`README.md:283-304`) | — | Solo afectan al paquete de DC01/W11. Necesita el MSI oficial de Velociraptor como entrada |
| `fase8-kvm/glkvm-cloud/docker-compose/database/*.db` | lo crea rttys a partir de `database/schema.sql` **(inferencia)** | contenedor como `0:0` (`docker-compose.yml:5`) | — |
| `scripts/dc-signed.env` | a mano | — | `dc-signed.sh` aborta (`scripts/dc-signed.sh:71`) |
| `~/tfm-scripts/check-kvm-lastseen.sh` | copia a mano de `fase8-kvm/scripts/` (`fase8-kvm/README.md:182,313`) | usuario | — |
| `/etc/systemd/system/tfm-fase6-iris.service` y `tfm-fase4-rustdesk.service` | `sudo cp` + `daemon-reload` + `enable --now` (`fase6-iris/README.md:353-355`) | root | Ver sección 4.3 |
| `/etc/sysctl.d/99-wazuh.conf` | `docs/README-fase1d-wazuh.md:53-56` | root | El indexador no arranca |
| `/etc/hosts` del host | a mano; fuente de verdad en `docs/resolucion-nombres.tsv:22-34` | root | Ver sección 5 |

---

## 3. Valores de entorno fijos

**P** = parametrizable por variable de Compose sin tocar el fichero (ya lo es, o basta un `.env`). **R** = exige reescribir el fichero.

### 3.1 Direcciones IP

| Valor | Dónde | Qué es | P / R |
|---|---|---|---|
| `192.168.127.138` | `fase4-breakglass-dc/headscale/config/config.yaml:31` | IP del DERP embebido | **R** (YAML de Headscale) |
| `192.168.127.138` | `fase1-infraestructura/wazuh/single-node/config/wazuh_dashboard/wazuh.yml:8` | `enrollment.dns` | **R** |
| `192.168.127.138` | `fase1-infraestructura/traefik/certs/iris.cnf:22` | SAN del certificado de IRIS | **R** |
| `192.168.127.138` | `docs/resolucion-nombres.tsv:32,35-37,39,41-47` | hosts de ubuntu, W11 y DC01 | **R** (es la fuente de `verify-hosts.sh`) |
| `192.168.0.70` | `fase1-infraestructura/traefik/certs/glkvm-cloud.cnf:22` | SAN del certificado de rttys | **R** |
| `192.168.0.70` | `fase8-kvm/glkvm-cloud/docker-compose/docker-compose.override.yml:14-15` | bind de los puertos 5912 y 10443 | **R** (literal; convertible a variable) |
| `192.168.0.36` | `fase1-infraestructura/traefik/certs/glkvm-device.cnf:20` | IP del GL-RM1 en el SAN | **R** |
| `100.64.0.1` | `fase6-iris/docker-compose.override.yml:27` | bind de nginx de IRIS | **R** (literal; convertible a variable) |
| `100.64.0.1` | `fase6-iris/systemd/tfm-fase6-iris.service:22` | espera de la IP | **R** (la propia unidad lo avisa en `:21`) |
| `100.64.0.1` | `scripts/verify-fase6.sh:30-31` | comprobación de escucha | **R** |
| `100.64.0.1` | `docs/resolucion-nombres.tsv:29,38,40` | hosts | **R** |
| `100.64.0.1` | `fase4-breakglass-dc/.env.example:3` | `TAILNET_IP` | **P** (`docker-compose.rustdesk.yml:10-13,25-26`; la unidad lo lee de `.env`, `tfm-fase4-rustdesk.service:18`) |
| `100.64.0.2` | `fase2-orquestador/n8n/docker-compose.yml:24` | `DC_AGENT_URL` | **R** (literal en `environment`) |
| `100.64.0.2` | `scripts/verify-dcagent-health.sh:39` | URL por defecto | P (admite URL por argumento, `:25`) |
| `100.64.0.0/10` | `headscale/config/config.yaml:19`; `fase4-breakglass-dc/scripts/isolate_host.ps1:6` | prefijo del tailnet | fijo |

`acl.hujson` solo menciona `100.64.0.1` y `100.64.0.4` en un comentario (`headscale/config/acl.hujson:29,31`); las reglas usan etiquetas, no IP.

### 3.2 Dominio y nombres de host

`ENCLAVE_DOMAIN` existe (`fase1-infraestructura/.env.example:1`) pero **solo lo usan dos etiquetas**: `fase1-infraestructura/docker-compose.yml:68` y `:120`. El resto del árbol lleva `oob.local` escrito:

| Fichero | Líneas | P / R |
|---|---|---|
| `fase1-infraestructura/docker-compose.yml` | `46` (router de Portainer) | **R** |
| `fase1-infraestructura/authelia/configuration.yml` | `20,24,28,31,34,37,40,43,48,54,55,56` | **R** |
| `fase1-infraestructura/traefik/dynamic/middlewares.yml` | `13` | **R** |
| `fase1-infraestructura/traefik/generate-oob-ca.sh` | `64,73-79` | **R** |
| `fase1-infraestructura/traefik/certs/{glkvm-cloud,glkvm-device,iris}.cnf` | `10,18,19` / `10,18` / `10,18` | **R** |
| `fase1-infraestructura/wazuh/single-node/docker-compose.yml` | `47` (`extra_hosts`), `108` | **R** |
| `fase1-infraestructura/overrides/misp-docker-compose.override.yml` y `misp/misp-docker/docker-compose.override.yml` | `9` | **R** |
| `misp/misp-docker/docker-compose.yml` | `101` (alias de red) | **R** |
| `fase2-orquestador/n8n/docker-compose.yml` | `9,12,27,38,44,52` | **R** |
| `fase2-orquestador/wazuh-integration/ossec-integration.xml` | `7` | **R** |
| `fase2-orquestador/n8n/workflows/wazuh-alert-handler.json` | `547,608,755,780` (`iris.oob.local:4833`) | **R** (JSON) |
| `fase4-breakglass-dc/workflows/fase4d-breakglass.json` | `684` (`kvm.oob.local`, 3 veces), `828,1030` | **R** (JSON) |
| `fase8-kvm/workflows/kvm-hook.json` | `49,78,107,136` (cabecera `Host`) | **R** (JSON) |
| `fase4-breakglass-dc/docker-compose.headscale-ui.yml` | `28` | **R** |
| `fase4-breakglass-dc/headscale-ui/container-config/config.yaml` | `6` | **R** |
| `fase4-breakglass-dc/headscale/config/config.yaml` | `4` (`server_url`) | **R** |
| `fase4-breakglass-dc/headscale/config/docker-compose.headscale.yml` | `19` | **R** |
| `fase5-velociraptor/docker-compose.yml` | `25,61` | **R** |
| `fase5-velociraptor/config-templates/server.config.template.yaml` | `55` (`public_url`) | **R** |
| `fase6-iris/docker-compose.override.yml` | `34` | **R** |
| `fase6-iris/.env.example` | `14` (`SERVER_NAME`), `46` | **P** |
| `fase8-kvm/glkvm-cloud/docker-compose/docker-compose.yml` | `76,85` | **R** |
| `docs/resolucion-nombres.tsv` | `22-47` | **R** |

Otros nombres fijos:

| Valor | Dónde | P / R |
|---|---|---|
| `velociraptor.local` | `config-templates/server.config.template.yaml:17,71`; `client.config.template.yaml:17`; `resolucion-nombres.tsv:35,46` | **R** |
| `iris.local` | `traefik/certs/iris.cnf:19` | **R** |
| `tailnet.internal` | `headscale/config/config.yaml:60` | **R** |
| `tfm-oob@` (usuario de Headscale) | `headscale/config/acl.hujson:8-11` | **R** |
| `orchestrator-tfm`, `dc01-tfm` (hostnames del tailnet) | solo en documentos (`docs/README-fase4b-tailnet.md:69,97`) y en `dcagent/agent_dc.py:219` | argumento de `tailscale up` |
| `single-node-wazuh.indexer-1` | `fase3-agentic/docker-compose.yml:25`; `fase5-orchestrator-api/docker-compose.yml:26`; `fase7-observabilidad/shared/metrics_client.py:11` | **R**. Depende del nombre de proyecto de Compose, o sea, del nombre del directorio `single-node` |
| `rcuser` | `fase1-infraestructura/docker-compose.yml:91` | **R** |
| Nombres de servicio Docker en workflows: `rocketchat:3000`, `langgraph-agent:8000`, `orchestrator:8000`, `misp`, `glkvm_cloud:8180`, `n8n:5678` | `wazuh-alert-handler.json:196,238,331,703`; `kvm-hook.json:43,72,101,130`; `rttys.conf.template:59` | Fijos mientras no cambien los `container_name` |

### 3.3 Identificador del dispositivo KVM

| Valor | Dónde | P / R |
|---|---|---|
| `zsb25f8` | `fase8-kvm/glkvm-cloud/docker-compose/docker-compose.yml:85` (regla de Traefik `kvmproxy`) | **R**. Una regla por dispositivo: «el patrón no escala» (`docs/resolucion-nombres.tsv:31`) |
| `zsb25f8.oob.local` | `docs/resolucion-nombres.tsv:31,42` | **R** |

El identificador lo asigna el dispositivo al registrarse. En una instalación limpia con el mismo GL-RM1 cabe esperar el mismo, pero no está comprobado (ver «No verificado»).

### 3.4 Rutas absolutas y usuario del sistema

| Valor | Dónde | P / R |
|---|---|---|
| `/home/jose/tfm-alerta-temprana-oob/fase4-breakglass-dc` | `fase4-breakglass-dc/systemd/tfm-fase4-rustdesk.service:11` | **R** |
| `/home/jose/tfm-alerta-temprana-oob/fase6-iris` | `fase6-iris/systemd/tfm-fase6-iris.service:11` | **R** |
| `User=jose`, `Group=jose` | `tfm-fase4-rustdesk.service:12-13`; `tfm-fase6-iris.service:12-13` | **R** |
| `~/tfm-scripts/` | `fase8-kvm/README.md:182,313` (solo documento) | — |
| `~/tfm-backups/` | `scripts/purge-history.sh:16-17` | No interviene en el despliegue |

### 3.5 Otros valores atados a la instancia actual

| Valor | Dónde | Consecuencia |
|---|---|---|
| Huella SHA-256 de la CA actual | `scripts/verify-fase6.sh:8` | Con CA nueva, la comprobación 4 falla siempre (`verify-fase6.sh:36-38`). **R** |
| Identificadores de workflow de la instancia actual | `fase2-orquestador/n8n/export-workflow.sh:31-32` | Los valores por defecto del script no sirven en otra instancia. **R** o pasar el identificador por argumento |
| Identificador del bot de Rocket.Chat | 14 literales (ver 1.3) | **R** |
| `mistral:7b` | `fase3-agentic/docker-compose.yml:19` | Literal en `environment`; `app/config.py:40` admite la variable. **R** |

---

## 4. Orden de arranque y dependencias

### 4.1 Redes

| Red | La crea | La usan |
|---|---|---|
| `oob-network` (externa) | **a mano**: `docker network create oob-network` (`fase1-infraestructura/README.md:160`) | Todos los compose |
| `single-node_default` | El compose de Wazuh, con nombre fijo (`wazuh/single-node/docker-compose.yml:134-136`) | Externa para `fase3-agentic/docker-compose.yml:44-45` y `fase5-orchestrator-api/docker-compose.yml:45-46` |
| `fase1-internal` | fase 1 (`fase1-infraestructura/docker-compose.yml:4-5`, `internal`) | mongodb, rocketchat |
| `iris_backend`, `iris_frontend` | fase 6, con nombre fijo (`fase6-iris/docker-compose.yml:58-62`) | IRIS |
| `kvm-internal` | fase 8 (`docker-compose.yml:119-120`) | rttys |

`docs/README-fase1a-traefik-portainer.md:258-275` describe una unidad `docker-oob-network.service` que recrea la red tras un reinicio. No está versionada como fichero.

### 4.2 Dependencias entre servicios

Dentro de un compose (`depends_on`):

- `rocketchat` → `mongodb` **healthy** (`fase1-infraestructura/docker-compose.yml:103-105`).
- `wazuh.dashboard` → `wazuh.indexer` (`wazuh/single-node/docker-compose.yml:98-99`).
- `minio-init` → `minio` healthy (`fase5-velociraptor/docker-compose.yml:73-75`).
- IRIS: `app` → `rabbitmq`, `db`; `worker` → `app`; `nginx` → `app` **healthy** (`docker-compose.base.yml:51-53,80-83`; `docker-compose.override.yml:28-30`).

Entre compose (no declaradas en ningún `depends_on`):

| Necesita | A quién | Evidencia |
|---|---|---|
| Todos los routers | Traefik y el middleware `authelia@file` | `fase1-infraestructura/traefik/dynamic/middlewares.yml:11-13` |
| Headscale (plano de control) | Traefik con el certificado comodín, **y** `hs.<dominio>` resuelto en el host | `docs/README-fase4b-tailnet.md:25-28,73-74`; `docs/resolucion-nombres.tsv:32` |
| El host en el tailnet | Headscale arriba, CA instalada en el host, `tailscaled` reiniciado | `docs/README-fase4b-tailnet.md:179-183` |
| RustDesk | la IP del tailnet (bind en `TAILNET_IP`) | `docker-compose.rustdesk.yml:10-13,25-26` |
| nginx de IRIS | la IP del tailnet (bind en `100.64.0.1`) | `fase6-iris/docker-compose.override.yml:27` |
| rttys (KVM) | la IP de LAN presente en el host (bind) | `fase8-kvm/…/docker-compose.override.yml:14-15` |
| rttys (hook de autorización) | n8n con el workflow `KVM Hook` activo; si n8n no responde, falla cerrado (`403`) | `rttys.conf.template:59`; `fase8-kvm/README.md:482` |
| `langgraph-agent` | Wazuh (red e indexador), Ollama | `fase3-agentic/docker-compose.yml:18,25,33` |
| `orchestrator` | Wazuh (red), MinIO, Velociraptor (`api_client.yaml`, `downloads/`) | `fase5-orchestrator-api/docker-compose.yml:10,16,35,40` |
| n8n (workflow principal) | `langgraph-agent`, `orchestrator`, `rocketchat`, `misp`, IRIS por `iris.<dominio>:4833` | `wazuh-alert-handler.json:196,238,331,608,703` |
| n8n → IRIS | **`iris.<dominio>` en el `/etc/hosts` del host**, que el contenedor hereda por `systemd-resolved` y el resolver de Docker. Dependencia implícita, no declarada en ningún compose | `docs/DECISION-n8n-iris-ruta-directa.md:42-44,89,109` |
| n8n → agente del DC | DC01 en el tailnet con la IP `100.64.0.2` | `n8n/docker-compose.yml:24` |
| Manager de Wazuh → n8n | `extra_hosts: n8n.oob.local:host-gateway`, es decir, Traefik en el host | `wazuh/single-node/docker-compose.yml:46-47`; `fase2-orquestador/README.md:140-145` |
| n8n (arranque) | `peers.json` y `certs/oob-rootCA.crt` presentes como ficheros | `n8n/docker-compose.yml:32-33` |

Puertos publicados en todas las interfaces que pueden chocar con algo en un Ubuntu de escritorio: `80`, `443` (`fase1-infraestructura/docker-compose.yml:15-16`); `1514`, `1515`, `514/udp`, `55000`, `9200` (`wazuh/single-node/docker-compose.yml:15-18,54`); `8001` (`fase5-velociraptor/docker-compose.yml:18`); `9000` (`:44`); `3478/udp` (`docker-compose.headscale.yml:14`); `8888` de `misp-guard` (`misp/misp-docker/docker-compose.yml:387-388`).

### 4.3 Unidades systemd

| Unidad | Qué espera | Qué ejecuta | Observaciones |
|---|---|---|---|
| `tfm-fase4-rustdesk.service` | `docker.service`, `tailscaled.service`, y la IP `TAILNET_IP` hasta 300 s (`:4-6,18`) | `compose -f docker-compose.rustdesk.yml down` y `up -d --wait` (`:20-21`) | Sin `--remove-orphans` a propósito: `headscale-ui` comparte proyecto y lo borraría (`:19`) |
| `tfm-fase6-iris.service` | `docker.service`, `tailscaled.service`, y `100.64.0.1` hasta 300 s (`:4-6,22`) | `compose down --remove-orphans` y `up -d --wait` (`:23-24`) | `TimeoutStartSec=300` (`:26`) |

Las dos esperan una IP que solo existe cuando `tailscaled` ha hablado con Headscale, que es un contenedor del propio enclave (`tfm-fase4-rustdesk.service:14-16`). Ninguna unidad gobierna Headscale, Traefik ni el resto: dependen de `restart: unless-stopped`/`always` del demonio.

### 4.4 Directorio y ficheros `-f` de cada compose

| Pila | Directorio de trabajo | Invocación | Por qué |
|---|---|---|---|
| Fase 1 núcleo | `fase1-infraestructura/` | `docker compose up -d` | Montajes relativos (`./traefik`, `./authelia`, `./mongodb`) |
| Certificados de Wazuh | `fase1-infraestructura/wazuh/single-node/` | `docker compose -f generate-indexer-certs.yml run --rm generator` | `wazuh/single-node/README.md:11` |
| Wazuh | `fase1-infraestructura/wazuh/single-node/` | `docker compose up -d` | El nombre de proyecto debe ser `single-node`: de él salen `single-node-wazuh.manager-1` e `…indexer-1`, que otros ficheros llevan escritos (3.2). Monta `../../../fase2-orquestador/wazuh-integration/custom-n8n` (`docker-compose.yml:45`) |
| Headscale | `fase4-breakglass-dc/headscale/config/` | `docker compose -f docker-compose.headscale.yml up -d` | El compose vive dentro de su directorio de configuración: monta `./` como `/etc/headscale` y `../lib` como datos (`docker-compose.headscale.yml:10-11`). Lanzado desde otro sitio con `--project-directory` distinto montaría otra cosa |
| Headscale UI | `fase4-breakglass-dc/` | `docker compose -f docker-compose.headscale-ui.yml up -d` | Monta `./headscale-ui/container-config` (`:23`) |
| RustDesk | `fase4-breakglass-dc/` | `docker compose -f docker-compose.rustdesk.yml up -d` (o la unidad) | Necesita `.env` con `TAILNET_IP`. Mismo proyecto que Headscale UI: **nunca** `--remove-orphans` |
| MISP | `misp/misp-docker/` | `docker compose up -d`, **sin `-f`** | El override se carga solo si Compose descubre los ficheros. Sin él, MISP queda publicado en todas las interfaces y sin router (`misp/misp-docker/.gitignore`, bloque final; `fase1-infraestructura/overrides/misp-docker-compose.override.yml:17-20`) |
| MinIO + Velociraptor | `fase5-velociraptor/` | `docker compose build velociraptor` (para poder generar la configuración) y luego `docker compose up -d` | `docker-compose.yml:3-7` |
| Ollama | `fase2-orquestador/ollama/` | `docker compose up -d` | — |
| Triage | `fase3-agentic/` | `docker compose up -d --build` | `fase2-orquestador/README.md:429-431`. Monta `../fase7-observabilidad/shared` (`docker-compose.yml:28`) |
| Orchestrator | `fase5-orchestrator-api/` | `docker compose up -d --build` | Monta rutas `../fase5-velociraptor/…` y `../fase7-observabilidad/…` (`docker-compose.yml:32,35,40`) |
| IRIS | `fase6-iris/` | `docker compose up -d --wait`, **sin `-f`** | Con `-f` explícito el override queda fuera **sin aviso** y se pierden la restricción de puerto y el bundle TLS; ya ocurrió (`fase6-iris/README.md:155-160`). Comprobación previa: `docker compose config \| grep -E 'CA_BUNDLE\|100\.64\.0\.1\|service_healthy'` (`fase6-iris/README.md:164`) |
| n8n | `fase2-orquestador/n8n/` | `docker compose up -d` | Monta `../../fase4-breakglass-dc/rustdesk/peers.json` (`docker-compose.yml:33`) |
| KVM | `fase8-kvm/glkvm-cloud/docker-compose/` | `docker compose up -d`, **sin `-f`** | El override fija la imagen por digest, restringe los puertos a la LAN y desactiva coturn (`docker-compose.override.yml:5,11-15,23`). Mismo mecanismo que fase 6 **(inferencia)** |

`fase6-iris/docker-compose.dev.yml` y `fase1-infraestructura/wazuh/multi-node/` no intervienen.

### 4.5 Orden de etapas propuesto

En cada frontera, **[C]** indica los secretos cosechables que quedan disponibles al cruzarla.

| Etapa | Contenido | Frontera |
|---|---|---|
| **0 · Host** | Paquetes (Docker, plugin de Compose, Tailscale, `sqlite3`, `jq`, `openssl`); `vm.max_map_count`; preguntar parámetros (IP de LAN, IP de enclave, dominio, hostname, IP esperada del tailnet); `/etc/hosts` del host; `docker network create oob-network` | — |
| **1 · Material previo** | Todos los secretos **G**; CA, comodín y certificados de IRIS y KVM; copias de la CA (n8n, IRIS, bundle); instalación de la CA en el host; `mongo-keyfile`; `acme.json`; `users_database.yml` (hash **D**); directorios `certificates/ldap`, `web_certificates`, `velociraptor-config`; `peers.json` vacío; reescritura de los ficheros **R** de la sección 3 | — |
| **2 · Fase 1 núcleo** | Traefik, Authelia, MongoDB, Rocket.Chat, Portainer. Iniciar el replica set y crear el usuario de Mongo (sección 5) | **[C]** administrador de Rocket.Chat; `RC_BOT_USER_ID`, `RC_BOT_TOKEN`; `IR_APPROVER_IDS`; `RC_OUTGOING_TOKEN` (el webhook saliente puede apuntar ya a la URL futura de n8n) |
| **3 · Wazuh** | Certificados del indexador; hashes de `internal_users.yml` (**D**, necesita la imagen del indexador); `wazuh.yml`; `up -d` | Existe `single-node_default`. Ningún **C** |
| **4 · Headscale y tailnet del host** | Headscale; `users create`; clave de preautorización del host; `tailscale up`; etiquetar el nodo desde el servidor | **[C]** `TAILNET_IP`; clave de API de Headscale |
| **5 · Servicios atados al tailnet** | `fase4-breakglass-dc/.env`; RustDesk; Headscale UI; IRIS | **[C]** clave pública de RustDesk (para DC01); clave de API de IRIS si no se fijó con `IRIS_ADM_API_KEY` |
| **6 · CTI y forense** | MISP; `build` de Velociraptor → `config generate` → edición → `up`; MinIO; usuario `tfm-orchestrator`; `api_client.yaml` | **[C]** `api_client.yaml`; `client.config.yaml` y MSI (para DC01/W11). `ADMIN_KEY` de MISP si no se fijó |
| **7 · Motores** | Ollama y descarga del modelo; `langgraph-agent`; `orchestrator` | — |
| **8 · Orquestador** | `n8n/.env` completo; n8n; alta del propietario; credenciales; reescritura e importación de los workflows; activación | **[C]** identificadores de las 6 credenciales de n8n; identificadores de los workflows |
| **9 · Cierre de integraciones** | Integración `custom-n8n` en el manager y reglas `local_rules.xml`; KVM (rttys); dashboard de fase 7; cron de `export-peers.sh` y `check-kvm-lastseen.sh`; unidades systemd | **[C]** identificador del dispositivo KVM cuando el GL-RM1 se registre |
| **10 · Paquete de salida** | CA, líneas de hosts, tokens, claves de preautorización, MSI, ficheros del dispositivo (sección 9) | — |

Dos órdenes que el documento actual invierte y conviene fijar:

- `fase2-orquestador/README.md:422-449` arranca el triage (paso 2) antes que nada; depende de `single-node_default`, así que Wazuh va primero.
- MISP no depende del tailnet: puede adelantarse a la etapa 3 si interesa paralelizar.

---

## 5. Pasos posteriores al arranque

«NI» = vía no interactiva.

| # | Paso | Documento | ¿NI? |
|---|---|---|---|
| 1 | Iniciar el replica set `rs0` y crear el usuario root de Mongo | `docs/README-fase1c-mongodb-rocketchat.md:95-97,184-204`; `fase1-infraestructura/mongodb/init-mongo.sh:11-21` | **Sí, con matiz.** `init-mongo.sh` hace exactamente eso con `mongosh`, pero **ningún compose lo monta ni lo ejecuta**. El documento describe un arranque en dos tiempos (primero sin keyfile). Si el script funciona contra el compose actual (con keyfile desde el inicio) no está comprobado. Hasta que se haga, `mongodb` queda `unhealthy` y `rocketchat` no arranca (`docker-compose.yml:91,103-105`) |
| 2 | Primer administrador de Rocket.Chat | `docs/README-fase1c-mongodb-rocketchat.md:119-121` | **No documentada.** El documento dice que el primer usuario del asistente pasa a ser administrador, pero el compose marca el asistente como completado (`docker-compose.yml:112`). Cómo nace el administrador con esa combinación no consta |
| 3 | Cuenta `orchestrator-bot`, token personal con omisión de 2FA, usuarios aprobadores | `fase1-infraestructura/README.md:212-214`; `docs/README-fase4d-flujo-aprobacion.md:78` | **No documentada** |
| 4 | Canales `general` y `alertas-cve`; permisos `create-c`/`create-p` del bot para los War Rooms `#inc-*` | `wazuh-alert-handler.json:815,837`; `docs/README-fase2bcd-workflow-n8n.md:204` | **No documentada.** `alertas-cve` no aparece en ningún procedimiento de creación |
| 5 | Webhook saliente de Rocket.Chat para `!ir` → `…/webhook/rc-breakglass` | `docs/README-fase4d-flujo-aprobacion.md:47-48,86`; ruta real en `fase4d-breakglass.json` (nodo `Webhook`) | **No documentada.** `fase4-breakglass-dc/README.md:89` dice `/webhook/ir-command`; el workflow versionado expone `rc-breakglass` |
| 6 | Usuarios de Authelia y alta de TOTP | `docs/README-fase1b-authelia.md:218-242` | Hash: **sí** (`authelia crypto hash generate argon2`, `:222-223`). TOTP: **no**, es un alta personal por navegador con enlace en `authelia/notification.txt` |
| 7 | Contraseñas de Wazuh: hashes y `wazuh.yml` | `config/wazuh_indexer/internal_users.yml:11-12`; `fase2-orquestador/README.md:545-546` | **Sí** (`hash.sh` dentro de la imagen). Es previo al arranque, no posterior |
| 8 | Usuario de Headscale, clave de preautorización, `tailscale up` del host | `docs/README-fase4b-tailnet.md:33,54,60-61,67-70` | **Sí.** Las etiquetas se asignan desde el servidor (`headscale nodes tag`), porque `--advertise-tags` falló (`docs/README-fase4b-tailnet.md:162-166`) |
| 9 | Validar la ACL | `headscale/config/acl.hujson:4` | **Sí**: `headscale policy check` |
| 10 | Clave de API en Headscale UI | `docs/README-fase4a-headscale-ui.md:103`; `headscale-ui/container-config/config.yaml:8-10` | Generación **sí**; pegado en la UI **manual** |
| 11 | Bucket `evidence` de MinIO | `fase5-velociraptor/init-minio-bucket.sh:3-5` | **Sí, ya automatizado** por el servicio `minio-init` (`docker-compose.yml:70-85`) |
| 12 | Usuario `tfm-orchestrator` y política `evidence-writer` en MinIO | `fase5-velociraptor/SECURITY-NOTICE.md:186-190`; `fase5-orchestrator-api/.env.example:14-15` | **No documentada.** Ni el comando ni el JSON de la política están en el repo; solo su descripción (sin `s3:DeleteObject`, con `s3:GetBucketLocation` y multiparte) |
| 13 | Configuración de Velociraptor: generar, alinear con la plantilla, abrir la API gRPC | `fase5-velociraptor/README.md:272-281,316-322` | Generación **sí**; la alineación es «a mano» (`:279`) |
| 14 | Cliente API de Velociraptor y ajuste de `api_connection_string` | `fase5-velociraptor/README.md:343-349,364-370` | **Sí** (CLI + edición de un campo) |
| 15 | Usuario de la GUI de Velociraptor | — | **No documentada** |
| 16 | IRIS: administrador, MFA y segunda cuenta | `fase6-iris/.env.example:46-49`; `scripts/verify-fase6.sh:59-68` | Administrador y clave de API: **sí**, por variables con BD vacía (1.7). **MFA: no**: `verify-fase6.sh` exige `enforce_mfa` activo y dos cuentas con MFA enrolado; el enrolado es por navegador |
| 17 | IRIS: cliente `IrisInitialClient` | `docs/README-Fase6b.md:44` | Lo crea IRIS por defecto **(inferencia por el nombre)** |
| 18 | n8n: alta del propietario | — | **No documentada** |
| 19 | n8n: crear las 6 credenciales | `fase2-orquestador/README.md:459,532` | **No documentada**; el repo dice «a mano» |
| 20 | n8n: importar workflows y reiniciar | `fase2-orquestador/README.md:446-448` | **Sí**: `docker cp` + `n8n import:workflow --input=…` + `docker restart n8n` |
| 21 | n8n: reasignar credenciales y activar | `fase2-orquestador/README.md:459`; `n8n/export-workflow.sh:8` | Reasignación: **no documentada**. El export deja `active` en `false` a propósito («el import no debe reactivar nada solo») |
| 22 | Integración `custom-n8n` en el manager: CA, `n8n-integration.conf`, bloque `<integration>`, reinicio | `fase2-orquestador/README.md:439-443` | **Sí** (`docker cp`, `docker exec … wazuh-control restart`). El script va por bind mount y necesita modo `755` (`fase2-orquestador/README.md:124,135`). **El bloque se pierde en cada recreación del contenedor** (`fase2-orquestador/README.md:117`) |
| 23 | Reglas `100600`–`100609` del manager | `docs/README-fase4-validacion.md:343-357` | **No**: hay que transcribirlas del documento |
| 24 | Modelo de Ollama (`mistral:7b`) | `docs/README-fase2e-ollama-ai-agent.md:23,35,79` | **No documentada**: consta que se descargó, no el comando. Requiere Internet |
| 25 | Dashboard de fase 7 | `fase7-observabilidad/README.md:308-313` | **Sí**, por la API de objetos guardados; marcado como «procedimiento no ejecutado». El índice `tfm-metrics-events` debe existir antes (`:316`) |
| 26 | KVM: usuarios y grupos de rttys | `fase8-kvm/README.md:360-369,410` | **No documentada** en los README; la API está descrita en `docs/api-reconocimiento-fase8.md` (no revisada línea a línea) |
| 27 | Cron: `export-peers.sh` cada 30 min; `check-kvm-lastseen.sh` cada 5 min | `fase4-breakglass-dc/rustdesk/export-peers.sh:9`; `fase8-kvm/README.md:313` | **Sí** (crontab del usuario). La línea exacta no está en el repo. `export-peers.sh` necesita `sqlite3` en el host (`export-peers.sh:15`) |
| 28 | Unidades systemd | `fase6-iris/README.md:353-355` | **Sí**. Para la de RustDesk no hay instrucciones propias; se asume el mismo procedimiento **(inferencia)** |
| 29 | `/etc/hosts` del host | `docs/resolucion-nombres.tsv:22-34`; `docs/README-resolucion-nombres.md` | **Sí**. La línea de `iris` comparte el alias `iris.local` (`resolucion-nombres.tsv:29`) |
| 30 | CA en el almacén del host y reinicio de `tailscaled` | `docs/README-fase4b-tailnet.md:179-183` | Reinicio **sí**; la instalación de la CA en Ubuntu **no tiene comando escrito** |

---

## 6. Workflows de n8n

### 6.1 Versionados

| Ruta | Nombre | Nodos | Webhooks | Credenciales (tipo · nombre × refs) | `$env` |
|---|---|---|---|---|---|
| `fase2-orquestador/n8n/workflows/wazuh-alert-handler.json` | Wazuh Alert Handler with Langgraph | 35 | `POST wazuh-alerts` | `rocketchatApi` · Rocket account ×9; `httpHeaderAuth` · Header Auth account ×5; `httpHeaderAuth` · AbuseIPDB ×1; `virusTotalApi` · VirusTotal account ×1; `mispApi` · MISP account ×1; `dfirIrisApi` · DFIR-IRIS account ×3 | `OOB_WEBHOOK_SECRET` (`:270`), `RC_BOT_USER_ID` (`:580`), `ORCH_HMAC_SECRET` (`:689`) |
| `fase4-breakglass-dc/workflows/fase4d-breakglass.json` | fase4d-breakglass | 40 | `POST rc-breakglass`; `bg-credential`; `kvm-approval` | `rocketchatApi` · Rocket account ×8; `httpHeaderAuth` · Header Auth account ×2; `dfirIrisApi` · DFIR-IRIS account ×2 | `RC_OUTGOING_TOKEN` (`:26`), `RC_URL` (`:52,321,429,474,509`), `IR_APPROVER_IDS` (`:92`), `DC_AGENT_URL` (`:355,369`), `AGENT_TOKEN` (`:355,375`), `AGENT_HMAC_SECRET` (`:355`), `CREDENTIAL_BASE_URL` (`:415`) |
| `fase8-kvm/workflows/kvm-hook.json` | KVM Hook | 12 | `kvm-hook` | ninguna (usa la cookie de sesión de rttys que recibe, `:52-53`) | ninguna |
| `fase5-velociraptor/n8n_fase5_workflow.json` | Fase5 - Velociraptor a MinIO | 8 | `POST dfir/collect` | ninguna | ninguna |

Total de referencias a credenciales: **32** (20 + 12), todas con `"id": "REEMPLAZAR"`. Ninguno de los cuatro ficheros tiene campo `id` de workflow; el de fase 5 conserva `versionId`.

Otras dependencias que los workflows llevan dentro:

- `kvm-hook.json:252` llama a `http://localhost:5678/webhook/kvm-approval`, servido por `fase4d-breakglass`: **los dos workflows tienen que estar activos a la vez**.
- `fase4d-breakglass.json:595` lee `/data/peers.json` con `fs`, lo que exige `NODE_FUNCTION_ALLOW_BUILTIN=crypto,fs` (`n8n/docker-compose.yml:15`) y el montaje de `:33`.
- El nodo MISP llama a `https://misp/…` con `allowUnauthorizedCerts: true` (`wazuh-alert-handler.json:238,244-246`). `fase2-orquestador/n8n/certs/misp.crt` está versionado (autofirmado, `CN=localhost`) y **ningún compose lo monta**: es un resto.
- Canales de Rocket.Chat que el flujo da por existentes: `alertas-cve` y `general` (`wazuh-alert-handler.json:815,837`).

### 6.2 Contraste con lo que los documentos dicen que hay en producción

| Lo que dicen los documentos | ¿Está en el repo? |
|---|---|
| Workflow principal con identificador propio de la instancia, exportable con `export-workflow.sh` (`n8n/export-workflow.sh:32`; `docs/revision-workflow1-caso-iris-warroom.md:661`) | Sí: `wazuh-alert-handler.json` |
| Workflow de break-glass (`export-workflow.sh:31`) | Sí: `fase4d-breakglass.json` |
| `kvm-hook` activo (`fase8-kvm/README.md:380-383`) | Sí: `kvm-hook.json` |
| Flujo auxiliar `echo`, borrado (`docs/AUDITORIA-CIERRE-2026-09-23.md:467`) | No, y no hace falta |
| `/webhook/ir-command` (`fase4-breakglass-dc/README.md:89`; dos menciones en documentos) | **No hay ningún webhook con esa ruta.** El versionado expone `rc-breakglass`. O el README está desfasado, o el workflow desplegado difiere del versionado |
| `/webhook/dc-action` (una mención en documentos) | **No.** `docs/README-fase4d-n8n.md:5-6` avisa de que esa versión del diseño fue sustituida |
| `Fase5 - Velociraptor a MinIO` (`dfir/collect`) | Sí, pero su estado en producción **no consta**. El workflow principal ya llama al orchestrator directamente (`wazuh-alert-handler.json:703`), lo que sugiere que es un resto de la fase 5 inicial |

No se ha encontrado en ningún documento un listado de los workflows de la instancia (la salida de `n8n list:workflow`). Que no haya workflows desplegados y no versionados **no se puede afirmar leyendo**: ver «No verificado» y la decisión 10.4.

---

## 7. Imágenes

### 7.1 Fijadas por digest

| Imagen | Dónde |
|---|---|
| `docker.n8n.io/n8nio/n8n:latest@sha256:fe36dc65…` | `fase2-orquestador/n8n/docker-compose.yml:3` |
| `glzhitong/glkvm-cloud@sha256:a04a1225…` | `fase8-kvm/glkvm-cloud/docker-compose/docker-compose.override.yml:5`. Espacio de nombres personal de Docker Hub; el propio fichero recomienda guardar copia con `docker save` (`:3-4`) |

### 7.2 Fijadas por etiqueta de versión (reproducibles salvo que el editor mueva la etiqueta)

| Imagen | Dónde |
|---|---|
| `traefik:v3.3` (menor, no parche) | `fase1-infraestructura/docker-compose.yml:9` |
| `mongo:8.0` (menor, no parche) | `fase1-infraestructura/docker-compose.yml:76` |
| `registry.rocket.chat/rocketchat/rocket.chat:${ROCKETCHAT_VERSION}` → `8.4.1` | `docker-compose.yml:100`; `.env.example:4` |
| `wazuh/wazuh-manager:4.14.0`, `wazuh-indexer:4.14.0`, `wazuh-dashboard:4.14.0` | `wazuh/single-node/docker-compose.yml:4,50,75` |
| `wazuh/wazuh-certs-generator:0.0.2` | `wazuh/single-node/generate-indexer-certs.yml:4` |
| `ollama/ollama:0.24.0` | `fase2-orquestador/ollama/docker-compose.yml:3` |
| `docker.io/headscale/headscale:0.28.0` | `headscale/config/docker-compose.headscale.yml:3` |
| `rustdesk/rustdesk-server:1.1.14` | `fase4-breakglass-dc/docker-compose.rustdesk.yml:3,18` |
| `ghcr.io/dfir-iris/iriswebapp_{db,app,nginx}:v2.4.27` | `fase6-iris/docker-compose.yml:18,27,37,46`; `.env.example:13,20,31` |
| `rabbitmq:3.13.7-management-alpine` | `fase6-iris/docker-compose.override.yml:43` (sustituye a `rabbitmq:3-management-alpine` de `docker-compose.base.yml:20`, flotante: otro motivo para no usar `-f`) |
| `ghcr.io/egos-tech/smtp:1.1.3`, `valkey/valkey:7.2`, `mariadb:10.11` | `misp/misp-docker/docker-compose.yml:5,22,63` |

### 7.3 Flotantes · riesgo de reproducibilidad

| Imagen | Dónde |
|---|---|
| `portainer/portainer-ce:latest` | `fase1-infraestructura/docker-compose.yml:31` |
| `authelia/authelia:latest` | `fase1-infraestructura/docker-compose.yml:55`. El README habla de «Authelia 4.39» (`fase1-infraestructura/README.md:17`); la configuración usa claves de esa rama (`authelia/configuration.yml:7-8`) |
| `ghcr.io/gurucomputing/headscale-ui:latest` | `fase4-breakglass-dc/docker-compose.headscale-ui.yml:19` (con un `TODO` en `:16-18`) |
| `minio/minio:latest` | `fase5-velociraptor/docker-compose.yml:36` |
| `minio/mc:latest` | `fase5-velociraptor/docker-compose.yml:71` |
| `ghcr.io/misp/misp-docker/misp-core:${CORE_RUNNING_TAG:-latest}` | `misp/misp-docker/docker-compose.yml:95`; la variable está comentada en `template.env:38` |
| `ghcr.io/misp/misp-docker/misp-modules:${MODULES_RUNNING_TAG:-latest}` | `docker-compose.yml:349`; `template.env:39` |
| `ghcr.io/misp/misp-docker/misp-guard:${GUARD_RUNNING_TAG:-latest}` | `docker-compose.yml:379`; `template.env:40` |
| `glzhitong/glkvm-cloud:latest` | `fase8-kvm/…/docker-compose.yml:3`. Solo si el override queda fuera |
| `coturn/coturn:edge-alpine` | `fase8-kvm/…/docker-compose.yml:93`. Desactivada por perfil (`docker-compose.override.yml:23`) |

`fase2-orquestador/README.md:547` habla de «nueve servicios» con `:latest`; el recuento de hoy, sin contar los dos de fase 8 que el override neutraliza, es de ocho.

### 7.4 Construidas en el despliegue

| Imagen | Base | Depende de la red |
|---|---|---|
| `velociraptor-oob:0.76.6` | `debian:bookworm-slim` (`velociraptor-image/Dockerfile:1`) | Descarga el binario de las releases de GitHub (`Dockerfile:8-10`), sin comprobación de suma |
| `langgraph-agent` | `python:3.11-slim` (`fase3-agentic/Dockerfile:1`) | PyPI; versiones fijadas en `requirements.txt` |
| `orchestrator` | `python:3.11-slim` (`fase5-orchestrator-api/Dockerfile:1`) | PyPI; versiones fijadas en `requirements.txt` |

Las tres bases son etiquetas flotantes.

---

## 8. Verificaciones existentes reutilizables

| Comprobación | Qué discrimina | Qué no |
|---|---|---|
| `scripts/verify-hosts.sh` (local) | Que el `/etc/hosts` del host coincide con `docs/resolucion-nombres.tsv`: nombre ausente, sobrante, IP distinta, duplicados (`verify-hosts.sh:31-32`) | Compara el fichero, **no la alcanzabilidad** ni que el servicio responda. No vigila MagicDNS (`:16-18`). Con IP o dominio nuevos hay que regenerar antes el `.tsv` |
| `scripts/verify-hosts.sh --emit` / `--check w11\|dc01` | Lo mismo para los hosts de Windows, con la salida pegada en un fichero (`:22-26`) | Necesita intervención manual en cada Windows |
| `scripts/verify-hosts.sh --check-doc` | Que el `.tsv` y la tabla del README no han divergido (`:27-28`) | Nada sobre los hosts reales |
| `scripts/verify-fase6.sh` | Comportamiento observable de IRIS: contenedores, pertenencia a `iris_frontend`, escucha solo en el tailnet, ancla de confianza, validación del certificado, tamaño del bundle, claves no públicas, `enforce_mfa`, dos cuentas con MFA (`verify-fase6.sh:16-68`) | Lleva escritas la huella de la CA actual (`:8`) y `100.64.0.1` (`:30-31`): **tal cual falla en una instalación limpia**. La comprobación 7 compara con `.env.model`, que no existe en el repo: con el fichero ausente solo detecta la clave vacía (`:51-57`). Las 8 y 9 no pueden pasar hasta el enrolado manual de MFA |
| `scripts/verify-dcagent-health.sh` | Que `/health` del agente del DC declara `hmac_required: true` (`verify-dcagent-health.sh:14-16`). Tiene modo `--from-file` y fixtures | No comprueba la ruta del log (`:20-21`) ni que el token esté configurado en la versión desplegada (`:18`). Solo sirve cuando DC01 ya está montado |
| `scripts/verify-no-secrets.sh` | Material sensible en ficheros **trackeados**: bloques PEM, campos `private_key`/`password_hash`/`nonce`, base64 largo bajo `fase5-velociraptor/`, lista de credenciales conocidas (`verify-no-secrets.sh:7-27`) | No ve ficheros sin trackear (los `.env` generados). No tiene regla para `password:` suelto: no señala `wazuh.yml:6`. Útil **después** del despliegue para confirmar que no se ha añadido nada al índice |
| `scripts/collect-signed.sh` | Extremo a extremo de `POST /velociraptor/collect` con firma HMAC; permite forzar firma inválida, replay y ventana temporal (`collect-signed.sh:19-24`) | Lanza una colección real: no es una sonda inocua. Lee el secreto de `fase5-orchestrator-api/.env` (`:26-27`) |
| `scripts/dc-signed.sh --selftest` | Canal firmado n8n → agente del DC (`dc-signed.sh:22-26`) | Requiere DC01 |
| `fase8-kvm/scripts/check-kvm-lastseen.sh` | Conexión TCP establecida del dispositivo contra rttys en el 5912 (`check-kvm-lastseen.sh:14-16,36-46`) | Usa `docker inspect` y `docker exec`. Nada sobre el hook ni la consola |
| `docker compose ps` de fase 1 | `authelia` y `mongodb` `healthy` (`fase1-infraestructura/README.md:226-230`) | `healthy` de Mongo implica replica set y usuario correctos (`docker-compose.yml:89-93`); no dice nada de Rocket.Chat |
| `mongosh … rs.status().ok` | Replica set iniciado (`fase1-infraestructura/README.md:244-249`) | — |
| `wget http://authelia:9091/api/health` desde Traefik | Alcance de Authelia (`fase1-infraestructura/README.md:254`) | No prueba la política |
| `curl` sin sesión → `302` a `auth.<dominio>` | Que el middleware protege el router (`fase1-infraestructura/README.md:32-34`) | Medido solo en `chat` y `n8n`; el resto «consta por configuración» |
| `wazuh-control status \| grep integrator` | Que `wazuh-integratord` está vivo, es decir, que hay bloque `<integration>` válido (`fase2-orquestador/README.md:117-119,468`) | No prueba la entrega |
| `tail integrations.log` | Entrega real: `custom-n8n` escribe el código HTTP de cada alerta (`custom-n8n:148-149`; `fase2-orquestador/README.md:475`) | Necesita que haya una alerta de nivel ≥ 7 (`ossec-integration.xml:8`) |
| `docker exec n8n wget -qO- http://langgraph-agent:8000/health` | Alcance n8n → triage (`fase2-orquestador/README.md:471`) | — |
| `docs/PROCEDIMIENTO-prueba-manual-webhook.md` | Inyección firmada de una alerta en `wazuh-alerts` | Manual; no revisado línea a línea |
| `headscale policy check --file …` | Sintaxis de la ACL (`headscale/config/acl.hujson:4`) | `check` valida el fichero; lo que está en vigor lo dice `get` (`docs/README-fase4a-headscale.md:48`) |
| `headscale nodes list` / `tailscale status` | Nodos registrados (`docs/README-fase4b-tailnet.md:110-116`) | No prueba la ACL |
| `docker compose config \| grep -E 'CA_BUNDLE\|100\.64\.0\.1\|service_healthy'` | Que el override de IRIS está cargado (`fase6-iris/README.md:164`) | Es una lectura de configuración, no de efecto. `docker compose config --quiet` no detecta la colisión de puertos del KVM (`fase8-kvm/README.md:227`) |
| Prueba gRPC desde el orchestrator | Autenticación con `api_client.yaml` y respuesta con filas (`fase5-velociraptor/README.md:378-397`) | Sin clientes registrados devuelve cero filas: distingue «autentica» de «no conecta», no de «hay flota» |
| `curl … /tfm-metrics-events/_count` | Que el índice de métricas existe y tiene documentos (`fase7-observabilidad/README.md:240-241`) | — |
| `openssl verify -CAfile oob-rootCA.crt oob-wildcard.crt` | Que el comodín lo firma la CA (`generate-oob-ca.sh:100`) | No prueba que Traefik lo sirva |

---

## 9. Fuera de alcance del nodo Ubuntu · paquete de salida

### 9.1 DC01 (controlador de dominio)

| Qué necesita | De dónde sale | Documento |
|---|---|---|
| `oob-rootCA.crt` para el almacén de confianza de Windows | etapa 1 | Requisito en `docs/README-fase4b-tailnet.md:25-28`. **El comando de importación en Windows no está escrito** |
| Líneas de hosts: `hs.<dominio>` y `velociraptor.local` → IP del enclave | `docs/resolucion-nombres.tsv:45-46` | `docs/README-resolucion-nombres.md` |
| Clave de preautorización de un solo uso, `tag:dc`, y el comando `tailscale up` | etapa 4 | `docs/README-fase4b-tailnet.md:78-98` |
| `AGENT_TOKEN`, `AGENT_HMAC_SECRET`, `AGENT_REQUIRE_HMAC=true`, `TFM_SCRIPTS_DIR`, `TFM_LOG_PATH`, `TFM_HEADSCALE_IP` | etapa 1 | `fase4-breakglass-dc/dcagent/README-despliegue.md:72-79,103-109`. `AppEnvironmentExtra` **reemplaza el conjunto completo**: el paquete debe llevar las seis líneas juntas (`:101-102`) |
| `agent_dc.py`, `requirements.txt` y los siete `.ps1` | `fase4-breakglass-dc/dcagent/`, `fase4-breakglass-dc/scripts/` | `dcagent/README-despliegue.md` |
| La IP de bind del agente (`--host 100.64.0.2`) | la asigna Headscale al DC | `dcagent/README-despliegue.md:91`. Debe coincidir con `DC_AGENT_URL` de n8n |
| Regla de firewall del puerto 8000 | fijo | `dcagent/README-despliegue.md:129-133` |
| RustDesk: servidor propio (IP del tailnet del host) y clave pública `id_ed25519.pub` | etapa 5 | `docs/README-fase4e-rustdesk-breakglass.md:96-100` |
| MSI de Velociraptor con la configuración de cliente embebida | etapa 6 | `fase5-velociraptor/README.md:291-304` |
| Agente de Wazuh apuntando al manager, y bloque `<localfile>` para `agent.log` | IP del enclave | `docs/README-fase4-validacion.md:334-340`. El alta del agente de Wazuh no tiene procedimiento propio en el repo |

### 9.2 W11 (puesto de analista)

| Qué necesita | De dónde sale | Documento |
|---|---|---|
| `oob-rootCA.crt` en el almacén de Windows y del navegador | etapa 1 | `fase8-kvm/README.md:158`. Sin comando escrito |
| Once líneas de hosts | `docs/resolucion-nombres.tsv:35-44,47` | `docs/README-resolucion-nombres.md`; comprobables con `verify-hosts.sh --emit w11` |
| Clave de preautorización de un solo uso, `tag:analyst` | etapa 4 | `docs/README-fase4b-tailnet.md:174-177` (el puesto de analista es un nodo propio) |
| Cliente RustDesk con el servidor y la clave pública del enclave | etapa 5 | `docs/README-fase4e-rustdesk-breakglass.md` |
| MSI de Velociraptor, si el puesto lleva cliente | etapa 6 | `fase5-velociraptor/SECURITY-NOTICE.md:67` |
| Credenciales personales: Authelia (contraseña y alta de TOTP), Rocket.Chat, IRIS (con MFA), rttys | etapas 2, 5 y 9 | Alta de TOTP: `fase1-infraestructura/README.md:201` |

### 9.3 GL-RM1 (KVM)

| Qué necesita | De dónde sale | Documento |
|---|---|---|
| `oob-rootCA.crt` en `/etc/kvmd/user/` | etapa 1 | `fase8-kvm/README.md:502-504` |
| `glkvm-device.crt` y su clave (EC `prime256v1`) en `/etc/kvmd/user/ssl/` | etapa 1, con `glkvm-device.cnf` | `fase8-kvm/README.md:254-256`. El SAN lleva la IP del dispositivo: un cambio de dirección invalida el certificado (`README.md:153`) |
| Valores de `S01selfCloud`: `HOSTNAME` y `WEBRTC_IP` (IP de LAN del host), `TOKEN` (= `RTTYS_TOKEN`), `WEBRTC_USERNAME`, `WEBRTC_PASSWORD` (= `TURN_PASS`), y la opción `-C` | etapa 1 | `fase8-kvm/README.md:193-202,502-504`; `docs/mejora2-tls-canal-rtty.md` |
| Endurecimiento del dispositivo | — | `docs/mejora6-endurecimiento-dispositivo.md` |
| **Sin** alta en el tailnet | — | Decisión D1 (`docs/credenciales-de-arranque.md:34-38,45`): el paquete del KVM no debe llevar clave de preautorización |

Las copias de configuración del dispositivo llevan `RTTYS_TOKEN` y `WEBRTC_PASSWORD` en claro (`fase8-kvm/backup-dispositivo/.gitignore:1-2`): el paquete de salida debe tratarse como material sensible y no puede vivir dentro del árbol del repositorio salvo en una ruta ignorada.

---

## 10. Bloqueos y decisiones abiertas

1. **Rocket.Chat no tiene vía de aprovisionamiento escrita.** Administrador, bot, token, aprobadores, canales y webhook saliente (pasos 2-5 de la sección 5) son hoy manuales, y de ellos dependen cuatro variables de n8n. Decisión: automatizar por la API REST interna (habría que probarlo primero) o dejar una pausa guiada en el script.
2. **Credenciales de n8n.** No hay vía no interactiva documentada para crearlas ni para sustituir los 32 `REEMPLAZAR`. Decisión: (a) pausa manual, (b) importar credenciales por CLI con identificadores elegidos por el script y reescribir los JSON antes de importar. La opción (b) no está probada en el repo.
3. **Los workflows versionados no son importables tal cual** en una instancia nueva: llevan 14 literales con el identificador del bot actual y el dominio escrito. Decisión: ¿el script reescribe una copia de trabajo fuera de git, o se cambian los ficheros versionados para que lleven marcadores?
4. **Paridad repo ↔ producción de n8n no comprobable leyendo.** Hace falta que Jose ejecute `n8n list:workflow` en la instancia actual y lo contraste con la sección 6, y que aclare `ir-command` frente a `rc-breakglass`.
5. **Ficheros versionados que el despliegue modifica:** `oob-rootCA.crt` (dos copias), `irisRootCACert.pem`, `ca-bundle-oob.crt`, `internal_users.yml`, `wazuh.yml`, `verify-fase6.sh` (huella) y todos los marcados **R** en la sección 3. Decisión: aceptar el árbol sucio, generar en rutas ignoradas y montar desde ahí, o convertirlos en plantillas.
6. **`wazuh.yml` lleva una contraseña literal en git** (`config/wazuh_dashboard/wazuh.yml:6`) y el README dice lo contrario. Decisión independiente del despliegue: confirmar si es la vigente y, si lo es, rotarla.
7. **MFA y TOTP son personales.** Authelia (TOTP) e IRIS (`enforce_mfa`, dos cuentas) no se pueden completar sin una persona con su dispositivo. El script puede dejarlo preparado, no terminado; `verify-fase6.sh` no pasará hasta entonces.
8. **Claves externas:** VirusTotal y AbuseIPDB. Las aporta Jose; decidir si el script las pide o admite seguir sin ellas (los nodos toleran el fallo, `fase2-orquestador/README.md:282`).
9. **Claves de preautorización en un paquete.** Por decisión del proyecto caducan en 1 h y son de un solo uso. Un paquete generado al final del despliegue obliga a montar DC01 y W11 dentro de esa hora. Decisión: ampliar la caducidad para el paquete, o que el paquete lleve el comando y la clave se genere en el momento.
10. **IP del tailnet no garantizada.** `100.64.0.1` (host) y `100.64.0.2` (DC01) salen de la asignación secuencial de Headscale (`config.yaml:21`) y del orden de alta. El script debe registrar el host primero y comprobar la IP obtenida antes de escribir el override de IRIS; para DC01, o se registra el segundo, o `DC_AGENT_URL` se parametriza.
11. **Dominio distinto de `oob.local`.** Es una reescritura de más de veinte ficheros (3.2), incluidos tres workflows y la configuración de Authelia. Decisión: ¿se admite de verdad otro dominio en esta primera versión, o se pregunta pero se valida que sea `oob.local`?
12. **MinIO:** falta el JSON de la política `evidence-writer`. Hay que recuperarlo de la instancia actual o reescribirlo a partir de su descripción.
13. **Velociraptor:** la alineación de `server.config.yaml` con la plantilla es manual, y no hay comando para el usuario de la GUI. Decisión: qué campos toca el script y con qué herramienta.
14. **Reglas propias de Wazuh y bloque `<integration>`** viven solo en el volumen `wazuh_etc`; el bloque se pierde al recrear el contenedor. Decisión: versionar un `local_rules.xml` y añadir el bloque al `wazuh_manager.conf` versionado, o que el script los inyecte cada vez.
15. **Plantillas que faltan o engañan:** `n8n/.env.example` (no existe), `fase8-kvm/.env` (la plantilla es la del upstream), `users_database.yml.example` (no existe), `ROOT_URL` (fuera de la plantilla de fase 1). El paso 2 debería empezar por crearlas.
16. **Salida a Internet durante el despliegue.** Imágenes, binario de Velociraptor, PyPI, modelo de Ollama y el instalador de Tailscale. Si el destino no tiene salida hace falta un paquete previo de imágenes.
17. **Usuario y ruta de las unidades systemd** (`jose`, `/home/jose/…`). Parámetros adicionales a los cinco previstos.
18. **Imágenes flotantes** (7.3). Decisión: fijar digest ahora, tomándolo de la instancia validada, o aceptar el riesgo en el primer despliegue.

---

## No verificado

Lo que sigue no se ha podido comprobar leyendo el repositorio. Nada de esto debe darse por cierto en el paso 2.

**Sobre el entorno real (no se ha tocado Docker ni ningún host):**

- Qué contenedores, redes y volúmenes existen hoy, y con qué versión real corren las imágenes `latest`.
- Qué workflows hay en la instancia de n8n y si coinciden con los cuatro versionados.
- El contenido de cualquier `.env`, clave, `api_client.yaml` o `users_database.yml` reales, y por tanto qué variables llevan de verdad.
- Si la contraseña de `wazuh.yml:6` y los hashes de `internal_users.yml` son los vigentes.
- La arquitectura de la imagen de KVM fijada por digest.
- Las entradas de `crontab` del usuario.
- Si `docker-oob-network.service` está instalada en el host.

**Inferencias marcadas en el texto:**

- Que Headscale crea por sí mismo sus claves y su base de datos en `../lib` en el primer arranque, y hbbs las suyas en `rustdesk/data/`.
- Que el primer nodo registrado recibe `100.64.0.1` y el segundo `100.64.0.2`.
- Que con `TAILNET_IP` vacío Compose publica RustDesk en todas las interfaces en vez de abortar.
- Que con `mongo-keyfile` ausente mongod no arranca (en lugar de arrancar sin keyfile).
- Que rttys crea su base de datos a partir de `database/schema.sql`.
- Que el proyecto de Compose de Headscale se llama `config`.
- Que omitir el override en fase 8 tiene el mismo efecto silencioso documentado para fase 6.
- Que la unidad de RustDesk se instala igual que la de IRIS.
- Que `IrisInitialClient` lo crea IRIS por defecto.
- Que el GL-RM1 conservará el identificador `zsb25f8` tras registrarse en una plataforma nueva.

**Vías no interactivas que parecen existir pero el repo no documenta ni prueba:**

- API REST de Rocket.Chat para crear usuarios, tokens personales, canales e integraciones; y si el token de un webhook saliente puede fijarse al crearlo (lo que haría `RC_OUTGOING_TOKEN` generable).
- `n8n import:credentials` y el alta del propietario de n8n sin navegador.
- Alta de usuario y política en MinIO con `mc admin`.
- Alta de usuario de la GUI de Velociraptor por CLI.
- Instalación de la CA en Ubuntu, en Windows y en los navegadores.
- Descarga del modelo con `ollama pull` dentro del contenedor.
- Creación de usuarios y grupos de rttys por su API.

**Comportamientos del software de terceros:**

- Que `IRIS_ADM_API_KEY` e `IRIS_ADM_PASSWORD` funcionen en la imagen `v2.4.27`: se ha leído el código vendorizado en `fase6-iris/source/`, no la imagen.
- Que `init-mongo.sh` funcione contra un mongod arrancado con `--keyFile` desde el primer momento (excepción de localhost), frente al arranque en dos tiempos que describe el documento.
- Cómo nace el primer administrador de Rocket.Chat 8.4.1 con el asistente marcado como completado.
- El formato que MISP exige a `ADMIN_KEY` y la longitud mínima de las credenciales de MinIO.
- Qué hace Authelia `latest` con la configuración actual si la versión ha avanzado respecto a la 4.39.

**Documentos no revisados línea a línea:** `docs/api-reconocimiento-fase8.md`, `docs/mejora2…mejora6`, `docs/PROCEDIMIENTO-prueba-manual-webhook.md`, `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md`, `docs/AUDITORIA-CIERRE-2026-09-23.md`, los informes de auditoría y el código Go de `fase8-kvm/glkvm-cloud/internal/`. Se han consultado por búsqueda, no leído enteros: puede haber pasos manuales adicionales descritos ahí.

---

## Resumen

### Hecho

- Leídos todos los compose, plantillas `.env`, unidades systemd, scripts de `scripts/` y de cada fase, los cuatro workflows de n8n y los README de fase; consultados por búsqueda los documentos de `docs/`.
- Las diez secciones, con evidencia `ruta:línea`, y la sección «No verificado».
- Revisado el entregable a mano: no contiene valores de secretos. Los cuatro puntos donde el repositorio lleva valores sensibles o atados a la instancia (`wazuh.yml:6`, `internal_users.yml:14,23`, los 14 literales del bot, `verify-fase6.sh:8`) se citan solo por ubicación. Los digest de imagen aparecen truncados.
- Sin `git commit`, sin `git push`, sin operaciones Docker, sin borrar nada. Único fichero creado: `docs/despliegue/INVENTARIO-despliegue.md`.

### Pendiente

- Las 18 decisiones de la sección 10; las que condicionan el diseño del script son la 1, 2, 3, 5, 9 y 11.
- Comprobaciones que solo Jose puede hacer en el laboratorio: listado de workflows de n8n, `crontab -l`, vigencia de la contraseña de `wazuh.yml`, versión real de las imágenes `latest`, JSON de la política de MinIO.
- Probar las vías no interactivas listadas en «No verificado» antes de escribir `deploy/deploy.sh`.

### Discrepancias con la lectura previa

| Lectura previa | Lo que hay |
|---|---|
| `.env.example` en ocho fases más `template.env`; n8n sin plantilla | **Confirmado.** Matiz: la de fase 8 es la del upstream y no es utilizable tal cual (1.8) |
| El compose de n8n exige siete variables; el workflow usa además `OOB_WEBHOOK_SECRET` | **Confirmado.** Se añade `N8N_ENCRYPTION_KEY`, que tampoco está en `environment` y solo la nombran los README. `RC_BOT_TOKEN` se exige en el compose pero ningún workflow versionado lo lee por `$env` |
| «Al menos 32 referencias» con `REEMPLAZAR` | **Exactamente 32** (20 + 12), en dos de los cuatro workflows; los otros dos no referencian credenciales. Seis combinaciones tipo·nombre, como se había visto |
| `peers.json` ignorado y montado en n8n | **Confirmado** |
| Falta `users_database.yml` | **Confirmado.** Además, la documentación cita un `.example` que no existe |
| `192.168.127.138` en `config.yaml`, `resolucion-nombres.tsv`, `wazuh.yml` | **Incompleto:** también en `traefik/certs/iris.cnf:22` |
| `192.168.0.70` en «los `.cnf`» | **Impreciso:** solo en `glkvm-cloud.cnf:22`. `glkvm-device.cnf:20` lleva `192.168.0.36` e `iris.cnf:22` lleva `192.168.127.138`. Falta además `fase8-kvm/…/docker-compose.override.yml:14-15` |
| `100.64.0.1` en override y unidad de IRIS y en la ACL | **Parcial:** en la ACL solo aparece en un comentario (`acl.hujson:29`). Faltaban `scripts/verify-fase6.sh:30-31` y el `.tsv` |
| `100.64.0.2` en `DC_AGENT_URL` | **Confirmado**; también en `scripts/verify-dcagent-health.sh:39` |
| `oob-rootCA.crt` versionado en dos sitios | **Son tres ficheros idénticos** (falta `fase6-iris/certificates/rootCA/irisRootCACert.pem`) más una cuarta copia embebida en `ca-bundle-oob.crt`. `misp.crt` está versionado pero ningún compose lo monta |
| Redes externas `oob-network` y `single-node_default` | **Confirmado** |
| Imágenes flotantes, «entre otras» `authelia:latest` | **Confirmado**: ocho efectivas (7.3) |

Hallazgos que la lectura previa no recogía:

- `wazuh.yml` e `internal_users.yml` están versionados con credenciales del laboratorio; el README afirma que `wazuh.yml` está excluido.
- `ROOT_URL` se consume y no está en la plantilla de fase 1.
- `init-mongo.sh` existe y ningún compose lo usa: el replica set y el usuario de Mongo no se crean solos.
- El bloque `<integration>` no está en el `wazuh_manager.conf` versionado, y las reglas `1006xx` no están en ningún fichero.
- n8n alcanza IRIS gracias al `/etc/hosts` del host: dependencia implícita, no declarada en ningún compose.
- `IRIS_ADM_API_KEY` y `ADMIN_KEY` de MISP permiten tratar esas dos claves como generables en vez de cosechables.
- `fase4-breakglass-dc/README.md:89` nombra un webhook (`ir-command`) que el workflow versionado no expone.
- `velociraptor-config/.gitkeep` se menciona en `.gitignore` y en `SECURITY-NOTICE.md`, pero no está versionado: el directorio no existe en un clon.
- `verify-fase6.sh` lleva la huella de la CA actual.
- La política `evidence-writer` de MinIO no está en el repositorio.
