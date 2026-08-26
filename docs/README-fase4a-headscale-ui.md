# Fase 4a — Headscale UI (gurucomputing/headscale-ui)

## Objetivo

Añadir una interfaz web sobre el Headscale ya desplegado en la Fase 4a, para poder visualizar nodos, rutas y claves preauth sin depender exclusivamente de la CLI (`docker exec headscale headscale ...`).

Se despliega el contenedor `headscale-ui` de gurucomputing dentro de la misma red Docker `oob-network` que ya usa el servicio `headscale`, sin exponer puertos adicionales del propio Headscale.

## Prerrequisitos

- Fase 4a: Headscale operativo en Docker, contenedor con `container_name: headscale`.
- Red Docker `oob-network` ya creada y usada por el resto del enclave.
- Puerto interno del API de Headscale accesible en `http://headscale:8080` dentro de la red Docker.

> **Requisito previo de red/PKI:** el navegador del analista debe confiar en la CA del
> enclave (ver `fase1-infraestructura/`) y debe poder resolver `hs.oob.local`, ya que
> tanto Headscale como Headscale UI se sirven bajo ese mismo host vía Traefik.

## Paso 1 — Crear la estructura de carpetas

```bash
mkdir -p ~/tfm-alerta-temprana-oob/fase4-breakglass-dc/headscale-ui/container-config
```

## Paso 2 — Crear `docker-compose.headscale-ui.yml`

> **Nota de endurecimiento posterior:** el bloque siguiente refleja el compose actual,
> servido detrás de Traefik con autenticación Authelia (`middlewares=authelia@docker`)
> en lugar del puerto `8443` directo del contenedor. `headscale-ui` es el activo de
> mayor valor de esta fase — permite emitir pre-auth keys, es decir, unir nodos
> arbitrarios al enclave — y no debe quedar accesible sin autenticación.

Guardar en `~/tfm-alerta-temprana-oob/fase4-breakglass-dc/docker-compose.headscale-ui.yml`:

```yaml
# docker-compose.headscale-ui.yml
# Fase 4a — Headscale UI integrado con Traefik
# Acceso esperado:
#   https://hs.${ENCLAVE_DOMAIN}/web
# Requisitos:
#   - Traefik desplegado en Fase 1 y conectado a oob-network
#   - Headscale accesible en la misma red Docker con nombre 'headscale'
#   - Misma base de dominio para Headscale y Headscale UI para evitar problemas de CORS

networks:
  oob-network:
    external: true

services:
  headscale-ui:
    # TODO: verificar tag disponible — fijar un tag inmutable/digest antes de
    # producción; 'latest' no es reproducible.
    image: ghcr.io/gurucomputing/headscale-ui:latest
    container_name: headscale-ui
    restart: unless-stopped
    volumes:
      - ./headscale-ui/container-config:/etc/headscale-ui
    networks:
      - oob-network
    labels:
        - "traefik.enable=true"
        - "traefik.http.routers.headscale-ui.rule=Host(`hs.oob.local`) && PathPrefix(`/web`)"
        - "traefik.http.routers.headscale-ui.entrypoints=websecure"
        - "traefik.http.routers.headscale-ui.tls=true"
        - "traefik.http.services.headscale-ui.loadbalancer.server.port=8080"
        - "traefik.docker.network=oob-network"
        - "traefik.http.routers.headscale-ui.middlewares=authelia@docker"
```

No se publica ningún puerto del contenedor directamente: el acceso es siempre
`https://hs.oob.local/web` a través de Traefik, protegido por Authelia.

## Paso 3 — Crear `config.yaml` de Headscale UI

Guardar en `headscale-ui/container-config/config.yaml`:

```yaml
# headscale-ui/container-config/config.yaml
# headscale-ui es una SPA: las llamadas al API las hace el navegador del
# analista, no el contenedor. Con http://headscale:8080 el navegador no
# puede resolver un nombre de red Docker y la UI nunca lista nodos.
# Debe apuntar al mismo origen público que sirve Traefik.
api_url: "https://hs.oob.local"

# La api_key debe quedar SIEMPRE vacía en el repositorio.
# Generar con: docker exec headscale headscale apikeys create
# y pegarla desde la UI (Settings) tras el primer acceso, nunca aquí.
api_key: ""
```

`api_url` debe apuntar al mismo origen público que sirve Traefik
(`https://hs.oob.local`), **no** al nombre del contenedor Headscale dentro de la red
Docker (`http://headscale:8080`): las peticiones las hace el navegador del analista,
que no puede resolver nombres de la red Docker interna. Este mismo motivo evita el
problema de CORS advertido al inicio del documento.

## Paso 4 — Generar la API key de Headscale

Desde el host donde corre Docker:

```bash
docker exec -it headscale headscale apikeys create --expiration 90d
```

Copiar el valor devuelto (algo similar a `OptHmxr0pQ.ewketuKkb2Gn...`). Esta clave se puede:

- pegar en `config.yaml` en el campo `api_key`, o
- introducir directamente desde la interfaz web, en la sección **Settings**, tras el primer arranque.

## Paso 5 — Levantar el contenedor

```bash
cd ~/tfm-alerta-temprana-oob/fase4-breakglass-dc
docker compose -f docker-compose.headscale-ui.yml up -d
docker ps | grep headscale-ui
```

## Paso 6 — Acceder a la interfaz

El contenedor no publica ningún puerto propio; el acceso es siempre a través de
Traefik, con TLS de la CA del enclave y autenticación Authelia delante:

```
https://hs.oob.local/web
```

Tras autenticarte en Authelia, la interfaz solicitará (si no se rellenó en `config.yaml`):

- **API URL**: `https://hs.oob.local`
- **API Key**: la generada en el Paso 4

## Paso 7 — Validación

Desde la UI deberías poder:

- Listar los nodos ya unidos a la tailnet (`orchestrator-tfm`, `dc01-tfm`, etc. de la Fase 4b).
- Ver el estado online/offline de cada nodo.
- Generar nuevas preauth keys desde el navegador.
- Revisar rutas anunciadas, si las hubiera.

## Seguridad

- El contenedor `headscale-ui` no publica ningún puerto propio; el acceso es siempre vía Traefik bajo `https://hs.oob.local/web`, con el certificado de la CA del enclave.
- La ruta está protegida por el middleware `authelia@docker`: sin sesión Authelia válida no se puede llegar a la UI que emite pre-auth keys para unir nodos a la tailnet.
- La API key de Headscale debe tratarse como secreto: no debe commitearse en el repositorio con un valor real relleno en `config.yaml`.

## Resultado

Con estos pasos, la Fase 4a queda ampliada con una interfaz web de administración para Headscale, sin modificar el despliegue existente del servidor Headscale ni de los nodos ya enrolados en la tailnet.

## Comandos de commit

```bash
cd ~/tfm-alerta-temprana-oob

git add fase4-breakglass-dc/docker-compose.headscale-ui.yml
git add fase4-breakglass-dc/headscale-ui/container-config/config.yaml
git add docs/README-fase4a-headscale-ui.md   # si se copia este README a docs/

git commit -m "fase4a: añadir headscale-ui como interfaz web de administración"
git push origin main
```
