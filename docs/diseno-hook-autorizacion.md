# Fase 8 · Mejora 1 — Hook de autorización y flujo de aprobación

**Estado:** diseño cerrado, pendiente de construcción.
**Origen:** el README lo planteaba como "flujo de solicitud de sesión con
aprobación, tipo RustDesk de Fase 4". El reconocimiento
(`docs/api-reconocimiento-fase8.md`) cambió su naturaleza: el hook es la única
autorización por dispositivo que existe en el nivel 1, y su construcción remedia
el P0-6.

---

## 1. Por qué el hook dejó de ser una mejora de proceso

Verificado por comportamiento, misma sesión de `operador1` (rol `user`, sin
grupo de usuarios asignado):

```
GET /api/devices        →  {"ok":true, ..., "total": 0}
GET /connect/zsb25f8    →  302  https://kvm.oob.local/rtty/zsb25f8
```

La ruta que consulta el modelo de autorización responde que no hay dispositivos
visibles. La ruta que da acceso redirige a la consola. Acceso confirmado hasta
shell en el GL-RM1 desde una ventana privada.

`ListDevices` (`internal/http/handler/device.go:38`) aplica un filtrado correcto:
resuelve los grupos de dispositivos del usuario y devuelve lista vacía si no
tiene ninguno; el rol `admin` queda exento y ve todo, incluidos los dispositivos
sin grupo. Ese control existe y funciona. Simplemente **no se consulta** en
`/connect/:devid`, `/cmd/:devid` ni `/web/:devid/...`, que pasan sólo por
`httpAuth` (existencia de sesión) y, en el caso del WebSocket,
por `handleUserConnection`, que sólo comprueba que el `devid` no esté vacío y
que el dispositivo exista.

El `devid` no es secreto: `zsb25f8` son 7 caracteres derivados de la MAC
(`9483c4cb25f8`) y aparece en la URL de cualquier sesión legítima.

---

## 2. Decisiones

> **Nomenclatura.** Se numeran como continuación de las decisiones del informe de
> auditoría de Fase 8 (`D1`–`D3`), con prefijo de ámbito para evitar la colisión
> con los defectos históricos `D1`–`D3` de `docs/README-resolucion-nombres.md` y
> con las decisiones de P1-1a, que usan la misma serie con otro significado.

| Id | Decisión | Justificación |
|---|---|---|
| F8-D4 | Devolución de llamada a rttys con la cookie del operador para resolver identidad y autorización | `sessionStore` es en memoria; la correspondencia `sid → userID` no está en SQLite y n8n no puede resolverla leyendo la base |
| F8-D5 | `/connect/` autorización automática; `/cmd/` y `/web/` requieren aprobación de segunda persona | Abrir consola es la operación normal del analista; exigir aprobación humana la haría inutilizable |
| F8-D6 | El estado de aprobación vive en n8n | No añade componentes al camino crítico de la vía de recuperación |
| F8-D7 | Llamadas en claro por nombre de contenedor dentro de `oob-network`, sin TLS ni CA | Ver §2.1 |
| F8-D8 | `GET /api/devices` con la cookie del operador es el oráculo de autorización | Reutiliza el control del propio producto; no reimplementa el esquema de grupos |

### 2.1 F8-D7 — Excepción acotada al principio de CA del enclave

Ambos sentidos van en claro dentro del bridge de Docker:

- rttys → n8n: `http://n8n:5678/webhook/kvm-hook`
- n8n → rttys: `http://glkvm_cloud:8180/...` con cabecera `Host: kvm.oob.local`

**Argumentos a favor.** El tráfico no abandona el host. Añadir Traefik al camino
crítico introduce una pieza más en la vía de recuperación. Montar
`ca-bundle-oob.crt` en un contenedor de terceros fijado por digest complica su
reemplazo. Y `glkvm_cloud` no está cubierto por el certificado `*.oob.local`, de
modo que la alternativa TLS exigiría además un alias de red.

**Riesgo residual, no minimizado.** Cualquier contenedor de `oob-network` puede
observar esas llamadas, que transportan la cookie de sesión del operador. Es una
excepción deliberada al argumento de que todo servicio del enclave usa el ancla
de confianza propia, y como tal debe figurar en la tabla de riesgos aceptados.

**Verificado:**

```
docker exec glkvm_cloud  wget http://n8n:5678/                              → 200
docker exec n8n  wget --header="Host: kvm.oob.local" \
                      http://glkvm_cloud:8180/auth-config                    → 200
```

