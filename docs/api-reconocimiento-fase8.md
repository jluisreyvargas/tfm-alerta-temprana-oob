# Fase 8 · Reconocimiento de las APIs (nivel 1 y nivel 2)

**Estado:** reconocimiento del nivel 1 cerrado; nivel 2 cerrado hasta el límite
de lo verificable sin acción con efecto físico sobre DC01.
**Método:** lectura del código vendorizado, de la configuración renderizada en
el contenedor, del estado en base de datos y de la configuración del
dispositivo, más sondeo activo restringido a `GET` sobre endpoints
inequívocamente de lectura. Ninguna petición con efecto de escritura.

> **Limitación del método.** La correspondencia entre el código vendorizado en
> `fase8-kvm/glkvm-cloud/` y la imagen en ejecución (`sha256:a04a1225…`) **no
> está verificada**: la extracción de cadenas del binario no llegó a ejecutarse.
> Las rutas y la lógica de autorización descritas en §2 y §3 provienen del
> código; los comportamientos verificados por sondeo (§1, §2.4, §4) provienen
> del binario en ejecución. Las dos fuentes concuerdan en todo lo contrastado
> —`AUTH_REQUIRED` donde el código exige sesión, `401` en `/connect/:devid`,
> `admin` en la base de datos, versión `v2.7.0`— pero la concordancia es
> parcial, no una equivalencia demostrada.

> **Precondición vigente durante todo el reconocimiento:** DC01 encendido y
> conectado por HDMI+USB al GL-RM1. Por eso quedan sin sondear las familias
> `atx`, `hid`, `msd`, `switch`, `fingerbot`, `upgrade` y `system/set_*`.

---

## 1. Instrumentos invalidados antes de obtener ningún dato

El reconocimiento produjo cinco instrumentos falsos. Tres de ellos habrían
producido un informe coherente y erróneo; los otros dos, un diagnóstico con
forma de resultado. El recorrido es más informativo que el resultado.

Los tres últimos proceden de comandos propuestos durante el análisis asistido y
se corrigieron sólo al observar la salida, no al revisar el diseño. Es el mismo
patrón que la contribución 10 del informe de auditoría.

| Instrumento | Por qué falló | Cómo se detectó |
|---|---|---|
| Código HTTP como indicador de existencia (nivel 1) | La SPA devuelve `200` con `index.html` (743 B) para cualquier ruta no registrada | Petición a ruta aleatoria antes de sondear nada |
| Código HTTP como indicador de autorización (nivel 1) | La API responde `200` y el rechazo va en el cuerpo (`{"ok":false,"code":"AUTH_REQUIRED"}`) | Tres endpoints distintos devolvieron `200` con idéntico tamaño de 126 B |
| `curl -s` sin comprobar código de salida | Con `--cacert` apuntando a una ruta inexistente, `curl` falla y no imprime nada; indistinguible de "cuerpo vacío" | Cinco endpoints devolvieron "vacío" simultáneamente |
| Copia de SQLite sin el `-wal` | Con WAL activo se lee el último checkpoint, no el estado actual: 143 KB de base frente a 99 KB sin aplicar | Diferencia de 6 h entre las marcas de tiempo de `.db` y `.db-wal` |
| `cmd \|\| echo "sin sqlite3"` | El comando falló por sintaxis del shell, no por falta del binario; el `\|\|` imprimió un diagnóstico falso con forma de resultado | `command -v sqlite3` por separado |

**Criterio válido en el nivel 1:** el campo `ok` del cuerpo JSON. El código HTTP
sólo es informativo en `/connect/:devid`, donde `c.AbortWithStatus` responde
antes de construir el sobre.

**Criterio válido en el nivel 2:** el código HTTP sí discrimina (`404` de 153 B
para ruta inexistente, `401` de 116 B para no autorizado).

---

## 2. Nivel 1 — Plataforma rttys (`glkvm_cloud`, v2.7.0)

Dos superficies distintas en el mismo binario.

### 2.1 API moderna (`internal/http/router.go`)

Grupo `/api` con `middleware.Auth(SessionStore, UserSvc, PermSvc)` y control de
permisos por ruta mediante `middleware.Require(permission.X)`.

