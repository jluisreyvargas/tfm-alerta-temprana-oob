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
| `disable_account.ps1 tfmuser` | `REQ-b2a531dc` | `ir_lead` → `ir_lead2` | `0` | `PENDIENTE` (esperado `False`) | no encontrada |
| `enable_account.ps1 tfmuser` | `REQ-cf55f263` | `ir_lead2` → `ir_lead` | `0` | `PENDIENTE` (esperado `True`) | no encontrada |

`reset_password.ps1` e `isolate_host.ps1` no se ejecutaron, como estaba
previsto. Además, en el DC siguen en simulación (§3.1).

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
| 1 | `(Get-ADUser tfmuser).Enabled` tras cada paso, o repetir la prueba guardando ambas consultas | Jose |
| 2 | Evidencia de que `tfmuser` es una cuenta sin privilegios (`Get-ADUser tfmuser -Properties MemberOf`) | Jose |
| 3 | Copia de `agent_dc.py` desplegado en `desplegado/agent_dc.py` | Jose |
| 4 | `curl -s http://100.64.0.2:8000/health` para confirmar la versión del agente en ejecución (§5.2) | Jose |
| 5 | Localizar las alertas `100601` de la prueba o la causa de su ausencia (§5.3) | Jose |
| 6 | Decidir la versión de `disable_account.ps1` y `enable_account.ps1` que se versiona (§5.1) | Decisión de Jose |
| 7 | Alinear `rustdesk_enable.ps1` entre DC y repositorio (§5.1) | Decisión de Jose |
| 8 | Redesplegar `agent_dc.py` de HEAD en el DC, o documentar por qué corre `8b00bdf` (§5.2) | Decisión de Jose |
| 9 | Corrección del P1 de `reset_password.ps1` antes de activarlo (§5.5) | Decisión de Jose |
| 10 | Control de `tailscale` desde la cuenta de dominio en el W11 (§5.4) | Decisión de Jose |
| 11 | `scripts/verify-hosts.sh` tras la unión al dominio | Jose |
| 12 | Medir las alertas propias del Directorio Activo (ampliación de M-24) | Pendiente |
| 13 | Migrar `TFM-DC-Agent` a una gMSA | Pendiente |
| 14 | `isolate_host.ps1` en real: requiere una ventana planificada | Pendiente |
