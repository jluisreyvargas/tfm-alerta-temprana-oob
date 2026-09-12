# Fase 8 · Mejora 1 — Construcción del webhook `kvm-hook`

**Alcance de esta entrega:** pasos 1, 2, 3 y 5 del §4 del diseño. Las acciones
`cmd` y `web` deniegan incondicionalmente; la aprobación de segunda persona
queda como bloque de trabajo separado.

**Estado del sistema al empezar:** `user-hook-url` ya está activo en la línea 59
de `/home/rttys.conf` y el webhook aprueba todo. Al sustituir la lógica, el
comportamiento cambia en la misma guardada del flujo: no hay `--force-recreate`
de por medio.

---

## 1. Topología

Cadena lineal, sin ramas condicionales:

```
Webhook → Devices → Me → Users → DeviceGroups → Decidir → Respond
```

Las cuatro llamadas se ejecutan siempre. Para un rol `user`, `Users` y
`DeviceGroups` devolverán `ok:false` por falta de permisos: es esperado y la
lógica no los consulta en ese camino.

**Por qué sin ramas.** `callUserHookUrl` interpreta cualquier cosa que no sea
`200` en menos de 3 s como denegación, incluida la ausencia de respuesta. Una
rama que no alcanza un nodo `Respond to Webhook` deniega por timeout y el
diagnóstico apunta a la red, no al flujo. Con un único camino y un solo nodo de
respuesta, ese modo de fallo no existe.

Coste: dos llamadas HTTP adicionales, del orden de 4 ms sobre los ~50 ms
medidos en V10.

---

## 2. Configuración de los nodos

### Webhook

- Método `GET`, path `kvm-hook`
- *Respond*: `Using 'Respond to Webhook' node`
- Nombre del nodo: **`Webhook`** (las expresiones lo referencian por ese nombre)

### Devices · Me · Users · DeviceGroups

Cuatro nodos **HTTP Request**, idénticos salvo la URL:

| Nodo | URL |
|---|---|
| `Devices` | `http://glkvm_cloud:8180/api/devices` |
| `Me` | `http://glkvm_cloud:8180/api/me` |
| `Users` | `http://glkvm_cloud:8180/api/users` |
| `DeviceGroups` | `http://glkvm_cloud:8180/api/device-groups` |

En los cuatro:

- Método `GET`
- **Send Headers** activado, dos cabeceras:
  - `Host` → `kvm.oob.local` (texto literal, sin expresión)
  - `Cookie` → expresión: `{{ $('Webhook').item.json.headers.cookie }}`
- *Settings → On Error*: **Continue (using error output)** → no, usar
  **Continue** a secas, para que el fallo siga la cadena
- *Settings → Always Output Data*: activado

> El campo `Cookie` debe estar en modo expresión (conmutador *fx*) y el valor
> **no** lleva `=` delante. El `=` es el prefijo interno que añade n8n; si se
> escribe a mano, rttys recibe `=sid=…`, no encuentra la cookie y responde
> `AUTH_REQUIRED` — indistinguible de una sesión rechazada.

### Decidir

Nodo **Code**, modo *Run Once for All Items*. Contenido en §3.

### Respond

Nodo **Respond to Webhook**:

- *Respond With*: `JSON`
- *Response Body*: `{{ JSON.stringify($json.body) }}`
- *Options → Response Code*: `{{ $json.status }}`

rttys ignora el cuerpo; sólo lee el código. El cuerpo existe para depuración y
para las pruebas con `curl`.

---

## 3. Nodo `Decidir`

