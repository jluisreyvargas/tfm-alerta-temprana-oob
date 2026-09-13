# Decisión — La GUI de Velociraptor queda fuera del SSO de Authelia

**Fecha:** 2026-09-13
**Decide:** Jose Luis Rey
**Afecta a:** `PLAN-P1-1a-borde-tls.md`, sección 3 (tabla de política por servicio)
**Estado del servicio:** detrás de Traefik, con `secure-headers@file`, sin `authelia@file`

---

## Qué se decide

La GUI de Velociraptor (`velociraptor.oob.local`) se sirve a través de Traefik con
el certificado del enclave y `secure-headers@file`, **sin el middleware de
Authelia**. La autenticación la sigue proporcionando el `Basic` propio de
Velociraptor.

Esto se aparta de la tabla de la sección 3 del plan, que asignaba
`secure-headers` + `authelia` a este servicio con el motivo «interfaz forense con
capacidad de colección». El motivo sigue siendo válido; lo que no es viable es el
mecanismo.

Es la segunda excepción al SSO del enclave, después del KVM. Se documenta por la
misma razón que aquella: lo que separa una asimetría deliberada de un olvido es
que esté escrita, con su fecha, su medición y su criterio de revisión.

---

## Por qué: la medición

`forwardAuth` de Authelia y un backend con HTTP Basic Auth son incompatibles.
Authelia consume la cabecera `Authorization`, así que la credencial del backend
nunca llega a él.

Con el router ya montado y `authelia@file` aplicado:

| Petición | Respuesta |
|---|---|
| Sin credencial, a `https://velociraptor.oob.local/` | `302` → `auth.oob.local/?rd=...` |
| Sin credencial, a `.../app/index.html` | `302` → `auth.oob.local/?rd=...` |
| **Con credencial Basic, a `.../app/index.html`** | **`401`, `WWW-Authenticate: Basic realm="Authorization Required"`** |
| Con la misma credencial, al backend directo `127.0.0.1:8889` | `200` |
| Sin credencial, al backend directo | `401`, `WWW-Authenticate: Basic realm="Restricted"` |

**El `realm` es lo que identifica al emisor.** Velociraptor responde
`realm="Restricted"`; el `401` que llega a través de Traefik dice
`realm="Authorization Required"`, que no es de Velociraptor: es de Authelia.
Authelia interpreta la credencial `admin` como un intento de autenticarse contra
ella misma con un usuario que no existe en su base —el único usuario del enclave
es `jose`— y responde `401` en lugar de redirigir al login.

En el navegador el efecto es un bucle: el `401` del flujo hace que el navegador
guarde y reenvíe la credencial en cada petición siguiente, y Authelia la
rechaza cada vez. Lo que el operador observa es «la GUI me pide credenciales y no
me las admite», sin ninguna indicación de cuál de los dos controles está
rechazando.

`GUI.authenticator.type: Basic` está declarado en
`velociraptor-config/server.config.yaml:124`.

### Por qué el patrón validado no cubría este caso

El piloto de MinIO y el precedente de Rocket.Chat establecieron que `forwardAuth`
no rompe WebSocket ni aplicaciones con sesión propia. Los dos usan sesión con
cookie. Ninguno usa Basic. El riesgo R2 del plan —«hay que verificarlo servicio
por servicio, no asumirlo»— era exactamente esto, y el fallo apareció en el
primer servicio que no compartía el mecanismo.

---

## Las alternativas descartadas, y con qué criterio

**OIDC contra Authelia.** Es la integración correcta y la que recomienda la
propia documentación de Velociraptor, que desaconseja `Basic` fuera de
laboratorio porque las contraseñas se almacenan con SHA-256 salteado, verificado
en cada petición HTTP, y son forzables offline si alguien se hace con el
almacén. Authelia es proveedor OpenID Connect y Velociraptor soporta
`type: oidc`.

Se descarta **por alcance, no por mérito**: exige levantar el proveedor OIDC en
Authelia con su cliente, secreto y URI de redirección, y reconfigurar el
autenticador de la herramienta forense. Es trabajo propio, con su plan y su
verificación, no un paso dentro de la Fase C.

Queda como **mejora identificada**, no como pendiente sin dueño. Si se aborda,
hay un detalle a tener en cuenta: cuando se asignan roles automáticamente vía
OIDC, se conceden en **todos** los orgs del servidor. Con un solo org es
irrelevante hoy, pero deja de serlo en cuanto haya más.

**Autenticador de cabecera de confianza (`Remote-User`).** Se propuso durante la
sesión y **se descartó al comprobar que no existe**. Los autenticadores
documentados de Velociraptor son `Basic`, los OAuth2 (GitHub, Azure, Google),
`oidc`, `saml` y `multi`. No hay autenticador de cabecera.

