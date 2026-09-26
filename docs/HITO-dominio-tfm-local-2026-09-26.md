# Hito · Promoción de `dc01-tfm` a controlador del dominio `tfm.local`

**Fecha:** 2026-09-26 · **Fase:** 4 (break-glass y scripts DC), con efecto en
las fases 1 (Wazuh), 5B (Velociraptor) y 8 · **Estado:** promoción y unión
acreditadas por evidencia; ejecución real acreditada para `disable_account.ps1`
y `enable_account.ps1`; auditoría en el SIEM de esa ejecución **no acreditada**
(ver §3.4 y §5.3).

Las evidencias se guardaron fuera del repositorio, en
`~/tfm-evidencias/dominio-tfm-local/`. Todos los ficheros llevan fecha de
modificación del 2026-09-26. Los cuatro ficheros de salida (`dc01.txt`,
`w11.txt`, `prueba-real.txt`, `enclave.txt`) están en
`desplegado/scripts/`, junto a las copias de los scripts, y no en la raíz de
la carpeta como indicaba el procedimiento. No afecta a su contenido.

> **Actualización (2026-09-27).** La auditoría en el SIEM de la ejecución real
> no se acreditó porque el agente escribía su registro en una ruta que Wazuh
> no lee. Es el hallazgo P1 de §5.6: el entorno del servicio estuvo incompleto
> del 12/09 al 27/09, y durante ese tiempo la firma HMAC tampoco se exigía.
> Está corregido y verificado por comportamiento: la alerta `100601` vuelve a
> llegar. Los `PENDIENTE` de la prueba real (§3.3, §4) se han completado con
> el log conservado `C:\tfm-agent\logs\agent.log` y con las comprobaciones
> de Jose del 26 y 27/09.

## 1. Qué cambió

- **`dc01-tfm` (Windows Server 2025)** pasa de servidor independiente a
  controlador del dominio `tfm.local`. Nivel funcional `Windows2025Domain`,
  NetBIOS `TFM`, titular del rol de emulador de PDC y catálogo global
  (`DomainRole : 5`, controlador principal).
- **`analyst-w11` (Windows 11)** se une al dominio. El nombre del equipo en
  Windows es `W11`, y el del nodo en el tailnet sigue siendo `analyst-w11`.
- **Scripts del agente.** En el DC, `disable_account.ps1` y
  `enable_account.ps1` ejecutan la orden real (`Disable-ADAccount`,
  `Enable-ADAccount`). **El resto de scripts no se ha activado.** En el DC,
  `reset_password.ps1` e `isolate_host.ps1` son idénticos byte a byte a los del
  repositorio y siguen en modo simulación (§3.1). La afirmación de partida de
  que «los scripts» se habían activado vale solo para estos dos.

## 2. Por qué se hizo al final

La funcionalidad de la plataforma no depende del dominio. El canal
out-of-band, la aprobación de dos personas, la firma HMAC, la entrega de
credenciales, la colección forense y el Plan C funcionan igual sobre un
servidor independiente. Todo eso se validó así.

La promoción tiene dos efectos. Wazuh pasa a observar un Directorio Activo
real, con su telemetría de Kerberos, replicación y cambios de objetos. Los
scripts de respuesta actúan sobre cuentas de dominio reales. Se dejó para
después de verificar todas las fases, para que un cambio de identidad del
host más vigilado no interfiriera con las validaciones en curso.

## 3. Evidencias

Transcritas de los ficheros aportados, sin secretos. Los hashes SHA-256 son de
ficheros de código, no de credenciales.

### 3.1 `dc01-tfm` (A1, `dc01.txt`)

```text
DNSRoot     : tfm.local
NetBIOSName : TFM
DomainMode  : Windows2025Domain
PDCEmulator : DC01-TFM.tfm.local

Name       : DC01-TFM
Domain     : tfm.local
DomainRole : 5

Name          Status StartType
Tailscale    Running Automatic
TFM-DC-Agent Running Automatic
Velociraptor Running Automatic
WazuhSvc     Running Automatic

Name         StartName
TFM-DC-Agent LocalSystem

tailscale ip -4 → 100.64.0.2
```

Hashes SHA-256 de lo desplegado, comparados con el repositorio
(`fase4-breakglass-dc/`, HEAD `db8aad0`):

