# Fase 4a — Despliegue de Headscale en Docker

## Objetivo

Desplegar el servidor **Headscale** como plano de control self-hosted para la red privada del enclave out-of-band del proyecto TFM, sustituyendo la dependencia prevista inicialmente con Cloudflare Tunnels por una arquitectura basada en **Headscale + clientes Tailscale**.[cite:32][cite:72]

En esta subfase se ha validado el arranque del servicio en Docker, la creación automática de la clave `noise_private.key`, la apertura de la base de datos SQLite y la respuesta correcta del endpoint de salud en el puerto publicado del host.[cite:32][cite:72]

## Alcance de la subfase

Esta subfase cubre exclusivamente la puesta en marcha del servidor Headscale dentro de la infraestructura Docker del proyecto, sin registrar todavía nodos cliente ni integrar aún los agentes DC o el flujo break-glass con RustDesk.[cite:32]

El resultado esperado de Fase 4a es disponer de un control plane operativo, persistente y documentado, listo para su uso en la siguiente subfase de enrolado de nodos del orquestador y del DC Windows 2025.[cite:32][cite:72]

## Estructura usada

La estructura de trabajo utilizada para esta subfase es la siguiente:

```text
fase4-breakglass-dc/
└── headscale/
    ├── config/
    │   ├── config.yaml
    │   └── docker-compose.headscale.yml
    └── lib/
```

La ruta que se ha validado para lanzar correctamente el servicio es:

```bash
/home/jose/tfm-alerta-temprana-oob/fase4-breakglass-dc/headscale/config
```

## Configuración validada

Se ha usado la imagen oficial `docker.io/headscale/headscale:0.28.0`, que sigue siendo una versión estable soportada en la documentación de despliegue en contenedor de Headscale.[cite:32]

El puerto `8080` interno del contenedor se ha publicado como `8090` en el host porque `8080` ya estaba ocupado por otro servicio del entorno del proyecto. Esta adaptación es válida siempre que `listen_addr` siga apuntando al puerto interno `8080` dentro del contenedor.[cite:32][cite:72]

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
      - /home/jose/tfm-alerta-temprana-oob/fase4-breakglass-dc/headscale/config:/etc/headscale
      - /home/jose/tfm-alerta-temprana-oob/fase4-breakglass-dc/headscale/lib:/var/lib/headscale
    ports:
      - "8090:8080"
      - "9090:9090"
    networks:
      - oob-network

networks:
  oob-network:
    external: true
```

### config.yaml

```yaml
server_url: http://headscale:8090

listen_addr: 0.0.0.0:8080
metrics_listen_addr: 0.0.0.0:9090
grpc_listen_addr: 0.0.0.0:50443
grpc_allow_insecure: true

noise:
  private_key_path: /var/lib/headscale/noise_private.key

prefixes:
  v4: 100.64.0.0/10
  v6: fd7a:115c:a1e0::/48
  allocation: sequential

derp:
  server:
    enabled: false
  urls:
    - https://controlplane.tailscale.com/derpmap/default
  auto_update_enabled: true
  update_frequency: 24h

disable_check_updates: false
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
  path: ""

dns:
  magic_dns: true
  base_domain: oob.local
  override_local_dns: false
  nameservers:
    global:
      - 1.1.1.1
    split: {}
  search_domains: []
  extra_records: []

unix_socket: /var/run/headscale/headscale.sock
unix_socket_permission: "0770"

logtail:
  enabled: false

randomize_client_port: false
```

## Incidencias resueltas

Durante la implementación se detectaron varios problemas que quedaron corregidos antes de validar la subfase:

- Uso de una versión antigua de la imagen en el primer borrador del `docker-compose`.[cite:32][cite:46]
- Necesidad del nuevo campo `noise.private_key_path`, obligatorio en versiones recientes para el protocolo Tailscale v2.[cite:61][cite:64]
- Error por configuración DNS al dejar `override_local_dns` activado sin definir `dns.nameservers.global`.[cite:72]
- Error de parseo YAML por haber pegado una URL en formato Markdown dentro del bloque `derp.urls`, lo que impedía que Headscale leyera correctamente el fichero de configuración.[cite:65][cite:74]
- Error de montaje de volúmenes por usar una ruta relativa incorrecta, que llevaba al contenedor a una carpeta distinta de la que contenía realmente `config.yaml`, provocando el mensaje `No config file found, using defaults`.[cite:32][cite:84]

La corrección final consistió en usar rutas absolutas hacia los directorios `config` y `lib`, asegurando que el contenedor leyera el fichero real desde `/etc/headscale/config.yaml`.[cite:32][cite:84]

## Despliegue y validación

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

Estos mensajes confirman que Headscale creó correctamente la clave Noise, abrió la base de datos SQLite y quedó escuchando en los puertos internos esperados.[cite:32][cite:72]

### Healthcheck

```bash
curl http://localhost:8090/health
```

Respuesta validada:

```json
{"status":"pass"}
```

La respuesta `pass` confirma que el control plane está operativo y que la subfase 4a puede darse por cerrada desde el punto de vista funcional.[cite:72]

## Resultado de la Fase 4a

La Fase 4a queda completada con un servidor Headscale estable, persistente y accesible desde el host en el puerto `8090`, integrado en la red Docker `oob-network` y preparado para registrar nodos del enclave y del DC en la siguiente subfase.[cite:32][cite:72]

Este resultado permite continuar con la **Fase 4b**, centrada en la creación del usuario lógico de la tailnet, la generación de pre-auth keys y el enrolado del orquestador y del Domain Controller Windows 2025.[cite:32]

## Comandos de commit

Una vez revisado el contenido de esta subfase, los comandos recomendados para guardar el avance en el repositorio son:

```bash
cd /home/jose/tfm-alerta-temprana-oob

git add fase4-breakglass-dc/headscale/config/docker-compose.headscale.yml
git add fase4-breakglass-dc/headscale/config/config.yaml
git add fase4-breakglass-dc/README-fase4a-headscale.md

git commit -m "fase4a: despliegue de headscale en docker"
git push origin main
```

Si se está trabajando en una rama específica para la Fase 4, el `push` debe adaptarse al nombre real de esa rama.
