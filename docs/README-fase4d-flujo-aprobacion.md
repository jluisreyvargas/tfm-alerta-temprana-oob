# Fase 4d — Flujo de aprobación y ejecución break-glass desde Rocket.Chat

## Objetivo

Convertir el War Room de Rocket.Chat en un puesto de mando operativo: permitir que
un responsable de incidentes solicite una acción sobre el Domain Controller
(ejecución de script o activación de RustDesk break-glass) **desde el propio
canal**, que esa solicitud requiera la aprobación de una segunda persona, y que la
ejecución quede firmada, auditada en el SIEM y con la credencial temporal
entregada solo tras MFA.

Este documento sustituye a los dos documentos de diseño previos
(`README-fase4d-n8n.md`, que describía el webhook `/dc-action` con
`decision=approved`, y `README-fase4e-rustdesk-breakglass.md`): la Fase 4d
implementada incorpora el despliegue de RustDesk de la antigua 4e y añade el
modelo de aprobación de dos personas, la resolución del identificador desde el
servidor de rendezvous y la entrega autenticada de la credencial.

## Alcance

- Canal de retorno Rocket.Chat → n8n mediante comandos `!ir` en el canal.
- Modelo de autorización por allowlist de aprobadores (`IR_APPROVER_IDS`), resuelto
  en el orquestador, no en la herramienta de chat.
- Regla de dos personas: quien solicita no puede aprobar su propia solicitud.
- Firma HMAC-SHA256 de la llamada n8n → agente DC (Paso 9, ya activa).
- Despliegue de RustDesk Server (`hbbs`/`hbbr`) self-hosted en el enclave.
- Resolución del identificador RustDesk desde el inventario de `hbbs`.
- Entrega de la credencial de un solo uso por endpoint autenticado
  (`/webhook/bg-credential`) tras Authelia + MFA, con registro de quién la
  recuperó y destrucción tras el primer uso.

## Prerrequisitos

- Fase 4a: Headscale operativo, Headscale UI tras Authelia.
- Fase 4b: nodos `orchestrator-tfm` (100.64.0.1), `dc01-tfm` (100.64.0.2) y
  `analyst-w11` (100.64.0.4) activos y etiquetados; política ACL aplicada.
- Fase 4c: DC Agent v2.0 operativo en `http://100.64.0.2:8000`, con
  `AGENT_REQUIRE_HMAC=true`.
- n8n accesible como `https://n8n.oob.local`; Rocket.Chat accesible desde el
  contenedor n8n por la red Docker interna (`http://rocketchat:3000`).
- Traefik con el proveedor de fichero (`authelia@file`) y `access_control` de
  Authelia con una regla para el host del endpoint de credenciales.

## Arquitectura del flujo

```text
Rocket.Chat (!ir ...)                             analista / IR lead
      │  outgoing webhook (token)
      ▼
n8n  /webhook/ir-command
      │  1. verifica token del webhook
      │  2. chat.getMessage  → confirma que el mensaje existe y quién lo escribió
      │  3. compara ese autor confirmado con IR_APPROVER_IDS  (allowlist)
      │  4. valida script/TTL contra la allowlist y los rangos
      ▼
Solicitud REQ-xxxxxxxx  (caducidad 15 min, guardada en $getWorkflowStaticData)
      │  segunda persona: !ir approve REQ-xxxxxxxx
      │  5. re-verifica autoría vía API; 6. exige aprobador ≠ solicitante
      ▼
n8n → DC Agent  POST /run
      │  X-Timestamp / X-Nonce / X-Signature   (HMAC-SHA256 sobre {ts}.{nonce}.{body})
      ▼
DC Agent (dc01-tfm)  → PowerShell allowlisted → resultado
      │
      ├─► SIEM: agent.log → Wazuh → regla 100603 (activación de acceso remoto)
      ├─► Rocket.Chat War Room: estado de la acción (sin credencial en claro)
      └─► credencial de un solo uso  →  /webhook/bg-credential
                                         (router Traefik authelia@file, priority=100,
                                          access_control → group:ir_lead + two_factor)
                                         entrega única → registra quién → destruye
```