| Fichero en el DC | SHA-256 en el DC (prefijo) | Repositorio | Resultado |
|---|---|---|---|
| `collect_logs.ps1` | `298EEA7D…` | idéntico | = |
| `disable_account.ps1` | `05376517…` | `f165c007…` | ≠ (activación + bloque comentado adicional, §5.1) |
| `enable_account.ps1` | `DB30A540…` | `7b3cc23d…` | ≠ (activación + bloque comentado adicional, §5.1) |
| `isolate_host.ps1` | `C15AEE0E…` | idéntico | = (sigue en simulación) |
| `reset_password.ps1` | `63713FA5…` | idéntico | = (sigue en simulación) |
| `rustdesk_disable.ps1` | `F577CEC9…` | idéntico | = |
| `rustdesk_enable.ps1` | `5B3E5905…` | `8267ce8a…` | ≠ (versión anterior, §5.1) |
| `agent_dc.py` | `65A813A0…` | `8b1bb2f5…` | ≠ (versión del commit `8b00bdf`, §5.2) |

Las copias de los siete `.ps1` en `desplegado/scripts/` tienen los mismos
hashes que `dc01.txt`: son fieles a lo que corre en el DC. **Falta la copia de
`agent_dc.py`** (`desplegado/agent_dc.py`): `PENDIENTE`. La comparación de
§5.2 se ha hecho por hash contra el historial de git.

### 3.2 `analyst-w11` (A2, `w11.txt`)

```text
Name         : W11
Domain       : tfm.local
PartOfDomain : True

nltest /dsgetdc:tfm.local
  DC: \\DC01-TFM.tfm.local
  Dirección: \\192.168.127.153
  Nombre del dominio: tfm.local · Nombre del bosque: tfm.local
  Marcas: PDC GC DS LDAP KDC TIMESERV GTIMESERV WRITABLE DNS_DC DNS_DOMAIN DNS_FOREST CLOSE_SITE …

InterfaceAlias ServerAddresses
Ethernet0      {192.168.127.153, 192.168.127.2}

chat.oob.local  100.64.0.1  TcpTestSucceeded True
iris.oob.local  100.64.0.1  TcpTestSucceeded True

tailscale status →
failed to connect to local tailscaled (which appears to be running as
tailscaled.exe, pid 8900). Got error: 401 Unauthorized: Tailscale running in
server mode ("W11\\jose"); connection from "TFM\\jose" not allowed
```

**Resolución de `*.oob.local`: sin cambios.** `chat.oob.local` e
`iris.oob.local` siguen resolviendo a `100.64.0.1`, que es lo que declara
`docs/resolucion-nombres.tsv` para el host `w11`. El DNS primario del W11 es
ahora el DC (`192.168.127.153`), pero el fichero `hosts` sigue teniendo
precedencia. No se ha modificado ni `resolucion-nombres.tsv` ni su
documentación. `PENDIENTE`: ejecutar `scripts/verify-hosts.sh` para
confirmarlo con el verificador.

`tailscale status` falla (§5.4). La conexión TCP a `100.64.0.1:443` prueba que
el túnel sigue operativo. Lo que no funciona es el control del cliente desde
la cuenta de dominio.

### 3.3 Prueba de ejecución real (A3, `prueba-real.txt`)

Transcripción de los mensajes de la war room (hora local del cliente):

```text
22:41 ir_lead   !ir run disable_account.ps1 tfmuser
22:41 bot       Solicitud REQ-b2a531dc pendiente de aprobación
                Acción: Ejecutar disable_account.ps1 sobre tfmuser · Solicitante: ir_lead
22:42 ir_lead2  !ir approve REQ-b2a531dc
22:42 bot       Acción ejecutada — solicitud REQ-b2a531dc
                Script: disable_account.ps1 · Código: 0
                Solicitado por: ir_lead · Aprobado por: ir_lead2
                TFM-AGENT: Deshabilitando cuenta AD: tfmuser

22:43 ir_lead2  !ir run enable_account.ps1 tfmuser
22:43 bot       Solicitud REQ-cf55f263 pendiente de aprobación
                Acción: Ejecutar enable_account.ps1 sobre tfmuser · Solicitante: ir_lead2
22:43 ir_lead   !ir approve REQ-cf55f263
22:43 bot       Acción ejecutada — solicitud REQ-cf55f263
                Script: enable_account.ps1 · Código: 0
                Solicitado por: ir_lead2 · Aprobado por: ir_lead
                TFM-AGENT: Habilitando cuenta AD: tfmuser
```

Diferencias con el procedimiento previsto:

- La cuenta de prueba es **`tfmuser`**, no `usuario.prueba`. No hay evidencia
  de su creación ni de que carezca de privilegios: `PENDIENTE`.
- **Faltan las dos consultas `(Get-ADUser tfmuser).Enabled`**: `PENDIENTE`.
  Sin ellas, lo que acredita el cambio de estado es la ausencia de la línea
  `DRY-RUN OK` en la salida y el código de salida `0`. Eso prueba que se
  ejecutó el script activado sin error. No prueba el estado resultante de la
  cuenta.
- Las dos aprobaciones cruzan solicitante y aprobador (`ir_lead` → `ir_lead2`
  y `ir_lead2` → `ir_lead`), como exige la regla de dos personas.

