# Fase 8 · KVM sobre IP — Auditoría y remediación

**Versión 3** — sesión de remediación cerrada
**Fechas:** 4–5 de septiembre de 2026
**Alcance:** `fase8-kvm/` + dispositivo GL-RM1 (`192.168.0.36`) + dependencias cruzadas con Fase 4

---

## 1. Estado

| Punto | Estado |
|---|---|
| 0. Verificación del binding de Headscale | ✅ Cerrado |
| 1. Generación de secretos | ✅ Aplicado |
| 2. `.env` del host | ✅ Aplicado y verificado |
| 3. Contenedores (`rttys` por digest, `coturn` eliminado) | ✅ Aplicado |
| 4. `S01selfCloud` en el dispositivo | ✅ Aplicado |
| 5. Regeneración y reinicio en frío | ✅ Verificado ×4 |
| 6.1 Registro del dispositivo | ✅ Verificado |
| 6.2 Vídeo por vía directa | ✅ Verificado — candidatos host, sin TURN |
| 6.3 Subdominios de consola | ⛔ Descartado — sustituido por D2 |
| 7. Planos de control externos | ✅ Cortados y verificados tras reinicio |
| 8. Historial de git | ✅ Sin acción necesaria — ver §7 |
| 9.1 Sonda de capacidad | ✅ Implementada y validada en 4 casos |
| 9.2 Prueba funcional mensual | ⏳ Pendiente de procedimentar |
| 9.3 Reescritura del README | ⏳ Pendiente |
| Certificado del dispositivo desde `oob-rootCA` | ✅ Instalado y persistente |
| Validación TLS del canal rtty (`-C`) | ⏳ Bloque separado |
| Trazabilidad del operador | ⏳ Pendiente |

**Resultado: el GL-RM1 volvió a estar en línea tras 54 días**, por ruta LAN, sin dependencia de Headscale ni de la nube del fabricante, con certificado del enclave, vídeo funcional y monitorización verificada.

---

## 2. Causa raíz

El dispositivo estuvo **54 días** sin registro válido en la plataforma (último registro exitoso: 12 jul 2026 18:36 UTC). Durante todo ese periodo estuvo encendido, con IP, respondiendo a ICMP y sirviendo su web UI local por HTTPS: cualquier sonda de disponibilidad convencional habría estado en verde.

| Fecha | Evento |
|---|---|
| 11 jul 19:56 | Alta del dispositivo en rttys; `remote_control` y `remote_ssh` verificados |
| 11 jul 20:01 | Se crea el usuario `kvm-devices` en Headscale — nunca se usa; el nodo queda bajo `tfm-oob` |
| 11 jul 21:49 | Commit `562a3d6`: `fase8-kvm/glkvm-cloud` entra como **submódulo** (modo 160000) |
| 12 jul 15:33 | `device_offline` y `device_online` con 4 s de diferencia |
| 12 jul **18:36** | Último registro exitoso. rtty deja de autenticar |
| 12 jul 20:55 | `status` marcado `offline` — **2 h 26 min después** |
| 12 jul | Commit `e9ef0a8`: el submódulo se sustituye por directorio normal |
| 13 jul 15:46 | El nodo `glkvm` pierde contacto con Headscale (21 h después de rtty) |
| 26 ago | Commit `8b00bdf`: endurecimiento de Headscale — `server_url` a `https://hs.oob.local`, binding a loopback |
| 1 sep | Intento de reconexión vía Tailscale; falla con `connection refused` contra `192.168.0.70:8090` |

**Causa raíz: una rotación de credenciales aplicada en un solo extremo, sin verificación funcional posterior.** Bastó rotar `RTTYS_TOKEN` y `TURN_PASS` en el servidor y no propagarlos al dispositivo para destruir la vía de recuperación física del enclave. No hizo falta un fallo técnico ni un ataque.

Evidencia directa: `logread` del dispositivo mostraba `connect '100.64.0.1:5912' timeout` cada 15 s, y tras corregir el host, `register fail: Invalid token`. Dos fallos encadenados: destino incorrecto y credencial obsoleta.

Que rtty muriera **21 horas antes** que la sesión de Tailscale descarta que la causa fuera pérdida de conectividad IP.

### Segunda ruptura, independiente

