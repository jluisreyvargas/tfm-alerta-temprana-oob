# Fase 4 — Validación funcional y de seguridad

Este documento recoge la validación empírica de la Fase 4 tras el proceso de
endurecimiento. Todas las salidas proceden de ejecuciones reales sobre el
entorno del proyecto; los valores sensibles (tokens, contraseñas, claves)
aparecen redactados.

**Fecha de validación:** 27 de agosto de 2026
**Nodos implicados:** `orchestrator-tfm` (100.64.0.1, Ubuntu Server), `dc01-tfm` (100.64.0.2, Windows Server 2025)

---

## 1. Alcance de la validación

| Subfase | Componente | Estado |
|---|---|---|
| 4a | Headscale control plane | ✅ Operativo |
| 4a | Headscale UI | ⚠️ Operativa, pendiente Authelia |
| 4b | Tailnet (2 nodos) | ✅ Conectividad directa |
| 4c | Agente DC (FastAPI/NSSM) | ✅ Validado, 9/9 pruebas |
| — | Break-glass RustDesk | ✅ Ciclo completo validado |
| — | Auditoría SIEM | ✅ Extremo a extremo |
| 4d | Flujo de aprobación | ❌ No implementado |

Quedan fuera de esta validación el endurecimiento del plano de control (paso a
HTTPS, DERP embebido, política ACL) y la firma HMAC de las peticiones,
documentados como trabajo pendiente en la sección 8.

---

## 2. Estado del agente

```bash
curl -s http://100.64.0.2:8000/health
```

```json
{
  "status": "ok",
  "agent": "dc01-tfm",
  "version": "2.0",
  "hmac_required": false,
  "token_configured": true,
  "scripts_dir": "C:\\tfm-scripts"
}
```

El agente se ejecuta como servicio Windows gestionado por NSSM, con arranque
automático y dependencia declarada del servicio Tailscale:

```
Application:     C:\tfm-dc-agent\.venv\Scripts\python.exe
AppParameters:   -m uvicorn agent_dc:app --host 100.64.0.2 --port 8000
AppDirectory:    C:\tfm-dc-agent
DependOnService: Tailscale
Start:           SERVICE_AUTO_START
```

El binding a `100.64.0.2` restringe la escucha a la interfaz de la tailnet. El
agente no es alcanzable desde la red corporativa aunque la regla de firewall
fallase:

```
netstat -ano | findstr ":8000"
TCP    100.64.0.2:8000    0.0.0.0:0    LISTENING
```

---

## 3. Batería de pruebas del agente

Ejecutadas desde `orchestrator-tfm` hacia `dc01-tfm` por la red privada Headscale.

### 3.1 Pruebas de no regresión

| # | Prueba | Resultado | Verificado |
|---:|---|---|:-:|
| 1 | Health check | 200, `version 2.0` | ✅ |
| 2 | Script válido (dry-run) | 200, `returncode: 0` | ✅ |
| 3 | Script fuera de allowlist | 400 `Script no permitido` | ✅ |
| 4 | Token incorrecto | 403 `Forbidden` | ✅ |

```json
// Prueba 2
{
  "script": "disable_account.ps1",
  "target": "usuario.prueba",
  "stdout": "TFM-AGENT: Deshabilitando cuenta AD: usuario.prueba\nDRY-RUN OK - Disable-ADAccount -Identity usuario.prueba\n",
  "stderr": "",
  "returncode": 0,
  "truncated": false
}
```

### 3.2 Controles de seguridad introducidos en el endurecimiento

| # | Control | Petición | Respuesta |
|---:|---|---|---|
| 5 | Anclaje de ruta | `"script": "..\\..\\Windows\\System32\\calc.exe"` | 400 `Script no permitido` |
| 6 | Validación de target | `"target": "a\"; calc.exe #"` | 400 `Invalid target` |
| 7 | Mapeo de parámetros | `rustdesk_enable.ps1` + `ttl_minutes` | 200, `warnings: []` |
| 8 | Rango de TTL | `"ttl_minutes": 99999` | 400 `Invalid ttl_minutes` |
| 9 | Saneado de salida | `collect_logs.ps1` | 200, `truncated: true` |

**Prueba 5 — anclaje de ruta.** La allowlist valida el nombre del script; el
anclaje valida además su ubicación real mediante `Path.resolve()`, comprobando
que el fichero resuelto pertenece exactamente al directorio permitido. Sin
este control, la construcción `f"C:\\tfm-scripts\\{script}"` de la versión
inicial permitía escapar del directorio.