> **Actualización (2026-09-27).** Completado con el registro del agente de
> esa noche, `C:\tfm-agent\logs\agent.log`, líneas 33–40. La copia se
> conserva en `~/tfm-evidencias/dominio-tfm-local/agent-log-C-tfm-agent-2026-09-12_2026-09-26.log`
> (ver §5.6):
>
> ```text
> 33  2026-09-26 22:33:38,483 INFO EJECUCION script=disable_account.ps1 target=tfm
> 34  2026-09-26 22:33:40,757 INFO RESULTADO script=disable_account.ps1 returncode=0
> 35  2026-09-26 22:40:04,064 INFO EJECUCION script=enable_account.ps1 target=tfm
> 36  2026-09-26 22:40:05,689 INFO RESULTADO script=enable_account.ps1 returncode=0
> 37  2026-09-26 22:42:17,802 INFO EJECUCION script=disable_account.ps1 target=tfmuser
> 38  2026-09-26 22:42:19,472 INFO RESULTADO script=disable_account.ps1 returncode=0
> 39  2026-09-26 22:43:42,414 INFO EJECUCION script=enable_account.ps1 target=tfmuser
> 40  2026-09-26 22:43:43,884 INFO RESULTADO script=enable_account.ps1 returncode=0
> ```
>
> - Antes de la prueba con `tfmuser` hubo una primera pareja sobre la cuenta
>   `tfm` (22:33 y 22:40), con código 0. Jose confirma que la cuenta quedó
>   habilitada. No consta en `prueba-real.txt` ni hay evidencia de los
>   privilegios de `tfm`.
> - Estado final: `(Get-ADUser tfmuser).Enabled` es `True`. `tfmuser` solo
>   pertenece a «Usuarios del dominio» y «Usuarios»: es una cuenta sin
>   privilegios.
> - **El estado intermedio (deshabilitada) no se capturó.** El efecto de
>   `disable_account.ps1` se acredita por el código 0 del script activado, no
>   por una consulta al directorio.

### 3.4 Enclave (A4, `enclave.txt`)

```text
Wazuh agent_control. List of available agents:
   ID: 000, Name: wazuh.manager (server), IP: 127.0.0.1, Active/Local
   ID: 001, Name: W11, IP: any, Active
   ID: 002, Name: DC01-TFM, IP: any, Active
   ID: 003, Name: ubuntuserver, IP: any, Active
```

Los nombres e identificadores de agente no cambian con la unión al dominio.
Son los mismos que registra el censo M-24
(`docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:783`) y la validación de la
Fase 4 (`"agent":{"id":"002","name":"DC01-TFM"}`,
`docs/README-fase4-validacion.md:360`).

**La segunda orden (`grep` de las reglas 100600–100609 en `alerts.json`) no
produjo salida.** El fichero recoge las dos órdenes y solo el resultado de la
primera. Ver §5.3.

## 4. Resultado de la prueba real

| Acción | Solicitud | Solicitante → aprobador | Código de salida | Estado de la cuenta (`Get-ADUser … .Enabled`) | Alerta SIEM `100601` |
|---|---|---|:-:|:-:|:-:|
| `disable_account.ps1 tfmuser` | `REQ-b2a531dc` | `ir_lead` → `ir_lead2` | `0` | no capturado (esperado `False`) | no generada: log en ruta no monitorizada (§5.6) |
| `enable_account.ps1 tfmuser` | `REQ-cf55f263` | `ir_lead2` → `ir_lead` | `0` | `True` | no generada: log en ruta no monitorizada (§5.6) |

> **Actualización (2026-09-27).** Tabla completada. La primera versión decía
> `PENDIENTE` en el estado de la cuenta y «no encontrada» en la alerta. El
> estado final procede de la consulta de Jose; el intermedio no se capturó.
> Las alertas no existieron: las líneas 37–40 se escribieron en
> `C:\tfm-agent\logs\agent.log`, que Wazuh no lee. La cadena
> agente → Wazuh se verificó después de la corrección con otra ejecución
> (`REQ-9253813e`, §5.6).

`reset_password.ps1` e `isolate_host.ps1` no se ejecutaron, como estaba
previsto. Además, en el DC siguen en simulación (§3.1).

> **Actualización (2026-09-27).** No se ejecutaron *en esta prueba*. El log
> conservado registra una ejecución anterior de `reset_password.ps1` sobre
> `tfmuser` el 24/09 a las 14:46:44 (líneas 25–26, código 0), y tres de
> `disable_account.ps1` sobre `tfmuser` el mismo día (líneas 27–32). No hay
> evidencia de qué versión de los scripts había en el DC el 24/09. Ver §5.5.

## 5. Hallazgos