El endurecimiento del 26 de agosto no causó el fallo de julio, pero **sí hizo fracasar el intento de recuperación del 1 de septiembre**: el dispositivo apuntaba a `http://192.168.0.70:8090` en claro, y ese binding pasó a loopback. Dos roturas separadas por seis semanas, la segunda enmascarando el diagnóstico de la primera.

### Hipótesis descartada

Se planteó que el endurecimiento de la Fase 4 hubiera causado la ruptura original. **Falsa por fechas.** Se deja constancia por su valor metodológico: era coherente con el patrón de fases anteriores y sólo la datación documental la refutó.

### Evidencia destruida por el propio fallo

El buffer de syslog del dispositivo cubre **22 horas**. El bucle de error (≈11.500 líneas/día, ~311.000 intentos fallidos en total) expulsó todo lo anterior. `find` por fechas de julio devuelve vacío, y `/etc/kvmd/user/scripts/` está datado en `Jan 1 1970`. **La datación sólo fue posible desde el host** (historial de git y base de datos de Headscale). `S01log-guardian.sh` no es rotación de logs: sólo trunca cuando no queda espacio en disco.

---

## 3. Decisiones de arquitectura

### D1 — El KVM queda fuera del tailnet

Si el operador necesita Headscale para usar el KVM, el KVM no es la vía que sobrevive a un fallo de Headscale. rtty conecta a `192.168.0.70:5912` por LAN; Tailscale desactivado en el dispositivo; nodo `glkvm` (ID 3) eliminado de Headscale.

**Verificado:** tras cuatro reinicios, las únicas conexiones salientes del dispositivo son rtty hacia `192.168.0.70:5912` y SSH de administración.

### D2 — Break-glass por la web UI local del dispositivo

El acceso a consola de vídeo se hace **directamente contra `https://192.168.0.36`**.

1. **Menos capas.** El camino por plataforma atraviesa Traefik, rttys, proxy HTTP y negociación WebRTC. El directo es navegador → dispositivo en el mismo segmento L2.
2. **Elimina la cuestión del TURN.** Verificado: janus escucha en `127.0.0.1:7771` y UDP en `192.168.0.36`, con `turn_rest_api_key = ""`. Candidatos host puros. Esto cierra el conflicto del 3478 con el DERP de la Fase 4.
3. **No depende de la plataforma.** Si `glkvm_cloud` cae, el acceso directo sigue disponible.
4. **Evita reemitir la PKI transversal.** La alternativa exigía SAN `*.kvm.oob.local` — los comodines TLS son de un solo nivel y `*.oob.local` no cubre `zsb25f8.kvm.oob.local` — más `HostRegexp` en Traefik y entradas DNS por dispositivo en cada equipo de analista.

**Modelo en dos niveles:**

| Nivel | Vía | Depende de | Uso |
|---|---|---|---|
| Normal | `https://kvm.oob.local` | Traefik, rttys, LAN | Inventario, estado, consola, auditoría |
| Break-glass | `https://192.168.0.36` | Sólo LAN | Vídeo, teclado, power reset |

**Riesgos aceptados, con fecha de revisión:**

- Autenticación local (`htpasswd`), **fuera de Authelia**. `totp.secret` a 0 bytes: sin segundo factor.
- Sin registro de acciones en IRIS por esta vía.
- Requiere custodia de credenciales fuera de línea y alerta sobre su utilización.

El certificado, que era el tercer riesgo, **ha quedado resuelto** (§5).

### D3 — `coturn` eliminado

`allowed-peer-ip=0.0.0.0/0` inválido en coturn (3072 reinicios); corregirlo tal cual dejaría un relay abierto; colisión del 3478 con el STUN del DERP de la Fase 4; imagen `edge-alpine` sin fijar. Con D2 verificado, el vídeo no lo necesita.

---

## 4. Hallazgos

### Críticos

**P0-1 · Credenciales comprometidas.** Rotadas. *Matiz: no llegaron a estar en el repositorio (§7).*

**P0-2 · Vía de recuperación inoperativa 54 días sin detección.** Corregida; sonda implementada y validada (§5).

**P0-3 · Cuatro credenciales fuera de inventario** descubiertas durante la auditoría: token rtty del dispositivo, `WEBRTC_PASSWORD`, token de `gl-cloud.conf`, `htpasswd` local.

**P0-4 · Plano de control del fabricante ACTIVO.**

```
192.168.0.36:60016 → 47.107.176.138:8883   1648/eco
```

