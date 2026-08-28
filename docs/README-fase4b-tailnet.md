# Fase 4b — Registro de nodos en Headscale

## Objetivo

Registrar el orquestador y el Domain Controller Windows 2025 dentro de la tailnet privada gestionada por Headscale, para disponer de conectividad OOB entre ambos nodos y poder continuar con la fase de scripts controlados y acceso break-glass.

Esta subfase deja preparada la red privada para que el orquestador pueda hablar con el DC mediante la IP Tailscale o el nombre MagicDNS, sin depender de Cloudflare Tunnels ni de dominios públicos.

## Alcance

En esta subfase se realiza:

- Creación del usuario lógico del proyecto en Headscale.
- Generación de una pre-auth key de un solo uso y etiquetada por nodo.
- Registro del orquestador Linux en la tailnet.
- Registro del DC Windows 2025 en la tailnet.
- Validación de visibilidad y conectividad entre nodos.

## Prerrequisitos

- Fase 4a cerrada y Headscale operativo en Docker.
- Contenedor `headscale` en ejecución.
- Usuario local con acceso al host Ubuntu que ejecuta Docker.
- Tailscale instalado o disponible para instalar en el orquestador y en el DC Windows.

> **Requisito previo de red/PKI:** cada nodo que se una a la tailnet debe tener
> instalada la CA del enclave (ver `fase1-infraestructura/`) y debe poder resolver
> `hs.oob.local` antes de ejecutar `tailscale up`.

## Paso 1 — Crear usuario en Headscale

```bash
docker exec headscale headscale users create tfm-oob
docker exec headscale headscale users list
```

El usuario `tfm-oob` será el espacio lógico donde se registrarán los nodos del proyecto.

## Paso 2 — Generar pre-auth key

> **Nota de endurecimiento posterior:** una clave reutilizable válida un año
> (`--reusable --expiration 8760h`) es funcionalmente una contraseña maestra sin
> caducidad para unir nodos al enclave. Se sustituye por una clave **de un solo uso**,
> **etiquetada** y de vida corta, generada individualmente para cada nodo justo antes
> de registrarlo (Pasos 3 y 4). La etiqueta (`tag:orchestrator` / `tag:dc`) es además
> obligatoria para que la política `acl.hujson` de la Fase 4a pueda aplicar
> microsegmentación — un nodo sin tag no matchea ninguna regla ACL.

## Paso 3 — Registrar el orquestador Linux

Primero instala Tailscale en el host del orquestador si todavía no está presente:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

Genera una pre-auth key de un solo uso para este nodo:

```bash
docker exec headscale headscale preauthkeys create \
  --user tfm-oob --expiration 1h --tags tag:orchestrator
```

Después conecta el nodo al control plane Headscale:

```bash
sudo tailscale up \
  --login-server https://hs.oob.local \
  --authkey <PREAUTH_KEY> --hostname orchestrator-tfm \
  --advertise-tags=tag:orchestrator --accept-dns=false
```

`--login-server` usa el hostname público `hs.oob.local` servido por Traefik (con la
CA del enclave), no la IP ni el puerto interno `8090` del contenedor.
`--accept-dns=false` evita que MagicDNS interfiera con la resolución DNS ya existente
del orquestador.

## Paso 4 — Registrar el DC Windows 2025

En el DC, abrir PowerShell como administrador e instalar Tailscale:

```powershell
winget install tailscale.tailscale
```

Genera una pre-auth key de un solo uso para este nodo:

```bash
docker exec headscale headscale preauthkeys create \
  --user tfm-oob --expiration 1h --tags tag:dc
```

Después unir el DC a Headscale:

```powershell
tailscale up --login-server https://hs.oob.local `
  --authkey <PREAUTH_KEY> --hostname dc01-tfm `
  --advertise-tags=tag:dc --accept-dns=false
```

Este paso deja al DC gestionado por la red privada del proyecto y accesible para el
agente Python y para futuras acciones de break-glass. `--accept-dns=false` evita que
MagicDNS interfiera con la resolución AD del DC. La etiqueta `tag:dc` es la que hace
efectiva la política ACL de la Fase 4a: sin ella el nodo no matchea ninguna regla y,
según el modo de política configurado, puede quedar sin conectividad útil.

## Paso 5 — Verificación en Headscale

```bash
docker exec headscale headscale nodes list
```

La salida debe mostrar al menos dos nodos: `orchestrator-tfm` y `dc01-tfm`.

## Paso 6 — Verificación de conectividad

En el orquestador:

```bash
tailscale status
ping <IP_TAILSCALE_DC01>
```

En el DC Windows:

```powershell
tailscale status
ping <IP_TAILSCALE_ORQUESTADOR>
```

La conectividad correcta confirma que la tailnet está operativa y que el canal OOB está listo para la siguiente subfase.

> **Resolución de nombres.** MagicDNS no está operativo en el despliegue actual
> (colisión de `base_domain` con el dominio de servicios del enclave, ver
> `README-fase4-pendientes.md`), así que `dc01-tfm` se resuelve por una entrada
> manual en `/etc/hosts` del orquestador — documentada en
> [`README-fase4c-dcagent.md`](README-fase4c-dcagent.md#resolución-de-nombres-en-el-orquestador),
> no en esta subfase.

## Resultado de la Fase 4b

La Fase 4b queda completada cuando Headscale muestra ambos nodos online y el orquestador puede alcanzar al DC por la red Tailscale/Headscale.

Con esta base ya es posible pasar a la Fase 4c, donde se integrará el Python Agent del DC y posteriormente el flujo break-glass con RustDesk.

## Comandos de commit

Una vez verificada la subfase, guarda el avance con:

```bash
cd /home/jose/tfm-alerta-temprana-oob

git add fase4-breakglass-dc/
git commit -m "fase4b: registro de nodos en tailnet headscale"
git push origin main
```

Si trabajas en otra rama, sustituye `main` por el nombre real de tu rama.
