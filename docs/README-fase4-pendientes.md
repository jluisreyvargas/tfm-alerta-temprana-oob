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

---

## 9. Firma HMAC del canal orquestador → agente

El agente (`fase4-breakglass-dc/dcagent/agent_dc.py`) ya implementa
verificación HMAC-SHA256 con ventana temporal de 300 s y control anti-replay
por nonce (`verify_signature()`), pero queda **desactivada** mediante
`AGENT_REQUIRE_HMAC=false` hasta que el lado que llama —el orquestador n8n—
firme las peticiones.

Pendiente:

- Nodo Code en n8n que genere las cabeceras `X-Timestamp`, `X-Nonce` y
  `X-Signature`, reutilizando el patrón de firma ya empleado en la Fase 2 para
  el canal de ingesta de Wazuh.
- Activar `AGENT_REQUIRE_HMAC=true` en el entorno del servicio NSSM
  (`fase4-breakglass-dc/dcagent/README-despliegue.md`) una vez el orquestador
  firme correctamente.

---

## 10. Fase 4d — Flujo de aprobación y ejecución

**Prioridad alta.** Es el bloque que convierte el canal de coordinación en un
puesto de mando operativo, en vez de un simple tablón informativo.

**Estado actual:** el War Room de Rocket.Chat se abre automáticamente ante una
alerta, pero es únicamente informativo. No existe camino de vuelta desde
Rocket.Chat hacia el orquestador: nadie puede activar break-glass, ejecutar un
script de respuesta ni aprobar una acción desde el propio canal.

Elementos a implementar:

- **Canal de retorno Rocket.Chat → n8n**: outgoing webhook o slash command.
- **Modelo de autorización**: verificación de pertenencia al grupo `ir_lead`
  realizada por n8n **contra Rocket.Chat** (o contra la fuente de verdad de
  grupos que corresponda), nunca confiando en el `username` recibido en el
  payload del webhook, que es falsificable por cualquiera que sepa la forma
  del mensaje.
- **Resolución del identificador RustDesk**: ya resuelta a nivel de diseño y de
  script — `scripts/rustdesk_enable.ps1` ya **no** lee el ID desde
  `RustDesk.toml` en el propio DC (autoinforme de un endpoint que en un
  escenario break-glass puede estar comprometido); devuelve el literal
  `"rustdesk_id": "resolver_en_hbbs"`, delegando la resolución al servidor de
  rendezvous del enclave (`SELECT id, note FROM peer;` sobre
  `rustdesk/data/db_v2.sqlite3` en `hbbs`, bajo control del equipo de
  respuesta — ver `docs/README-fase4-validacion.md`, sección 5.2). **Lo que
  falta implementar** es el lado del orquestador: el nodo n8n que reciba esta
  respuesta debe reconocer el literal `resolver_en_hbbs` y ejecutar esa
  consulta automáticamente en vez de requerir intervención manual.
- **Entrega de la credencial temporal**: decisión de diseño pendiente. Publicar
  la contraseña de un solo uso que genera `rustdesk_enable.ps1` en un canal de
  Rocket.Chat supondría dejar una credencial de acceso remoto a un Domain
  Controller en el historial permanente de la sala, visible para todos sus
  miembros y sincronizada a los clientes. El TTL de 30 minutos limita la
  ventana de *uso*, pero no la persistencia del *secreto* en el historial.
  Opciones a evaluar: mensaje efímero, entrega por mensaje directo al
  aprobador, o recuperación desde un endpoint autenticado del orquestador
  mediante el identificador del incidente.
- **Callback y registro del caso** en DFIR-IRIS.

**Dependencia:** el punto 9 (firma HMAC) deja de ser opcional en cuanto
Rocket.Chat pueda disparar acciones sobre el DC a través del orquestador. La
protección anti-replay pasa a formar parte del propio modelo de autorización,
no solo de la higiene del canal.

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