MQTT sobre TLS contra infraestructura de Alibaba Cloud (China). El daemon `eco` (`/usr/bin/gl-cloud`) mantenía canal propio y **participaba en el arranque de rtty** (`gl-cloud[1648]: (kvm.lua:221) start rtty`). Una primera evaluación basada en `ps` concluyó erróneamente que no había plano de control externo; sólo `netstat -tnp | grep ESTABLISHED` lo reveló. **Desactivado y verificado tras reinicio.**

**P0-5 · Tailscale saliente a infraestructura pública.**

```
192.168.0.36:58638 → 199.165.136.100:443   1792/tailscaled
```

**Desactivado.**

### Altos

**P1-1 · `S01selfCloud` regenera `rtty-loop.sh` en cada arranque** vía `S99custom` (que recorre `S??*`, patrón que `rtty-loop.sh` no cumple). Corregir sólo `rtty-loop.sh` produce un arreglo que desaparece en el siguiente reinicio, sin aviso.

**P1-2 · Dependencia de Internet en el arranque.** Verificada activa (`docker exec` devolvía `77.226.198.189` vía `api.ipify.org`). **Corregida** con `GLKVM_ACCESS_IP=192.168.0.70`.

**P1-3 · TLS sin validación en el canal rtty.** El cliente usa `-s` (cifra, no verifica). Registrado en cada conexión:

```
rtty: (rtty.c:655) SSL certificate error(18): self-signed certificate
```

**El sistema señala la ausencia del control como advertencia y continúa operando con normalidad.** Pendiente, bloque separado (§6).

**P1-4 · Trazabilidad forense parcial.** Resuelto para el dispositivo: `ip` pasó de `172.24.0.1` (gateway del bridge) a `192.168.0.36`. **Pendiente** para el operador: `client_ip` registra `172.18.0.1` para cualquier analista.

**P1-5 · La instrumentación de estado de rttys no es fiable.** Descubierto al construir la sonda. Cuatro campos, ninguno útil como indicador de contacto continuo:

| Campo | Problema |
|---|---|
| `status` | 2 h 26 min de retraso demostrado (12 jul) |
| `last_seen_at` | **No es un heartbeat**: registra el instante del último *registro*. Con el dispositivo conectado, el valor crece indefinidamente |
| `updated_at` | Idéntico a `last_seen_at`, igualmente estático |
| `device_event_logs` | No registró una desconexión provocada durante las pruebas |

Explica por qué los 54 días pasaron desapercibidos: no había ninguna capa de la plataforma donde mirar y obtener la verdad.

### Medios

**P2-1 · Bug de escape en el script de aprovisionamiento del fabricante.** La UI genera el heredoc anidado sin los `\`, de modo que las expansiones ocurren al generar y no al ejecutar. Resultado verificado:

```sh
device_id=zsb25f8
if ! pgrep -f "rtty.*-d 94:83:c4:cb:25:f8" > /dev/null; then
```

Funciona en este dispositivo, pero el watchdog dejó de ser genérico.

**P2-2 · Imagen sin fijar.** **Corregido**: `sha256:a04a1225…`. Namespace personal de Docker Hub; conviene `docker save` de respaldo.

**P2-3 · Tres planos de control adicionales, inertes por ausencia de configuración.** `S99cloudflare`, `S99zerotier` y `S99netbird` leen `/etc/kvmd/user/<servicio>.json` y salen con `SKIP`/`DISABLED` si no existe o `enable != true`. **Distinción importante frente a P0-4:** GL.iNet Cloud estaba armado con token y UUID persistidos; estos tres están inertes porque nadie los configuró, no por una decisión tomada. Un fichero JSON de 30 bytes los activa.

**Efecto secundario persistente:** `S99zerotier` y `S99netbird` añaden `net.ipv4.ip_forward=1`, `net.ipv6.conf.all.forwarding=1` y `accept_ra=2` a `/etc/sysctl.conf` al arrancar, y **no lo revierten al parar**. Si alguno llegara a activarse, el GL-RM1 quedaría convertido en router de forma permanente.

**P2-4 · README con arquitectura abandonada y capacidades falsas.** Pendiente (§6).

**P2-5 · Certificado del dispositivo caducado en 1979.** **Resuelto** (§5).

**P2-6 · Secretos en `docker logs`.** El dump de configuración de rttys imprime `Token` y `Password` en claro. Si la Fase 7 instrumenta este contenedor, están indexados en OpenSearch. **Verificar en la remediación de Fase 7.**

**P2-7 · Syslog del dispositivo sin rotación efectiva.** Buffer de 22 h, saturable por cualquier componente en bucle.

### Bajos

`user: "0:0"` en el contenedor; `SELFHOST_WEBUI_URL` duplicado en `.env` (corregido); `/tmp/turnserver.json` con contraseña en claro en cada arranque; `ui/env/.env.development` con IP pública fija en la copia vendorizada; `runner.pyc` sin fuente (el firmware distribuye sólo bytecode).

---

## 5. Ejecutado y verificado

### Punto 0 — Binding de Headscale

`server_url: https://hs.oob.local`, con router Traefik. Ambos nodos vivos confirman `"ControlURL": "https://hs.oob.local"` con `"Health": []`. **El binding `127.0.0.1:8090` es un residuo** y puede eliminarse en el bloque de endurecimiento de la Fase 4.

