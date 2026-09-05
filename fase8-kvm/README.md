# Fase 8 · Recuperación física: KVM sobre IP

> **Objetivo**
> Proporcionar una vía de recuperación física del Domain Controller que siga
> operativa cuando fallen el acceso remoto por software (Fase 4) y el propio
> plano de control del enclave.

> **Principio rector aplicado**
> La vía de último recurso no puede depender de la infraestructura cuya caída
> justifica su uso. En esta fase eso significa: sin tailnet, sin nube del
> fabricante, sin servicios de terceros.

---

## Estado

**Operativo y verificado**

- [x] GL-RM1 registrado en la plataforma por ruta LAN (`192.168.0.70:5912`)
- [x] Arranque en frío verificado (4 reinicios, con y sin `gl-cloud`)
- [x] Vídeo y teclado funcionales por acceso directo al dispositivo
- [x] Certificado del dispositivo emitido desde `oob-rootCA`, persistente
- [x] Planos de control externos del fabricante desactivados y verificados
- [x] Monitorización de capacidad con prueba negativa validada
- [x] Imagen de la plataforma fijada por digest
- [x] Puertos restringidos a la interfaz LAN

**Pendiente** — ver [Mejoras previstas](#mejoras-previstas)

- [ ] Validación TLS del canal rtty (`-C` con `oob-rootCA`)
- [ ] Trazabilidad del operador en `device_event_logs`
- [ ] Flujo de solicitud de sesión con aprobación
- [ ] Política de dos personas para `powerreset`
- [ ] Integración con IRIS y Rocket.Chat
- [ ] Prueba funcional mensual procedimentada

> **Nota histórica**
> La versión anterior de este README marcaba como completadas cuatro
> capacidades no implementadas (fallback automático RustDesk→KVM, política de
> dos personas, mTLS sobre Cloudflare Access, integración en inventario del
> orquestador) y documentaba una arquitectura basada en Cloudflare Access,
> abandonada durante la implementación por ser incompatible con el principio
> rector. Se corrige aquí. El detalle está en
> [`docs/INFORME-AUDITORIA-FASE8.md`](../docs/INFORME-AUDITORIA-FASE8.md).

---

## Arquitectura

El acceso al KVM se organiza en **dos niveles independientes**. El nivel normal
pasa por la plataforma; el de break-glass va directo al hardware.

```text
NIVEL 1 — Operación normal
┌──────────────┐   HTTPS    ┌─────────┐         ┌──────────────┐
│   Analista   │───────────▶│ Traefik │────────▶│ glkvm_cloud  │
│  (LAN o VPN) │  kvm.oob   │ + TLS   │         │   (rttys)    │
└──────────────┘   .local   └─────────┘         └──────┬───────┘
                                                       │ rtty/5912
                                                       │ (el dispositivo
                                                       │  inicia la conexion)
                                                ┌──────▼───────┐
NIVEL 2 — Break-glass                           │   GL-RM1     │
┌──────────────┐        HTTPS directo           │ 192.168.0.36 │
│   Analista   │──────────────────────────────▶ │              │
│    (LAN)     │   glkvm-device.oob.local       └──────┬───────┘
└──────────────┘   o 192.168.0.36                      │ HDMI + USB
                                                ┌──────▼───────┐
                                                │  DC01-TFM    │
                                                │ Windows 2025 │
                                                └──────────────┘
```

### Por qué dos niveles

| | Nivel 1 (plataforma) | Nivel 2 (break-glass) |
|---|---|---|
| **URL** | `https://kvm.oob.local` | `https://glkvm-device.oob.local` |
| **Depende de** | Traefik, rttys, Docker, LAN | Sólo LAN |
| **Autenticación** | Local de rttys | Local del dispositivo (`htpasswd`) |
| **Uso** | Inventario, estado, consola, auditoría | Vídeo, teclado, power reset |
| **Vídeo** | Proxy por subdominio (no operativo) | Directo, candidatos ICE host |

El nivel 2 existe porque el nivel 1 tiene cuatro dependencias que pueden fallar
durante el incidente. Si `glkvm_cloud` cae, el acceso directo sigue disponible:
el dispositivo sirve su propia interfaz sin intermediarios.

### El KVM está fuera del tailnet, a propósito

Durante 54 días la configuración del dispositivo apuntó a `100.64.0.1:5912`
—la IP del orquestador en el tailnet—, de modo que la vía de recuperación
dependía por completo de Headscale. Se corrigió a `192.168.0.70:5912` por LAN,
se desactivó Tailscale en el dispositivo y se eliminó el nodo `glkvm` de
Headscale.

**Consecuencia operativa:** el break-glass por KVM se ejecuta desde un equipo en
`192.168.0.0/24`. No es accesible desde el tailnet, y eso es intencional.

---

## Acceso

### Resolución de nombres

En cada equipo de analista, en `/etc/hosts` (Linux/macOS) o
`C:\Windows\System32\drivers\etc\hosts` (Windows):

```text
192.168.0.70    kvm.oob.local
192.168.0.36    glkvm-device.oob.local
```

El certificado del dispositivo incluye `DNS:glkvm-device.oob.local` e
`IP:192.168.0.36` en sus SAN, de modo que ambas formas validan contra la CA del
enclave. Se prefiere el nombre: la IP es frágil ante cambios de red y obliga a
reemitir el certificado si el dispositivo cambia de dirección.

> **Requisito:** el GL-RM1 debe tener IP fija o reserva DHCP en
> `192.168.0.36`. Un cambio de dirección invalida el certificado y rompe la
> configuración de rtty.

### Confianza en la CA del enclave

Para que el navegador valide sin advertencias, hay que importar
`fase1-infraestructura/traefik/certs/oob-rootCA.crt` como autoridad de confianza
en cada equipo de analista.

Verificación desde línea de comandos:

```bash
curl --cacert fase1-infraestructura/traefik/certs/oob-rootCA.crt \
     -o /dev/null -w 'HTTP %{http_code}\n' https://192.168.0.36/
```

Debe devolver `HTTP 200` sin `-k`.

---

## Componentes

| Componente | Ubicación | Función |
|---|---|---|
| `glkvm_cloud` | Contenedor en `192.168.0.70` | Plataforma rttys: inventario, consola, proxy |
| GL-RM1 | `192.168.0.36`, LAN | Hardware KVM: HDMI, USB HID, control de potencia |
| `rtty` | Cliente en el dispositivo | Túnel saliente hacia `192.168.0.70:5912` |
| `S01selfCloud` | `/etc/kvmd/user/scripts/` | **Fuente de verdad** de la configuración de rtty |
| `rtty-loop.sh` | `/etc/kvmd/user/scripts/` | Watchdog. **Generado**, no editar |
| `check-kvm-lastseen.sh` | `~/tfm-scripts/` | Sonda de capacidad, cada 5 min |

### Advertencia sobre `rtty-loop.sh`

`S01selfCloud` **regenera** `rtty-loop.sh` desde un heredoc en cada arranque,
vía `S99custom`. Editar `rtty-loop.sh` directamente produce un cambio que
desaparece en el siguiente reinicio, sin ningún aviso.

Toda modificación va en las variables de cabecera de `S01selfCloud`:

```sh
HOSTNAME="192.168.0.70"
PORT=":5912"
TOKEN="<RTTYS_TOKEN, idéntico al del .env de la plataforma>"
WEBRTC_IP="192.168.0.70"
WEBRTC_PORT="3478"
WEBRTC_USERNAME="glkvmcloudwebrtcuser"
WEBRTC_PASSWORD="<TURN_PASS, idéntico al del .env>"
```

Después: `/etc/kvmd/user/scripts/S01selfCloud restart`

---

## Configuración aplicada

### Plataforma

`fase8-kvm/glkvm-cloud/docker-compose/docker-compose.override.yml`:

```yaml
services:
  rttys:
    image: glzhitong/glkvm-cloud@sha256:a04a1225...   # fijada por digest
    ports: !override                                  # REEMPLAZA, no fusiona
      - "192.168.0.70:5912:5912"
      - "192.168.0.70:10443:10443"
  coturn:
    profiles: ["disabled"]                            # eliminado del despliegue
```

> **`!override` es obligatorio.** Sin esa etiqueta, Compose *fusiona* las listas
> de `ports` del fichero base y del override, y el contenedor intenta bindear
> `0.0.0.0:5912` y `192.168.0.70:5912` a la vez, colisionando consigo mismo con
> un `address already in use` que parece un puerto ocupado por otro proceso.
> `docker compose config --quiet` valida la sintaxis y no detecta el problema.

En `.env`:

```ini
GLKVM_ACCESS_IP=192.168.0.70   # NO dejar vacío
```

> Con este valor vacío, el entrypoint del contenedor consulta `api.ipify.org`,
> `ifconfig.me` u OpenDNS para autodetectar la IP pública. Es una dependencia de
> Internet en el arranque de la vía de recuperación, y sin salida a Internet el
> fallback es `127.0.0.1`.

### coturn eliminado

El vídeo se negocia entre el navegador del analista y el dispositivo, ambos en
el mismo segmento L2: ICE resuelve con candidatos host y no interviene TURN.
Verificado: janus escucha en `127.0.0.1:7771` y UDP en `192.168.0.36`, con
`turn_rest_api_key = ""`.

Además, el `turnserver.conf.template` del proyecto vendorizado contiene
`allowed-peer-ip=0.0.0.0/0`, que coturn rechaza (no admite CIDR en ese
parámetro): 3072 reinicios acumulados. Y su puerto 3478 colisiona con el
`stun_listen_addr` del DERP embebido de Headscale que necesita la Fase 4.

### Certificado del dispositivo

Emitido desde `oob-rootCA` con clave EC `prime256v1` —la misma curva que genera
el firmware— y SAN `DNS:glkvm-device.oob.local`, `IP:192.168.0.36`,
`DNS:localhost`, `IP:127.0.0.1`. Instalado en `/etc/kvmd/user/ssl/`.

> El firmware **desactiva deliberadamente** la comprobación de caducidad en
> `check_cert_valid` (`S99kvmd-nginx`), con un comentario que lo documenta. Por
> eso el dispositivo servía un certificado autofirmado caducado en 1979 sin
> señalar nada. Sí verifica formato y correspondencia clave/certificado, así que
> un certificado válido del enclave se acepta y no se regenera.

---

## Verificación

### Estado actual

```bash
# ¿Hay conexión real del dispositivo?
docker exec glkvm_cloud sh -c 'netstat -tn | grep 5912'

# ¿El certificado del dispositivo valida contra la CA del enclave?
curl --cacert fase1-infraestructura/traefik/certs/oob-rootCA.crt \
     -o /dev/null -w 'HTTP %{http_code}\n' https://192.168.0.36/

# ¿Qué hace el cliente en el dispositivo?
ssh root@192.168.0.36 'logread | grep -i rtty | tail -5'
```

### No usar estos indicadores

Los cuatro campos de estado de la plataforma resultaron no fiables como
indicador de contacto continuo:

| Indicador | Problema |
|---|---|
| `devices.status` | 2 h 26 min de retraso demostrado |
| `devices.last_seen_at` | **No es un heartbeat**: registra el último *registro*. Con el dispositivo conectado, el valor crece indefinidamente |
| `devices.updated_at` | Idéntico al anterior |
| `device_event_logs` | No registró una desconexión provocada en pruebas |
| `ping` / puerto 443 del dispositivo | Estuvieron en verde durante los 54 días de caída |

### Prueba de arranque en frío

Tras cualquier cambio en el dispositivo:

```bash
ssh root@192.168.0.36 reboot
sleep 90
docker exec glkvm_cloud sh -c 'netstat -tn | grep -c ":5912.*ESTABLISHED"'   # → 1
```

`/etc` está sobre overlayfs con upper en `/userdata`, partición persistente. Un
cambio que sobrevive al editor pero no al reinicio reproduce exactamente el
fallo que esta fase corrige.

---

## Monitorización

`~/tfm-scripts/check-kvm-lastseen.sh`, en cron cada 5 minutos.

Mide **la conexión TCP establecida dentro del namespace de red del contenedor**,
no un campo de estado. La conexión no es visible con `ss` en el host: termina
dentro del contenedor, detrás del `docker-proxy`.

| Código | Significado |
|---|---|
| `0` | Conexión establecida |
| `1` | Sin conexión — vía de recuperación NO disponible |
| `2` | Contenedor caído o consulta fallida |

Validada en los cuatro casos, incluida la detección de una caída real producida
durante las pruebas. **Cualquier modificación exige repetir la prueba negativa:**
una sonda no probada es el control ausente que esta fase documenta.

```bash
# Prueba negativa
ssh root@192.168.0.36   # y dentro: pkill -f rtty-loop.sh; kill -9 <PID de rtty>
~/tfm-scripts/check-kvm-lastseen.sh; echo "exit=$?"   # esperado: 1
ssh root@192.168.0.36 '/etc/kvmd/user/scripts/S01selfCloud start'
```

---

## Riesgos aceptados

Con fecha de revisión en la defensa del TFM.

| Riesgo | Justificación | Compensación |
|---|---|---|
| Autenticación del nivel 2 fuera de Authelia | La vía de último recurso no puede depender del SSO del enclave | Credencial en custodia fuera de línea; acceso sólo desde LAN |
| Sin segundo factor en el dispositivo (`totp.secret` vacío) | Ídem | Ídem |
| Acciones del nivel 2 sin registro en IRIS | El dispositivo no tiene integración | Registro manual obligatorio en el caso IRIS |
| Canal rtty cifrado sin validar certificado | Requiere modificar el firmware | Segmento LAN aislado; pendiente de corrección |
| Certificado ligado a IP | Necesario para acceso directo | IP fija/reserva DHCP documentada |

---

## Mejoras previstas

### 1. Flujo de solicitud de sesión con aprobación

Réplica del modelo de la Fase 4 para RustDesk, adaptado al KVM. Es la mejora de
mayor valor pendiente: convierte un acceso permanente en uno solicitado,
aprobado, temporal y auditado.

**Diseño propuesto:**

```text
Analista ──▶ n8n: "solicitar sesión KVM en DC01, 30 min"
                │
                ├─▶ Rocket.Chat: petición al IR Lead
                │       └─ 1 aprobación → sesión de consola
                │       └─ 2 aprobaciones (IR Lead + IT Ops) → powerreset
                │
                ├─▶ IRIS: alta de la acción en el caso
                │
                └─▶ Publicación del enlace en el War Room + temporizador
```

Cuestiones a resolver antes de implementar:

- El dispositivo no expone API de gestión de sesiones. Habría que orquestar
  sobre la API de rttys (nivel 1) o sobre la del propio GL-RM1, aún sin
  documentar en este proyecto.
- El nivel 2 no puede depender de n8n: si n8n cae, el break-glass debe seguir
  funcionando. El flujo de aprobación aplicaría al nivel 1, y el nivel 2
  quedaría como vía manual con registro obligatorio *a posteriori*.
- La política de dos personas para `powerreset` exige un mecanismo que impida
  el atajo. Con acceso directo al dispositivo, un operador con credenciales
  puede reiniciar el DC sin pasar por el flujo. Esto es una **limitación
  estructural del nivel 2**, no un defecto de implementación, y debe
  documentarse como tal.

### 2. Validación TLS del canal rtty

Colocar `oob-rootCA.crt` en ruta persistente del dispositivo, añadir `-C <ruta>`
al heredoc de `S01selfCloud` y emitir el certificado de rttys con SAN para
`192.168.0.70`. Elimina el `SSL certificate error(18)` que aparece hoy en cada
conexión.

### 3. Trazabilidad del operador

`device_event_logs` registra `client_ip = 172.18.0.1` —el gateway del bridge de
Docker— para cualquier analista. Requiere PROXY protocol o cabeceras reenviadas
desde Traefik hasta rttys. Sin esto, la atribución de un `powerreset` sobre el
DC es inexistente.

### 4. Consola de dispositivo por subdominio (nivel 1)

El Remote Control de la plataforma genera URLs del tipo
`https://<deviceId>.kvm.oob.local/...`. Requiere regla `HostRegexp` en Traefik y
un certificado con SAN `*.kvm.oob.local` — los comodines TLS son de un solo
nivel y `*.oob.local` no lo cubre. Descartado a favor del acceso directo, pero
sería la vía para que el nivel 1 tenga vídeo propio.

### 5. Prueba funcional mensual

Procedimentar y registrar en IRIS: abrir consola, confirmar vídeo y teclado,
**con Headscale detenido**. Es la prueba que valida la premisa de la fase. Sin
ejecutar acciones de potencia.

### 6. Endurecimiento adicional del dispositivo

- Rotación del syslog: el buffer de 22 h es saturable por cualquier componente
  en bucle, y así se perdió la evidencia forense del incidente de julio.
- Revisión de `S99cloudflare`, `S99zerotier` y `S99netbird`: inertes por
  ausencia de fichero de configuración, no por decisión. Un JSON de 30 bytes
  los activa. ZeroTier y NetBird además escriben `ip_forward=1` en
  `/etc/sysctl.conf` al arrancar y no lo revierten al parar.
- `docker save` de la imagen de la plataforma: namespace personal de Docker Hub.

---

## Referencias

- [`docs/INFORME-AUDITORIA-FASE8.md`](../docs/INFORME-AUDITORIA-FASE8.md) —
  auditoría completa, causa raíz y contribuciones metodológicas
- [`fase4-breakglass-dc/`](../fase4-breakglass-dc/) — acceso remoto por software
  y flujo de aprobación que sirve de modelo para la mejora 1
- [`fase1-infraestructura/traefik/generate-oob-ca.sh`](../fase1-infraestructura/traefik/generate-oob-ca.sh) —
  CA del enclave
- `glkvm-cloud/` — proyecto vendorizado de GL.iNet, con su propia licencia