| Ruta | Método | Autorización | Evidencia |
|---|---|---|---|
| `/auth-config` | GET | **Pública** | Sondeada sin credencial → `ok:true` |
| `/api/login` | POST | Pública | Fuente |
| `/api/script-info` | GET | Sesión, **sin `Require`** | Fuente + sondeada → `AUTH_REQUIRED` |
| `/api/me`, `/api/me/profile`, `/api/me/2fa/*` | GET/PUT/POST/DELETE | `MeRead` | Fuente; `/api/me` sondeada |
| `/api/devices` | GET | `DeviceRead` | Fuente + sondeada |
| `/api/devices/:id` | PUT/DELETE | `DeviceWrite` | Fuente |
| `/api/devices/move-to-device-group` | POST | `DeviceGroupWrite` | Fuente |
| `/api/users`, `/api/users/:id` | GET/POST/PUT/DELETE | `UserRead` / `UserWrite` | Fuente |
| `/api/user-groups*` | GET/POST/PUT/DELETE | `UserGroupRead` / `UserGroupWrite` | Fuente |
| `/api/device-groups*` | GET/POST/PUT/DELETE | `DeviceGroupRead` / `DeviceGroupWrite` | Fuente |
| `/api/device-event-logs` | GET | `DeviceLogRead` | Fuente + sondeada |
| `/api/notification/{smtp,rules,recipients}` | GET/PUT/POST/DELETE | `NotificationRead` / `NotificationWrite` | Fuente |
| `/auth/oidc/login`, `/auth/oidc/callback` | GET | Pública (flujo OIDC) | Fuente |

### 2.2 API heredada (`internal/server/api.go`)

Grupo `authorized` bajo `/`. **No usa `permission.*`.** Autentica con
`httpAuth`: cookie `sid` validada contra `sessionStore`, salvo dos atajos.

| Ruta | Método | Efecto | Hook |
|---|---|---|---|
| `/connect/:devid` | GET | WebSocket a consola; sin `Upgrade`, redirige a `/rtty/:devid` | Sí |
| `/cmd/:devid` | POST | **Ejecución de comandos en el dispositivo** | Sí |
| `/web/:devid/:proto/:addr/*path` | ANY | **Proxy HTTP a dirección arbitraria alcanzable desde el dispositivo** | Sí (en `httpProxyRedirect`) |

Verificado: `/connect/<aleatorio>` sin cookie → `401`, cuerpo de 0 bytes.

### 2.3 Atajos de `httpAuth`

```go
if !cfg.LocalAuth && isLocalRequest(c) { return true }
if cfg.Password == ""                  { return true }
```

- `isLocalRequest` comprueba **sólo loopback** (`addr.IP.IsLoopback()`).
  `172.18.0.1` no lo es.
- `boot.go:26` fija `LocalAuth: true` por defecto, con lo que la primera
  condición nunca se cumple.
- `/auth-config` publica `legacyPassword:true`, luego `cfg.Password != ""` y la
  segunda tampoco.

Tres razones independientes. Ninguna procede de `rttys.conf`: `local-auth` no
está en el fichero renderizado ni en la plantilla, de modo que el control
depende de un valor por defecto del código.

### 2.4 Configuración efectiva

Claves consultadas en `/home/rttys.conf` renderizado. Sólo `admin-name` está
presente, y vacía.

| Clave | Estado | Efecto |
|---|---|---|
| `allow-origins` | Ausente | `cors.Default()` no se activa. CORS descartado como hallazgo en nivel 1 |
| `auth-session-ttl` | Ausente | `24 * time.Hour` por defecto (`config.go:128`). Vida de la cookie `sid` |
| `web-ui-host` | Ausente | El middleware de validación de Host no actúa. Traefik enruta por Host, efecto práctico nulo |
| `local-auth` | Ausente | `boot.go:26` fija `true`; el atajo de loopback queda inactivo |
| `user-hook-url` | Ausente | **El hook no se invoca: `callUserHookUrl` devuelve `true`** |
| `dev-hook-url` | Ausente | Sin notificación en el registro del dispositivo |
| `admin-name` | Presente, vacía | `config.go:274` la sustituye por `"admin"` |

**Persistencia.** La base SQLite está en bind mount
(`docker-compose/database/glkvm-cloud.db` → `/home/database/`), fuera del
contenedor. Explica que el registro de julio sobreviviera a las recreaciones y
hubiera que eliminarlo desde la UI. Exclusión de git verificada con
`git add --dry-run`: sólo `schema.sql` está trackeado; el commit `3c5b77a` es la
exclusión deliberada.

---

## 3. Mecánica del hook de autorización

`callUserHookUrl(cfg, c)` — `internal/server/api.go:353`.

| Aspecto | Comportamiento |
|---|---|
| URL | Fija, `cfg.UserHookUrl`. **No lleva el `devid`** |
| Método | `GET` siempre, sea cual sea el original |
| Contexto entregado | `X-Rttys-Hook: true`, `X-Original-Method`, `X-Original-URL` |
| Cabeceras | Copia **todas** salvo `upgrade`, `connection`, `accept-encoding`. **Incluye `Cookie`** |
| Timeout | 3 s |
| `UserHookUrl == ""` | `return true` — **permite** |
| Error de red | `return false` — deniega |
| Respuesta ≠ 200 | `return false` — deniega |
| Respuesta 200 | `return true` |