**Prueba 6 — validación de target.** En Windows, `subprocess` serializa la
lista de argumentos a una cadena de comandos antes de invocar `CreateProcess`.
Un `target` con comillas o guión inicial permite inyectar argumentos
adicionales a `powershell.exe`. El control aplica
`re.fullmatch(r"[A-Za-z0-9._\-\\]{1,64}")`.

**Prueba 9 — saneado de salida.** El campo `truncated: true` confirma que el
límite de 8.000 caracteres actúa sobre el contenido devuelto. Es relevante
porque `collect_logs.ps1` extrae el campo `Message` del registro de seguridad
de Windows, contenido parcialmente controlable por un atacante, que viaja
desde el DC hacia el orquestador y, en las fases posteriores, hacia el motor
de triaje. Ver sección 7.

---

## 4. Control de acceso al sistema de ficheros

La allowlist del agente valida el nombre del fichero invocado, no su
contenido. El servicio se ejecuta como `LocalSystem`, que en un Domain
Controller equivale al contexto de la cuenta de máquina. Si un principal sin
privilegios pudiera escribir en el directorio de scripts, podría sustituir el
contenido de cualquier `.ps1` de la allowlist y obtener ejecución arbitraria
como `SYSTEM` en el DC, invocada por el propio agente y superando todos sus
controles.

Configuración aplicada:

```powershell
icacls C:\tfm-scripts /inheritance:r
icacls C:\tfm-scripts /grant:r "SYSTEM:(OI)(CI)(RX)"
icacls C:\tfm-scripts /grant:r "Administradores:(OI)(CI)(F)"

icacls C:\tfm-dc-agent /inheritance:r
icacls C:\tfm-dc-agent /grant:r "SYSTEM:(OI)(CI)(RX)"
icacls C:\tfm-dc-agent /grant:r "Administradores:(OI)(CI)(F)"

icacls C:\tfm-dc-agent\logs /inheritance:r
icacls C:\tfm-dc-agent\logs /grant:r "SYSTEM:(OI)(CI)(M)"
icacls C:\tfm-dc-agent\logs /grant:r "Administradores:(OI)(CI)(F)"
```

`SYSTEM` recibe `RX` (lectura y ejecución) sobre el código y los scripts, y `M`
(modificación) únicamente sobre el directorio de logs. El servicio puede
ejecutar los scripts pero no alterarlos.

La separación de `C:\tfm-scripts` y `C:\tfm-dc-agent` es deliberada: mantenerlos
en un mismo directorio anularía el valor del anclaje de ruta, ya que código del
agente, entorno virtual y scripts compartirían permisos.

**Conclusión aplicable al diseño:** una allowlist por nombre de fichero solo
aporta seguridad si va acompañada de control de integridad sobre el directorio
que la contiene. El cierre completo requeriría verificación de firma
Authenticode antes de cada invocación, identificado como trabajo futuro.

---

## 5. Canal de acceso remoto break-glass

### 5.1 Ciclo de habilitación y caducidad

La versión inicial de `rustdesk_enable.ps1` programaba la tarea de caducidad
pero nunca arrancaba el servicio, mientras que `rustdesk_disable.ps1` lo dejaba
en estado `Disabled`. El resultado era que el break-glass quedaba inoperativo
tras el primer ciclo de uso.

Secuencia de validación ejecutada en el DC:

```
enable (TTL=2 min)   →  Status: Running    StartType: Manual
[espera 150 s]       →  Status: Stopped    StartType: Disabled
enable (TTL=30 min)  →  Status: Running    StartType: Manual
```

La tercera línea es la prueba determinante: confirma que el canal es
reutilizable tras una caducidad previa.

Salida estructurada del script:

```json
{
  "password": "<REDACTADO>",
  "rustdesk_id": "resolver_en_hbbs",
  "service": "Running",
  "ttl_task": "Ready",
  "warnings": [],
  "ttl_minutes": 30
}
```

Correcciones aplicadas respecto a la versión inicial:

- Arranque efectivo del servicio (`Set-Service -StartupType Manual` +
  `Start-Service`), que revierte el estado dejado por el script de
  deshabilitación.
- Contraseña de un solo uso generada con
  `System.Security.Cryptography.RandomNumberGenerator` en lugar de
  `Get-Random`, que emplea un PRNG no apto para material criptográfico.