Sin la cabecera `Host`, el middleware `WebUIHost` de `ListenAPI` responde `400`
con HTML de error. La cabecera es obligatoria, no opcional.

### 2.2 F8-D8 — Por qué el oráculo y no una lista propia

`/api/devices` ejecuta el mismo `ListDevices` que sirve a la interfaz. Cambios de
grupos hechos desde la UI se reflejan en el hook sin sincronizar nada, y el
control queda verificable con la misma prueba de §1 invertida. Una lista propia
en n8n exigiría mantener dos fuentes de verdad y divergiría en silencio.

Contrapartida: el hook hereda la política del producto, incluida la exención del
rol `admin`. Decisión de política pendiente (§7).

---

## 3. Mecánica del hook

`callUserHookUrl` — `internal/server/api.go:353`.

| Aspecto | Comportamiento |
|---|---|
| URL | Fija, sin el `devid`. Una sola para las tres acciones |
| Método | `GET` siempre, sea cual sea el original |
| Contexto | `X-Rttys-Hook: true`, `X-Original-Method`, `X-Original-URL` |
| Cabeceras | Copia todas salvo `upgrade`, `connection`, `accept-encoding`. **Incluye `Cookie`** |
| Timeout | 3 s |
| `UserHookUrl == ""` | `return true` — **permite** |
| Error de red | `return false` — deniega |
| Respuesta ≠ 200 | `return false` — deniega |

Invocado desde `/connect/:devid` (api.go:215), `/cmd/:devid` (api.go:241) y
`httpProxyRedirect` (http.go:286), que sirve `/web/:devid/:proto/:addr/*path`.
Las tres rutas heredadas quedan cubiertas.

---

## 4. Lógica del webhook

```
GET http://n8n:5678/webhook/kvm-hook
    X-Rttys-Hook: true
    X-Original-URL: /connect/zsb25f8?group=
    X-Original-Method: GET
    Cookie: sid=<sesión del operador>

1. Extraer devid y acción de X-Original-URL
   · sin devid, o URL no reconocida → 403

2. GET http://glkvm_cloud:8180/api/devices
     Host: kvm.oob.local
     Cookie: <la recibida>
   · fallo, timeout, o ok:false → 403

3. ¿devid en data.items[].ddns?
   · no → 403                                    [remedia P0-6]

4. GET http://glkvm_cloud:8180/api/me  (mismo Host y cookie)
   → username, role, para la traza

5. acción == connect            → 200
   acción == cmd | web          → ¿aprobación vigente para (username, devid)?
                                   → 200 / 403

6. Registrar la decisión
```

**Criterio de éxito en los pasos 2 y 4: el campo `ok` del cuerpo, nunca el código
HTTP.** La API devuelve `200` con `{"ok":false,"code":"AUTH_REQUIRED"}` cuando
rechaza. Un webhook que compruebe el estado HTTP aprobará peticiones no
autenticadas.

### 4.1 Presupuesto de latencia

Dos llamadas HTTP dentro del host más una lectura de estado, contra un límite de
3 s. Debe **medirse antes de activar el hook**, ejecutando las mismas llamadas
desde el contenedor de n8n. Superar el timeout equivale a denegar todo.

---

## 5. Alcance del control: qué cubre y qué no

**Cubierto.** Las tres rutas heredadas del puerto 8180 (`/connect/`, `/cmd/`,
`/web/`), que son las que dan acceso a consola, comando y proxy.

**Vía paralela acotada.** El puerto 10443 (`ListenHttpProxy`) es un listener
independiente que no pasa por el `gin.Engine` ni por el grupo `authorized`. No
tiene autenticación propia: consume un vale de un solo uso (`rttysid` → cookie
`rtty-http-sid`) emitido por `httpProxyRedirect` **después** de que el hook
apruebe. El control está en origen. Sin cookie válida responde el HTML de error.

Dos matices que quedan fuera del alcance del hook:

- El `rttysid` viaja en la URL y luego en cookie, en claro, en el puerto 10443.
  Quien observe la URL tiene la sesión.
- `httpProxySessionsClean` expira las sesiones cada 30 s. **El hook autoriza la
  emisión, no la vida posterior:** una sesión ya aprobada sigue activa aunque la
  aprobación se revoque.

**Fuera de alcance por diseño.** El nivel 2 (`192.168.0.36` directo) no pasa por
rttys ni por el hook. Ver §6.

---

## 6. El hook introduce una dependencia, y por qué es aceptable

`callUserHookUrl` falla cerrado. Con `user-hook-url` configurado, **si n8n no
responde en 3 s, toda apertura de consola y todo comando devuelven 403**. El
enclave dependería de n8n para acceder al KVM durante el incidente en el que n8n
podría ser precisamente lo que está caído.

