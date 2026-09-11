# Fase 8 · Mejora 1 — Riesgos aceptados antes de activar el hook

**Estado:** escrito antes de la activación. Ninguno de los riesgos de este
documento se descubrió al fallar; los tres son consecuencia conocida del diseño
(`docs/diseno-hook-autorizacion.md`).

**Condición de uso:** este documento debe estar en el repositorio y referenciado
desde el README **antes** de añadir `user-hook-url` a la plantilla. A partir de
ese momento el comportamiento del sistema cambia y la marcha atrás exige un
reinicio de contenedor.

---

## 1. Qué cambia al activar

Hoy `user-hook-url` está ausente y `callUserHookUrl` devuelve `true` sin
consultar nada. El nivel 1 no tiene autorización por dispositivo: cualquier
cuenta con sesión válida alcanza la consola —y desde ahí la shell— de cualquier
`devid`, aunque `GET /api/devices` le devuelva lista vacía. Es el P0-6, y está
abierto.

Al configurar `user-hook-url` se remedia el P0-6 y, en el mismo acto, el acceso
por el nivel 1 pasa a depender de n8n. `callUserHookUrl` falla cerrado: error de
red, respuesta distinta de `200` o más de 3 s de latencia equivalen a denegar.
Con el hook activo, **n8n caído es nivel 1 caído**: ni consola, ni comando, ni
proxy.

Verificado en el árbol vendorizado y contrastado contra el binario en ejecución
(`/usr/bin/rttys`): las tres rutas heredadas invocan el hook —`/connect/:devid`
(api.go:215), `/cmd/:devid` (api.go:241) y `httpProxyRedirect` (http.go:286),
que sirve `/web/:devid/:proto/:addr/*path`.

---

## 2. Riesgos aceptados

### RA-1 · El nivel 2 queda exento de gobierno, por diseño

El acceso directo al dispositivo (`https://192.168.0.36`) no atraviesa rttys. Un
operador con la credencial local abre la web UI del GL-RM1, pulsa el control de
potencia y reinicia DC01 sin pasar por el hook, por n8n ni por IRIS.

**Por qué se acepta.** Es la contrapartida necesaria de RA-1 sobre la
dependencia introducida en §1. El modelo de dos niveles ya existía y lo sostienen
dos decisiones del informe de auditoría de Fase 8: **D1** (el KVM queda fuera del
tailnet) y **D2** (break-glass por la web UI local). La defensa en profundidad
exige una vía de emergencia que no dependa de la infraestructura que puede estar
caída; el enclave entero se argumenta sobre ese principio. Cerrar el nivel 2
convertiría al orquestador en punto único de fallo de la vía de recuperación.

**Qué implica asumirlo.** El nivel 2 no es prevenible, sólo detectable, y la
detección no puede residir en el dispositivo:

- No hay modelo de autorización por acción. `htpasswd` de 44 bytes, `auth.yaml`
  a `{}`, `totp.secret` vacío. No existe separación que permita conceder consola
  y negar potencia.
- No hay registro persistente exportable. El syslog es un buffer de 22 h
  saturable (P2-7) y `nginx-kvmd.conf` lleva `access_log off`. La tabla
  `device_event_logs` no ve el nivel 2: sus eventos proceden todos de rttys.

**Ampliación (mejora 6).** La descripción de esta vía como "la web UI local del
dispositivo" es incompleta. El inventario de la mejora 6 encontró `dropbear`
escuchando en `0.0.0.0:22` con autenticación por contraseña habilitada para
`root`: una segunda vía a shell que no pasa por kvmd, ni por nginx, ni por
`auth_request`. Documentada como RA-4 en
`docs/mejora6-endurecimiento-dispositivo.md`, con su justificación y su vía de
remediación. El sondeo de `/api/atx/click` descrito abajo como pendiente **ya se
ejecutó**: responde `401`, de modo que la premisa de este riesgo —"operador con
credencial local", no "cualquier equipo de la LAN"— queda verificada.  

**Control compensatorio.** El observador ha de ser independiente del dispositivo:
Wazuh en DC01 registrando un apagado inesperado, o la caída de su heartbeat vista
desde el enclave. Auditoría *a posteriori*, no control en tiempo real.

Ambos puntos están pendientes de verificación final (`docs/api-reconocimiento-fase8.md`
§6, hueco 2: 8 de 110 endpoints del dispositivo verificados). Si al sondear
`/api/atx/click` resultara no exigir credencial, el riesgo cambia de naturaleza:
dejaría de ser "operador con credencial local" para ser "cualquier equipo de
`192.168.0.0/24`", y RA-1 tendría que reevaluarse antes de darlo por aceptado.

### RA-2 · Cookie de sesión en claro dentro de `oob-network`

Decisión F8-D7. Ambos sentidos del flujo van sin TLS dentro del bridge de
Docker: rttys → `http://n8n:5678/webhook/kvm-hook`, y n8n →
`http://glkvm_cloud:8180/...` con cabecera `Host: kvm.oob.local`.

`callUserHookUrl` copia **todas** las cabeceras de la petición original salvo
`upgrade`, `connection` y `accept-encoding`. Incluye `Cookie`. Cualquier
contenedor con acceso a `oob-network` puede observar la cookie de sesión del
operador.

