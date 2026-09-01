# 🔗 Fase 4 · Break-Glass sobre Domain Controllers

> [!NOTE]
> **🎯 Objetivo de la fase**
> Disponer de acceso remoto controlado y de ejecución de scripts de respuesta
> sobre Domain Controllers Windows 2025 **cuando se asume la red corporativa /
> AD comprometida**, por un plano de red out-of-band autohospedado (Headscale +
> Tailscale + DERP embebido) y con doble aprobación humana desde el War Room.

> [!TIP]
> El canal OOB no depende de ningún servicio externo: control plane
> (`hs.oob.local`, Traefik + CA del enclave), plano de datos (WireGuard directo)
> y relay (DERP embebido `region_id: 999`) son todos del propio enclave.

## 📚 Documentación por subfase (en `docs/`)

| Subfase | Documento | Contenido |
|---|---|---|
| 4a | `README-fase4a-headscale.md` | Control plane Headscale endurecido (Paso 8) |
| 4a | `README-fase4a-headscale-ui.md` | Headscale UI tras Authelia (`two_factor`) |
| 4b | `README-fase4b-tailnet.md` | Enrolado de nodos, etiquetas, política ACL |
| 4c | `README-fase4c-dcagent.md` | Agente FastAPI v2.0 en el DC + firma HMAC (Paso 9) |
| 4d | `README-fase4d-flujo-aprobacion.md` | Aprobación de dos personas y break-glass RustDesk |
| — | `README-fase4-validacion.md` | Validación funcional y de seguridad, hallazgos |
| — | `README-fase4-pendientes.md` | Trabajo pendiente con estado real verificado |

`README-fase4d-n8n.md` y `README-fase4e-rustdesk-breakglass.md` son diseño
histórico, reemplazados por `README-fase4d-flujo-aprobacion.md`.

## 📋 Estado

- [x] 🐳 RustDesk Server (`hbbs`/`hbbr`) self-hosted en el enclave, cifrado obligatorio (`-k _`), escucha en la interfaz del tailnet
- [x] 🕸️ Headscale control plane endurecido (HTTPS vía Traefik, DERP embebido, gRPC/métricas en loopback) — **Paso 8**
- [x] 🔐 Headscale UI protegida con Authelia (`group:ir_lead`, `two_factor`)
- [x] 🏷️ Nodos enrolados con etiquetas (`tag:orchestrator`, `tag:dc`, `tag:analyst`) y política ACL de microsegmentación aplicada
- [x] 🤖 Agente Python FastAPI v2.0 en el DC W2025 como servicio NSSM, binding a `100.64.0.2`, allowlist de 7 scripts, anclaje de ruta, ACL de directorios
- [x] ✍️ Firma HMAC-SHA256 + anti-replay activa (`AGENT_REQUIRE_HMAC=true`) — **Paso 9**
- [x] ✅ Flujo 4d: aprobación en Rocket.Chat (`!ir`) → n8n → agente DC, regla de dos personas, entrega de credencial tras MFA, identificador RustDesk resuelto desde el servidor de rendezvous
- [x] 📡 Auditoría extremo a extremo en el SIEM del propio enclave (reglas `100600`–`100610`)
- [ ] 🗂️ Callback y registro del caso en DFIR-IRIS (Fase 6)
- [ ] 💾 Workflow de n8n exportado con `export-workflow.sh` (hoy vive solo en el volumen de n8n)
- [ ] 🏷️ `glkvm` etiquetado (`tag:kvm`) — offline desde el 13/07, aislado en el tailnet mientras tanto

## 🏗️ Arquitectura del flujo 4d

```text
Rocket.Chat War Room                    IR lead / analista
   │  !ir run <script> <target>  /  !ir rustdesk <ttl>
   ▼
outgoing webhook  ──(token del webhook)──►  n8n  /webhook/ir-command
                                              │  chat.getMessage → confirma autoría
                                              │  autor confirmado ∈ IR_APPROVER_IDS
                                              │  valida script / rango de TTL
                                              ▼
                                     Solicitud REQ-xxxxxxxx  (caduca 15 min)
                                              │  !ir approve REQ-xxxxxxxx
                                              │  aprobador ≠ solicitante  (regla de dos personas)
                                              ▼
   n8n  ──►  DC Agent (dc01-tfm:8000) /run
             X-Timestamp / X-Nonce / X-Signature   HMAC-SHA256({ts}.{nonce}.{body})
                                              ▼
                     PowerShell allowlisted  →  resultado estructurado
                                              │
             ┌────────────────────────────────┼────────────────────────────────┐
             ▼                                ▼                                ▼
     SIEM: agent.log → Wazuh          Rocket.Chat War Room            credencial de un solo uso
     regla 100603 (acceso remoto)     estado de la acción            /webhook/bg-credential
                                      (sin credencial en claro)      router Traefik authelia@file
                                                                     priority=100, group:ir_lead
                                                                     + two_factor → entrega única
                                                                     → registra quién → destruye
```

