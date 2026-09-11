# Fase 8 · Mejora 6 — Endurecimiento del dispositivo GL-RM1

**Estado:** inventario cerrado, correcciones aplicadas, tres riesgos aceptados y
una propuesta pendiente de decisión.

**Método:** lectura del sistema de ficheros y de los servicios en ejecución desde
la consola del dispositivo, más sondeo activo desde el host del enclave
(`192.168.0.70`) para lo que debía medirse desde fuera. Un sondeo con efecto
físico sobre DC01, ejecutado con ventana acordada.

> **Nota de alcance.** El hallazgo de más peso de esta mejora —§6, la clave de
> preautorización de Headscale— no pertenece al dispositivo. Apareció al tirar
> del hilo de Tailscale y se documenta aquí porque aquí se encontró.

---

## 1. Lo primero: qué persiste

Condiciona todo lo demás. Un endurecimiento que no sobrevive al reinicio es peor
que no hacerlo, porque deja una casilla marcada sobre un control inexistente.

```
/dev/root  on /rom  type squashfs (ro)
overlay:/overlay on /  type overlay (rw, upperdir=/userdata/overlay/upper)
```

La base es de solo lectura y las escrituras van al overlay, que persiste. Lo que
puede deshacer un cambio no es el montaje, sino un script de arranque que
regenere el fichero.

**Mecanismo de regeneración, precisado.** `S99custom` recorre
`/etc/kvmd/user/scripts/` con el patrón `S??*` y ejecuta como root todo lo que
coincida. Ahí vive `S01selfCloud`, que en su `start()` escribe `rtty-loop.sh`
con un heredoc **incondicional**, detrás de una guarda `pgrep`: en arranque en
frío regenera; en un `restart` con el watchdog vivo, no.

Consecuencia para la mejora 2: el `-C` con `oob-rootCA` va dentro del heredoc de
`S01selfCloud`, no en `rtty-loop.sh`. Editar el fichero generado es el mismo
patrón que V6 persigue en el nivel 1.

---

## 2. Hueco 2 del reconocimiento, cerrado

El §6 del reconocimiento dejaba pendiente si las acciones con efecto físico
exigen credencial. Verificado desde `192.168.0.70`, con DC01 prescindible y
criterio fijado antes de ejecutar:

| Sondeo | Resultado |
|---|---|
| `GET /api/atx` | `401` |
| `GET /redfish/v1/Systems` | `401` |
| `POST /api/atx/click?button=power` | `401`, DC01 sin alterar |

**RA-1 queda verificado.** La premisa del documento de riesgos de la mejora 1
—"un operador con la credencial local"— era correcta. No es "cualquier equipo de
`192.168.0.0/24`". El riesgo aceptado deja de ser una suposición.

Confirma también lo que el reconocimiento llamaba "la capa que aparenta el
control sin ejercerlo": `gl.ctx-server.conf` anula `auth_request` para `/api`,
pero kvmd autentica una capa por debajo.

---

## 3. Inventario de servicios que escuchan

No existía. El reconocimiento inventarió 110 endpoints de la API y ningún puerto.

| Puerto | Proceso | Alcance | Valoración |
|---|---|---|---|
| 22/tcp | `dropbear` | `0.0.0.0` e `::` | **Riesgo aceptado, RA-4** |
| 80/tcp, 443/tcp | `nginx` | `0.0.0.0` | Superficie ya inventariada; ver §5 |
| 8081/tcp | `nginx` | `127.0.0.1` | Confinado |
| 7771/tcp | `janus` | `127.0.0.1` | Confinado |
| 53/tcp+udp | `connmand` | `127.0.0.1` | Confinado |
| 123/udp | `ntpd` | `0.0.0.0` | Recorte propuesto |
| 5353/udp | `mdnsd`, `mDNSResponder`, `gl-pion` | `0.0.0.0` | Descubrimiento mDNS, tres procesos |
| varios/udp | `gl-pion`, `janus` | LAN | WebRTC, puertos efímeros |