### 5.1 Scripts desplegados que no coinciden con el repositorio (B2)

- **`disable_account.ps1` y `enable_account.ps1`.** Además de la activación
  (orden real descomentada y línea `DRY-RUN OK` comentada), la versión del DC
  añade al principio un bloque comentado de nueve líneas, «Para server
  standalone», con la variante `Disable-LocalUser`/`Enable-LocalUser`. Es
  inerte, pero es una diferencia distinta de la activación. **No se ha
  sustituido el fichero del repositorio: decisión de Jose.** Las opciones son
  copiar la versión desplegada tal cual (el repositorio documentaría también
  la variante independiente) o activar el repositorio sin el bloque, lo que
  obliga a retirarlo también en el DC para que los hashes coincidan.
- **`rustdesk_enable.ps1`.** La versión del DC es **anterior** a la del
  repositorio. Le faltan el `try/catch` alrededor de `rustdesk.exe --password`
  (con su lista `warnings`), la salida ordenada y el comentario sobre la
  procedencia del identificador. Usa 20 bytes aleatorios en lugar de 16, añade
  `Start-Sleep -Seconds 3`, `-NonInteractive` en la tarea `RustDesk-AutoOff` y
  `-ErrorAction SilentlyContinue` con valor `NO_CREADA` al consultar la tarea.
  No tiene que ver con el dominio. **Decisión de Jose:** decidir qué versión
  es la buena y alinear la otra. La prueba 7 de
  `docs/README-fase4-validacion.md` (`warnings: []`) describe un campo que la
  versión del DC sí emite, dentro de `$result`.
- **Credenciales literales:** ninguna. Los siete scripts desplegados solo
  contienen `password` como nombre de campo o de variable (contraseña de
  sesión de RustDesk generada en tiempo de ejecución y contraseña generada por
  `reset_password.ps1`). No hay ningún valor fijo.

### 5.2 `agent_dc.py` desplegado es la versión de `8b00bdf` (B3)

No se aportó la copia desplegada (`PENDIENTE`), pero el hash de `dc01.txt`
basta para identificarla. `65A813A0…` coincide exactamente con
`git show 8b00bdf:fase4-breakglass-dc/dcagent/agent_dc.py` convertido a CRLF,
es decir, la versión del 2026-08-26. No coincide con la de HEAD (último cambio
en `397ea99`, 2026-09-01), ni en LF ni en CRLF. Diferencias entre ambas:

```diff
-LOG_PATH = Path(os.environ.get("TFM_LOG_PATH", r"C:\tfm-agent\logs\agent.log"))
+LOG_PATH = Path(os.environ.get("TFM_LOG_PATH", r"C:\tfm-dc-agent\logs\agent.log"))
@@ async def health():
+        "token_configured": bool(VALID_TOKEN),
```

Consecuencias:

- **`/health` del agente en ejecución no emite `token_configured`.** Pero
  `docs/README-fase4-validacion.md:45` y `docs/README-fase4c-dcagent.md:492`
  muestran una salida de `/health` con ese campo. O el DC ejecutó en algún
  momento la versión nueva y después se restauró la anterior, o esas salidas
  no proceden de este fichero. `PENDIENTE`: `curl -s http://100.64.0.2:8000/health`
  desde el orquestador lo resuelve.
- **La ruta de log por defecto es otra.** Si el servicio NSSM no define
  `TFM_LOG_PATH`, el agente escribe en `C:\tfm-agent\logs\agent.log`. El
  `localfile` de Wazuh y la regla `100600` (`<location>tfm-dc-agent</location>`)
  vigilan `C:\tfm-dc-agent\logs\agent.log`. Es una causa posible de §5.3,
  no comprobada.

**Hallazgo:** lo desplegado en el DC no es lo versionado. El repositorio no
acredita qué código ejecuta hoy el servicio que actúa sobre el dominio.

> **Actualización (2026-09-27).** La segunda consecuencia se confirmó: el
> servicio no definía `TFM_LOG_PATH` y el agente escribía en la ruta por
> defecto de la versión `8b00bdf`. Ver §5.6. La primera sigue abierta. El
> `/health` posterior a la corrección confirma `"hmac_required":true`, pero no
> hay evidencia sobre `token_configured`. Tampoco se ha redesplegado
> `agent_dc.py` de HEAD (pendiente 8).

### 5.3 La ejecución real no aparece en el SIEM (A4)

La prueba de §4 debió producir al menos dos alertas `100601` («ejecución de
script en DC») entre las 22:41 y las 22:43. El `grep` sobre `alerts.json` no
devolvió nada. Con la evidencia disponible no se puede distinguir entre:

1. el agente escribe en otra ruta (§5.2);
2. el agente Wazuh del DC dejó de leer el `localfile` tras la promoción;
3. un fallo de la propia consulta (fichero rotado o patrón distinto del que
   se esperaba).