**Modos de fallo.** Cerrado ante caída de n8n; abierto ante ausencia de
configuración. La segunda es la peligrosa: `rttys.conf` se regenera desde
`/tpl/rttys.conf.tmpl` en cada arranque del contenedor, y la plantilla no
contiene `user-hook-url`. Un control escrito sobre el fichero renderizado
desaparece en el siguiente reinicio sin ningún aviso — el mismo patrón que
`S01selfCloud` regenerando `rtty-loop.sh` en el dispositivo (P1-1).

**Restricción de implementación.** El `render()` del entrypoint sólo sustituye
`{{KEY}}` para las variables de su lista, donde no figura ninguna clave de hook.
No basta con una variable de entorno: hay que modificar la plantilla.

**Defecto de instrumentación.** `upath := c.Request.URL.RawPath`; en Go
`RawPath` está vacío salvo rutas con caracteres escapados, de modo que los
`log.Error()` del hook registran una ruta vacía justo cuando falla.

### 3.1 Hook de dispositivo — no utilizable para el flujo

`DevHookUrl` (`internal/server/device.go:484`), `POST` en el registro del
dispositivo, payload `{"group","devid","token"}`.

Falla **cerrado**: `err` o `≠200` devuelven `devRegErrHookFailed` y el
dispositivo no se registra. Apuntarlo a n8n haría que la vía de recuperación
física dependiera de n8n, reintroduciendo la dependencia que D1 eliminó.
Además transporta el token del dispositivo en claro.

---

## 4. Nivel 2 — Dispositivo GL-RM1 (kvmd, linaje PiKVM)

### 4.1 La capa que aparenta el control no lo ejerce

`gl.ctx-server.conf` declara `auth_request /auth_check` a nivel de servidor y
después lo anula con `auth_request off` en `/`, `/login`, `/share`, `/api`,
`/api/ws`, `/api/hid/print`, `/api/msd/*`, `/api/upgrade/*`, `/api/log`,
`/api/system/ssl_cert`, `/redfish` y `/same_check`. La única ruta que conserva
la comprobación en nginx es `/streamer`.

**Verificado por comportamiento:** kvmd autentica igualmente. `/api/info`,
`/api/system/capability`, `/api/auth/check` y `/api/wol/list` devuelven `401`
sin credencial. El control existe, una capa por debajo de donde la
configuración sugiere.

### 4.2 Superficie declarada

110 endpoints extraídos del bundle `/rom/usr/share/kvmd/glweb/assets/*.js`.
Familias: `auth`, `2fa`, `init`, `info`, `ws`, `atx`, `hid`, `msd`, `switch`,
`fingerbot`, `streamer`, `upgrade`, `system`, `wol`, `turn`, `custom_screen`,
`asr`, `modem`, `ap`, `repeater`, `tailscale`, `netbird`, `zerotier`.

| Ruta | Autenticación | Evidencia |
|---|---|---|
| `/api/init/is_inited` | **Ninguna** | Sondeada → `{"country_code":"CN","is_inited":true}` |
| `/api/2fa/is_enabled` | **Ninguna** | Sondeada → `{"enabled":false}` |
| `/api/info` | Requerida | Sondeada → `401` |
| `/api/system/capability` | Requerida | Sondeada → `401` |
| `/api/auth/check` | Requerida | Sondeada → `401` |
| `/api/wol/list` | Requerida | Sondeada → `401` |
| `/redfish/v1` | **Ninguna** | Sondeada → `200`, ServiceRoot |
| `/redfish/v1/Systems` | Requerida | Sondeada → `401` |
| Resto | **Sin verificar** | Sólo declarada por el bundle |

**Acciones con efecto físico sobre DC01, sin sondear:** `/api/atx/click`,
`/api/upgrade/reboot`, `/api/upgrade/reset_default`, `/api/fingerbot/click`,
`/api/switch/set_active`, `/api/hid/*`, `/api/msd/*`, `/api/system/set_*`.
`main.yaml` confirma `atx: type: glatx` y `hid: type: otg`.

### 4.3 Superficie no contemplada en la auditoría