## Autorización por allowlist, no por roles

Rocket.Chat Community no permite crear roles propios, y el bot no tiene el permiso
`view-full-other-user-info`, por lo que `users.info` devuelve
`canViewAllInfo: false` y omite el campo `roles`. La autorización se resuelve con
`IR_APPROVER_IDS`, una lista de identificadores de Rocket.Chat mantenida como
variable de entorno de n8n.

Esto tiene una ventaja de diseño que debe constar: **la decisión de autorización
vive en el orquestador, no en la herramienta de chat.** Un compromiso de
Rocket.Chat permite publicar mensajes, pero no añadirse a la lista de aprobadores.
La cadena de confianza es:

1. token del webhook saliente → autentica que la llamada viene de Rocket.Chat;
2. `chat.getMessage` → confirma contra la API que el mensaje existe y quién lo
   escribió;
3. ese autor confirmado se compara con `IR_APPROVER_IDS`.

El `user_id` que llega en el payload del webhook **nunca** se usa para autorizar:
es un campo que cualquiera que conozca la forma del mensaje puede falsificar.

### Regla de dos personas

Una solicitud (`!ir run …` / `!ir rustdesk …`) genera un identificador
`REQ-xxxxxxxx` con caducidad de 15 minutos. La ejecución solo se dispara con un
segundo `!ir approve REQ-xxxxxxxx` de un aprobador **distinto** del solicitante;
la auto-aprobación se rechaza explícitamente (`🚫 requiere segundo responsable`).
Una segunda aprobación sobre una solicitud ya resuelta devuelve `ya resuelta
(approved)`.

## Comunicación por red Docker interna

La API de Rocket.Chat está tras Authelia, por lo que un Personal Access Token no
basta desde fuera. n8n la consume por `http://rocketchat:3000`, sin pasar por
Traefik.

**Consecuencia a documentar:** el PAT viaja en claro entre contenedores del
bridge Docker. Se acepta y se documenta como tal; la alternativa —excluir
`/api/` del middleware de Authelia— abriría toda la API de Rocket.Chat a
cualquiera con acceso de red al host.

## Resolución del identificador RustDesk

El identificador del par se obtiene del inventario del servidor de rendezvous, no
del endpoint:

```text
export-peers.sh  →  rustdesk/data/db_v2.sqlite3 (SELECT id, note FROM peer;)
                 →  rustdesk/peers.json  (cron cada 30 min)
                 →  nodo Code en n8n (lee peers.json con el módulo fs)
```

En un escenario break-glass el DC puede estar comprometido y podría mentir sobre
su propia identidad; el servidor `hbbs` está bajo control del equipo de
respuesta. `rustdesk_enable.ps1` en el DC devuelve deliberadamente el literal
`"rustdesk_id": "resolver_en_hbbs"` y es n8n quien lo resuelve.

El filtro es por el campo `note` de la tabla `peer`, **no por posición**: hay más
de un cliente registrado contra el mismo `hbbs` (p. ej. `orchestrator-client` y
`dc01-tfm`).

## Despliegue de RustDesk Server

`docker-compose.rustdesk.yml` levanta `hbbs` y `hbbr`. Estado final endurecido
(detalle y evidencia de tráfico en `README-fase4-validacion.md`, sección 5):

| Aspecto | Antes | Después |
|---|---|---|
| Tag de imagen | `:latest` | `rustdesk/rustdesk-server:1.1.14` |
| Cifrado | sin `-k`: aceptaba clientes sin clave | `-k _`: cifrado obligatorio |
| Relay | `relay-servers=[]` (hbbr no enlazado) | enlazado vía `-r rustdesk-hbbr:21117` |
| Escucha | `0.0.0.0:21115-21119` | `100.64.0.1` (interfaz tailnet) |