`PENDIENTE`, sin volcar el entorno del servicio (contiene `AGENT_TOKEN` y
`AGENT_HMAC_SECRET`):

- En el DC: `Test-Path C:\tfm-agent\logs\agent.log`,
  `Get-Content C:\tfm-dc-agent\logs\agent.log -Tail 10`.
- En el enclave: el mismo `grep` sobre `/var/ossec/logs/archives/` si el
  archivado está activo, o una búsqueda por `rule.id:1006*` en el panel de
  Wazuh.

Mientras no se resuelva, la fila «Auditoría extremo a extremo en el SIEM»
(`fase4-breakglass-dc/README.md`) vale para la validación en simulación del
2026-08-27, no para la ejecución real.

> **Actualización (2026-09-27).** Causa determinada: la hipótesis 1. El
> servicio no tenía `TFM_LOG_PATH`, y el agente escribía en
> `C:\tfm-agent\logs\agent.log` desde el 12/09. Corregido y verificado con
> la alerta `100601` de `REQ-9253813e`. Detalle en §5.6.

### 5.4 `tailscale` no se controla desde la cuenta de dominio en el W11

`tailscaled` corre en *server mode* ligado a la cuenta local `W11\jose`, y
rechaza a `TFM\jose` con `401 Unauthorized`. El túnel funciona (§3.2). Pero el
analista, con sesión de dominio, no puede consultar ni cambiar el estado del
cliente, y un `tailscale up` o un reenrolado exigen volver a la cuenta local.
Severidad baja: afecta a la operación, no al canal. `PENDIENTE`: decidir si se
reasigna el modo servidor a la cuenta de dominio o se documenta el uso de la
cuenta local.

### 5.5 P1 · `reset_password.ps1` publicaría la contraseña nueva en la war room (B4)

**Cadena, con el script activado:**

1. `fase4-breakglass-dc/scripts/reset_password.ps1:6` genera la contraseña, y
   `:15` la emite en stdout como JSON:
   `@{ target = $target; password = $newPass; must_change = $true } | ConvertTo-Json -Compress`.
2. `fase4-breakglass-dc/dcagent/agent_dc.py:201` y `:208` devuelven ese stdout
   al orquestador, saneado solo de caracteres de control y truncado a 8.000
   caracteres. No redacta nada.
3. `fase4-breakglass-dc/workflows/fase4d-breakglass.json:39` (`Parse Command`)
   admite `reset_password.ps1` en `!ir run`.
4. `fase4-breakglass-dc/workflows/fase4d-breakglass.json:415` (`Build Agent
   Reply`): solo la rama `meta.verb === 'rustdesk'` desvía la credencial al
   almacén de un solo uso. Para `run`, la rama `else` publica
   `String(agent.stdout).slice(0, 1200)` en el canal. La salida completa de
   `reset_password.ps1` son dos líneas `TFM-AGENT`/`DRY-RUN` y un JSON de unos
   80 caracteres, muy por debajo del límite, así que **la contraseña se
   publica completa**.

**Efecto:** la contraseña nueva de una cuenta de `tfm.local` quedaría en el
historial permanente de la sala, visible para todos sus miembros y
sincronizada a los clientes. También quedaría en los datos de ejecución de
n8n (salida del nodo `Call DC Agent`). `-ChangePasswordAtLogon` no lo mitiga.
Quien lea el canal antes que el titular puede iniciar sesión y fijar su propia
contraseña. Es exactamente el riesgo que el proyecto ya descartó para RustDesk
(`docs/README-fase4d-flujo-aprobacion.md:163-166`).

**Estado hoy:** latente. En el DC, `reset_password.ps1` sigue en simulación
(§3.1). La contraseña que publica no se aplica a ninguna cuenta. El hallazgo
se materializa en el momento en que se active.

**Corrección propuesta (no aplicada; decisión de Jose):**

- En `Build Agent Reply`, tratar `reset_password.ps1` como la rama de
  RustDesk. Si `salida.password` existe, guardarla en `store.credentials` con
  TTL y publicar solo el enlace a `/webhook/bg-credential` (Authelia,
  `group:ir_lead`, `two_factor`, entrega única). En general, no publicar
  nunca el stdout en bruto de un script cuya última línea JSON tenga campo
  `password`.
- Complementario: que `reset_password.ps1` no emita la contraseña en claro en
  la misma salida que las líneas informativas, o que el agente la redacte
  antes de devolverla y la entregue por un canal aparte.
- Hasta entonces, no activar `reset_password.ps1` en el DC.