**Sin túnel saliente.** Las cinco conexiones establecidas van todas a
`192.168.0.70`: tres a `443` (consola web), una a `22` (sesión de trabajo) y una
desde `38542` a `5912` (canal rtty). El aislamiento del enclave aguanta.

**Servicios con script de arranque que no corren:** `ttyd`, `cloudflare`,
`snmpd`, `netbird`, `zerotier`. No son superficie hoy.

`snmpd` queda **descartado** en firme: su `start()` exige
`/etc/snmp/snmpd.conf`, que no existe, y `SNMPDOPTS` fija la escucha en
`127.0.0.1`. Aunque arrancara, no expondría nada a la LAN.

---

## 4. Corrección al reconocimiento · `ipmipasswd` y `vncpasswd` no son almacenes

El §4.3 del reconocimiento los describe como "dos almacenes de credenciales fuera
del inventario de cuatro del P0-3", citando sus tamaños (822 B y 637 B).

**Son plantillas del linaje PiKVM, sin entradas.** Los bytes son cabecera
explicativa: el propio texto de `vncpasswd` indica que sin entradas VNCAuth queda
deshabilitado. La única referencia en `override.yaml` está comentada. Nada
escucha en 623 (IPMI) ni 5900 (VNC), y la sección `vnc:` de `main.yaml` sólo
configura el sumidero JPEG, sin bloque de autenticación.

Inferir contenido del tamaño de un fichero es el mismo error de fondo que
identificar un proceso por el nombre que muestra `ps` (P0-4).

Queda una observación menor: ambos están en `644`. Sin contenido es indiferente,
pero si algún día se pueblan heredan el permiso.

**El inventario del P0-3 sí crece, por otra vía:** `S01selfCloud` guarda `TOKEN`
y `WEBRTC_PASSWORD` en claro. Está en `701` —sólo root, que es correcto— pero es
un almacén de credenciales introducido por la operación, no por el fabricante.

---

## 5. `/same_check` es un oráculo de identidad sin autenticación

El reconocimiento lo anota como "servido en claro por el puerto 80, único
`location` que no redirige a HTTPS, con CORS `*`". Sondeado, es más que eso.

Acepta un parámetro `mac` y responde si coincide con la del dispositivo:

| Petición | Respuesta |
|---|---|
| `?mac=94:83:c4:cb:25:f8` | `{"ok":true,"result":{"result":true}}` |
| `?mac=94-83-C4-CB-25-F8` | `result: false` |
| `?mac=9483c4cb25f8` | `result: false` |
| sin parámetro | `400`, `Missing MAC address parameter` |

Comparación literal, sensible al formato. Sin credencial, por HTTP plano, con
`Access-Control-Allow-Origin: *`.

**Por qué importa.** El CORS permisivo significa que cualquier página web que
visite el analista puede consultarlo desde su navegador y leer la respuesta. No
hace falta estar en la LAN: basta que alguien de la LAN abra una pestaña. Es una
vía de descubrimiento desde fuera del perímetro.

Y la MAC deriva en el `devid`: `zsb25f8` son los últimos 7 caracteres de
`9483c4cb25f8`. El diseño del hook ya asume que el `devid` no es secreto; esto lo
demuestra por una vía que no requiere sesión alguna en rttys.

**No es remediable sin romper la interfaz.** El `auth_request off` explícito en
los tres ficheros de nginx indica que la UI lo consulta antes de autenticarse.

**Sí es opción cerrar la variante en claro:** eliminar el bloque de
`nginx-kvmd.conf` (líneas 55-59) deja el endpoint accesible sólo por HTTPS. No
quita el CORS ni la falta de autenticación, pero elimina el texto plano. Requiere
verificar antes que la UI no lo consulta por HTTP, lo que depende de la captura
de red pendiente.

---

## 6. La clave de preautorización de Headscale

Al comprobar el estado de Tailscale en el dispositivo apareció un hallazgo que no
pertenece al dispositivo.

