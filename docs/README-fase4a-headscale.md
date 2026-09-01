# Fase 4a — Despliegue de Headscale en Docker

## Objetivo

Desplegar el servidor **Headscale** como plano de control self-hosted para la red privada del enclave out-of-band del proyecto TFM, sustituyendo la dependencia prevista inicialmente con Cloudflare Tunnels por una arquitectura basada en **Headscale + clientes Tailscale**.

En esta subfase se ha validado el arranque del servicio en Docker, la creación automática de la clave `noise_private.key`, la apertura de la base de datos SQLite y la respuesta correcta del endpoint de salud en el puerto publicado del host.

## Alcance de la subfase

Esta subfase cubre exclusivamente la puesta en marcha del servidor Headscale dentro de la infraestructura Docker del proyecto, sin registrar todavía nodos cliente ni integrar aún los agentes DC o el flujo break-glass con RustDesk.

El resultado esperado de Fase 4a es disponer de un control plane operativo, persistente y documentado, listo para su uso en la siguiente subfase de enrolado de nodos del orquestador y del DC Windows 2025.

## Estructura usada

La estructura de trabajo utilizada para esta subfase es la siguiente:

```text
fase4-breakglass-dc/
└── headscale/
    ├── config/
    │   ├── config.yaml
    │   ├── acl.hujson
    │   └── docker-compose.headscale.yml
    └── lib/
```

La ruta que se ha validado para lanzar correctamente el servicio es:

```bash
/home/jose/tfm-alerta-temprana-oob/fase4-breakglass-dc/headscale/config
```

## Configuración validada

> **Nota — configuración escrita, endurecimiento aún no aplicado al contenedor
> en ejecución.** Los bloques de `docker-compose.headscale.yml`, `config.yaml`
> y `acl.hujson` que siguen a continuación **ya reflejan la versión endurecida**
> (`server_url` público vía Traefik, gRPC/métricas en loopback, DERP embebido,
> política ACL). Lo que sigue pendiente no es escribir esa configuración —ya
> está en el repositorio— sino **aplicarla**: el contenedor `headscale` sigue
> en ejecución desde antes de que estos ficheros se modificaran por última vez,
> así que el servicio real todavía atiende con los parámetros previos al
> endurecimiento hasta que se recree (`docker compose down && docker compose up -d`
> sobre `docker-compose.headscale.yml`). El detalle completo, incluidos los
> pasos operativos pendientes tras el reinicio (reetiquetado de nodos, validación
> de la política ACL), se documenta en
> [`README-fase4-pendientes.md`](README-fase4-pendientes.md).

Se ha usado la imagen oficial `docker.io/headscale/headscale:0.28.0`, que sigue siendo una versión estable soportada en la documentación de despliegue en contenedor de Headscale.

El puerto `8080` interno del contenedor se ha publicado como `8090` en el host porque `8080` ya estaba ocupado por otro servicio del entorno del proyecto. Esta adaptación es válida siempre que `listen_addr` siga apuntando al puerto interno `8080` dentro del contenedor.

> **Nota de endurecimiento posterior:** los bloques siguientes reflejan la configuración
> ya endurecida (server_url público vía Traefik, gRPC/métricas solo en loopback, DERP
> embebido sin depender de infraestructura de Tailscale Inc., y política ACL obligatoria).
> Ver `fase4-breakglass-dc/headscale/config/` para la versión siempre actualizada.

### docker-compose.headscale.yml

```yaml
services:
  headscale:
    image: docker.io/headscale/headscale:0.28.0
    container_name: headscale
    restart: unless-stopped
    command: serve
    tmpfs:
      - /var/run/headscale
    volumes:
      - ./:/etc/headscale
      - ../lib:/var/lib/headscale
    ports:
      - "127.0.0.1:8090:8080"   # fallback de diagnóstico, no acceso normal
      - "3478:3478/udp"         # STUN del DERP embebido
    networks:
      - oob-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.headscale.rule=Host(`hs.oob.local`)"
      - "traefik.http.routers.headscale.entrypoints=websecure"
      - "traefik.http.routers.headscale.tls=true"
      - "traefik.http.services.headscale.loadbalancer.server.port=8080"
      - "traefik.docker.network=oob-network"

networks:
  oob-network:
    external: true
```

