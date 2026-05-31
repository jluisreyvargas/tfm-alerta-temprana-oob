# Fase 4b — Registro de nodos en Headscale

## Objetivo

Registrar el orquestador y el Domain Controller Windows 2025 dentro de la tailnet privada gestionada por Headscale, para disponer de conectividad OOB entre ambos nodos y poder continuar con la fase de scripts controlados y acceso break-glass.[web:24][web:126]

Esta subfase deja preparada la red privada para que el orquestador pueda hablar con el DC mediante la IP Tailscale o el nombre MagicDNS, sin depender de Cloudflare Tunnels ni de dominios públicos.[web:24][web:127]

## Alcance

En esta subfase se realiza:

- Creación del usuario lógico del proyecto en Headscale.[web:126]
- Generación de una pre-auth key reutilizable para enrolar nodos.[web:24][web:127]
- Registro del orquestador Linux en la tailnet.[web:24][web:126]
- Registro del DC Windows 2025 en la tailnet.[web:24][web:127]
- Validación de visibilidad y conectividad entre nodos.[web:24][web:126]

## Prerrequisitos

- Fase 4a cerrada y Headscale operativo en Docker.
- Contenedor `headscale` en ejecución.
- Usuario local con acceso al host Ubuntu que ejecuta Docker.
- Tailscale instalado o disponible para instalar en el orquestador y en el DC Windows.[web:24][web:127]

## Paso 1 — Crear usuario en Headscale

```bash
docker exec headscale headscale users create tfm-oob
docker exec headscale headscale users list
```

El usuario `tfm-oob` será el espacio lógico donde se registrarán los nodos del proyecto.[web:126]

## Paso 2 — Generar pre-auth key

```bash
docker exec headscale headscale preauthkeys create   --user tfm-oob   --reusable   --expiration 8760h
```

La clave resultante debe guardarse como secreto local porque se usará para registrar el orquestador y el DC sin login interactivo.[web:24][web:127]

## Paso 3 — Registrar el orquestador Linux

Primero instala Tailscale en el host del orquestador si todavía no está presente:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

Después conecta el nodo al control plane Headscale:

```bash
sudo tailscale up   --login-server http://<IP_DEL_HOST_HEADSCALE>:8090   --authkey <PREAUTH_KEY>   --hostname orchestrator-tfm
```

Sustituir `<IP_DEL_HOST_HEADSCALE>` por la IP real del host Ubuntu donde corre Docker, no por el nombre del contenedor `headscale`.[web:24][web:126]

## Paso 4 — Registrar el DC Windows 2025

En el DC, abrir PowerShell como administrador e instalar Tailscale:

```powershell
winget install tailscale.tailscale
```

Después unir el DC a Headscale:

```powershell
tailscale up --login-server http://<IP_DEL_HOST_HEADSCALE>:8090 --authkey <PREAUTH_KEY> --hostname dc01-tfm
```

Este paso deja al DC gestionado por la red privada del proyecto y accesible para el agente Python y para futuras acciones de break-glass.[web:24][web:127]

## Paso 5 — Verificación en Headscale

```bash
docker exec headscale headscale nodes list
```

La salida debe mostrar al menos dos nodos: `orchestrator-tfm` y `dc01-tfm`.[web:126]

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

La conectividad correcta confirma que la tailnet está operativa y que el canal OOB está listo para la siguiente subfase.[web:24][web:127]

## Resultado de la Fase 4b

La Fase 4b queda completada cuando Headscale muestra ambos nodos online y el orquestador puede alcanzar al DC por la red Tailscale/Headscale.[web:24][web:126]

Con esta base ya es posible pasar a la Fase 4c, donde se integrará el Python Agent del DC y posteriormente el flujo break-glass con RustDesk.[web:24]

## Comandos de commit

Una vez verificada la subfase, guarda el avance con:

```bash
cd /home/jose/tfm-alerta-temprana-oob

git add fase4-breakglass-dc/
git commit -m "fase4b: registro de nodos en tailnet headscale"
git push origin main
```

Si trabajas en otra rama, sustituye `main` por el nombre real de tu rama.
