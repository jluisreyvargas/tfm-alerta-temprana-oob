# Fase 4a — Headscale UI (gurucomputing/headscale-ui)

## Objetivo

Añadir una interfaz web sobre el Headscale ya desplegado en la Fase 4a, para poder visualizar nodos, rutas y claves preauth sin depender exclusivamente de la CLI (`docker exec headscale headscale ...`).

Se despliega el contenedor `headscale-ui` de gurucomputing dentro de la misma red Docker `oob-network` que ya usa el servicio `headscale`, sin exponer puertos adicionales del propio Headscale.

## Prerrequisitos

- Fase 4a: Headscale operativo en Docker, contenedor con `container_name: headscale`.
- Red Docker `oob-network` ya creada y usada por el resto del enclave.
- Puerto interno del API de Headscale accesible en `http://headscale:8080` dentro de la red Docker.

## Paso 1 — Crear la estructura de carpetas

```bash
mkdir -p ~/tfm-alerta-temprana-oob/fase4-breakglass-dc/headscale-ui/container-config
```

## Paso 2 — Crear `docker-compose.headscale-ui.yml`

Guardar en `~/tfm-alerta-temprana-oob/fase4-breakglass-dc/docker-compose.headscale-ui.yml`:

```yaml
services:
  headscale-ui:
    image: ghcr.io/gurucomputing/headscale-ui:latest
    container_name: headscale-ui
    restart: unless-stopped
    volumes:
      - ./headscale-ui/container-config:/etc/headscale-ui
    ports:
      - "8443:8443"
    networks:
      - oob-network
    depends_on:
      - headscale

networks:
  oob-network:
    external: true
```

> Nota: si tu servicio Headscale no se llama exactamente `headscale` en el compose de la Fase 4a, ajusta el nombre en `depends_on` y en `api_url` del `config.yaml`.

## Paso 3 — Crear `config.yaml` de Headscale UI

Guardar en `headscale-ui/container-config/config.yaml`:

```yaml
api_url: "http://headscale:8080"
api_key: ""
```

`api_url` debe apuntar al nombre del contenedor Headscale dentro de la red Docker (`http://headscale:8080`), no a `localhost` ni a la IP pública del host.

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

Headscale UI expone un certificado autofirmado por defecto en el puerto 8443.

```
https://<IP-del-host-docker>:8443
```

Al aceptar el certificado autofirmado, la interfaz solicitará (si no se rellenó en `config.yaml`):

- **API URL**: `http://headscale:8080`
- **API Key**: la generada en el Paso 4

## Paso 7 — Validación

Desde la UI deberías poder:

- Listar los nodos ya unidos a la tailnet (`orchestrator-tfm`, `dc01-tfm`, etc. de la Fase 4b).
- Ver el estado online/offline de cada nodo.
- Generar nuevas preauth keys desde el navegador.
- Revisar rutas anunciadas, si las hubiera.

## Seguridad

- El contenedor `headscale-ui` solo se comunica con Headscale a través de la red Docker interna `oob-network`; el API de Headscale no queda expuesto directamente a internet.
- El acceso web usa TLS autofirmado por defecto; si el enclave ya tiene un reverse proxy (Traefik/Caddy) delante de otros servicios, se recomienda enrutar `headscale-ui` bajo un subpath o subdominio con certificado válido, en lugar de exponer el puerto 8443 directamente.
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