> **Actualización (2026-09-27).** Este camino ya se recorrió una vez. El log
> conservado registra `reset_password.ps1 target=tfmuser` el 24/09 a las
> 14:46:44, con código 0 (líneas 25–26). Por el código de `Build Agent Reply`,
> el bot debió de publicar en la sala la contraseña generada. Si el script del
> DC era entonces la versión en simulación (lo es el 26/09, §3.1), esa
> contraseña no se aplicó a la cuenta. No hay evidencia de la versión del
> 24/09 ni del mensaje publicado. `PENDIENTE`: revisar en la war room el
> mensaje de esa solicitud y, si la contraseña se hubiera aplicado, tratarla
> como comprometida.

### 5.6 Hallazgo P1 · Entorno incompleto del servicio del agente (12–27/09)

**Clasificación: fallo silencioso.** Durante unos 14 días, `/health`
respondió `"status":"ok"`. El agente ejecutó con normalidad, con código 0 y
el resultado publicado en la war room. Mientras tanto, **la firma HMAC no se
exigía y ninguna ejecución llegaba al SIEM.** Ningún componente dio una señal
de error.

> **Actualización (2026-09-27).** Incorporado al catálogo de fallos
> silenciosos como caso **B39** (familia B, mecanismo M2 «Lo declarado no es
> lo desplegado», con M5 como asignación discutible):
> [`CATALOGO-fallos-silenciosos.md`](CATALOGO-fallos-silenciosos.md) §3.

**Síntoma.** La ejecución real de §4 no produjo la alerta `100601` esperada
(§3.4, §5.3). Al comparar la ruta que monitoriza Wazuh con la ruta en la que
escribía el agente, y al leer `/health`, apareció el resto.

**Cronología.**

| Momento | Hecho | Fuente |
|---|---|---|
| 12/09/2026 23:36:55 | Última escritura en `C:\tfm-dc-agent\logs\agent.log`, la ruta que monitoriza Wazuh (`ossec.conf` del agente Wazuh del DC, línea 40, `<location>`) | Salida de Jose |
| 12/09/2026 23:57:44 | Primera línea de `C:\tfm-agent\logs\agent.log`: `EJECUCION script=rustdesk_enable.ps1` | Log conservado, línea 1 |
| 12/09 – 26/09 | 20 ejecuciones registradas solo en la ruta no monitorizada: `rustdesk_enable.ps1` (11), `collect_logs.ps1` (1), `reset_password.ps1` (1), `disable_account.ps1` (5), `enable_account.ps1` (2). Todas con código 0 | Log conservado, líneas 1–40 |
| 26/09/2026 22:43:43 | Última escritura en `C:\tfm-agent\logs\agent.log` | Log conservado, línea 40 |
| 27/09/2026 ~00:1x | Corrección del entorno y reinicio del servicio | Salida de Jose |
| 27/09/2026 00:13:13 | Primera ejecución verificada tras la corrección (`REQ-9253813e`) | `C:\tfm-dc-agent\logs\agent.log`, líneas 117–118 |

**Causa probable.** Se reescribió `AppEnvironmentExtra` con solo dos
variables. Antes de la corrección, la clave del servicio `TFM-DC-Agent`
contenía únicamente `AGENT_TOKEN` y `AGENT_HMAC_SECRET`. Faltaban
`AGENT_REQUIRE_HMAC`, `TFM_SCRIPTS_DIR`, `TFM_LOG_PATH` y `TFM_HEADSCALE_IP`.
El riesgo estaba documentado: `AppEnvironmentExtra` reemplaza el conjunto
completo de variables, no lo fusiona (advertencia operativa en
`docs/README-fase4c-dcagent.md:660-664`). No consta qué operación reescribió
la clave el 12/09 entre las 23:36 y las 23:57.

**Efecto.**

- **Firma HMAC no exigida.** Sin `AGENT_REQUIRE_HMAC=true`, la versión
  desplegada (`8b00bdf`) toma `false` por defecto, y `/health` devolvía
  `"hmac_required": false`. Siguieron activos el token Bearer y la ACL del
  tailnet, pero no la protección contra replay ni la firma del cuerpo que
  documenta el Paso 9.
- **Auditoría fuera del SIEM.** Sin `TFM_LOG_PATH`, el agente usó su ruta por
  defecto, `C:\tfm-agent\logs\agent.log`. El `localfile` de Wazuh no la lee y
  la regla `100600` no la cubre. Ninguna de las 20 ejecuciones del periodo
  generó `100601` ni `100603`, incluidas las once activaciones de acceso
  remoto con RustDesk.
- **Duración:** del 12/09 a las 23:57 al 27/09 hacia las 00:1x, unos 14 días.
- **Consecuencia latente.** `isolate_host.ps1` lee `TFM_HEADSCALE_IP`
  (`fase4-breakglass-dc/scripts/isolate_host.ps1:5`) para la regla que
  preserva el control plane del canal OOB. Sin la variable, esa regla habría
  recibido una dirección vacía; qué habría hecho `New-NetFirewallRule` en ese
  caso no está comprobado. El script no se ejecutó en el periodo.
