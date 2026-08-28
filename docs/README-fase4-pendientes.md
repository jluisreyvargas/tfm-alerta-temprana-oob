# Fase 4 — Trabajo pendiente

Este documento centraliza lo que queda por hacer en la Fase 4 (break-glass y
acción remota sobre Domain Controllers) tras el endurecimiento y la validación
empírica ya realizados. Cada apartado indica su estado real verificado, no una
suposición sobre lo que "debería" faltar.

---

## 8. Endurecimiento del plano de control (Headscale)

**Es el único bloque de trabajo pendiente que es destructivo**: recrear el
contenedor `headscale` con la configuración endurecida hace que los nodos ya
registrados (`orchestrator-tfm`, `dc01-tfm`) pierdan la sesión de control plane
hasta que se reautentiquen, porque `server_url` y `base_domain` cambian.

### Estado real: la configuración ya está escrita, no aplicada

A diferencia de lo que podría sugerir una lectura superficial de
`fase4-breakglass-dc/headscale/config/`, **el endurecimiento no está pendiente
de diseñarse ni de escribirse — ya está en los tres ficheros del repositorio**
(`config.yaml`, `acl.hujson`, `docker-compose.headscale.yml`). Lo que está
pendiente es aplicarlo: el contenedor `headscale` lleva en ejecución desde
antes de que esos ficheros se modificasen por última vez, así que el servicio
real que atienden los nodos hoy sigue operando con los parámetros previos al
endurecimiento.

| Elemento | Estado en los ficheros del repo | Qué falta realmente |
|---|---|---|
| `server_url` | ya `https://hs.oob.local` (vía Traefik, con la CA del enclave) | recrear el contenedor (`docker compose down && up -d`) |
| DERP | ya embebido (`derp.server.enabled: true`), `urls: []` — sin depender de `controlplane.tailscale.com` | recrear el contenedor; el primer arranque genera `derp_server_private.key` |
| Comprobación de versión | ya `disable_check_updates: true` | recrear el contenedor |
| DNS del tailnet | `nameservers.global: []` — ya no apunta a `1.1.1.1` (Cloudflare) | decidir si se necesita un resolver interno explícito para los clientes de la tailnet, o si el vacío es intencional |
| `base_domain` | ya `tailnet.internal` (separado de `oob.local`, que sirve el resto del enclave) | recrear el contenedor |
| gRPC | ya `127.0.0.1:50443` | recrear el contenedor |
| Métricas | ya `127.0.0.1:9090`, sin publicar puerto en el host (el compose actual no mapea `9090` en absoluto) | recrear el contenedor |
| Política ACL | ya `policy.path: /etc/headscale/acl.hujson`, fichero presente con reglas | recrear el contenedor; validar con `docker exec headscale headscale policy check --file /etc/headscale/acl.hujson` |
| Etiquetas de nodo | `acl.hujson` ya define `tag:dc`, `tag:orchestrator`, `tag:analyst` en `tagOwners` | los nodos ya registrados deben **re-unirse** con `--advertise-tags=...` (Fase 4b); un nodo sin tag no matchea ninguna regla ACL, así que hasta que se re-registren, la microsegmentación no tiene efecto sobre ellos aunque la política ya esté activa |

Requisitos previos en cada nodo, sin cambios: CA del enclave en el almacén de
confianza y resolución de `hs.oob.local`.

### Por qué el plano de control necesita su propia PKI

Un enclave out-of-band no puede apoyarse en la PKI corporativa (AD CS), porque
esa PKI es uno de los activos que se asume comprometido en el escenario que
justifica el enclave. Necesita su propia cadena de confianza y su propio
mecanismo de distribución — la CA del enclave (`fase1-infraestructura/`), no
la del dominio.

### Por qué el DERP embebido importa

Mientras el mapa de relay se obtuviera de `controlplane.tailscale.com`, el
tráfico break-glass podía relayarse por infraestructura de un tercero cuando
el NAT impedía conexión directa entre nodos, lo que contradice el principio
rector del proyecto (cero dependencias de servicios externos críticos). El
DERP embebido ya escrito en `config.yaml` resuelve esto — pendiente, de nuevo,
solo de aplicarse.

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

- **Authelia sobre Headscale UI**: el compose de `headscale-ui` ya referencia
  el middleware `authelia@docker`, pero `fase1-infraestructura/authelia/configuration.yml`
  no tiene ninguna regla de `access_control` para el dominio `hs.oob.local`
  (solo existe una para `chat.oob.local`, restringida a `group:ir_lead`, con
  `default_policy: deny`). Sin una regla propia, el comportamiento real de esa
  ruta no está verificado — puede estar bloqueada para todos en vez de exigir
  sesión Authelia del grupo correcto. Pendiente: añadir la regla para
  `hs.oob.local` replicando el patrón de Rocket.Chat, y verificar el resultado
  con una petición no autenticada.
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
  de terceros del TFM): mapa DERP de Tailscale (mientras no se aplique el
  endurecimiento del punto 8), comprobación de versión de Headscale, aviso de
  nueva versión de RustDesk en cada arranque del cliente, y AbuseIPDB/VirusTotal
  de fases anteriores (Fase 2).
