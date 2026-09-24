# Hallazgo · Los contenedores de RustDesk arrancan sin red

> **Actualizado el 2026-09-24.** Causa raíz determinada, fallo reproducido en
> un arranque en frío y reparación aplicada. Dos afirmaciones de la versión del
> 2026-09-23 eran incorrectas —la hipótesis sobre la red externa y la ausencia
> total de señal en el log—; se conservan abajo tal como se escribieron y se
> corrigen en la sección final.

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

---

## Actualización (2026-09-24): causa raíz, reproducción y reparación

### Reproducido en arranque en frío

Tras reiniciar el servidor el 2026-09-24, el barrido de los 29 contenedores en
ejecución volvió a dar `rustdesk-hbbs` y `rustdesk-hbbr` sin red y ningún puerto
2111x publicado, con el resto del laboratorio funcionando. El fallo no fue un
caso aislado.

### Causa raíz

La hipótesis del 2026-09-23 (orden de arranque frente a una red `external`)
**era incorrecta**: los dos contenedores se unieron a `oob-network` sin problema
en el arranque (`sbJoin` en `journalctl -u docker -b`). Lo que falla es la
publicación del puerto:

failed to bind host port 100.64.0.1:21117/tcp: cannot assign requested address (hbbr)
failed to bind host port 100.64.0.1:21115/tcp: cannot assign requested address (hbbs)


`100.64.0.1` es la IP del tailnet, y no existe en el host cuando la política
de reinicio de Docker intenta levantar los contenedores. Cronología medida:

| Hora | Evento |
|---|---|
| 12:42:39 | `tailscaled` arranca sin caché de netmap: sin IP hasta hablar con su servidor de control |
| 12:44:59 | Arranca el contenedor `headscale`, que **es** ese servidor de control |
| 12:45:08 / 12:45:17 | `hbbr` y `hbbs` fallan el bind; quedan parados |
| 12:45:45 | `tailscaled` contacta con Headscale |
| 12:46:01 | `tailscale0` recibe `100.64.0.1/32` |

**Dependencia circular de arranque:** el canal de rescate publica sobre una
dirección que solo existe cuando el plano de control del propio enclave ya ha
arrancado, y pierde la carrera por unos 45 segundos.

El estado «`running` sin red» del 2026-09-23 es la consecuencia del arranque
manual posterior: los contenedores, parados por el fallo, se levantaron desde
Portainer y quedaron en ejecución sin red. Por qué ese arranque manual deja
`Networks: {}` no se ha determinado; se ha medido el resultado, no el
mecanismo interno.

Posible intermitencia, **no medida**: `tailscaled` escribe la netmap en caché
de disco; con caché, la IP podría aparecer antes y el fallo no producirse. Eso
explicaría que la fase se validara correctamente en su día, y es la razón de
que la reparación no pueda confiar en los tiempos.

### IRIS tiene el mismo fallo latente

`iriswebapp_nginx` publica en `100.64.0.1:4833` y falló el bind exactamente
igual a las 12:45:06. Lo salva `tfm-fase6-iris.service`, que hace `down` + `up`
más tarde, pero no por diseño: la unidad arrancó a las 12:45:34, **27 segundos
antes** de que existiera la IP, y funcionó solo porque la cadena de
`depends_on` y healthchecks retrasó a nginx hasta las 12:48.
`After=tailscaled.service` ordena tras el *inicio* de `tailscaled`, no tras la
asignación de la IP.

Generalización: todo servicio que publique en la IP del tailnet depende de una
carrera de arranque contra el Headscale del enclave. Dos de los tres afectados
fallaban en silencio; el tercero se salvaba por la duración de su propio
arranque.

### Corrección: el log sí da señal

La versión del 2026-09-23 afirmaba que el log de `hbbs` no daba ninguna señal.
No es así. `hbbs` se arranca con `-r rustdesk-hbbr:21117`; sin red no hay DNS de
Docker, no resuelve ese nombre y deja la lista de relays vacía:

| Arranque | Red | `relay-servers=` | Tiempo hasta esa línea |
|---|---|---|---|
| 23-09 18:48 | sin red | `[]` | 5 s (espera de DNS) |
| 23-09 21:08 (reparación) | con red | `["rustdesk-hbbr:21117"]` | 2,5 s |
| 24-09 10:54 UTC | sin red | `[]` | 5 s |