**Situación en el GL-RM1.** `tailscale.json` contiene `{"enable": false}`, no hay
daemon corriendo, y `S99tailscale` lee esa bandera con `jq`. Pero
`/etc/kvmd/user/tailscale/` conserva `tailscaled.state` (2122 B), `derpmap.cached.json`,
`files/` y `profile-data/0ba0/`: el estado de nodo persiste. El reconocimiento lo
llama "desactivado por bandera, con estado de nodo persistido", y es exacto.

**Situación en Headscale.** El nodo del KVM no figura en `nodes list` — sólo
`orchestrator-tfm`, `dc01-tfm` y `analyst-w11`, con un hueco en el ID 3 que
sugiere un nodo eliminado, coherente con el directorio `files/tfm-oob-uid-1/` y
con la fecha del 5 de septiembre en `tailscaled.state`.

**El hallazgo.** `preauthkeys list` mostraba diez claves. La ID 1 era
**reutilizable, sin usar, creada el 31 de mayo de 2026 y vigente hasta el 31 de
mayo de 2027**. Un año de validez y reutilización ilimitada.

Cualquiera con acceso a esa clave podía incorporar un nodo al tailnet sin
intervención del operador. Y el tailnet es donde viven el orquestador, DC01 y el
equipo del analista. Es de más alcance que RA-4: SSH da shell en el KVM; esta
clave daba entrada a la red interna del enclave.

La clave es anterior a todas las decisiones de aislamiento de Fase 8. **D1 —el
KVM queda fuera del tailnet— se sostenía sólo en la bandera del cliente**, no en
el servidor.

**Acción tomada.** `preauthkeys expire -i 1`. Verificado después: la clave figura
expirada y los tres nodos siguen `online`, lo que confirma que una preauthkey
autoriza el registro inicial y no sostiene la sesión. Las ID 2-7 estaban
caducadas desde agosto; las 8, 9 y 10 están usadas y no son reutilizables.

**D1 pasa a sostenerse en los dos lados:** bandera en el cliente y ninguna vía de
alta en el servidor.

**Patrón que conviene nombrar.** Una credencial creada durante el arranque del
proyecto sobrevive a las decisiones de arquitectura tomadas después, porque
ninguna fase vuelve a mirarla. No la encontró ninguna revisión: apareció tirando
de un hilo sobre otra cosa.

**Consecuencia operativa.** Ya no hay clave reutilizable para altas. El
procedimiento de alta debe crear una clave de un solo uso y vida corta en el
momento (`headscale preauthkeys create`). Si algún documento de la memoria
describe el alta con clave reutilizable, hay que actualizarlo.

---

## 7. Riesgos aceptados

### RA-4 · SSH con contraseña para `root`, abierto a la LAN

`dropbear` escucha en `0.0.0.0:22` e `:::22`. `/etc/default/dropbear` no existe,
de modo que `DROPBEAR_ARGS` es sólo `-R` y la autenticación por contraseña queda
habilitada. `/etc/shadow` tiene una única cuenta con hash válido, `root`, con
algoritmo `$6$` (SHA-512 con sal).

**Lo que cambia respecto a lo documentado.** RA-1 describe la vía de emergencia
como "abrir la web UI local y pulsar el control de potencia". Es incompleta: hay
una segunda vía, shell como root por SSH, que no pasa por kvmd, ni por nginx, ni
por `auth_request`, ni por ninguno de los 110 endpoints inventariados. El `401`
de `/api/atx/click` verificado en §2 no la cubre.

**Por qué se acepta.** La contraseña es propia, fuerte, y **distinta** de la de la
web UI, de modo que una fuga por una vía no compromete la otra. El endurecimiento
correcto —`DROPBEAR_ARGS="-s"`, sólo clave pública— exige instalar antes una
clave en `/root/.ssh/authorized_keys`, que hoy no existe. Aplicarlo sin esa
clave, o sin acceso físico garantizado al dispositivo, dejaría al operador fuera
de la vía de emergencia que RA-1 compra.

