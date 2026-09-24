# Hallazgo · Los contenedores de RustDesk arrancan sin red

**Fecha:** 2026-09-23 · **Fase:** 4 (break-glass) · **Severidad:** P0 (capacidad de
rescate no disponible) · **Estado:** reparado y verificado por comportamiento;
causa raíz del arranque no determinada.

## Síntoma

Ninguno. Ese es el hallazgo.

## Qué se midió

Estado inicial, tras el arranque del laboratorio del 2026-09-23 (`StartedAt`
18:48):

- `docker ps` muestra `rustdesk-hbbs` y `rustdesk-hbbr` como `running`, con la
  columna de puertos **vacía**.
- `docker inspect ... .HostConfig.PortBindings` devuelve los bindings correctos:
  `100.64.0.1:21115`, `:21116` (TCP y UDP), `:21118` para `hbbs`.
- `docker inspect ... .NetworkSettings.Networks` devuelve **`{}`**.
- `sudo ss -tlnp` no muestra ningún `docker-proxy` en el rango 21115-21119.
- El log de `hbbs` desde el arranque imprime `Listening on tcp/udp :21116`,
  `Listening on tcp :21115`, `Listening on websocket :21118` y `Start`, **sin un
  solo error ni aviso**. `hbbr` no emite ninguna línea.

Un barrido de los 28 contenedores en ejecución confirmó que **solo estos dos**
estaban sin red; los otros 26 estaban conectados.

## Mecanismo

Los contenedores arrancaron sin adjuntarse a `oob-network` (declarada
`external: true` en `fase4-breakglass-dc/docker-compose.rustdesk.yml`). Sin
interfaz de red no se crea el proceso `docker-proxy`, de modo que los
`PortBindings` quedan declarados y sin efecto. El proceso `hbbs` escucha
correctamente dentro de su propio espacio de red, aislado, donde ningún cliente
puede alcanzarlo.

La red existía y estaba operativa en ese momento (22 contenedores adjuntos).
La definición del compose es correcta. **La causa del no-reenganche en el
arranque no se ha determinado**; la hipótesis no verificada es el orden de
arranque con `restart: unless-stopped` frente a una red externa.

## Verificación

Par diferencial desde DC01-TFM (`100.64.0.2`), única variable modificada la
conexión de los contenedores a la red:

| Momento | Comando | Resultado |
|---|---|---|
| Antes | `Test-NetConnection 100.64.0.1 -Port 21116` | `TcpTestSucceeded: False` |
| Después | `Test-NetConnection 100.64.0.1 -Port 21116` | `TcpTestSucceeded: True` |

La política ACL de Headscale no se tocó entre ambas medidas. Se comprobó en el
netmap del nodo destino que la regla `SrcIPs 100.64.0.2 → 100.64.0.1:21115-21119`
(TCP y UDP) existe y estaba vigente en las dos medidas, de modo que el `False`
inicial no era atribuible al filtro.

Reparación: `docker compose -f docker-compose.rustdesk.yml up -d` desde
`fase4-breakglass-dc/`. Tras ella, los cinco puertos publicados en
`100.64.0.1` (no en `0.0.0.0`), verificado con `ss`.

Con esto queda además verificada por comportamiento la afirmación de
`fase4-breakglass-dc/README.md:96-97` (D-27 del informe de auditoría de cierre),
que hasta hoy solo constaba por lectura de configuración.

## Por qué importa

Tres instrumentos independientes, los tres informando correctamente de su propia
capa, producen en conjunto una conclusión falsa:

| Instrumento | Informa | Realidad |
|---|---|---|
| `docker ps` | `running` | Sin red |
| `docker inspect` (PortBindings) | `100.64.0.1:21115-21118` | Bindings sin efecto |
| Log de la aplicación | `Listening on…` / `Start` | Inalcanzable |

Ninguno miente. No hay instrumento mal elegido ni control ausente: el fallo **no
es detectable desde dentro del sistema**. Solo aparece al preguntar desde el
consumidor —¿puede el nodo a rescatar alcanzar el servidor?—, que es el criterio
de verificación por comportamiento que este proyecto adopta.

Agrava el caso que afecte al canal de break-glass. Es el único componente que no
se ejercita en el uso diario: una avería en cualquiera de los otros 26
contenedores se manifiesta en minutos, mientras que esta puede durar
indefinidamente. Toda capacidad de emergencia comparte esa propiedad, y de ahí
se sigue directamente la necesidad de la prueba periódica de resiliencia
(`docs/mejora5-prueba-mensual-resiliencia.md`), hoy con una sola ejecución
registrada.

## Consecuencias

1. **Antes de cualquier demostración en vivo** hay que verificar que los 28
   contenedores están adjuntos a su red. El mismo arranque que produjo este
   estado puede repetirse.
2. **Pendiente:** determinar la causa del no-reenganche y si el estado se venía
   repitiendo desde el 2026-09-12 (`Created`). Si los arranques anteriores lo
   dejaron igual, el canal habría estado caído desde la validación de la fase.
3. **Trampa documentada para futuras lecturas de `ss`:** el proceso
   `/usr/share/rustdesk/rustdesk --server` del host, escuchando en
   `0.0.0.0:21119/udp` y `0.0.0.0:40034/udp`, es el **cliente de escritorio** de
   RustDesk en modo servicio, no el servidor. Coexiste con el `docker-proxy` de
   `100.64.0.1:21119/tcp` sin relación alguna.
4. La ACL concede a DC01 el rango completo 21115-21119 en TCP y UDP, más ancho
   que lo realmente publicado (`21115/udp` no se publica).

## Errores de análisis durante el diagnóstico

Registrados como material de la sección de método, por la misma razón que los
anteriores: el sesgo hacia inferir comportamiento a partir de una declaración no
depende del nivel de competencia.

1. **El binario del host.** Se afirmó que el proceso `rustdesk` del host «es el
   que sirve RustDesk» y que escuchaba en `0.0.0.0`, concluyendo que el canal
   estaba sobreexpuesto a la LAN corporativa. Falso: es el cliente de escritorio.
   Se saltó del nombre del binario a su función sin comprobarla.
2. **La ACL.** Se afirmó que la política probablemente no concedía a DC01 acceso
   al enclave, a partir de una lectura parcial del netmap cortada por `grep -A 40`
   en la primera regla. La tercera regla concedía exactamente lo necesario.
3. **El control positivo mal elegido.** Se propuso `100.64.0.1:4833` (IRIS) como
   control positivo desde DC01, sin comprobar que la ACL autorizase ese destino
   a ese origen. No lo autoriza —solo al analista—, de modo que su `False` era el
   comportamiento correcto de la política y no una avería.

En los tres casos la corrección vino de leer el dato completo, no de razonar
mejor: el mismo remedio que el proyecto aplica al sistema.