Resolución del identificador RustDesk (fuera de banda respecto al DC):

```text
export-peers.sh (cron 30 min)  →  rustdesk/data/db_v2.sqlite3
                               →  rustdesk/peers.json  →  nodo Code en n8n (filtra por note)
```

## 🔧 Componentes

### 🕸️ Headscale + Tailscale + DERP embebido
- **Control plane:** `https://hs.oob.local` (Traefik, CA del enclave). gRPC y métricas en `127.0.0.1`.
- **Plano de datos:** WireGuard directo entre nodos (`active; direct`).
- **Relay:** DERP embebido `region_id: 999` (`oob`), `derp.urls: []`, STUN UDP `3478`. Requiere `derp.server.ipv4` explícito (ver hallazgos en `docs/README-fase4a-headscale.md`).

### 🤖 DC Agent (`dcagent/agent_dc.py`, v2.0)
- **Servicio:** NSSM `TFM-DC-Agent`, venv en `C:\tfm-dc-agent\`, `--host 100.64.0.2 --port 8000`, `DependOnService Tailscale`.
- **Auth:** Bearer token en tiempo constante **+** firma HMAC-SHA256 obligatoria (`X-Timestamp`/`X-Nonce`/`X-Signature`, ventana 300 s, anti-replay por nonce).
- **Allowlist (7):** `disable_account`, `enable_account`, `collect_logs`, `isolate_host`, `reset_password`, `rustdesk_enable`, `rustdesk_disable` (`.ps1` en `C:\tfm-scripts\`, con anclaje de ruta y ACL de solo lectura/ejecución para `SYSTEM`).

### 🖥️ RustDesk Server
- `rustdesk/rustdesk-server:1.1.14`, `hbbs -r rustdesk-hbbr:21117 -k _` / `hbbr -k _`.
- Escucha en `100.64.0.1` (interfaz tailnet). Puertos `21115-21119`.
- Contraseña de sesión de un solo uso (`RandomNumberGenerator`), TTL por tarea programada `RustDesk-AutoOff`.

### 🧭 Orquestación (n8n) + War Room (Rocket.Chat)
- n8n consume la API de Rocket.Chat por la red Docker interna (`http://rocketchat:3000`), sin pasar por Traefik/Authelia.
- Autorización por `IR_APPROVER_IDS` (variable de entorno de n8n), resuelta en el orquestador, no en el chat.

## ⚠️ Consideraciones de seguridad

| Control | Estado | Nota |
|---|:--:|---|
| Bearer token en el agente | ✅ | Comparación en tiempo constante (`secrets.compare_digest`) |
| Firma HMAC del canal n8n → agente | ✅ | `AGENT_REQUIRE_HMAC=true` (Paso 9) |
| Anti-replay (nonce + ventana temporal) | ✅ | Nonces retenidos 300 s; replay → `409` / alerta `100606` |
| Microsegmentación por ACL | ✅ | Política `acl.hujson` con etiquetas; "el DC nunca es origen" salvo registro RustDesk |
| Allowlist de scripts + anclaje de ruta | ✅ | Nombre validado y ubicación real comprobada con `Path.resolve()` |
| ACL de directorios en el DC | ✅ | `SYSTEM` solo `RX` sobre código y scripts; `M` solo sobre `logs\` |
| Aprobación de dos personas | ✅ | Solicitante ≠ aprobador; solicitudes con caducidad |
| Entrega de credencial | ✅ | Endpoint autenticado (Authelia + `two_factor`), un solo uso, con registro |
| Break-glass por red subyacente corporativa | ⚠️ | El control plane se alcanza por la red corporativa (limitación conocida del laboratorio) |
| Cuenta de servicio `LocalSystem` en el DC | ⚠️ | Procedería una gMSA con derechos delegados sobre la OU objetivo |
| Integridad de scripts (Authenticode) | ⚖️ | Evaluado y descartado: cubierto parcialmente por ACL de directorio. Ver justificación en `docs/README-fase4-pendientes.md` |

## ✅ Validación

Batería completa con salidas reales y hallazgos en
[`docs/README-fase4-validacion.md`](../docs/README-fase4-validacion.md): 9/9
pruebas del agente, 5/5 de la firma HMAC, 11/11 del flujo de aprobación 4d, y
verificación por captura de tráfico de que el canal break-glass discurre por
`tailscale0`.

## 🚀 Próximos pasos

1. 🗂️ Integrar DFIR-IRIS para el registro del caso (Fase 6).
2. 🦎 Colección forense con Velociraptor (Fase 5).
3. 📈 Cuadros de mando en OpenSearch (Fase 7).
