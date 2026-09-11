# Fase 8 · Mejora 1 — Cierre: hook de autorización del nivel 1

**Estado:** construido, activo y verificado. El P0-6 queda remediado para las
tres rutas heredadas. La aprobación de segunda persona para `cmd` y `web` no
está construida: ambas acciones deniegan incondicionalmente.

---

## 1. Resultado

Antes: cualquier cuenta con sesión válida en rttys alcanzaba la consola —y desde
ahí la shell— de cualquier dispositivo, con independencia de su asignación de
grupos. Verificado con `operador2`, cuenta sin grupo: `GET /connect/zsb25f8`
devolvía `302` hacia `/rtty/zsb25f8`.

Después: la misma petición devuelve `403`.

El control se ejerce en `user-hook-url`, que rttys consulta desde
`/connect/:devid` (api.go:215), `/cmd/:devid` (api.go:241) y `httpProxyRedirect`
(http.go:286), que sirve `/web/:devid/:proto/:addr/*path`. Las tres rutas
heredadas quedan cubiertas con una única configuración y sin parchear el binario.

---

## 2. Verificaciones

| # | Prueba | Resultado | Evidencia |
|---|---|---|---|
| V1 | `operador2` sin grupo → `/connect/zsb25f8` | **Aprobada** | `403` en navegador. Antes `302` |
| V2 | `operador1` con grupo TFM → `/connect/zsb25f8` | **Aprobada** | Acceso al dashboard |
| V3 | `admin` → `/connect/zsb25f8` | **Aprobada** | Acceso por intersección de grupos, no por exención |
| V4 | n8n detenido → `/connect/` | **Aprobada** | `403`, y `https://192.168.0.36` operativo |
| V5 | Error interno del flujo | **Aprobada tras corrección** | `throw` en el Code → `403`. Ver §3 |
| V6 | `--force-recreate` | **Aprobada** | `user-hook-url` en línea 59 de `/home/rttys.conf` |
| V7 | `/cmd/` sin aprobación previa | **Aprobada** | `POST` → `403`, cuerpo vacío, comando no ejecutado |
| V8 | Autoaprobación rechazada | **No aplica todavía** | Vive en el bloque de aprobación de segunda persona |
| V9 | Cookie ausente | **Reenunciada** | Ver §4 |
| V10 | Latencia | **Aprobada** | p50 103 ms, p95 135 ms, máx 151 ms, contra 3.000 |

V2 y V3 son las que distinguen un control de una avería: V1, V5, V7 y V9 las
superaría igual un flujo que denegase todo.

### Presupuesto de latencia

| Tramo | p50 | p95 |
|---|---|---|
| Flujo completo, medido desde el contenedor de n8n | 103 ms | 135 ms |
| — de los cuales, las cuatro llamadas al oráculo | ~4 ms | ~35 ms |
| Bridge `glkvm_cloud → n8n` | ~1 ms | ~5 ms |

El sumando dominante es la ejecución del flujo de n8n, no las llamadas HTTP que
el §4.1 del diseño presupuestaba. Consecuencia práctica: añadir nodos pesa más
que añadir consultas.

---

## 3. Hallazgo · El webhook falla abierto ante error interno del orquestador

`callUserHookUrl` falla cerrado ante error de red y ante respuesta distinta de
`200`. V4 lo confirma. Pero un error **dentro** del flujo de n8n no produce
ninguna de las dos cosas: con *Respond via 'Respond to Webhook' node*, un camino
que no alcanza un nodo de respuesta hace que n8n cierre la petición con `200`
por defecto, y rttys lo lee como aprobación.

No es teórico. Ocurrió dos veces durante la construcción, sin buscarlo:

- El nodo Code en modo *Run Once for Each Item* devolviendo un array →
  `A 'json' property isn't an object` → `200`.
- El nodo If con la condición configurada como `String` recibiendo un número →
  `Wrong type: '403' is a number but was expecting a string` → `200`.

