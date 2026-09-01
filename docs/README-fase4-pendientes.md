# Fase 4 — Trabajo pendiente

Este documento centraliza lo que queda por hacer en la Fase 4 (break-glass y
acción remota sobre Domain Controllers) tras el endurecimiento y la validación
empírica ya realizados. Cada apartado indica su estado real verificado, no una
suposición sobre lo que "debería" faltar.

---

## 8. Endurecimiento del plano de control (Headscale) — ✅ RESUELTO (28/08/2026)

Aplicado y verificado empíricamente. Recrear el contenedor `headscale` con la
configuración endurecida hizo que los nodos ya registrados (`orchestrator-tfm`,
`dc01-tfm`) perdieran la sesión de control plane hasta reautenticarse, porque
`server_url` y `base_domain` cambiaron — era el único bloque de este trabajo
pendiente que resultaba destructivo, y se ejecutó como tal (backup previo,
reautenticación uno a uno, plan de vuelta atrás preparado).

| Elemento | Antes | Después |
|---|---|---|
| `server_url` | `http://headscale:8090` (puerto inexistente en la red Docker) | `https://hs.oob.local` vía Traefik con la CA del enclave |
| DERP | Mapa público de Tailscale, 28 regiones | Región embebida `oob` (id 999), `urls: []` |
| Descubrimiento STUN | IP pública `77.226.198.189` vía servidores de Tailscale | `192.168.127.138:41641`, local |
| `disable_check_updates` | `false` | `true` |
| DNS del tailnet | `1.1.1.1` (Cloudflare) | `global: []` |
| `base_domain` | `oob.local` (colisionaba con los servicios) | `tailnet.internal` |
| gRPC / métricas | `0.0.0.0` | `127.0.0.1` |
| Política ACL | `path: ""` (allow-all) | `acl.hujson` activa |
| Etiquetas de nodo | Ninguna | `tag:orchestrator`, `tag:dc` |

Evidencias registradas:

- `magicsock: home is now derp-999 (oob)` y `derphttp.Client.Connect: connecting to derp-999 (oob)` en los logs de `tailscaled`.
- Desde `dc01-tfm`: `Test-NetConnection 100.64.0.1 -Port 22` y `-Port 8000` devuelven `TcpTestSucceeded: False` con la ACL activa.
- RustDesk sigue fluyendo: `tcpdump -ni tailscale0 port 21116` captura tráfico `100.64.0.2 → 100.64.0.1`.
- `curl -H "Host: hs.oob.local" https://localhost/web` devuelve `302` hacia Authelia.

Detalle completo de la ejecución, los hallazgos durante el proceso y las dos
incidencias del endurecimiento: [`README-fase4-validacion.md`](README-fase4-validacion.md).

### Por qué el plano de control necesita su propia PKI

Un enclave out-of-band no puede apoyarse en la PKI corporativa (AD CS), porque
esa PKI es uno de los activos que se asume comprometido en el escenario que
justifica el enclave. Necesita su propia cadena de confianza y su propio
mecanismo de distribución — la CA del enclave (`fase1-infraestructura/`), no
la del dominio.

### Por qué el DERP embebido importa

Mientras el mapa de relay se obtenía de `controlplane.tailscale.com`, el
tráfico break-glass podía relayarse por infraestructura de un tercero cuando
el NAT impedía conexión directa entre nodos, lo que contradecía el principio
rector del proyecto (cero dependencias de servicios externos críticos). El
DERP embebido lo resuelve.

### 8.1 Pendientes nuevos, detectados durante la ejecución

- **`glkvm` sin etiquetar.** Offline desde el 13/07; queda aislado en el
  tailnet al aplicar la ACL. Su acceso principal es la plataforma KVM por red
  cableada, no el tailnet. Etiquetar como `tag:kvm` cuando vuelva a conectar.
- **Sin monitorización de disponibilidad del tailnet.** `glkvm` estuvo 46 días
  caído sin detección.
- **El plano de control viaja por la red corporativa.** El control plane de
  Tailscale se alcanza siempre por la red subyacente, nunca por el propio
  tailnet — si no, no habría arranque en frío. En un despliegue real
  requeriría un enlace subyacente dedicado. Limitación conocida del
  laboratorio.
- **Pre-auth keys sin inventariar.** Existe un usuario `kvm-devices` (id 2)
  sin nodos asociados. Revisar claves huérfanas.
- **La CA del enclave se distribuye manualmente.** Hubo que instalarla en el
  DC, en el orquestador y en el W11. No escala y no es viable durante un
  incidente: debe formar parte del alta de cada nodo.
- **No hay resolución de nombres propia del enclave.** Cada máquina necesita
  entradas manuales en `hosts` para `hs.oob.local`, `kvm.oob.local`,
  `auth.oob.local`, `chat.oob.local`, `n8n.oob.local`. MagicDNS no cubre estos
  nombres porque vive en `tailnet.internal`. Un resolver interno (`dnsmasq`)
  resolvería esto; la distribución de la CA sigue siendo un problema aparte.
- **Caducidad del certificado del enclave.** Sin renovación automática, el plano
  de control tiene una fecha de expiración operativa.

---

## 9. Firma HMAC del canal orquestador → agente — ✅ RESUELTO (Paso 9)