- `TFM_SCRIPTS_DIR` ausente no tuvo efecto: el valor por defecto del agente es
  el mismo, `C:\tfm-scripts`.

**Corrección (27/09/2026).** Se reescribió `AppEnvironmentExtra` conservando
`AGENT_TOKEN` y `AGENT_HMAC_SECRET` sin mostrarlos, y se añadió:

```text
AGENT_REQUIRE_HMAC=true
TFM_SCRIPTS_DIR=C:\tfm-scripts
TFM_LOG_PATH=C:\tfm-dc-agent\logs\agent.log
TFM_HEADSCALE_IP=192.168.127.138
```

Después se reinició el servicio, que quedó en `Running`.

**Verificación por comportamiento.**

1. `curl -s http://100.64.0.2:8000/health` devuelve `"hmac_required":true`.
2. `REQ-9253813e` (`!ir run collect_logs.ps1 dc-signed-selftest`, solicitada
   por `ir_lead` y aprobada por `ir_lead2`) se ejecuta con código 0. Con la
   firma ya exigida, eso demuestra que n8n firma con el mismo secreto que el
   agente.
3. `C:\tfm-dc-agent\logs\agent.log`, líneas 117–118: `EJECUCION` a las
   00:13:13,985 y `RESULTADO returncode=0` a las 00:13:20,865 del 27/09.
4. Wazuh: alerta `100601` («TFM Break-glass: ejecucion de script en DC») del
   agente `002 DC01-TFM`, con `location` `C:\tfm-dc-agent\logs\agent.log`, a
   las 22:13:13 UTC del 26/09, que son las 00:13:13 locales del 27/09. Es la
   misma ejecución.

Control reutilizable: `scripts/verify-dcagent-health.sh` falla si `/health`
no es JSON o no declara `"hmac_required": true`.

**Evidencia conservada.** El log `C:\tfm-agent\logs\agent.log` queda en el
DC. La copia está en
`~/tfm-evidencias/dominio-tfm-local/agent-log-C-tfm-agent-2026-09-12_2026-09-26.log`,
fuera del repositorio.

#### Conservación de evidencia

Por decisión de Jose (27/09/2026), el log se conserva como evidencia y **no se
versiona**. En el repositorio solo se cita su hash. Fuente:
`~/tfm-evidencias/dominio-tfm-local/conservacion-log.txt`.

| Elemento | Valor |
|---|---|
| Original | `C:\tfm-agent\logs\agent.log` en `dc01-tfm` |
| Solo lectura en el DC | Se ordenó con `Set-ItemProperty … -Name IsReadOnly -Value $true`. `conservacion-log.txt` no recoge ninguna salida que lo confirme: `PENDIENTE` (`(Get-Item C:\tfm-agent\logs\agent.log).IsReadOnly`) |
| Copia | `~/tfm-evidencias/dominio-tfm-local/agent-log-C-tfm-agent-2026-09-12_2026-09-26.log` (3.686 bytes, 40 líneas, permisos `0555`) |
| SHA-256 del original (`Get-FileHash`, DC) | `7917E284C62E84F991DEB4669BEE62B35B7653622AB53A33AF420CB1505F15EC` |
| SHA-256 de la copia (`sha256sum`, enclave) | `7917e284c62e84f991deb4669bee62b35b7653622ab53a33af420cb1505f15ec` |
| ¿Coinciden? | **Sí** (la diferencia es solo de mayúsculas). Recalculado el 27/09 con el mismo resultado |
| Rango temporal | Del 12/09/2026 a las 23:57:44,486 (línea 1) al 26/09/2026 a las 22:43:43,884 (línea 40) |

La copia actual se creó a las 00:33:33 del 27/09 y conserva como fecha de
modificación la del original (26/09 22:43:43,884). Una copia anterior
(00:29, 3.646 bytes) tenía 40 bytes menos, uno por línea, lo que apunta a
finales de línea convertidos. Se sustituyó antes de tomar los hashes, así que
no afecta a la tabla, pero de ella no se conserva ningún hash.

### 5.7 P2 · Acentos mal codificados en la salida de `collect_logs.ps1`

La salida de `collect_logs.ps1` publicada en la war room para `REQ-9253813e`
muestra los acentos mal codificados («Informaci¢n»). Por el carácter, parece
que la consola usa la página de códigos OEM 850 y n8n decodifica en otra. No
está comprobado. Afecta a la legibilidad y, potencialmente, al hash que
calcula el propio script si el texto se re-codifica por el camino. No afecta a
la ejecución. `PENDIENTE` de diagnóstico.