### Puntos 1–2 — Secretos y `.env`

`RTTYS_TOKEN` (64 hex), `RTTYS_PASS` y `TURN_PASS` (32 alfanuméricos), generados sin símbolos: el `sed` del entrypoint sólo escapa `/` y `&`, y un metacarácter no escapado produciría un `rttys.conf` corrupto sin error visible. Verificados por longitud, formato, ausencia de valores viejos y exclusión del índice.

### Punto 3 — Contenedores

`docker-compose.override.yml` con imagen por digest, puertos restringidos a `192.168.0.70` y `coturn` con `profiles: ["disabled"]`.

**Incidente registrado — fusión de listas en Compose.** El primer intento falló con `address already in use` de forma reproducible, con el kernel confirmando los puertos libres, sin sockets, sin reglas iptables residuales y sin proxies huérfanos. La causa: **Compose fusiona las listas de `ports` entre base y override en lugar de reemplazarlas**, de modo que el contenedor intentaba bindear `0.0.0.0:5912` y `192.168.0.70:5912` a la vez y colisionaba consigo mismo.

`docker compose config --quiet` respondió "sintaxis OK" porque la sintaxis era correcta; lo incorrecto era la semántica del merge. Se resolvió con la etiqueta `!override`. Durante el diagnóstico se reinició el daemon de Docker innecesariamente, persiguiendo una hipótesis de estado interno que era falsa.

### Puntos 4–5 — Dispositivo

Persistencia verificada **antes** de editar: `upperdir=/userdata/overlay/upper` sobre partición real. `S05async-commit.sh` resultó ser una optimización del kernel de Rockchip, no un commit diferido.

**Registro antiguo como bloqueo.** Tras corregir host y token, el servidor seguía respondiendo `invalid token for device 'zsb25f8'` pese a coincidir los hashes en `.env`, `rttys.conf` renderizado y `rtty-loop.sh`. La causa era el registro de julio persistente en la base de datos. Eliminarlo desde la UI y dejar que el dispositivo se registrara de nuevo lo resolvió (`id` pasó de 1 a 2).

**Reinicio en frío verificado cuatro veces**, la última sin `gl-cloud` activo, confirmando que `rtty-loop.sh` vía `S99custom` es un camino de arranque independiente del plano de control del fabricante.

### Punto 6.2 — Vídeo

Verificado funcional por `https://192.168.0.36`. Janus escucha en `127.0.0.1:7771` y UDP en `192.168.0.36`, sin `cert_pem`/`cert_key` en `janus.jcfg` y sin ficheros `.pem` en disco: **certificado DTLS efímero generado en cada arranque**. Es el comportamiento estándar de WebRTC y no constituye excepción a la PKI del enclave — la autenticación va por el fingerprint publicado en el SDP, y el SDP viaja por la señalización HTTPS, que sí valida contra `oob-rootCA`.

### Certificado del dispositivo

Emitido desde `oob-rootCA` siguiendo el molde de la Fase 6 (`iris.cnf`): clave EC `prime256v1` — misma curva que genera el firmware —, SAN con `DNS:glkvm-device.oob.local`, `IP:192.168.0.36`, `DNS:localhost`, `IP:127.0.0.1`, 825 días.

**El firmware desactiva deliberadamente la comprobación de caducidad.** En `S99kvmd-nginx`:

```sh
# Do not check whether the certificate has expired
# if ! openssl x509 -in "$cert_file" -noout -checkend 86400 ...
```

`check_cert_valid` sólo verifica formato del certificado, formato de la clave y que las claves públicas coincidan. Esto explica por qué un certificado caducado en 1979 servía la vía de break-glass: el firmware decidió no mirar, y lo documentó en un comentario. **Es un control deliberadamente desactivado en el código, no una omisión.**

Verificación completa:

```
subject=CN = glkvm-device.oob.local
issuer=CN = OOB Enclave Root CA
curl --cacert oob-rootCA.crt https://192.168.0.36/  →  HTTP 200
```

**Persistencia confirmada tras reinicio:** `server.crt` conserva 1484 bytes y la fecha de instalación; `check_cert_valid` lo aceptó y no regeneró el autofirmado. La vía de break-glass es ahora verificable criptográficamente contra el trust anchor del enclave.

### Punto 7 — Planos de control

GL.iNet Cloud y Tailscale desactivados y verificados tras reinicio. Cloudflare, ZeroTier y NetBird confirmados sin proceso y sin fichero de configuración. Única conexión saliente: rtty hacia `192.168.0.70:5912`.

### Punto 9.1 — Sonda de capacidad

**Tres criterios descartados antes de llegar a uno válido.** El recorrido es más informativo que el resultado:

1. **`status`** — descartado por diseño: 2 h 26 min de retraso demostrado en julio.
2. **`last_seen_at`** — implementado y programado en cron. En operación, el valor crecía al ritmo exacto del reloj (78 s → 124 s → 425 s) con el dispositivo conectado y funcionando. **No es un heartbeat: registra el último registro.** Habría disparado una falsa alarma a los 900 s. Detectado porque se observó el log de la sonda en operación, no por revisar su diseño.
3. **Prueba negativa fallida en silencio** — un `pkill` a través de `ssh '...'` no expandió el patrón por capas de comillas, dejando el proceso vivo. Se midieron tres minutos de un sistema sano creyendo medir un sistema caído. La contradicción entre `ps` vacío y `netstat` con conexión estaba visible desde el principio y se descartó demasiado rápido.

**Criterio final:** conexión TCP `ESTABLISHED` al puerto 5912 **dentro del namespace de red del contenedor**. La conexión no es visible con `ss` en el host: termina dentro del contenedor, detrás del `docker-proxy`.

```bash
docker exec glkvm_cloud sh -c 'netstat -tn | grep -c ":5912.*ESTABLISHED"'
```

Es una medida de comportamiento, no de estado declarado. Verificado: al matar el proceso con `kill -9`, el contador baja a 0 de inmediato.

**Validación en los cuatro casos:**

| Caso | Resultado | Origen |
|---|---|---|
| Operación normal | `exit=0` | manual y cron |
| Cliente caído | `ALERTA` | **cron, 23:15:01** |
| Servicio caído | `exit=2` | manual, 23:04:49 |
| Recuperación | `exit=0` | manual, 23:15:51 |

La detección del cliente caído la produjo la **ejecución programada**, no una invocación manual: cron ejecutó la sonda durante la ventana real de caída y alertó correctamente. La caída duró menos de cinco minutos y aun así cayó dentro de un ciclo — con el umbral de 900 s del diseño anterior no se habría visto nada.

Como subproducto se verificó que el watchdog del dispositivo se recupera solo de una muerte abrupta del proceso rtty, sin intervención.

Programada cada 5 minutos en el crontab del usuario (sin `sudo`: la BD ya no se consulta).

**Pendientes menores:** rotación del log (288 líneas/día); condición de alerta sólo en cambio de estado, para no saturar el canal durante una caída prolongada.

---

## 6. Pendiente

**Validación TLS del canal rtty (P1-3).** Colocar `oob-rootCA` en ruta persistente del dispositivo, añadir `-C <ruta>` al heredoc de `S01selfCloud`, y emitir el certificado de rttys con SAN para `192.168.0.70`. Se mantiene separado porque mezclarlo con la reconexión juntaba dos cambios con modos de fallo distintos.

**Trazabilidad del operador (P1-4).** PROXY protocol o cabeceras reenviadas desde Traefik hasta rttys.

