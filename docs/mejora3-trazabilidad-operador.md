# Fase 8 · Mejora 3 — Trazabilidad del operador

**Estado:** resuelta. Se resolvió con cuentas nominales, no con PROXY protocol.
Este documento registra por qué, qué cubre el registro resultante y qué no.

**Relación con el informe de auditoría:** cierra el P1-4, con la reformulación
que introdujo el reconocimiento de Fase 8.

---

## 1. El diagnóstico original era correcto en el síntoma y equivocado en la causa

El informe de auditoría concluye que la atribución es inexistente porque
`client_ip` registra `172.18.0.1` en todos los eventos, que es la puerta de
enlace del bridge de Docker y no la dirección del analista. La mejora propuesta
era habilitar PROXY protocol en Traefik para que la IP real llegara a rttys.

El reconocimiento encontró que la tabla `device_event_logs` tiene además
`actor_user_id` y `actor_name`, poblados por `principalFromCtx`
(`internal/server/api.go:432`), y que el campo se rellena en todos los eventos
originados por un operador. El control no faltaba: **sólo existía un principal**.
La tabla `users` contenía una única fila, `admin`, de modo que `actor_name`
siempre valía lo mismo.

`client_ip` era la pista equivocada. Con credencial compartida, la IP del
analista tampoco identifica a nadie: dice desde qué máquina se hizo, no quién lo
hizo. Y en un enclave donde el acceso normal pasa por un contenedor, la IP
correcta sería la de ese contenedor la mitad de las veces.

---

## 2. Cómo se resolvió

Creando cuentas nominales. La plataforma pasó de una fila en `users` a tres:

| Cuenta | Rol | Grupo de usuarios | Papel |
|---|---|---|---|
| `admin` | `admin` | TFM | Administración |
| `operador1` | `user` | TFM | Analista con asignación |
| `operador2` | `user` | (ninguno) | Caso negativo permanente de verificación |

No se tocó Traefik. No se habilitó PROXY protocol. `client_ip` sigue valiendo
`172.18.0.1` en todos los eventos y es correcto que así sea: refleja el salto
real de red, y la identidad la aporta otro campo.

**Verificado en base de datos**, con los eventos acumulados hasta el 11 de
septiembre de 2026:

| `event_type` | Eventos | `actor_name` poblado |
|---|---|---|
| `remote_control` | 10 | 10 (`admin` 9, `operador1` 1) |
| `remote_ssh` | 14 | 14 (`admin` 7, `operador1` 7) |
| `device_online` | 18 | 0 |
| `device_offline` | 15 | 0 |

El campo se puebla en todos los eventos originados por un operador y queda vacío
en los originados por el dispositivo, que es el comportamiento correcto. Con dos
principales activos, `actor_name` discrimina.

**El hook es lo que hace que la atribución sirva para algo.** Antes de la mejora
1, la tabla registraba a quién sin impedir nada: cualquier cuenta con sesión
alcanzaba cualquier dispositivo, de modo que saber quién entró no distinguía un
acceso legítimo de uno que no debió ocurrir. Con el control por dispositivo
activo, un evento en la tabla es un acceso autorizado y atribuido.

---

## 3. Qué cubre el registro, y qué no

`device_event_logs` registra **sesiones establecidas**, no autorizaciones ni
intentos. La distinción importa y está verificada por ausencia:

**No se registran las denegaciones.** `callUserHookUrl` corta antes de
`handleUserConnection`, que es donde se escribe el evento. El `403` que recibió
`operador2` en la prueba V1 de la mejora 1 no dejó rastro en la tabla. Un
operador sin asignación puede sondear indefinidamente sin aparecer.

**No se registran las aprobaciones que no llegan a sesión.** Un acceso de
`admin` autorizado por el hook, que carga la interfaz pero no abre la consola,
no genera evento. Verificado: el acceso del 10 de septiembre no consta; el del
11, con consola abierta hasta la shell, sí.

**El único registro de las denegaciones está en n8n**, en las ejecuciones del
webhook, y su nodo de decisión escribe `username`, `devid`, acción, decisión y
motivo. Eso convierte la decisión sobre el guardado de ejecuciones —planteada
hasta ahora como asunto de privacidad, porque la salida del nodo Webhook
contiene la cookie del operador— en una decisión que también afecta a la
trazabilidad. Desactivarlo sin sustituirlo elimina el único registro de los
accesos rechazados.

### 3.1 `ended_at` es fiable en el cierre limpio, no siempre

La columna se puebla al terminar la sesión y permite calcular duraciones, que es
lo que el §8 del reconocimiento propone para cerrar el ciclo sobre esta tabla en
lugar de construir un registro paralelo.

Con una excepción medida: de 24 eventos de operador, 23 tienen `ended_at`
poblado. El evento `id=22`, un `remote_control` de `admin` del 5 de septiembre,
sigue sin cerrar seis días después. `remote_ssh` cierra en 14 de 14;
`remote_control`, en 9 de 10.

Un cierre no registrado produce una sesión aparentemente eterna. Para métricas de
duración conviene descartar los registros sin `ended_at` en lugar de tratarlos
como sesiones vivas.

Es el mismo patrón del P1-5, que documenta `device_online` sin su
`device_offline` correspondiente: hoy 18 frente a 15. La diferencia de tres se
mantiene estable desde el reconocimiento, de modo que no es deriva acumulativa
sino un desfase fijo.

---

## 4. Consecuencia para la propuesta original

**PROXY protocol queda descartado**, no aplazado. No resuelve el problema que
decía resolver:

- Daría la IP del analista, que con credencial compartida no identifica a nadie.
- Añade configuración a Traefik, que está en el camino del acceso al nivel 1.
- El campo que resuelve la atribución ya existía y ya estaba poblado.

**La alternativa que sí escala** es el proveedor OIDC contra Authelia. `users`
tiene columna `authProvider` y la API moderna expone `/auth/oidc/login` y
`/auth/oidc/callback`, de modo que el esquema está preparado. Con tres cuentas
locales la atribución funciona; con más operadores, la gestión de credenciales
locales deja de ser razonable.

Queda fuera del alcance de esta mejora y no bloquea nada.

---

## 5. Casilla del README

La casilla de trazabilidad pasa a verificable con esta evidencia:

- `actor_user_id` y `actor_name` poblados en 24 de 24 eventos de operador.
- Dos principales distintos observados en los eventos, sobre tres cuentas
  existentes.
- Con el alcance explícito del §3: sesiones establecidas, no intentos.

Es el patrón que el §8 del reconocimiento describe para el nivel 2 y que aquí se
aplica al nivel 1: convertir una casilla afirmada en un control verificable, con
su límite escrito al lado.