El acceso normal es `https://hs.oob.local` vía Traefik; el puerto `8090` en `127.0.0.1`
queda solo como fallback de diagnóstico local al host Docker.

### config.yaml

```yaml
# --- TFM alerta-temprana-oob — Headscale v0.28 (endurecido) ---
# El plano de control del enclave OOB no depende de infraestructura externa.

server_url: https://hs.oob.local

listen_addr: 0.0.0.0:8080

# Métricas y gRPC solo en loopback: cualquier contenedor de oob-network
# (n8n, MISP, Rocket.Chat, Wazuh) podría administrar la tailnet si el
# gRPC inseguro escuchase en 0.0.0.0.
metrics_listen_addr: 127.0.0.1:9090
grpc_listen_addr: 127.0.0.1:50443
grpc_allow_insecure: true

noise:
  private_key_path: /var/lib/headscale/noise_private.key

prefixes:
  v4: 100.64.0.0/10
  v6: fd7a:115c:a1e0::/48
  allocation: sequential

# DERP embebido: sin relay por infraestructura de Tailscale Inc.
derp:
  server:
    enabled: true
    region_id: 999
    region_code: "oob"
    region_name: "OOB Enclave DERP"
    stun_listen_addr: "0.0.0.0:3478"
    # ipv4 explícito: sin él, el DERP se anuncia solo por nombre (hs.oob.local)
    # y tailscaled —que corre como servicio del sistema— no lo resuelve por el
    # mismo /etc/hosts que el shell del usuario. Síntoma: UDP: false y "no
    # response to latency probes". Ver "Hallazgos" más abajo.
    ipv4: "<IP_HOST>"
    private_key_path: /var/lib/headscale/derp_server_private.key
    automatically_add_embedded_derp_region: true
  urls: []
  paths: []
  auto_update_enabled: false
  update_frequency: 24h

disable_check_updates: true
ephemeral_node_inactivity_timeout: 30m

database:
  type: sqlite
  sqlite:
    path: /var/lib/headscale/db.sqlite
    write_ahead_log: true

log:
  level: info
  format: text

policy:
  mode: file
  path: /etc/headscale/acl.hujson

# base_domain NO puede solaparse con oob.local: Headscale rechaza arrancar
# si el host de server_url pertenece a base_domain.
dns:
  magic_dns: true
  base_domain: tailnet.internal
  override_local_dns: false
  nameservers:
    global: []
    split: {}
  search_domains: []
  extra_records: []

unix_socket: /var/run/headscale/headscale.sock
unix_socket_permission: "0770"

logtail:
  enabled: false

randomize_client_port: false
```

### acl.hujson

Sin política ACL, Headscale aplica "allow all": un DC comprometido alcanzaría n8n,
Wazuh, MISP e IRIS. La política vigente restringe explícitamente qué origen puede
llegar a qué destino. El principio rector es **"el DC es destino, nunca origen"**,
con una única excepción acotada: el cliente RustDesk del DC necesita registro
saliente contra el servidor de rendezvous del enclave (`hbbs`/`hbbr`), y esa
dependencia no se detectó al diseñar la política sino al aplicarla y comprobar el
comportamiento con tráfico real (ver `README-fase4-validacion.md`).

Reflejo del fichero real (`fase4-breakglass-dc/headscale/config/acl.hujson`):