**Por qué se acepta.** El tráfico no abandona el host. La alternativa TLS mete a
Traefik en el camino crítico de la vía de recuperación, obliga a montar
`ca-bundle-oob.crt` en un contenedor de terceros fijado por digest, y exige un
alias de red porque `glkvm_cloud` no está cubierto por el certificado
`*.oob.local`.

**Excepción explícita.** Contradice el argumento de que todo servicio del enclave
usa el ancla de confianza propia. Figura aquí precisamente por eso: es una
excepción acotada y consciente, no un olvido.

**Pendiente de acotar antes de activar.** Si Authelia emite su cookie sobre el
dominio `.oob.local` y no sobre el host concreto, el navegador la envía también a
`kvm.oob.local` y lo que cruza el bridge en claro no es sólo el `sid` de rttys,
sino la cookie de SSO del enclave. La captura del paso de activación permisiva
(§4) lo resuelve por observación. Si se confirma, la magnitud de RA-2 aumenta y
hay que decidir si se filtra la cabecera antes de reenviarla.

### RA-3 · El hook autoriza la emisión, no la vida de la sesión

El puerto 10443 (`ListenHttpProxy`) es un listener independiente que no pasa por
el `gin.Engine` ni por el grupo `authorized`. Consume un vale de un solo uso
(`rttysid` → cookie `rtty-http-sid`) emitido por `httpProxyRedirect` **después**
de que el hook apruebe. El control está en origen, y eso basta para impedir la
emisión no autorizada, pero:

- el `rttysid` viaja en la URL y luego en cookie, en claro, por el puerto 10443:
  quien observe la URL tiene la sesión;
- `httpProxySessionsClean` expira sesiones cada 30 s, pero una sesión ya emitida
  sigue viva aunque la aprobación se revoque.

**Por qué se acepta.** Revocación en caliente exigiría intervenir el listener del
proxy, que es código del fabricante fuera del alcance de la mejora. La ventana
está acotada por el ciclo de limpieza y por la propia naturaleza del vale.

---

## 3. Marcha atrás

Quitar la línea `user-hook-url` de
`docker-compose/templates/rttys.conf.template` y ejecutar
`docker compose up --force-recreate` desde el directorio de Fase 8. El sistema
vuelve al estado actual: fail-open, P0-6 abierto, nivel 1 accesible.

Mientras dure la reversión el nivel 2 sigue operativo, que es justamente lo que
RA-1 compra.

**No hay marcha atrás por fichero renderizado.** `/home/rttys.conf` se regenera
desde la plantilla en cada arranque: editarlo no revierte nada de forma
duradera, y editarlo para *activar* tampoco persiste. Es el mismo patrón que
`S01selfCloud` regenerando `rtty-loop.sh` en el dispositivo (P1-1), y la razón de
ser de la prueba V6.

---

## 4. Condiciones que deben cumplirse antes de activar

| # | Condición | Estado |
|---|---|---|
| C1 | Este documento en el repositorio y referenciado desde el README | |
| C2 | Latencia de los pasos 2 y 4 del webhook medida desde el contenedor de n8n, muy por debajo de 3 s (V10) | |
| C3 | Webhook desplegado en modo **permisivo** (registra y devuelve `200` incondicionalmente) | |
| C4 | Cabeceras reales capturadas para las tres acciones (`connect`, `cmd`, `web`) | |
| C5 | Alcance real de RA-2 acotado con la captura de C4 | |
| C6 | Decidida la política del §7 del diseño (exención del rol `admin`) | |

C3 merece justificación: activar el hook contra un webhook permisivo deja el
sistema funcionalmente como está hoy —fail-open, que es el estado actual del
P0-6— y a cambio entrega las cabeceras reales, la medición de V10 con tráfico de
producción y la prueba V6. Sustituye a la simulación con `curl`, que asume
precisamente lo que hay que comprobar, y a la captura HAR que el reconocimiento
declaraba bloqueante.

El riesgo de C3 es que la dependencia de §1 ya está viva: n8n caído deniega todo
el nivel 1 aunque el webhook no decida nada todavía.

---

## 5. Divergencia respecto al upstream

`user-hook-url` no está en la plantilla del fabricante y el `render()` del
entrypoint sólo sustituye `{{KEY}}` para las variables de su lista, donde no
figura ninguna clave de hook. Una variable de entorno no basta: hay que modificar
un fichero vendorizado.

Consecuencia: el cambio vive en el árbol de `glkvm-cloud/` y una actualización
del vendor lo revertiría en silencio, devolviendo el sistema al estado del P0-6.
Debe quedar registrado como divergencia y verificarse tras cada actualización.

---

## 6. Regla de entradas de confianza para el webhook

Derivada de la lectura de `callUserHookUrl`: el bucle copia todas las cabeceras
del cliente con `Add` **antes** de los tres `Set` de identificación. Sólo
`X-Rttys-Hook`, `X-Original-Method` y `X-Original-URL` no son falsificables por
el operador, porque `Set` sobrescribe. Todo lo demás que llegue al webhook viene
de su navegador.

Ninguna señal de aprobación puede leerse de una cabecera entrante. El estado de
aprobación vive en n8n (F8-D6) y la identidad se resuelve consultando el oráculo
con la cookie recibida (F8-D8), nunca aceptando lo que la petición declare.