El cliente del DC apunta al **ID/Relay Server en la dirección del tailnet**
(`100.64.0.1`), no a una dirección de la red corporativa: se verificó por captura
`tcpdump -ni tailscale0 port 21116` que el tráfico break-glass discurre por
`tailscale0` (`100.64.0.2 → 100.64.0.1`).

## Entrega de la credencial

`rustdesk_enable.ps1` genera una contraseña de un solo uso
(`RandomNumberGenerator`, no `Get-Random`). Esa contraseña **no** se publica en el
canal. El flujo es:

- La credencial se recupera desde `/webhook/bg-credential`, protegido por un
  router de Traefik con `authelia@file` y `priority=100`, más una regla en
  `access_control` de Authelia restringida a `group:ir_lead` con `two_factor`.
- Se entrega **una sola vez**, se registra quién la recuperó y se destruye.
- En el canal solo viaja el enlace.

**Motivo, que debe constar:** publicar la contraseña en el canal dejaría una
credencial de acceso a un Domain Controller en el historial permanente de una
sala, visible para todos sus miembros, indexada y sincronizada a los clientes. El
TTL limita el *uso*, no la *persistencia* del secreto.

### Nota sobre las rutas de webhook

`/webhook/` **no** pasa por Authelia por defecto —es correcto, para que
Rocket.Chat pueda entregar comandos sin autenticación interactiva—, pero eso
significa que el endpoint de credenciales necesita su **propio router con
prioridad mayor** (`priority=100`) que sí imponga `authelia@file`. Sin él, la
credencial quedaría accesible a cualquiera con acceso de red al host.

## Tabla de validación

| # | Prueba | Resultado |
|---:|---|---|
| 1 | `!ir help` desde usuario no autorizado | Rechazo, sin solicitud creada |
| 2 | `!ir run malicioso.ps1` | Script no permitido desde el canal |
| 3 | `!ir rustdesk 9999` | TTL fuera de rango (1–240) |
| 4 | Solicitud válida | Identificador `REQ-xxxxxxxx`, caducidad 15 min |
| 5 | Auto-aprobación | 🚫 Rechazado: requiere segundo responsable |
| 6 | Identificador inexistente | `no encontrada o caducada` |
| 7 | Aprobación por segundo responsable | Ejecución, alerta `100603`, credencial disponible |
| 8 | Doble aprobación | `ya resuelta (approved)` |
| 9 | Credencial sin sesión Authelia | `403` / redirección a MFA |
| 10 | Credencial con MFA | ID, contraseña y enlace `rustdesk://` |
| 11 | Reutilización del enlace | `Credencial ya consumida. Recuperada por <usuario>` |

## Estado de la Fase 4d

Completada:

- Canal de retorno `!ir` Rocket.Chat → n8n.
- Autorización por `IR_APPROVER_IDS` resuelta en el orquestador, con la cadena de
  confianza token → `chat.getMessage` → allowlist.
- Regla de dos personas con solicitudes caducables.
- Llamada n8n → agente DC firmada con HMAC-SHA256 (Paso 9).
- Resolución del identificador RustDesk desde `hbbs` (`export-peers.sh` →
  `peers.json`).
- Entrega de la credencial tras Authelia + MFA, de un solo uso y con registro.
- Auditoría en el SIEM del propio enclave (regla `100603` en la ejecución
  legítima).

Pendiente (ver `README-fase4-pendientes.md`):

- Callback y registro del caso en DFIR-IRIS (Fase 6).
- Workflow exportado con `export-workflow.sh` (hoy vive solo en el volumen de
  n8n; `$getWorkflowStaticData` se pierde si el workflow se reimporta).
- El enlace de credencial no es clicable en Rocket.Chat (formato Markdown del
  mensaje).