```hujson
// NOTA v0.28: los usuarios se referencian con sufijo '@'.
// El bloque "tests" de la primera versión NO existe en Headscale v0.28 (es
// sintaxis de Tailscale SaaS); headscale devolvía `unknown field "tests"` pero
// arrancaba sin política, en allow-all silencioso. Eliminado.
{
  "tagOwners": {
    "tag:orchestrator": ["tfm-oob@"],
    "tag:dc":           ["tfm-oob@"],
    "tag:analyst":      ["tfm-oob@"],
    "tag:kvm":          ["tfm-oob@"],
  },

  "acls": [
    { "action": "accept", "src": ["tag:orchestrator"], "dst": ["tag:dc:8000"] },

    // El analista se conecta al servidor de rendezvous del enclave, no al
    // endpoint: RustDesk es un protocolo mediado y ambos extremos acuden a
    // hbbs/hbbr. La regla inicial (tag:analyst -> tag:dc:21115-21119) partía de
    // una topología equivocada: el cliente del DC no escucha en esos puertos.
    { "action": "accept", "src": ["tag:analyst"], "dst": ["tag:orchestrator:21115-21119,22"] },
    { "action": "accept", "src": ["tag:analyst"], "dst": ["tag:kvm:443,80,22"] },

    // Excepción acotada al principio "el DC nunca es origen": el cliente
    // RustDesk debe registrarse contra el rendezvous del enclave. Limitado a
    // señalización y relay; no habilita ningún otro destino.
    { "action": "accept", "src": ["tag:dc"], "dst": ["tag:orchestrator:21115-21119"] },
  ],
}
```

Validar con: `docker exec headscale headscale policy check --file /etc/headscale/acl.hujson`
(este paso no es opcional: Headscale ignora en silencio una política inválida y
sigue operando en allow-all — ver `README-fase4-validacion.md`, sección de hallazgos).

## Estado final verificado del plano de control

Tras el Paso 8 (endurecimiento, 28/08/2026) el plano de control queda así, verificado
por logs de `tailscaled` y `tailscale status` (no por `netcheck` — ver hallazgos):

| Parámetro | Valor final |
|---|---|
| `server_url` | `https://hs.oob.local` (vía Traefik, CA del enclave) |
| DERP | Embebido, `region_id: 999`, `region_code: oob`, `ipv4: <IP_HOST>` |
| `derp.urls` | `[]` — sin mapa DERP externo |
| `disable_check_updates` | `true` |
| `base_domain` | `tailnet.internal` |
| `dns.nameservers.global` | `[]` |
| `metrics_listen_addr` | `127.0.0.1:9090` |
| `grpc_listen_addr` | `127.0.0.1:50443` |
| `policy.path` | `/etc/headscale/acl.hujson` |
| STUN | UDP `3478` publicado |

## Hallazgos

**`derp.server.ipv4` es necesario.** Sin ese campo, el DERP embebido se anuncia
únicamente por nombre (`hs.oob.local`). `tailscaled` corre como servicio del
sistema y no resuelve ese nombre por el `/etc/hosts` del usuario del mismo modo
que lo hace el shell interactivo, así que el nodo no alcanzaba el relay: el
síntoma era `UDP: false` y `no response to latency probes`. Fijar
`ipv4: <IP_HOST>` (la dirección de la red subyacente del host) lo resuelve.

**`hs.oob.local` debe resolver a la red subyacente, no a una IP del tailnet.** El
plano de control de Tailscale se alcanza siempre por la red subyacente. Si
`hs.oob.local` resolviera a una dirección del propio tailnet, un nodo que
perdiera su sesión de control plane no podría reautenticarse —necesitaría el
tailnet que precisamente ha perdido—. Esto **no** contradice el principio OOB:
la propiedad out-of-band la aporta el plano de datos (WireGuard directo y el DERP
autohospedado), no el plano de control; pero exige que el plano de control tenga
una ruta subyacente que sobreviva al incidente. En el laboratorio esa ruta es la
red corporativa, y queda documentado como **limitación conocida** (ver
`README-fase4-pendientes.md`).