- Principal explícito en `Register-ScheduledTask`. Sin
  `-Principal ... -LogonType ServiceAccount`, la API falla con `0x80070534`
  bajo el contexto SYSTEM del servicio, error que no se manifiesta al ejecutar
  el script desde una sesión interactiva.
- Eliminación del identificador RustDesk incrustado en el código, que estaba
  versionado en un repositorio público.

### 5.2 Resolución del identificador

El identificador del par no se obtiene en el endpoint. RustDesk almacena el
valor cifrado (`enc_id`) en su fichero de configuración y las banderas de
línea de comandos abren la interfaz gráfica en lugar de emitirlo por salida
estándar, comportamiento inservible bajo un servicio sin sesión interactiva.

La resolución se delega al servidor de rendezvous del enclave:

```bash
sqlite3 rustdesk/data/db_v2.sqlite3 "SELECT id, note FROM peer;"
```

Además de ser técnicamente más fiable, la decisión tiene fundamento de diseño:
en un escenario break-glass el endpoint puede estar comprometido, por lo que
la identidad del par debe proceder del componente bajo control del equipo de
respuesta, no del sistema bajo investigación.

### 5.3 Configuración del servidor

```
IMAGE:   rustdesk/rustdesk-server:1.1.14
COMMAND: hbbs -r rustdesk-hbbr:21117 -k _   /   hbbr -k _
PORTS:   100.64.0.1:21115-21116, 100.64.0.1:21117-21119
INFO [src/common.rs:45] relay-servers=["rustdesk-hbbr:21117"]
INFO [src/rendezvous_server.rs:1205] Key: <REDACTADO>
```

Cambios respecto al despliegue inicial:

| Aspecto | Antes | Después |
|---|---|---|
| Tag de imagen | `:latest` | `1.1.14` |
| Cifrado | Sin `-k`: aceptaba clientes sin clave | `-k _`: cifrado obligatorio |
| Relay | `relay-servers=[]` (hbbr no enlazado) | Enlazado vía `-r` |
| Escucha | `0.0.0.0:21115-21119` | `100.64.0.1` (interfaz tailnet) |

### 5.4 Verificación del canal por captura de tráfico

La configuración del cliente apuntaba inicialmente a `192.168.127.138`, una
dirección de la red corporativa. El servidor era el correcto y la clave
estaba correctamente configurada, por lo que una revisión de configuración
habría dado el componente por válido; sin embargo, el canal de acceso remoto
discurría por la infraestructura cuya indisponibilidad justifica la existencia
del enclave.

Tras reconfigurar el cliente hacia la dirección del tailnet:

```
# tcpdump -ni tailscale0 port 21116

18:38:40.280509 IP 100.64.0.1.21116 > 100.64.0.2.56213: Flags [S.]
18:38:40.691080 IP 100.64.0.2.64083 > 100.64.0.1.21116: UDP, length 15
18:38:40.691750 IP 100.64.0.1.21116 > 100.64.0.2.64083: UDP, length 2
18:38:49.448188 IP 100.64.0.2.56215 > 100.64.0.1.21116: Flags [F.]
```

Origen `100.64.0.2`, destino `100.64.0.1`, sobre la interfaz `tailscale0`. El
canal break-glass opera sobre la red privada del enclave.

**Observación metodológica.** Los registros del servidor RustDesk no permiten
esta verificación: el NAT del bridge Docker enmascara el origen y todos los
pares aparecen como `172.18.0.1`. Para un componente cuyo requisito funcional
es operar con independencia de la infraestructura corporativa, la comprobación
debe hacerse a nivel de red, no a nivel de aplicación ni de configuración.

---

## 6. Auditoría en el SIEM

Los eventos del agente se incorporan al SIEM del propio enclave, cerrando el
circuito de trazabilidad mientras la gestión de casos en DFIR-IRIS no está
integrada.

### 6.1 Configuración

En el agente Wazuh del DC (`ossec.conf`):

```xml
<localfile>
  <log_format>syslog</log_format>
  <location>C:\tfm-dc-agent\logs\agent.log</location>
</localfile>
```

En el manager (`local_rules.xml`), diez reglas agrupadas bajo `tfm,breakglass`.
La regla base filtra por origen en lugar de por decodificador, ya que el
registro es texto plano sin formato reconocido por los decodificadores nativos
de Windows (`"decoder": {}` en los eventos archivados):