**Prueba funcional mensual (9.2).** Con registro en IRIS: abrir consola por la vía directa, confirmar vídeo y teclado, y verificar que funciona **con Headscale detenido** — la prueba que valida la premisa entera de la fase. No ejecutar acciones de potencia.

**Reescritura del README (9.3).**

| Actual | Corrección |
|---|---|
| `[x] mTLS en Cloudflare Access` | Eliminar. Registro de decisión: incompatible con el principio OOB. |
| `[x] Flujo fallback automático RustDesk→KVM` | `[ ]` — no consta implementado en n8n |
| `[x] Política 2-person rule para powerreset` | `[ ]` — no implementada |
| `[x] GL.iNet KVM integrado en inventario` | Verificar antes de mantener |
| Clase `GLKVM` con `http://` y basic auth | Eliminar: no corresponde a la API real |
| Arquitectura de fallback | Sustituir por el modelo de dos niveles de D2 |

Secciones nuevas: inventario de planos de control externos y su estado; el incidente de los 54 días; riesgos aceptados con fecha de revisión.

**`.env.example` (9.4).** Eliminado del disco. `docker-compose/README.md` instruye a copiarlo para desplegar: regenerarlo con placeholders o ajustar la nota, o queda un procedimiento de despliegue roto para quien reproduzca el trabajo.

---

## 7. Punto 8 — Sin acción necesaria

**Los secretos de la Fase 8 nunca estuvieron en el repositorio.** Confirmado por cuatro vías:

```
git ls-files --error-unmatch .env.example  → no conocido por git
git cat-file -p HEAD:.env.example          → 0 coincidencias
blobs .env.example en todo el historial    → 8 ficheros, ninguno de fase8
grep del token en todos los blobs          → 0
```

El commit `e9ef0a8` sustituyó el gitlink por un directorio normal, pero `docker-compose/` quedó fuera del índice. **No hay `git filter-repo`, no hay reescritura de historial, no hay `push --force`.**

Se añadió `fase8-kvm/backup-dispositivo/` con `.gitignore` propio para las copias de configuración del dispositivo, que contienen token y contraseña WebRTC en claro. Exclusión verificada con `git add --dry-run` (autoritativo; `git check-ignore -v` devuelve exit 0 también en coincidencias de negación).

La rotación del punto 1 se mantiene íntegra: los secretos siguen comprometidos por otras vías.

---

## 8. Contribuciones a la memoria

**1. La ausencia de un control se manifiesta como operación normal — y aquí produjo señal positiva activa.** El dispositivo estuvo 54 días respondiendo a ping y sirviendo HTTPS mientras la capacidad que justificaba su existencia no existía.

**2. Un control de seguridad destruyó una capacidad de seguridad.** La rotación de credenciales, aplicada en un solo extremo y sin verificación funcional, eliminó la vía de recuperación física del enclave.

**3. Un bug contenía un fallo de arquitectura.** `allowed-peer-ip=0.0.0.0/0` mataba a coturn en el parseo, antes de bindear, manteniendo libre por accidente el puerto 3478 del STUN del DERP de la Fase 4. Corregir el bug de forma aislada habría roto una fase distinta, mediante una carrera resuelta por orden de arranque.

**4. El fallo destruyó su propia evidencia.** El bucle de error inundó un buffer de syslog de 22 horas y dejó al dispositivo sin historial forense.

**5. Independencia del plano de datos no es independencia del plano de acceso.** La premisa documentada era que el KVM conectaba por LAN. En realidad estaba configurado contra `100.64.0.1`: la vía de recuperación dependía por completo del componente del que debía ser independiente.

**6. Los planos de control latentes son un riesgo distinto de los activos — y la distinción exige verificar la capa correcta.** Una evaluación basada en `ps` concluyó que no había plano de control externo. `netstat -tnp | grep ESTABLISHED` reveló una conexión MQTT establecida contra infraestructura del fabricante en China. Además, la distinción entre "armado con credenciales persistidas" (GL.iNet Cloud) e "inerte por ausencia de configuración" (Cloudflare, ZeroTier, NetBird) es una diferencia de riesgo real, no de grado.

**7. Un control puede estar deliberadamente desactivado en el código, con comentario.** El firmware del GL-RM1 comenta explícitamente la comprobación de caducidad de certificados en `check_cert_valid`. No es un descuido: es una decisión documentada de preservar la operación normal a costa de la verificación. Resultado observado: un certificado caducado en 1979 sirviendo la vía de break-glass del enclave.