## 6. Impacto en la validez de lo documentado

- **Todas las validaciones del repositorio son anteriores a la promoción.** La
  de la Fase 4 (2026-08-27, `docs/README-fase4-validacion.md`) se hizo sobre
  un servidor independiente y con los scripts en simulación. Sus salidas
  `DRY-RUN OK` son correctas para esa fecha. Lo mismo vale para las fases 5B,
  6, 7 y 8, y para la auditoría de cierre (`docs/AUDITORIA-CIERRE-2026-09-23.md`).
- **El censo de alertas M-24** (52.513 alertas en cuatro meses) mide un DC sin
  Directorio Activo. Las alertas propias del Directorio Activo (Kerberos,
  cambios de objetos y de grupos privilegiados, replicación) **no se han medido
  todavía**, ni su volumen ni su efecto sobre el filtro de postura y el umbral
  de escalada de la Fase 2.
- **`LocalSystem` en un controlador de dominio.** El servicio `TFM-DC-Agent`
  sigue como `LocalSystem` (§3.1). Ahora actúa en la red con la identidad del
  propio controlador (`DC01-TFM$`), que en el directorio tiene control
  prácticamente total del dominio. El riesgo descrito en
  `docs/README-fase4c-dcagent.md` («Control de acceso al sistema de ficheros»)
  deja de ser teórico. La gMSA con derechos delegados sobre la OU objetivo
  gana peso, y su bloqueo técnico («requiere KDS root key y Active Directory
  real», `docs/README-fase4-pendientes.md:172-175`) ya no existe.
- **Resolución de nombres:** sin impacto observado (§3.2).

## 7. Pendientes

| # | Pendiente | Quién |
|---:|---|---|
| 1 | ~~`(Get-ADUser tfmuser).Enabled` tras cada paso~~ Estado final `True` acreditado; el intermedio no se capturó (§3.3) | Resuelto en parte (2026-09-27) |
| 2 | ~~Evidencia de que `tfmuser` es una cuenta sin privilegios~~ Solo «Usuarios del dominio» y «Usuarios» (§3.3) | Resuelto (2026-09-27) |
| 3 | Copia de `agent_dc.py` desplegado en `desplegado/agent_dc.py` | Jose |
| 4 | `curl -s http://100.64.0.2:8000/health`: `hmac_required:true` confirmado (§5.6); falta constancia de si emite `token_configured` (§5.2) | Resuelto en parte (2026-09-27) |
| 5 | ~~Localizar las alertas `100601` de la prueba o la causa de su ausencia~~ Causa: `TFM_LOG_PATH` ausente; corregido y verificado (§5.6) | Resuelto (2026-09-27) |
| 6 | Decidir la versión de `disable_account.ps1` y `enable_account.ps1` que se versiona (§5.1) | Decisión de Jose |
| 7 | Alinear `rustdesk_enable.ps1` entre DC y repositorio (§5.1) | Decisión de Jose |
| 8 | Redesplegar `agent_dc.py` de HEAD en el DC, o documentar por qué corre `8b00bdf` (§5.2) | Decisión de Jose |
| 9 | Corrección del P1 de `reset_password.ps1` antes de activarlo (§5.5) | Decisión de Jose |
| 10 | Control de `tailscale` desde la cuenta de dominio en el W11 (§5.4) | Decisión de Jose |
| 11 | `scripts/verify-hosts.sh` tras la unión al dominio | Jose |
| 12 | Medir las alertas propias del Directorio Activo (ampliación de M-24) | Pendiente |
| 13 | Migrar `TFM-DC-Agent` a una gMSA | Pendiente |
| 14 | `isolate_host.ps1` en real: requiere una ventana planificada | Pendiente |
| 15 | Revisar el mensaje publicado en la war room para `reset_password.ps1` del 24/09 (§5.5) | Jose |
| 16 | Diagnosticar la codificación de la salida de `collect_logs.ps1` (§5.7, P2) | Pendiente |
| 17 | Averiguar qué reescribió `AppEnvironmentExtra` el 12/09 entre las 23:36 y las 23:57 (§5.6) | Pendiente |
| 18 | Ejecutar `scripts/verify-dcagent-health.sh` contra el agente tras cada cambio del servicio | Jose |
| 19 | ~~Incorporar §5.6 al catálogo de fallos silenciosos~~ Incorporado como B39 | Resuelto (2026-09-27) |
| 20 | Confirmar el atributo de solo lectura del log original en el DC (§5.6, «Conservación de evidencia») | Jose |

> **Actualización (2026-09-27).** Filas 1, 2, 4 y 5 actualizadas y filas
> 15–19 añadidas tras el hallazgo de §5.6. Después, fila 19 resuelta
> (caso B39 del catálogo) y fila 20 añadida.