```xml
<rule id="100600" level="0">
  <location>tfm-dc-agent</location>
  <description>TFM DC Agent - evento base</description>
</rule>
```

| ID | Nivel | Condición |
|---|---:|---|
| 100601 | 5 | Ejecución de script (con etiquetas GDPR y PCI-DSS) |
| 100602 | 10 | Aislamiento de host solicitado |
| 100603 | 10 | Activación de acceso remoto |
| 100604 | 12 | Token inválido |
| 100605 | 12 | Firma HMAC inválida |
| 100606 | 12 | Replay detectado |
| 100607 | 8 | Script fuera de allowlist |
| 100608 | 8 | Parámetro target rechazado |
| 100609 | 8 | Intento de path traversal |
| 100610 | 13 | Correlación: 5 intentos no autorizados en 120 s |

### 6.2 Validación extremo a extremo

Ejecución legítima:

```json
{"rule":{"level":5,"description":"TFM Break-glass: ejecucion de script en DC",
"id":"100601","groups":["tfm","breakglass"],"gdpr":["IV_35.7.d"],"pci_dss":["10.2.7"]},
"agent":{"id":"002","name":"DC01-TFM"},
"full_log":"2026-08-27 19:23:47,102 INFO EJECUCION script=disable_account.ps1 target=usuario.prueba",
"location":"C:\\tfm-dc-agent\\logs\\agent.log"}
```

Intento de acceso no autorizado:

```json
{"rule":{"level":12,"description":"TFM Break-glass: token invalido en el agente del DC",
"id":"100604","mail":true,"groups":["tfm","breakglass"]},
"agent":{"id":"002","name":"DC01-TFM"},
"full_log":"2026-08-27 19:23:47,730 WARNING Token invalido"}
```

La alerta de nivel 12 propagó hasta el canal de coordinación sin modificar el
flujo construido en las fases anteriores:

```
🚨 Incidente CRITICA — TFM Break-glass: token invalido en el agente del DC
   War Room abierto: inc-100604-1787851429-1565316
```

Cadena completa verificada:

```
Agente DC → agent.log → Wazuh agent → manager → regla 100604
  → n8n → Rocket.Chat (War Room)
```

**Resultado relevante.** El canal de respuesta a incidentes queda auditado por
el mismo SIEM que lo activa, y los intentos de uso no autorizado del canal
generan apertura automática de sala de coordinación. El componente que ejecuta
acciones sobre el Domain Controller es también un objetivo de ataque, y se
monitoriza como tal.

### 6.3 Limitación identificada

El agente Wazuh del DC reporta desde `192.168.127.153`, dirección de la
interfaz corporativa. Es coherente con el diseño —la telemetría de seguridad
no forma parte del canal out-of-band—, pero implica que una caída de la red
corporativa suprime la visibilidad SIEM aunque el canal break-glass permanezca
operativo sobre Headscale. Queda documentado como limitación conocida.

---

## 7. Superficie de inyección en el canal de respuesta

El agente devuelve la salida estándar de los scripts al orquestador. En el
caso de `collect_logs.ps1`, esa salida incluye el campo `Message` del registro
de seguridad de Windows, cuyo contenido es parcialmente controlable por un
atacante que genere eventos en el sistema.

El recorrido de ese contenido es: DC → orquestador → motor de triaje. Es
decir, la telemetría de entrada no es la única superficie de inyección
indirecta del sistema: los resultados de las acciones de respuesta constituyen
una segunda vía, con el agravante de proceder de un componente que la
arquitectura trata como confiable.

Mitigación implementada:

- Eliminación de caracteres de control sobre `stdout` y `stderr`.
- Truncado a 8.000 caracteres con indicador explícito `truncated`.
- Emisión estructurada en JSON con hash SHA-256 del contenido recogido,
  orientada a la custodia de evidencias de la Fase 5.

Pendiente: delimitación explícita del contenido antes de su entrega al motor
de triaje.

---

## 8. Trabajo pendiente

> Plano de control TLS, DERP embebido, política ACL y Authelia en Headscale UI
> —listados aquí como pendientes en la validación original de la Fase 4c—
> quedaron **resueltos** en el Paso 8 (28/08/2026). Detalle y evidencias en la
> sección 10 de este documento y en
> [`README-fase4-pendientes.md`](README-fase4-pendientes.md).