**Riesgo residual, no minimizado.** `dropbear` no limita intentos y el dispositivo
no tiene `fail2ban` ni equivalente. Un atacante en `192.168.0.0/24` puede
intentar fuerza bruta indefinidamente sin ser frenado ni registrado de forma
persistente (`access_log off`; syslog en buffer de 22 h, P2-7).

**Vía de remediación, cuando haya acceso físico garantizado.** En este orden
estricto: generar par de claves en el host, copiar la pública al dispositivo,
verificar el acceso sin contraseña **desde una sesión nueva sin cerrar la
existente**, y sólo entonces crear `/etc/default/dropbear` con
`DROPBEAR_ARGS="-s"` y reiniciar el servicio. Verificado que sólo `S50dropbear`
referencia ese fichero: nadie lo regenera y persiste por el overlay.

### RA-5 · El token del dispositivo es visible en la tabla de procesos

`rtty` recibe el token como argumento `-t`, porque así lo construye el heredoc de
`S01selfCloud`. Cualquier proceso del dispositivo puede leerlo en
`/proc/<pid>/cmdline`, sin privilegio.

Es la **cuarta vía de fuga del mismo secreto**, junto al P1-6
(`/api/script-info`), al P2-6 (`docker logs`) y al payload de `DevHookUrl`. Y la
más accesible de las cuatro: no requiere ser root, ni acceso a la plataforma, ni
leer ficheros.

**Por qué se acepta.** No es remediable desde el proyecto: `rtty` no admite el
token por otra vía que el argumento.

**Nota operativa.** El mismo valor está en `.env` del enclave (`RTTYS_TOKEN`) y en
la línea 5 de `S01selfCloud`. Una rotación exige cambiar ambos a la vez; cambiar
uno solo deja el KVM fuera de línea.

### RA-6 · `/same_check` divulga identidad sin autenticación

Descrito en §5. Se acepta porque no es remediable sin romper la interfaz, y
porque lo que divulga —la MAC, y con ella el `devid`— el diseño del hook ya
trataba como no secreto.

Queda como acción propuesta cerrar la variante por el puerto 80.

---

## 8. Correcciones aplicadas

**`/etc/dropbear` estaba en `777`.** El directorio que contiene la clave de host
SSH era escribible por cualquier usuario. La clave en sí estaba en `600`, pero eso
no protege: borrar un fichero depende del permiso del directorio. Un proceso sin
privilegios podría haber sustituido la clave de host, invalidando cualquier
verificación de huella por parte del cliente. Corregido a `755`.

Barrido posterior sin más hallazgos: `find /etc/kvmd /etc/dropbear /etc/snmp
-type d -perm -o+w` y su equivalente para ficheros devuelven vacío.

**Residuos de edición eliminados de `/etc/kvmd/user/scripts/`:**

- `.S01selfCloud.swp`, fichero de intercambio de vim de una sesión interrumpida,
  con permisos `644` frente al `701` del script original. El endurecimiento de
  permisos del script quedaba anulado por un artefacto que nadie miró. Verificado
  que **no** contenía el token.
- `S01selfCloud.bak-19700101`. Peor que un residuo: **coincide con el patrón
  `S??*` de `S99custom` y se ejecutaba como root en cada arranque**, junto al
  original. La colisión estaba amortiguada por casualidad — el `pgrep` de la línea
  16 hace que el segundo en ejecutarse encuentre el watchdog ya corriendo y
  salga—, no por diseño. Con valores distintos y otra ordenación, habría arrancado
  con la configuración antigua.

Ambos son de operación, no del fabricante. La convención `fichero.bak` es segura
en casi cualquier directorio; en este no, porque el patrón es `S??*` y no exige
extensión.

**Clave de preautorización ID 1 expirada** en Headscale. Ver §6.

**Recortes propuestos, no aplicados:** `ntpd` escuchando en `0.0.0.0:123` cuando
el dispositivo sólo necesita ser cliente; y el bloque de `/same_check` en el
puerto 80.