Lo que lo hace aceptable es el modelo de dos niveles ya existente, sostenido por
dos decisiones del informe de auditoría de Fase 8: **D1** (el KVM queda fuera del
tailnet) y **D2** (break-glass por la web UI local del dispositivo). El nivel 2 es
LAN-only y no atraviesa rttys. Sigue siendo break-glass sin gobierno.

**Formulación explícita:** el hook gobierna el nivel 1, que es la vía normal. El
nivel 2 queda como recurso deliberadamente exento de controles, auditado *a
posteriori* y no en tiempo real. La defensa en profundidad exige una vía de
emergencia sin gobierno; la honestidad consiste en documentarla, no en fingir que
está cubierta.

Esto debe quedar escrito **antes** de activar el hook, no descubrirse cuando
falle.

---

## 7. Decisión de política pendiente

¿El rol `admin` se exime de la comprobación de dispositivo?

- **Exento** — reproduce el comportamiento actual de `ListDevices`, que ya exime
  al admin. Coherente con el producto, y el admin conserva acceso si la
  configuración de grupos se corrompe.
- **No exento** — más estricto y más coherente con la regla de dos personas de la
  Fase 4d: nadie accede a un dispositivo sin asignación explícita.

Con F8-D8, la exención la aplica `ListDevices` por su cuenta: `/api/devices` como
admin devuelve todos los dispositivos. Para **no** eximirlo hay que añadir una
comprobación adicional en el webhook, consultando el rol de `/api/me`.

---

## 8. Verificación

Definida antes de construir. Un control no probado no cuenta.

| # | Prueba | Aprobado si |
|---|---|---|
| V1 | `operador1` sin grupo → `GET /connect/zsb25f8` | **403**. Hoy da `302 → /rtty/zsb25f8` |
| V2 | `operador1` con grupo TFM → `GET /connect/zsb25f8` | `302`, y `actor_name='operador1'` en `device_event_logs` |
| V3 | `admin` → `GET /connect/zsb25f8` | `302`. No romper la vía normal |
| V4 | n8n detenido → cualquier `/connect/` | `403`, **y nivel 2 (`192.168.0.36`) operativo** |
| V5 | Webhook responde 500 | `403` |
| V6 | `docker compose up --force-recreate` | `user-hook-url` sigue presente en `/home/rttys.conf` |
| V7 | `/cmd/` sin aprobación previa | `403` |
| V8 | Aprobación emitida por el propio solicitante | Rechazada |
| V9 | Cookie ausente o manipulada | `403`, sin caída del webhook |
| V10 | Latencia de los pasos 2 y 4 | Muy por debajo de 3 s, medido desde el contenedor de n8n |

**V1 es la prueba de remediación.** Es literalmente el comando ya ejecutado en
§1, esperando `403` en lugar de `302`.

**V6 es la crítica.** El modo de fallo abierto del hook es la ausencia de
configuración, y `/home/rttys.conf` se regenera desde `/tpl/rttys.conf.tmpl` en
cada arranque del contenedor. Un control escrito sobre el fichero renderizado
desaparece en el siguiente reinicio, sin ningún aviso, y devuelve el sistema al
estado del P0-6. Es el mismo patrón que `S01selfCloud` regenerando
`rtty-loop.sh` en el dispositivo (P1-1).

---

## 9. Restricción de implementación

`user-hook-url` **no está en la plantilla** `docker-compose/templates/rttys.conf.template`,
y el `render()` del entrypoint sólo sustituye `{{KEY}}` para las variables de su
lista, donde no figura ninguna clave de hook. No basta con una variable de
entorno: hay que modificar la plantilla, que es un fichero vendorizado del
fabricante.

Consecuencia: el cambio queda en el árbol de `glkvm-cloud/`, y una actualización
del vendor lo revertiría. Debe quedar registrado como divergencia respecto al
upstream.

---

## 10. Orden de construcción

1. Medir latencia de los pasos 2 y 4 desde el contenedor de n8n (V10)
2. Construir el webhook en n8n **sin activar el hook**; probarlo con `curl`
   simulando las cabeceras que envía rttys
3. Decidir §7 (exención del rol admin)
4. Añadir `user-hook-url` a la **plantilla**
5. `--force-recreate` y ejecutar V1–V9 en orden

Los pasos 1 a 3 no modifican el comportamiento del sistema. El paso 4 sí, y a
partir de ahí el hook está activo: un webhook mal construido deniega todo acceso
por el nivel 1.