**8. La monitorización de una capacidad debe medir comportamiento, no estado declarado — y la propia sonda necesita verificación en operación.** Los cuatro instrumentos de estado de rttys resultaron no fiables (P1-5). El control diseñado para corregir el hallazgo central de la fase **falló dos veces por el mismo mecanismo que documenta**: primero apoyándose en un campo cuyo nombre prometía un heartbeat que no entregaba, después con una prueba negativa que no probó nada por un error de escapado. Ambos se detectaron sólo porque se observó el comportamiento en operación.

**9. Fallar abierto y fallar cerrado.** Durante la sesión se produjeron ambos modos, en controles construidos para esta misma remediación:

- **Abierto:** una comprobación de que certificado y clave casaban (`[ "$A" = "$B" ]`) devolvió éxito comparando dos cadenas vacías, porque el `scp` previo no había llegado. Dio verde precisamente por no tener nada que comprobar.
- **Cerrado:** la sonda de monitorización, con un bug de ruta (`$HOME` bajo `sudo`), alertó en lugar de callar.

Ambos tenían un defecto; sólo uno habría pasado desapercibido. La distinción debe ser un criterio de diseño explícito en cualquier control de verificación.

**10. Verificar el instrumento de verificación.** El volcado automatizado inicial contenía tres afirmaciones factuales, las tres erróneas, en tres direcciones distintas:

| Afirmación | Realidad | Sesgo |
|---|---|---|
| `glkvm.cer`/`glkvm.key` son directorios vacíos creados por Docker | Ficheros PEM válidos de 1992 y 3268 bytes | Fallo inventado |
| No hay gitlink; es copia vendorizada normal | Fue submódulo (modo 160000) del 11 al 12 de julio | Historial mal descrito |
| `.env.example` trackeado con secretos reales | No está en el índice ni en ningún blob del historial | Riesgo sobreestimado |

Las dos primeras se presentaron como "nota factual, no interpretación". La tercera abrió el informe con énfasis explícito sobre su carácter de comprobación de seguridad. **El mayor énfasis metodológico acompañó al error de mayor consecuencia**: de esa afirmación salió la restricción de secuenciación que estructuró el plan de remediación completo. El marcador lingüístico de confianza no correlacionó con la fiabilidad, y las comprobaciones que las habrían desmontado eran baratas: `file`, `git log --raw`, `git ls-files`.

Errores del mismo tipo se produjeron durante el análisis asistido: una hipótesis causal coherente pero falsa; un diagnóstico erróneo de estado del daemon de Docker que llevó a un reinicio innecesario del stack; una comparación de credenciales en la que se confundió un hash con el valor que representaba, lo que habría llevado a "corregir" un token correcto; una hipótesis de conexiones fantasma formulada sobre una prueba que no había ejecutado nada. En todos los casos la corrección vino de un dato empírico, no de un razonamiento mejor.

**Formulación general: la ausencia de verificación se manifiesta como un informe bien formateado.** El principio que la tesis aplica a sistemas aplica igualmente al proceso de auditoría y a las herramientas que lo asisten.

**11. Las restricciones de secuenciación caducan.** La regla inicial era: recuperar acceso local *antes* de rotar `RTTYS_TOKEN`, o la rotación invalidaría el registro y se perdería la vía de recuperación física. La investigación de la causa raíz la eliminó: el acceso local estaba disponible y el registro llevaba 54 días roto, de modo que rotar no podía invalidar un vínculo inexistente. El paso de más riesgo del plan se convirtió en el de menos.

---

## 9. Huecos abiertos

**Qué tumbó la sesión de Tailscale del KVM el 13 de julio.** El binding del 8090 permaneció en `0.0.0.0` hasta el 26 de agosto y no había expiración configurada. No bloquea la remediación —el KVM sale del tailnet por D1— pero no debe darse por explicado. Hipótesis no verificada: un reinicio del dispositivo sin que `tailscaled` recuperase estado.

**Precisión sobre la cifra de 54 días.** `last_seen_at` registra el último *registro exitoso*, no el último contacto (P1-5). La cifra es correcta como "días sin registro válido", que es lo que define la pérdida de capacidad. La evidencia directa del `logread` del dispositivo —`connect timeout` continuo— confirma que no hubo servicio durante ese periodo.