---

## 9. Propuesta pendiente · activar el segundo factor de kvmd

El P2-9 documenta que `/api/2fa/is_enabled` responde `{"enabled":false}` sin
autenticación: el dispositivo anuncia a cualquiera de la LAN que no tiene segundo
factor. `totp.secret` está a 0 bytes.

Activarlo cierra el P2-9 y **no toca SSH**, de modo que no compromete la vía de
emergencia de RA-4.

**Alcance real.** El TOTP es de kvmd, la web UI. `dropbear` no lo consulta.
Protege la vía que RA-1 describe y deja RA-4 exactamente igual.

**Precauciones antes de activar.** Es la interfaz de emergencia: perder el secreto,
o una deriva del reloj, dejan al operador fuera. El secreto debe guardarse **fuera
del enclave** antes de activar. El reloj importa: `ntpd` corre, pero el
dispositivo ha estado periodos largos sin red.

**Verificación propuesta.** Activar, guardar el secreto, cerrar sesión, comprobar
el acceso con código, y confirmar que `/api/2fa/is_enabled` pasa a `true` — lo que
cierra el P2-9 y, de paso, vuelve a demostrar que el endpoint sigue siendo
público, que es el hallazgo en sí.

---

## 10. Limitación del método · las métricas de continuidad no son extrapolables

Durante el inventario se observó un `load average` de 10,6 sostenido con las
cuatro CPU ociosas, 24.452 reintentos acumulados del watchdog de rtty, y en
`dmesg` una caída del enlace ethernet de casi 9 horas.

**No es inestabilidad del dispositivo.** El laboratorio no está permanentemente
encendido: se alimenta cuando hay trabajo sobre el proyecto. Las caídas de enlace
son apagados del switch, y los reintentos son el watchdog haciendo su trabajo
mientras no había red —y reconectando solo en cada ocasión, que es buena señal.

**Lo que sí debe quedar escrito:** cualquier métrica de continuidad tomada en este
laboratorio está contaminada por el ciclo de encendido. Afecta al uptime, al
tamaño del log de rtty y a los `device_online` sin su `device_offline`
correspondiente del P1-5. Una afirmación sobre disponibilidad basada en estos
datos, sin ese matiz, no sería honesta.

Y afecta a una conclusión del §8 del reconocimiento: la detección del
`powerreset` del nivel 2 se delega en un observador independiente —Wazuh en DC01,
o la caída de su heartbeat vista desde el enclave—. En un entorno con cortes de
alimentación programados, un heartbeat ausente es indistinguible de un apagado
provocado. El observador independiente requiere que la alimentación no lo sea.

---

## 11. Nota sobre instrumentos

Dos instrumentos falsos durante este inventario, ambos del mismo tipo: salida
plausible en lugar de error.

- **`ps w`** devolvió 5 procesos en un sistema con 162. Sin argumentos, busybox
  lista sólo los del terminal actual. Leído tal cual, llevaba a concluir que el
  watchdog de rtty había muerto y que la vía de recuperación estaba sin
  supervisión. `netstat -tnp` dio la respuesta correcta identificando por conexión
  y PID en lugar de por nombre.
- **`awk '$9!="S"'`** sobre la salida de `top` no filtró nada, porque la columna de
  estado no es la novena en este `top`. Devolvió la lista entera en lugar de
  fallar.

Y dos más que no llegaron a producir conclusión falsa porque se contrastaron a
tiempo: un `2>/dev/null` que ocultó errores de sintaxis de `headscale` y devolvió
salida vacía indistinguible de "no hay claves"; y la primera consulta a
`/same_check`, donde `false` para la MAC real significaba formato incorrecto y no
ausencia de oráculo.

Se suman a la serie del §1 del reconocimiento. El patrón común: el instrumento no
protesta, devuelve algo peor de lo que se cree, y la única defensa es contrastar
con un segundo instrumento que mida lo mismo por otra vía.
