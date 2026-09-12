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
- [x] Certificado del dispositivo emitido desde `oob-rootCA`, persistente —
  emitido y verificable (`glkvm-device.crt`, SAN `IP:192.168.0.36`,
  `serverAuth`), pero **no en uso**: la autenticación del dispositivo ante rttys
  sigue siendo el token (`device.go:470`). `rtty` admite `-c`/`-k` para
  certificado de cliente; la autenticación mutua queda como mejora posible
- [x] Planos de control externos del fabricante desactivados y verificados
- [x] Monitorización de capacidad con prueba negativa validada
- [x] Imagen de la plataforma fijada por digest
- [x] Puertos restringidos a la interfaz LAN

**Mejoras previstas** — estado a 11 sep 2026, detalle en
[Mejoras previstas](#mejoras-previstas)

- [x] Validación TLS del canal rtty (`-C` con `oob-rootCA`) — mejora 2, con
  prueba negativa. Exigió antes emitir un certificado de servidor para rttys:
  presentaba la CA raíz del enclave, cuya clave privada estaba montada en el
  contenedor
- [x] Trazabilidad del operador en `device_event_logs` — mejora 3. Resuelta con
  cuentas nominales, no con PROXY protocol. Alcance: registra sesiones
  establecidas, **no** intentos denegados
- [x] Autorización por dispositivo en el nivel 1 — mejora 1. `user-hook-url`
  cubre `/connect/`, `/cmd/` y `/web/`; remedia el P0-6
- [ ] Flujo de solicitud de sesión con aprobación de segunda persona — diseñado
  (F8-D5), **no construido**. `/cmd/` y `/web/` deniegan incondicionalmente
- [ ] ~~Política de dos personas para `powerreset`~~ — **no es construible tal
  como estaba enunciada**. `powerreset` es una acción del nivel 2, que no
  atraviesa rttys ni el hook. Lo gobernable desde el nivel 1 son `/cmd/` y
  `/web/`; el nivel 2 queda como vía de emergencia auditada *a posteriori*
  (RA-1). Ver `docs/riesgos-aceptados-hook-nivel1.md`
- [ ] Integración con IRIS y Rocket.Chat
- [x] Prueba funcional mensual procedimentada — mejora 5, M1–M7 con criterio de
  aprobado fijado. El planteamiento original (detener Headscale) no medía nada:
  el plano de datos sobrevive. El modo de fallo real es coordinador caído **más**
  nodo reiniciado

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

**Parcialmente construida** (11 sep 2026). El reconocimiento cambió su
naturaleza: no era una mejora de proceso, sino **la única autorización por
dispositivo que existe en el nivel 1**.

Verificado antes de construir: `operador1` sin grupo recibía `{"total": 0}` de
`GET /api/devices` y, a la vez, `302` hacia la consola en `GET /connect/zsb25f8`.
El modelo de autorización decía que no había dispositivos visibles y la ruta de
acceso llevaba a la shell del GL-RM1. Eso es el **P0-6**, y `user-hook-url` lo
remedia sin parchear rttys: intercepta `/connect/`, `/cmd/` y `/web/`.

**Construido:** autorización por dispositivo. El webhook resuelve identidad con
`/api/me` y consulta el propio `ListDevices` del producto como oráculo, de modo
que hereda el esquema de grupos sin reimplementarlo. El rol `admin` **no** se
exime: su asignación se resuelve por intersección de grupos de usuario.

**No construido:** la aprobación de segunda persona. `/cmd/` y `/web/` deniegan
incondicionalmente con motivo `aprobacion no implementada`.

Ver `docs/diseno-hook-autorizacion.md`, `docs/cierre-mejora1-hook.md` y
`docs/webhook-kvm-hook-construccion.md`.

**Diseño original, conservado como referencia:**

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

Las tres cuestiones que este README anticipó resultaron ser las correctas, y
así se resolvieron:

- **API de gestión de sesiones.** Resuelto por el nivel 1: `user-hook-url` es un
  punto de control del propio rttys, sin API nueva. El hook recibe `devid` y
  acción en `X-Original-URL`, y la cookie del analista para resolver identidad.
  Presupuesto de 3 s de timeout; medido p95 de 135 ms.
- **El nivel 2 no depende de n8n.** Verificado (V4): con n8n detenido,
  `/connect/` devuelve `403` —el hook falla cerrado— y `https://192.168.0.36`
  sigue operativo. Las dos mitades cuentan: el hook cerrado sin vía de emergencia
  sería un enclave inaccesible, y la vía sin hook sería el P0-6. El nivel 2 queda
  como vía manual auditada *a posteriori*, tal como este README anticipaba.

  Matiz encontrado al construir: `callUserHookUrl` falla cerrado ante caída de
  n8n y ante respuesta distinta de `200`, pero **abierto** ante un error interno
  del propio flujo, que responde `200` por defecto. Mitigado cableando la salida
  de error de cada nodo al camino que deniega.
- **La política de dos personas para `powerreset` no es construible.** Con
  acceso directo al dispositivo, un operador con credenciales reinicia el DC sin
  pasar por el flujo. Confirmado además que las acciones de potencia exigen
  credencial (`POST /api/atx/click` → `401` desde la LAN), de modo que la premisa
  es «operador con credencial local», no «cualquier equipo de la red». Queda
  documentado como **RA-1**, riesgo aceptado, en
  `docs/riesgos-aceptados-hook-nivel1.md`, con su control compensatorio: la
  detección ha de residir en un observador independiente del dispositivo.

### 2. Validación TLS del canal rtty

**Implementada** (11 sep 2026). `oob-rootCA.crt` en `/etc/kvmd/user/`, `-C` en el
heredoc de `S01selfCloud` —nunca en `rtty-loop.sh`, que se regenera— y
certificado `glkvm-cloud.crt` con SAN `IP:192.168.0.70` y `serverAuth`.

El paso previo resultó ser el hallazgo: rttys presentaba **la CA raíz del
enclave** como certificado de servidor, y su clave privada estaba montada en el
contenedor del fabricante. El `-x` de rtty no era un descuido: era lo único que
hacía funcionar el canal, porque ese certificado no podía validar.

Verificada con prueba negativa: con `-C` apuntando a una CA que no es la
emisora, rtty no conecta. Ver `docs/mejora2-tls-canal-rtty.md`.

### 3. Trazabilidad del operador

**Resuelta** (11 sep 2026), y **no con PROXY protocol**, que queda descartado.

`client_ip` era la pista equivocada. La tabla tiene además `actor_user_id` y
`actor_name`, poblados en todos los eventos de operador; lo que faltaba era más
de un principal — `users` tenía una sola fila. Con tres cuentas nominales, la
atribución discrimina. La IP del analista, con credencial compartida, tampoco
habría identificado a nadie.

Alcance: la tabla registra **sesiones establecidas**, no intentos. Las
denegaciones del hook no dejan rastro, porque corta antes de
`handleUserConnection`. Ver `docs/mejora3-trazabilidad-operador.md`.

### 4. Consola de dispositivo por subdominio (nivel 1)

**Analizada y descartada** (11 sep 2026), pero por una razón distinta de la que
se creía. No era sólo comodidad: hoy `/web/` sirve la interfaz del propio GL-RM1
**dentro del origen** `https://kvm.oob.local`, de modo que el JavaScript del
dispositivo —la pieza de terceros que el enclave no considera confiable—
comparte origen con la consola de la plataforma. Un subdominio por dispositivo
le daría origen propio.

No se implementa porque con **un solo KVM** el aislamiento no separa nada, y el
coste toca cuatro capas: certificado con SAN `*.kvm.oob.local` (los comodines son
de un solo nivel), enrutado de cliente de la SPA —la consola usa
`/#/rtty/<devid>`, con fragmento que no llega al servidor—, la validación de Host
de `api.go:185`, y reglas en Traefik.

**Condición de reevaluación:** si el enclave incorpora un segundo KVM, debe
implementarse antes de habilitar `/web/` para ambos. Ver
`docs/mejora4-consola-subdominio.md`.

### 5. Prueba funcional mensual

**Procedimentada** (11 sep 2026), con los modos de fallo medidos en la primera
ejecución. El planteamiento original no medía nada: **detener Headscale casi no
rompe el tailnet**, porque Tailscale separa plano de control y plano de datos y
los nodos registrados siguen comunicándose. Una prueba así pasa siempre.

El modo de fallo real es **coordinador caído más nodo reiniciado**: DC01
reiniciado con Headscale parado queda fuera del tailnet hasta que el coordinador
vuelve.

Consecuencia para la detección del nivel 2: la caída del heartbeat de DC01 no
discrimina un `powerreset` malicioso de una caída del coordinador, porque un
`powerreset` reinicia DC01 y un atacante puede tumbar Headscale primero. La
detección debe apoyarse en el registro local de Wazuh.

Procedimiento M1–M7 con criterio de aprobado fijado antes de ejecutar, en
`docs/mejora5-prueba-mensual-resiliencia.md`.

### 6. Endurecimiento adicional del dispositivo

**Inventariada** (11 sep 2026), con correcciones aplicadas y riesgos aceptados.
Es la mejora que más creció respecto a su alcance original. Detalle completo en
`docs/mejora6-endurecimiento-dispositivo.md`.

**Base establecida.** Lo que persiste: `/` monta un overlay sobre un squashfs de
solo lectura, de modo que los cambios en `/etc` sobreviven. Lo que puede
deshacerlos es un script de arranque: `S99custom` ejecuta como root **todo lo que
coincida con `S??*`** en `/etc/kvmd/user/scripts/`.

**Aplicado:**

- `/etc/dropbear` estaba en `777`. El directorio de la clave de host SSH era
  escribible por cualquiera: borrar un fichero depende del permiso del
  directorio, no del fichero. Corregido a `755`.
- Eliminados dos residuos de edición en `/etc/kvmd/user/scripts/`. Uno de ellos,
  `S01selfCloud.bak-19700101`, **coincidía con el patrón `S??*` y se ejecutaba
  como root en cada arranque** junto al original; la colisión estaba amortiguada
  por un `pgrep`, no por diseño.

**Riesgos aceptados, documentados:**

- **RA-4 · SSH con contraseña para `root`, abierto a la LAN.** `dropbear` escucha
  en `0.0.0.0:22` sin `-s`. Amplía la descripción de la vía de emergencia de
  RA-1: hay una segunda vía a shell que no pasa por kvmd ni por `auth_request`.
  Se acepta porque la contraseña es propia y distinta de la de la web UI, y
  porque endurecer sin clave pública instalada dejaría al operador fuera del
  break-glass.
- **RA-5 · El token del dispositivo es visible en `/proc/<pid>/cmdline`**, porque
  `rtty` lo recibe como argumento `-t`. Cuarta vía de fuga del mismo secreto y la
  más accesible: no requiere privilegio. No es remediable desde el proyecto.
- **RA-6 · `/same_check` es un oráculo de identidad.** Dada una MAC en formato con
  dos puntos, responde si coincide con la del dispositivo. Sin autenticación, en
  claro por el puerto 80, con CORS `*` — consultable desde el navegador de
  cualquiera que visite una página web, sin estar en la LAN.

**Corrección al reconocimiento:** `ipmipasswd` y `vncpasswd` **no** son almacenes
de credenciales, son plantillas de PiKVM sin entradas. El inventario del P0-3 sí
crece por otra vía: `S01selfCloud` guarda `TOKEN` y `WEBRTC_PASSWORD` en claro.

**Propuestas pendientes:**

- Activar el segundo factor de kvmd, que cierra el P2-9 —`/api/2fa/is_enabled`
  anuncia sin autenticación que no hay segundo factor— y no toca SSH, de modo que
  no compromete RA-4. Requiere guardar el secreto fuera del enclave.
- Recortar `ntpd` de `0.0.0.0:123` a cliente.
- Cerrar la variante en claro de `/same_check` por el puerto 80.
- Rotación del syslog: el buffer de 22 h es saturable por cualquier componente
  en bucle, y así se perdió la evidencia forense del incidente de julio.
- `S99cloudflare`, `S99zerotier` y `S99netbird`: inertes por ausencia de fichero
  de configuración, no por decisión — verificado que los tres salen por esa
  guarda antes de evaluar la bandera `.enable`. Un JSON de 30 bytes los activa.
  ZeroTier y NetBird además escriben `ip_forward=1` en `/etc/sysctl.conf` al
  arrancar y no lo revierten al parar. Distinto de Tailscale, que **sí** tiene su
  JSON con `{"enable": false}` y conserva estado de nodo persistido.
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