La forma en que se descartó importa: fue lo único de la sesión que no cayó por
medición del sistema sino por consultar la documentación antes de configurarlo.
De haberse aplicado a ciegas, un campo no reconocido habría hecho que
Velociraptor arrancase con su autenticador por defecto, con el operador creyendo
que el SSO estaba integrado. Un mecanismo de autenticación configurado sobre una
suposición es precisamente el defecto que este proyecto documenta.

**Dejar el router con Authelia y el 8889 abierto.** Descartado por ser el peor de
los tres estados posibles: el servicio parece protegido, no es usable por el
nombre, y sigue accesible por el puerto directo. Es la situación que la sección 6
del plan describe para el dashboard de Wazuh.

---

## Lo que esta decisión acepta

1. **Velociraptor autentica con un solo usuario `admin` y sin segundo factor.**
   Es la interfaz con capacidad de colección forense sobre todos los endpoints
   del enclave, y es la única UI relevante sin 2FA. El riesgo es real y no se
   compensa con el `secure-headers`.
2. **El cierre del 8889 (Fase D) sigue siendo necesario**, y por el mismo motivo
   que antes: un servicio proxificado con la puerta de atrás abierta equivale a
   uno no proxificado. Aquí no hay agravante de exposición añadida —el backend
   pide su Basic en los dos caminos— pero sí de coherencia del inventario.
3. **La regla de Authelia para `velociraptor.oob.local` se retiró** de
   `configuration.yml`. Una regla que ningún router consulta es un artefacto que
   documenta una protección inexistente: el mismo mecanismo que el middleware
   comentado de Wazuh. Si se adopta OIDC, la regla no vuelve: el flujo sería
   distinto.
4. **Revisión:** si se aborda la integración OIDC, esta decisión se revisa
   entera. Mientras tanto, cualquier cambio que añada usuarios a la GUI de
   Velociraptor obliga a reconsiderar el punto 1, porque el argumento de «un solo
   operador» deja de sostenerse.

---

## Efecto secundario verificado

Sin `forwardAuth` delante, **el riesgo R3 del plan desaparece para este
servicio**. Verificado por comportamiento desde el W11: la GUI carga, el listado
de clientes se puebla en vivo —que es lo que usa el WebSocket— y la descarga de
un JSON de resultado funciona, lo que ejercita además el `public_url` corregido.

Es un beneficio colateral de una decisión tomada por otro motivo, y conviene no
confundirlo con una justificación: si se adopta OIDC, R3 habrá que verificarlo de
nuevo.

---

## Comparación con la excepción del KVM

Las dos excepciones al SSO del enclave tienen motivos distintos y conviene no
tratarlas como un mismo caso:

| | KVM (`kvm.oob.local`) | Velociraptor (`velociraptor.oob.local`) |
|---|---|---|
| Motivo | Camino de recuperación: una dependencia de autenticación reproduce el problema que el enclave evita | Incompatibilidad técnica medida entre `forwardAuth` y Basic Auth |
| ¿Podría integrarse? | No se quiere | Sí, vía OIDC; descartado por alcance |
| Autenticación propia | Sí, rttys | Sí, Basic de Velociraptor |
| Riesgo residual | P0-6, remediado (ver `cierre-mejora1-hook.md`) | Un solo usuario, sin 2FA |

La del KVM es una asimetría **deliberada de diseño**. Esta es una **limitación
aceptada**, con la integración correcta identificada y pospuesta. La distinción
importa para el TFM: la primera defiende una posición, la segunda reconoce una
deuda.

---

## Aportación al TFM

**Dos controles correctos que se anulan al componerse.** Authelia funciona.
El Basic de Velociraptor funciona. Puestos en serie, el resultado es un servicio
al que no se puede entrar, y el síntoma —un diálogo de credenciales que no
admite la credencial— no señala a ninguno de los dos. Solo el `realm` de la
cabecera `WWW-Authenticate` distingue quién está rechazando, y eso no es visible
en un navegador.

Es la misma familia que la composición del P0-6 con la exclusión del KVM de
Authelia, y que el caso del acceso del analista a Wazuh: el defecto no está en
ningún artefacto, está en la relación entre dos que son correctos por separado.
Con una diferencia útil: aquí el fallo es ruidoso. La composición rompe el
servicio en vez de dejarlo abierto, así que se descubre el primer día en lugar de
en una auditoría.

**Un plan que asigna la misma política a servicios que no comparten mecanismo.**
La tabla de la sección 3 del plan distinguía servicios por lo que hacen —«gestión
de casos», «interfaz forense»— y no por cómo autentican. Ese eje es el que
determinó el resultado. La verificación servicio por servicio que exigía R2 no
era una precaución de proceso: era la única forma de descubrirlo, porque la
información que decidía el resultado no estaba en la tabla.