- `/redfish` proxied a kvmd, con `auth_request off` y CORS `*`. **Acotado por
  sondeo:** `/redfish/v1` responde `200` sin credencial (ServiceRoot v1.6.0,
  anónimo por especificación); `/redfish/v1/Systems` responde `401`. La
  autenticación de kvmd cubre la rama con capacidad de acción — otra vez la capa
  que aparenta el control sin ejercerlo. Segunda superficie de gestión del
  dispositivo, no inventariada. Existen `/etc/kvmd/ipmipasswd` (822 B) y
  `/etc/kvmd/vncpasswd` (637 B), dos almacenes de credenciales fuera del
  inventario de cuatro del P0-3.
- `/same_check` servido **en claro por el puerto 80**, el único `location` que
  no redirige a HTTPS, con CORS `*`.
- `/dav/` proxied a `127.0.0.1:8080`, donde no escucha ningún proceso.
  Configurado sin backend.

---

## 5. Hallazgos nuevos

**P1-6 · `/api/script-info` entrega `RTTYS_TOKEN` y `WEBRTC_PASSWORD` a
cualquier usuario autenticado.** Única ruta de la API moderna sin
`middleware.Require`. `device.go:470` (`cfg.Token != "" && dev.token != cfg.Token`)
confirma que ese token es la credencial de autenticación del dispositivo.
Tercera vía de fuga del mismo secreto, junto al P2-6 (`docker logs`) y al
payload de `DevHookUrl`. Verificado que **no** es accesible sin sesión.

**P2-8 · `/auth-config` público.** Divulga versión (`v2.7.0`) y esquema de
autenticación (`legacyPassword`, LDAP y OIDC desactivados) sin credencial.

**P2-9 · El dispositivo anuncia la ausencia de segundo factor sin
autenticación.** `/api/2fa/is_enabled` → `{"enabled":false}`. El `totp.secret`
de 0 bytes documentado en la auditoría es observable remotamente por cualquiera
en la LAN. No sólo falta el control: su ausencia es publicada.

**Corrección al P0-4 / punto 7.** `eco` no es `gl-cloud`: es un lanzador
genérico que ejecuta el binario indicado en `argv[1]`. Las dos instancias vivas
son `/usr/bin/repeater` y `/usr/bin/gl_kvm_monitor`. `netstat -tn` confirma
únicamente dos conexiones establecidas, ambas hacia `192.168.0.70`. El punto 7
se mantiene correcto. Identificar un proceso por el nombre que muestra `ps` es
el mismo error que el P0-4 documenta.

**Reformulación del P1-4 · La trazabilidad del operador existe y es
degenerada.** El informe concluye que la atribución es inexistente porque
`client_ip` registra `172.18.0.1`. La tabla `device_event_logs` tiene además
`actor_user_id` y `actor_name`, poblados por `principalFromCtx`
(`internal/server/api.go:432`). Estado real de los 31 eventos:

| `event_type` | Eventos | `actor_user_id` | `actor_name` | `client_ip` |
|---|---|---|---|---|
| `remote_control` | 8 | 8/8 | 8/8 | `172.18.0.1` |
| `remote_ssh` | 4 | 4/4 | 4/4 | `172.18.0.1` |
| `device_online` | 11 | 0 | 0 | (vacío) |
| `device_offline` | 8 | 0 | 0 | (vacío) |

El campo se puebla en todos los eventos originados por un operador y se deja
vacío en los originados por el dispositivo, que es el comportamiento correcto.
**El control falla porque sólo existe un principal:** la tabla `users` contiene
una única fila (`admin`), de modo que `actor_name` siempre vale lo mismo.

Consecuencia para la mejora 3: PROXY protocol no resuelve el problema —daría la
IP del analista, que con credencial compartida tampoco identifica a nadie—. Lo
resuelve una cuenta por operador, o el proveedor OIDC contra Authelia. El
esquema ya está preparado para recibirla.

Observación colateral: 11 `device_online` frente a 8 `device_offline`. Tres
conexiones sin desconexión registrada, coherente con el P1-5.

**P2-10 · Nombre de la cuenta administrativa por defecto silencioso.**
`RTTYS_ADMIN_NAME` está vacío en `.env`; `xconfig/config.go:274` lo sustituye
por `"admin"` y valida el formato con `^[a-zA-Z0-9]+$`. La guarda está en la
carga de configuración, no en el punto de uso: `ensureAdminUser` ejecuta
`UPDATE users SET username = ? WHERE is_system = 1 AND role = 'admin' AND
username != ?` sin validar. Verificado en base: una fila, `'admin'`, `is_system=1`.
No es un defecto de la plataforma; es un valor efectivo que no consta en la
documentación del proyecto.