## Incidencias resueltas

Durante la implementación se detectaron varios problemas que quedaron corregidos antes de validar la subfase:

- Uso de una versión antigua de la imagen en el primer borrador del `docker-compose`.
- Necesidad del nuevo campo `noise.private_key_path`, obligatorio en versiones recientes para el protocolo Tailscale v2.
- Error por configuración DNS al dejar `override_local_dns` activado sin definir `dns.nameservers.global`.
- Error de parseo YAML por haber pegado una URL en formato Markdown dentro del bloque `derp.urls`, lo que impedía que Headscale leyera correctamente el fichero de configuración.
- Error de montaje de volúmenes por invocar `docker compose -f <ruta_absoluta>/docker-compose.headscale.yml` desde un directorio de trabajo distinto: con `-f` apuntando a un fichero fuera del directorio actual, Docker Compose resuelve los volúmenes con ruta relativa (`./`) contra el *directorio de trabajo del comando*, no contra el directorio donde vive el propio fichero compose — así el contenedor montaba una carpeta distinta de la que contenía realmente `config.yaml`, provocando el mensaje `No config file found, using defaults`.

**Diagnóstico corregido:** el fallo no estaba en usar rutas relativas per se, sino en invocar `docker compose -f` con una ruta absoluta al fichero desde otro directorio. Cuando se ejecuta `docker compose -f /ruta/absoluta/fichero.yml up -d`, el *project directory* que Compose usa para resolver rutas relativas (`./`) es el directorio donde reside `fichero.yml`, no el `cwd` del comando — así que `./` sí resuelve correctamente siempre que se invoque `cd` al directorio del compose primero (o se deje que Compose lo infiera del propio `-f`). Por eso la configuración actual vuelve a usar rutas relativas (`./` y `../lib`) en `docker-compose.headscale.yml`, evitando además hardcodear la ruta absoluta del host `/home/jose/...`, que impedía que un tercero desplegara el repo tal cual.

## Despliegue y validación

> **Requisito previo de red/PKI:** los nodos que se registrarán contra este control
> plane deben tener instalada la CA del enclave (ver `fase1-infraestructura/`) y
> deben poder resolver `hs.oob.local` antes de intentar unirse a la tailnet.

### Arranque del servicio

```bash
cd /home/jose/tfm-alerta-temprana-oob/fase4-breakglass-dc/headscale/config

docker compose -f /home/jose/tfm-alerta-temprana-oob/fase4-breakglass-dc/headscale/config/docker-compose.headscale.yml up -d
```

### Verificación de logs

```bash
docker logs --tail 50 headscale
```

Salida relevante observada en la validación:

```text
INF No private key file at path, creating... path=/var/lib/headscale/noise_private.key
INF Opening database database=sqlite3 path=/var/lib/headscale/db.sqlite
INF Starting Headscale ... version=v0.28.0
INF listening and serving HTTP on: 0.0.0.0:8080
INF listening and serving debug and metrics on: 0.0.0.0:9090
```

Estos mensajes confirman que Headscale creó correctamente la clave Noise, abrió la base de datos SQLite y quedó escuchando en los puertos internos esperados.

### Healthcheck

```bash
curl http://localhost:8090/health
```

Respuesta validada:

```json
{"status":"pass"}
```

La respuesta `pass` confirma que el control plane está operativo y que la subfase 4a puede darse por cerrada desde el punto de vista funcional.

## Resultado de la Fase 4a

La Fase 4a queda completada con un servidor Headscale estable, persistente y accesible desde el host en el puerto `8090`, integrado en la red Docker `oob-network` y preparado para registrar nodos del enclave y del DC en la siguiente subfase.

Este resultado permite continuar con la **Fase 4b**, centrada en la creación del usuario lógico de la tailnet, la generación de pre-auth keys y el enrolado del orquestador y del Domain Controller Windows 2025.