Es un discriminador determinista, pero de nivel `INFO`, no un error: nadie lo
miraría sin saber qué buscar. La conclusión de fondo se matiza, no se invierte:
el fallo es detectable desde dentro **si se sabe qué buscar**, y no produce
ningún síntoma que obligue a buscarlo. Además, en la ventana reparada consta un
registro de cliente (`update_pk` a las 21:15, origen `172.18.0.1`, la pasarela
de Docker, que oculta el nodo real): primera evidencia en log de que el
servidor atendió a alguien.

### Reparación

Unidades systemd versionadas que **esperan a que la IP exista** antes de
levantar los contenedores (máx. 300 s):

- Nueva: `fase4-breakglass-dc/systemd/tfm-fase4-rustdesk.service`, instalada y
  habilitada. Sin `--remove-orphans`: `headscale-ui` comparte proyecto de
  Compose con `fase4-breakglass-dc/` y lo borraría en cada arranque.
- Parcheada: `fase6-iris/systemd/tfm-fase6-iris.service`, con la misma espera
  (IP fija, tomada de `fase6-iris/docker-compose.override.yml:27`).

Trampa de implementación: en las líneas `Exec*` de systemd los `$` del shell van
duplicados (`$$`); sin duplicar, systemd sustituye las variables antes del
shell y la espera sale al instante con valores vacíos, sin error.

La política de reinicio de Docker sigue intentando levantar los contenedores en
el arranque y seguirá registrando el fallo de bind: es ruido esperado; la
unidad los levanta después.

**Verificado en caliente (2026-09-24 14:16):** unidad `active (exited)` con los
tres pasos en `status=0/SUCCESS`; `hbbs` y `hbbr` en `oob-network`; cinco puertos
en `100.64.0.1`; `headscale-ui` intacto. **Pendiente:** la prueba en arranque en
frío, que es la única que acredita la reparación.

**Regla de operación:** no arrancar `hbbs`/`hbbr` desde Portainer ni con
`docker start`. Si el canal está caído: `sudo systemctl restart
tfm-fase4-rustdesk.service`.

### Errores de análisis (continuación)

4. **La hipótesis de la red externa.** Se registró como hipótesis no verificada,
   lo cual era correcto, pero se escribió sin haber consultado el log del
   demonio de Docker, que contenía la causa real desde el primer día.
5. **«Ningún instrumento da señal».** Se afirmó sin tener un arranque sano con
   el que comparar el log. La señal existía; faltaba la referencia.

### Prueba en arranque en frío (2026-09-24, tras `sudo reboot`)

Resultado: `tfm-fase4-rustdesk` y `tfm-fase6-iris` en `active`; 29
contenedores, ninguno sin red; seis puertos en `100.64.0.1` (21115-21119 y
4833); desde DC01, `Test-NetConnection 100.64.0.1 -Port 21116` → `True`. Sin
intervención manual.

La espera se ejercitó: `tailscaled` arrancó sin caché de netmap a las 14:21:01
y pasó a `Running` a las 14:23:13; la unidad arrancó a las 14:23:10, **antes**
de que existiera la IP, y lanzó el compose a las 14:23:15, tras dos
comprobaciones fallidas del bucle.

**Corrección:** la hipótesis de la caché de netmap como fuente de
intermitencia queda refutada para este arranque (tampoco había caché). El
journal de Docker no registra ningún fallo de bind, y los contenedores
aparecen como `Creating`: el `ExecStop=... down` de las unidades los eliminó en
el apagado limpio, así que la política de reinicio de Docker no tuvo nada que
levantar. El arranque del 2026-09-24 a las 12:42 mostraba `layer not mounted` y
`Removing stale sandbox`, compatibles con un **apagado no limpio**, en el que
los `ExecStop` no corren y los contenedores sobreviven. Hipótesis no medida.

**Pendiente:** la prueba tras un apagado no limpio (en VMware, *Power Off* en
vez de reinicio). Por diseño la unidad debería recuperar el canal —los
contenedores quedan `Exited` tras fallar el bind, y la unidad hace `down` +
`up` al tener la IP—, pero es el caso operativamente relevante (un corte de
corriente durante un incidente) y no está acreditado.