El agente (`fase4-breakglass-dc/dcagent/agent_dc.py`) verifica HMAC-SHA256 sobre
`{timestamp}.{nonce}.{body}` con ventana temporal de 300 s y anti-replay por
nonce (`verify_signature()`). Desde el Paso 9 corre con
`AGENT_REQUIRE_HMAC=true`: el nodo Code de n8n genera `X-Timestamp`, `X-Nonce` y
`X-Signature`, reutilizando el patrón de firma de la Fase 2. `/health` devuelve
`"hmac_required": true`.

Validación (5/5) en `README-fase4-validacion.md`, sección 3.3: petición firmada
`200`; replay `409`/`100606`; firma inválida `403`/`100605`; timestamp fuera de
ventana `400`; sin cabeceras `400`.

---

## 10. Fase 4d — Flujo de aprobación y ejecución — ✅ RESUELTO

El War Room dejó de ser un tablón informativo: hay camino de vuelta desde
Rocket.Chat hacia el orquestador mediante comandos `!ir` (outgoing webhook). Lo
implementado, con detalle en
[`README-fase4d-flujo-aprobacion.md`](README-fase4d-flujo-aprobacion.md):

- **Autorización por allowlist en el orquestador.** Rocket.Chat Community no
  permite roles propios y el bot no tiene `view-full-other-user-info`
  (`users.info` devuelve `canViewAllInfo: false` sin `roles`). Se usa
  `IR_APPROVER_IDS` (variable de entorno de n8n). Cadena de confianza: token del
  webhook → `chat.getMessage` confirma autoría → autor confirmado ∈ allowlist.
  El `user_id` del payload nunca se usa para autorizar.
- **Regla de dos personas** con solicitudes `REQ-xxxxxxxx` caducables (15 min);
  auto-aprobación rechazada.
- **Resolución del identificador RustDesk** desde `hbbs`: `export-peers.sh`
  (cron 30 min) → `peers.json` → nodo Code en n8n, filtrando por el campo
  `note`.
- **Entrega de la credencial** por `/webhook/bg-credential`, router Traefik con
  `authelia@file` y `priority=100` + regla `access_control` a `group:ir_lead`
  con `two_factor`: un solo uso, se registra quién la recuperó, se destruye. En
  el canal solo viaja el enlace.
- **Firma HMAC** (punto 9) activa en la llamada n8n → agente DC.

Validación 11/11 en `README-fase4-validacion.md` y en el documento de la subfase.

Pendientes que quedan de este bloque:

- **Callback y registro del caso en DFIR-IRIS** (Fase 6).
- **Workflow exportado con `export-workflow.sh`.** Hoy vive solo en el volumen
  de n8n; `$getWorkflowStaticData` (donde se guardan solicitudes y credenciales)
  se pierde si el workflow se reimporta.
- **El enlace de credencial no es clicable en Rocket.Chat.** Pendiente ajustar
  el formato Markdown del mensaje.
- **El mensaje de alerta muestra "desde ."**: el template de n8n espera un
  `data.srcip` que estos eventos no traen; debe caer a `location` o al nombre
  del agente.

---

## 11. Otros pendientes

> **Authelia sobre Headscale UI — ✅ RESUELTO (28/08/2026).** El router usa
> `authelia@file` (la referencia `authelia@docker` no existía como middleware
> y Traefik la descartaba en silencio, dejando la ruta en `200` sin
> autenticación — ver el hallazgo detallado en
> [`README-fase4-validacion.md`](README-fase4-validacion.md)). Ahora
> `fase1-infraestructura/authelia/configuration.yml` tiene la regla para
> `hs.oob.local` (`subject: 'group:ir_lead'`, `policy: two_factor`) y una
> petición no autenticada a `/web` devuelve `302` hacia Authelia.

- **Cuenta de servicio del agente DC**: `LocalSystem` es el máximo privilegio
  posible en un DC. Procedería una gMSA con derechos delegados únicamente sobre
  la OU objetivo. Requiere KDS root key y Active Directory real, no disponibles
  en el laboratorio actual.
- **Verificación de integridad de scripts**: firma Authenticode validada antes
  de cada invocación, en lugar de confiar solo en el anclaje de ruta y la
  allowlist por nombre.
- **Almacenamiento del token del agente**: `AGENT_TOKEN` reside en el bloque de
  entorno del servicio NSSM (`AppEnvironmentExtra`), legible desde el registro
  de Windows por cualquier proceso con privilegios suficientes para leer la
  configuración del servicio. Alternativa evaluada: fichero cifrado con DPAPI
  de máquina. Se descartó endurecer la ACL de la clave de registro del
  servicio tras comprobar que dejaba el servicio inarrancable.
- **Visibilidad SIEM sobre red corporativa**: el agente Wazuh del DC reporta
  por la interfaz de red corporativa, no por la tailnet. Una caída de esa red
  suprime la visibilidad SIEM sobre el DC aunque el canal break-glass (que va
  por Headscale/Tailscale) siga operativo — dos planos de red con
  disponibilidad independiente que conviene tener presente al interpretar
  silencio de logs durante un incidente.
- **Dependencias salientes inventariadas** (para el análisis de superficie
  de terceros del TFM): tras el Paso 8, ya no dependen de terceros el mapa DERP
  (embebido) ni la comprobación de versión de Headscale (`disable_check_updates:
  true`). Quedan: aviso de nueva versión de RustDesk en cada arranque del
  cliente, y AbuseIPDB/VirusTotal de fases anteriores (Fase 2).
- **Rotación de los secretos de la Fase 8** (`RTTYS_TOKEN`, `RTTYS_PASS`,
  `TURN_PASS`): estuvieron commiteados en `.env.example` y deben rotarse.