```js
// Fase 8 · mejora 1 — decisión de autorización del hook de rttys.
// Entradas de confianza: sólo X-Rttys-Hook, X-Original-Method, X-Original-URL
// (rttys las fija con Set, sobrescribiendo lo que mande el cliente) y la
// cookie validada contra el oráculo. Nada más de la petición es fiable.

const hdrs = $('Webhook').item.json.headers || {};
const raw = String(hdrs['x-original-url'] || '');
const metodo = String(hdrs['x-original-method'] || '');
const esHook = String(hdrs['x-rttys-hook'] || '') === 'true';

const traza = {
  ts: Math.floor(Date.now() / 1000),
  url: raw,
  metodo,
  accion: null,
  devid: null,
  username: null,
  role: null,
  decision: 'deny',
  motivo: null,
};

const salir = (status, motivo) => {
  traza.decision = status === 200 ? 'allow' : 'deny';
  traza.motivo = motivo;
  return [{ json: { status, body: { decision: traza.decision, motivo }, traza } }];
};

// Sobre válido sólo si ok === true. Un cuerpo sin campo `ok` (404 de la API,
// HTML del middleware WebUIHost) no es aprobación.
const sobre = (nombre) => {
  try {
    const j = $(nombre).item.json;
    return j && j.ok === true ? j : null;
  } catch (e) {
    return null;
  }
};

// ---- Paso 1: acción y devid --------------------------------------------
if (!esHook) return salir(403, 'sin X-Rttys-Hook');

const ruta = raw.split('?')[0];
const m = ruta.match(/^\/(connect|cmd|web)\/([A-Za-z0-9_-]{1,64})(?:\/|$)/);
if (!m) return salir(403, 'URL no reconocida');

const accion = m[1];
const devid = m[2];
traza.accion = accion;
traza.devid = devid;

// ---- Paso 2: identidad --------------------------------------------------
const me = sobre('Me');
const usuario = me && me.data && me.data.user;
if (!usuario || !usuario.username) return salir(403, 'identidad no resuelta');

traza.username = usuario.username;
traza.role = usuario.role;

// ---- Paso 3: autorización sobre el dispositivo --------------------------
const devices = sobre('Devices');
if (!devices || !devices.data || !Array.isArray(devices.data.items)) {
  return salir(403, 'oraculo no disponible');
}

const item = devices.data.items.find((d) => d.ddns === devid);

if (usuario.role !== 'admin') {
  // Camino normal: ListDevices ya filtra por grupo. Si no está, no procede.
  if (!item) return salir(403, 'dispositivo no asignado');
} else {
  // El admin ve todos los dispositivos, así que el oráculo no discrimina.
  // C6: no se exime. Hay que resolver su asignación por otra vía.
  if (!item) return salir(403, 'dispositivo inexistente');
  if (!item.deviceGroupId) return salir(403, 'dispositivo sin grupo');

  const users = sobre('Users');
  const grupos = sobre('DeviceGroups');
  if (!users || !grupos) return salir(403, 'resolucion de grupos no disponible');

  const fila = (users.data.items || []).find((u) => u.username === usuario.username);
  if (!fila) return salir(403, 'usuario no listado');

  const mios = (fila.userGroupList || []).map((g) => g.userGroupId);
  const grupo = (grupos.data.items || []).find((g) => g.id === item.deviceGroupId);
  if (!grupo) return salir(403, 'grupo de dispositivo no encontrado');

  const suyos = (grupo.userGroupList || []).map((g) => g.userGroupId);
  if (!mios.some((id) => suyos.includes(id))) {
    return salir(403, 'admin sin asignacion al grupo');
  }
}

// ---- Paso 4: política por acción ---------------------------------------
if (accion === 'connect') return salir(200, 'consola autorizada');

// cmd y web exigen aprobación de segunda persona, aún no construida.
return salir(403, 'aprobacion no implementada');
```

La traza no contiene la cookie. Registra `username`, `devid`, acción, decisión y
motivo, que es lo que pide el paso 6 del §4 del diseño.

---

## 4. Pruebas antes de dar el control por bueno

Con el flujo guardado, navegando en ventana privada:

| # | Sujeto | Acción | Esperado |
|---|---|---|---|
| V1 | `operador2` | `/connect/zsb25f8` | **403**. Hoy da `302` |
| V2 | `operador1` | `/connect/zsb25f8` | `302`, y `actor_name='operador1'` en `device_event_logs` |
| V3 | `admin` | `/connect/zsb25f8` | `302` vía intersección de grupos, no por exención |
| V7 | `operador1` | `/cmd/zsb25f8` | `403`, motivo `aprobacion no implementada` |
| V9 | sin cookie | `/connect/zsb25f8` | No llega al hook: `httpAuth` corta antes |

V9 merece un matiz. Sin cookie, rttys rechaza en `httpAuth` y el webhook nunca
se invoca, así que la prueba no ejerce el flujo. Para ejercerlo hace falta una
cookie con formato válido y sesión inexistente, y entonces el motivo esperado es
`identidad no resuelta`.

**V1 y V2 tienen que pasar juntas.** Un webhook roto —cookie mal formada,
expresión sin resolver— deniega el 100% de las peticiones y superaría V1, V7 y
V9 sin ejercer ninguna lógica. Sólo V2 y V3 distinguen "deniega porque decide"
de "deniega porque está roto".

Después, repetir V10 con el flujo completo: cuatro llamadas y un Code node pesan
más que el flujo vacío medido.

---

## 5. Marcha atrás

Sustituir el nodo `Decidir` por uno que devuelva `{ status: 200 }` restituye el
estado permisivo actual sin tocar rttys. Para desactivar el hook por completo,
quitar la línea 59 de la plantilla y `--force-recreate`.

---

## 6. Pendientes que esto no cierra

- **Estado de aprobación y emisión** para `cmd` y `web`, con V8 (rechazo de la
  autoaprobación) dentro de ese bloque, no del hook.
- **Paginación.** `/api/devices` devuelve `pageSize` igual al número de
  elementos y `/api/users` no devuelve `total`. Con un dispositivo y tres
  cuentas no se distingue si hay límite de página. Si la lista crece, un
  dispositivo fuera de la primera página se leería como "no asignado" y el hook
  denegaría por ausencia.
- **C5 · alcance real de RA-2.** La captura de `/connect/` muestra que rttys
  envía la cookie; falta comprobar si Authelia emite sobre `.oob.local` y lo que
  cruza es además la cookie de SSO.
- **Guardado de ejecuciones.** La salida del nodo `Webhook` contiene la cookie y
  queda en la base de n8n. Con el hook en producción conviene desactivar el
  guardado de ejecuciones correctas y conservar la traza del nodo `Decidir` por
  otra vía, o llevar el almacenamiento en reposo a RA-2 de forma explícita.