Durante esos minutos el hook aprobaba todo mientras aparentaba estar roto.

**Vía de abuso.** El operador controla todas las cabeceras de la petición salvo
las tres que rttys fija con `Set`. Cualquier valor que provoque una excepción en
cualquier nodo produciría su propia aprobación. No se ha encontrado una, pero el
modo de fallo la haría explotable.

**Mitigación adoptada.** La salida de error de cada nodo se cablea al
`Respond to Webhook` que deniega (*Settings → On Error → Continue (using error
output)*). El principio:

> Todo conector de salida del flujo debe llegar a un nodo de respuesta. Una
> salida suelta no es un detalle del lienzo: es una aprobación silenciosa.

Verificado con `throw new Error('V5')` en la primera línea del Code → `403`.

**Consecuencia para el reconocimiento.** El §3 del reconocimiento describe el
modo de fallo abierto como "ausencia de configuración". Es incompleto: hay una
segunda forma, y es un error no capturado dentro del orquestador. La primera se
detecta con V6; la segunda sólo con V5.

---

## 4. Correcciones a documentos previos

**`docs/diseno-hook-autorizacion.md` §1.** El `total: 0` de `operador1` es
evidencia histórica: la cuenta fue asignada al grupo TFM posteriormente. Quien
reejecute el comando obtiene `total: 1`. La cuenta permanente para el caso
negativo es `operador2`.

**`docs/diseno-hook-autorizacion.md` §6.** "Falla cerrado" es cierto para caída
de n8n y para respuesta distinta de `200`, no para error interno del flujo. Ver §3.

**`docs/diseno-hook-autorizacion.md` §8, V9.** Mal enunciada. Sin cookie,
`httpAuth` rechaza con `401` antes de invocar el hook, de modo que la prueba
ejerce la primera capa y no el webhook. Para ejercer el webhook hace falta una
cookie con formato válido y sesión inexistente; el motivo esperado entonces es
`identidad no resuelta`.

**`docs/diseno-hook-autorizacion.md` §4, sobre `/cmd/`.** El hook se invoca
**antes** de `BindJSON` (api.go:241), así que el webhook nunca ve el comando:
sólo recibe `devid` y acción. Aprobar `/cmd/` es aprobar *cualquier* comando en
ese dispositivo. La política por comando no es construible en este punto de
control.

**`docs/api-reconocimiento-fase8.md` §3.** Añadir el segundo modo de fallo
abierto descrito en §3 de este documento.

---

## 5. Regla de instrumentación

Tres iteraciones se perdieron midiendo la salida del nodo Code en lugar del
código HTTP. Las tres tenían causas distintas —modo del Code, tipo de la
condición del If, salida de error sin cablear— y el mismo síntoma: el flujo
"decidía" `403` y rttys recibía `200`.

> En este flujo, la evidencia válida es el código HTTP que ve rttys. Nunca el
> cuerpo del webhook, nunca la salida del nodo Code, nunca lo que muestra la UI
> de n8n.

Instrumento de referencia, sin cookie y sin efecto sobre el dispositivo:

```bash
docker exec -i n8n node -e '
const http=require("http");
http.request({host:"localhost",port:5678,path:"/webhook/kvm-hook",method:"GET",
 headers:{"x-rttys-hook":"true","x-original-url":"/connect/zsb25f8","x-original-method":"GET"}},
 r=>{let b="";r.on("data",d=>b+=d);r.on("end",()=>console.log("status HTTP:",r.statusCode))}).end()'
```

Es la cuarta entrada de la serie del §1 del reconocimiento, esta vez en la fase
de construcción y no en la de reconocimiento. La quinta es el `grep` de busybox
sobre binarios, que devolvió cuatro de cinco coincidencias sin señal de
truncamiento.

---

## 6. Configuración final del flujo

```
Webhook ─→ Devices ─→ Me ─→ Users ─→ DeviceGroups ─→ Decidir ─→ If ─┬→ Respond 200
                                                          │         └→ Respond 403
                                                          └──── error ──→ Respond 403
                                                                  If error ──→ Respond 403
```