| Elemento | Descripción |
|---|---|
| Firma HMAC | Implementada en el agente, desactivada por bandera hasta que el orquestador firme |
| Cuenta de servicio | `LocalSystem`; procedería una gMSA con derechos delegados sobre la OU objetivo |
| Verificación de integridad | Firma Authenticode de los scripts previa a su invocación |
| Fase 4d | Flujo de aprobación y ejecución desde el canal de coordinación |

---

## 9. Incidencias durante el endurecimiento

Se documentan por su valor metodológico: en ambos casos, una medida de
seguridad correctamente concebida dejó inoperativo un componente por no
validarse antes de aplicarse.

**Descriptor de seguridad del servicio.** La restricción de la ACL sobre la
clave de registro del servicio del agente, aplicada para limitar la lectura
del token, empleó `SetAccessRuleProtection($true, $false)` sin copiar las
reglas heredadas. El resultado fue una DACL vacía que denegaba el acceso a
todos los principales, incluido SYSTEM. El Gestor de Control de Servicios no
pudo leer la configuración y el servicio quedó inarrancable, con recuperación
únicamente mediante eliminación y reinstalación del servicio. La
reinstalación destruyó además el único lugar donde residía el token,
recuperable gracias a la copia previa del estado.

**Reglas del SIEM.** La incorporación de reglas con un decodificador
inexistente (`windows_date_format`) y con sintaxis PCRE no soportada por el
motor OS_Regex de Wazuh impidió el arranque de `wazuh-analysisd`, dejando el
manager sin procesamiento de alertas.

Ambos incidentes eran evitables mediante las herramientas de validación previa
disponibles (`wazuh-analysisd -t`, `headscale policy check`), incorporadas al
procedimiento a partir de entonces.

**Conclusión aplicable al diseño:** el endurecimiento tiene coste operativo y
su aplicación sin validación previa puede producir indisponibilidad del
componente que se pretende proteger. En un entorno de respuesta a incidentes,
esa indisponibilidad se manifestaría precisamente durante el incidente.

---

## 10. Hallazgos del endurecimiento del plano de control (Paso 8)

Ejecución del 28 de agosto de 2026. Es el material más citable de la fase: en
los cuatro casos, la ausencia de un control se manifiesta como funcionamiento
normal, no como error.

**Traefik descarta silenciosamente un middleware inexistente.** El router de
Headscale UI referenciaba `authelia@docker`, un middleware que no existe en
este despliegue — la instancia de Authelia se integra mediante el proveedor de
fichero de Traefik (`authelia@file`), no mediante labels de un contenedor
Authelia. Con la referencia errónea, Traefik descartaba el middleware sin
emitir ningún error y el router respondía `200` sin autenticación. Rocket.Chat
nunca tuvo este problema porque siempre usó `authelia@file`. Un control mal
referenciado no falla: simplemente no se aplica.

**Headscale ignora silenciosamente una política inválida.** `acl.hujson`
incluía un bloque `"tests"` que no existe en la versión 0.28. `headscale
policy check` devolvía `unknown field "tests"`, pero el servidor arrancó sin
la política y siguió operando en allow-all. Sin ejecutar la validación
explícita, se habría dado por implementada una microsegmentación inexistente.

**Una label de Traefik en el compose no es un control activo hasta recrear el
contenedor.** Tres casos en la misma sesión: Headscale sin router, RustDesk
sin `-k`, y la UI sin Authelia. El repositorio decía una cosa y el runtime
hacía otra.

**La microsegmentación reveló una dependencia no declarada en el diseño.** El
principio "el DC es destino, nunca origen" era correcto para las acciones de
respuesta, pero el cliente RustDesk necesita registro saliente contra el
servidor de rendezvous. No se detectó al diseñar la política ni al revisarla:
apareció al aplicarla y comprobar el comportamiento. Se resolvió con una
excepción acotada a `tag:dc → tag:orchestrator:21115-21119`.

### Observaciones técnicas menores

- Al asignar etiquetas, los nodos pasan de su usuario a *tagged-devices* y sus
  claves dejan de caducar: los dispositivos etiquetados no están sujetos a
  expiración de sesión de usuario.
- Las ACL de Tailscale filtran TCP y UDP por puerto; ICMP se rige por la
  existencia de cualquier regla entre el par de nodos. Al añadir la excepción
  de RustDesk, el ping DC→orquestador pasó de fallar a funcionar, mientras el
  filtrado TCP seguía intacto.