> **Matiz al principio de Fase 5** (`.env.example` con valores vacíos, no
> placeholders). Aquí el vacío no forzó asignación explícita: llegó hasta un
> `UPDATE` destructivo y fue absorbido por una guarda del fabricante. La regla
> completa es *valores vacíos **y** validación en la carga*; sin la segunda
> mitad, el vacío sólo aplaza el problema hasta el punto de uso.

**Corrección · `gl_kvm_monitor`.** Bytecode Lua 5.4, sin cadenas `http`, `https`
ni `mqtt`. Coherente con `gl-cloud[1648]: (kvm.lua:221) start rtty` del informe:
el firmware orquesta en Lua. Sin plano de control externo.

**Matiz al P2-3.** Tailscale no está inerte: `/etc/kvmd/user/tailscale/`
conserva `tailscaled.state` (2122 B), `files/tfm-oob-uid-1/` y
`profile-data/0ba0/netmap-cache/`, y `tailscale.json` contiene sólo `enable`.
Es una tercera categoría que no aparece en la tabla del informe: **desactivado
por bandera, con estado de nodo persistido**. Reactivar no exige
reprovisionar. `netbird/` sí está vacío.

---

## 6. Huecos abiertos

Cerrados en el reconocimiento: `allow-origins`, `auth-session-ttl`, `/redfish`,
`gl_kvm_monitor`, `admin-name`, esquema de `device_event_logs`, exclusión de git
de la base de datos.

Quedan dos, ambos requieren acción del operador:

1. **Captura HAR de la UI del nivel 1.** Sin ella no está verificado el lado
   cliente de la autenticación de `/connect/:devid`, que es lo que el flujo
   orquestado tendrá que reproducir. Bloquea escribir el nodo de n8n, porque
   determina qué llega en las cabeceras reenviadas al hook.
2. **Autenticación del resto de la API del dispositivo.** 8 endpoints de 110
   verificados. En particular, si `/api/atx/click` y el `POST` de reset de
   Redfish exigen credencial. Requiere ventana con DC01 prescindible y criterio
   definido antes de ejecutar: `401` sin cookie es aprobado; cualquier otra
   respuesta significa que cualquier equipo de `192.168.0.0/24` puede reiniciar
   el DC sin autenticarse.

## 7. Consecuencias para la mejora 1

1. El punto de control existe y no requiere parchear rttys: `user-hook-url`
   intercepta consola, comando y proxy.
2. El hook debe consultar un estado de aprobación ya resuelto. Con 3 s de
   timeout no puede contener la interacción humana.
3. `X-Original-URL` es el único portador del `devid` y de la acción. La política
   por acción se decide en el orquestador, no en rttys.
4. El hook recibe la cookie de sesión del analista. Aprovechable para
   atribución; es también una credencial cruzando un límite de confianza, y debe
   ser decisión explícita.
5. La configuración va en la plantilla, no en el fichero renderizado.
6. Prueba negativa obligatoria antes de dar el control por válido: hook que
   deniega → `403`; hook inalcanzable → `403`; **hook ausente → permite**, que
   es el modo que hay que detectar en la verificación de arranque en frío.
7. `dev-hook-url` queda descartado para el flujo de aprobación.

---

## 8. Limitación estructural del nivel 2

Nada de lo anterior alcanza al acceso directo al dispositivo. Un operador con la
credencial local abre `https://192.168.0.36`, pulsa el control de potencia y
reinicia DC01 sin pasar por el hook, por n8n ni por IRIS.

Del reconocimiento se desprende, pendiente de verificar los dos puntos:

- **Sin modelo de autorización por acción.** `htpasswd` de 44 bytes,
  `auth.yaml` a `{}`, `totp.secret` vacío. No hay separación de roles que
  permita conceder consola y negar potencia.
- **Sin registro persistente exportable.** El syslog es un buffer de 22 h
  saturable (P2-7), y `access_log off` en `nginx-kvmd.conf`. La tabla
  `device_event_logs` de la plataforma no ve el nivel 2: sus 31 eventos proceden
  todos de rttys.

Si ambos se confirman, la conclusión honesta es que en el nivel 2 el
`powerreset` **no es prevenible, sólo detectable**, y la detección no puede
residir en el dispositivo. El observador ha de ser independiente: Wazuh en DC01
registrando un apagado inesperado, o la caída de su heartbeat vista desde el
enclave. Eso es coherente con el principio rector y convierte una casilla falsa
del README en un control verificable.

Para el nivel 1, en cambio, el registro de sesión ya existe:
`device_event_logs` guarda `event_type`, `actor_user_id`, `actor_name`,
`created_at` y `ended_at`. El flujo de aprobación puede cerrar el ciclo sobre esa
tabla en lugar de construir un registro paralelo, siempre que antes exista más de
un usuario.