- **Webhook**: `GET /webhook/kvm-hook`, *Respond: Using 'Respond to Webhook' node*.
- **Cuatro HTTP Request**: `GET` contra `/api/devices`, `/api/me`, `/api/users`,
  `/api/device-groups` en `http://glkvm_cloud:8180`, con cabeceras `Host:
  kvm.oob.local` (literal) y `Cookie: {{ $('Webhook').item.json.headers.cookie }}`
  (expresión, sin `=` delante). *On Error: Continue*.
- **Decidir**: Code, *Run Once for All Items*. Salida de error cableada al
  `Respond` de `403`.
- **If**: condición **Number**, `{{ $json.status }}` **Equal** `200`. Rama *true*
  al `Respond` de `200`, rama *false* y salida de error al de `403`.
- **Dos Respond to Webhook**: *Respond With: No Data*, *Response Code* `200` y
  `403` como números literales.

La polaridad del If importa: comparando contra `200`, un `status` inesperado cae
en *false* y deniega. Comparando contra `403`, aprobaría.

Cadena lineal sin ramas condicionales en las llamadas: las cuatro se ejecutan
siempre, incluso cuando el rol es `user` y dos fallarán por permisos. Cuesta unos
4 ms y elimina el riesgo de una rama sin nodo de respuesta.

---

## 7. Pendientes

**Del propio hook:**

- Aprobación de segunda persona para `cmd` y `web`, con V8 dentro de ese bloque.
  Hoy ambas deniegan incondicionalmente.
- **Paginación.** `/api/devices` devuelve `pageSize` igual al número de elementos
  y `/api/users` no devuelve `total`. Con un dispositivo y tres cuentas no se
  distingue si hay límite de página. Si la lista crece, un dispositivo fuera de
  la primera página se leería como "no asignado".
- **C5 · alcance real de RA-2.** Falta comprobar si Authelia emite cookie sobre
  `.oob.local`, en cuyo caso lo que cruza el bridge en claro incluye la cookie de
  SSO y no sólo el `sid` de rttys.
- **Guardado de ejecuciones.** La salida del nodo Webhook contiene la cookie del
  operador y queda en la base de n8n. Decidir entre desactivar el guardado de
  ejecuciones correctas —perdiendo la traza— o llevar el almacenamiento en reposo
  a RA-2 de forma explícita.

**De higiene, antes de cerrar la sesión de trabajo:**

- Registrar en git la modificación de
  `docker-compose/templates/rttys.conf.template` como divergencia respecto al
  upstream (§9 del diseño). El bind mount es fichero a fichero, así que una
  actualización del vendor produciría conflicto visible, no reversión silenciosa.
- Cerrar desde la UI las sesiones de `admin`, `operador1` y `operador2` cuyos
  `sid` circularon durante la construcción. TTL de 24 h.
- `rm /tmp/rttys.bin` en el host y `rm /tmp/mide.js /tmp/mide2.js` en n8n.
- Borrar el flujo auxiliar `echo`: devuelve las cabeceras que recibe, sin
  autenticación, dentro de `oob-network`.

**Rotación a decidir:** el fichero `/home/rttys.conf` renderizado, con `token` y
`password` en claro, se volcó durante la construcción. El `token` es la
credencial de autenticación del dispositivo (P1-6).

---

## 8. Lo que este control no cubre

Sin cambios respecto al §5 y §6 del diseño y a RA-1:

- El nivel 2 (`https://192.168.0.36`) no atraviesa rttys ni el hook. V4 confirma
  que sigue operativo con n8n caído, que es lo que sostiene la vía de emergencia.
- El puerto 10443 consume un vale emitido *después* de que el hook apruebe. El
  control está en origen; una sesión ya emitida sobrevive a la revocación.
- Aprobar `/cmd/` aprueba cualquier comando, no uno concreto (§4).
