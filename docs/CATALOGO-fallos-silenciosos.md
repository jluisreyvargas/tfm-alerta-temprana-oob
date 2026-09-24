# Catálogo canónico de fallos silenciosos

**Fecha:** 2026-09-24

Responde al hallazgo A-22 de `docs/AUDITORIA-CIERRE-2026-09-23.md` (`:243-248`):
el `README.md` raíz habla de «ocho casos registrados» y remite a
`docs/api-reconocimiento-fase8.md` §1, que enumera cinco. Este documento
sustituye esa cifra por una lista trazable caso a caso.

> **Referencias `fichero:línea` ancladas al commit `3f26c07`.** Las citas se
> validaron contra el árbol de ese commit. Las notas añadidas después en varios
> documentos desplazan números de línea; para ver cada cita tal como se
> comprobó: `git show 3f26c07:<fichero>`. La fila B1 se actualizó después para
> citar M-46 (`77e4d1c`).

---

## 1. Criterio

Un caso entra si **ocurrió de hecho en el proyecto**, no como hipótesis, y si un
instrumento, control o componente informó de éxito o de normalidad (o no informó
de nada) mientras no se cumplía la función que debía cumplir. Quedan fuera los
riesgos y deudas sin ocurrencia registrada, los fallos ruidosos (los que sí
producían un error visible) y los fallos que se evitaron antes de producirse,
salvo que el mecanismo silencioso llegara a observarse: entonces entran con el
estado «evitado». Cada caso incluido cita al menos un `fichero:línea` leído.

- **Familia A · El observador.** Instrumentos de diagnóstico, medición o
  verificación que se usaron durante el desarrollo, la auditoría o la
  verificación: un `curl`, un código HTTP, una sonda, un script de comprobación,
  una copia de base de datos, una consulta.
- **Familia B · El sistema observado.** Componentes o controles del enclave en
  funcionamiento: un nodo de n8n, un healthcheck, un contenedor, una política.
  Si el componente forma parte del enclave desplegado, el caso es B aunque se
  descubriera durante un diagnóstico.

**Estado**, según lo que diga la fuente: *corregido*, *mitigado* (la causa sigue
y el efecto se contiene en otro punto), *evitado*, *riesgo aceptado*, *abierto*
o *no consta* (la fuente no dice nada). En la familia A, «corregido» significa
que el instrumento se sustituyó o que la conclusión se rectificó.

**Origen:** pone «análisis asistido» solo cuando la fuente lo dice
expresamente.

Los identificadores de hallazgo van con su documento de origen, porque hay
colisiones conocidas (`P1-6`, `P0-4`, entre otras): ver
`docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md` §3.5.1. Las entradas
`M-n` son siempre de `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md` (abreviado
«REGISTRO-MEDICIONES» en las tablas).

---

## 2. Familia A · El observador

| Id | Caso | Qué informaba | Qué ocurría | Cómo se detectó | Fuente (fichero:línea) | Estado | Origen |
|---|---|---|---|---|---|---|---|
| A1 | Código HTTP tomado como indicador de existencia en la API del KVM (nivel 1) | `200` | La SPA devuelve `index.html` (743 B) para cualquier ruta no registrada | Petición a una ruta aleatoria antes de sondear | `docs/api-reconocimiento-fase8.md:38` | corregido (criterio: campo `ok`, `:44-46`) | |
| A2 | Código HTTP tomado como indicador de autorización (nivel 1) | `200` | El rechazo va en el cuerpo (`{"ok":false,"code":"AUTH_REQUIRED"}`) | Tres endpoints con `200` e idéntico tamaño de 126 B | `docs/api-reconocimiento-fase8.md:39` | corregido | |
| A3 | `curl -s` sin comprobar el código de salida | Cuerpo vacío | `curl` fallaba por un `--cacert` inexistente y no imprimía nada | Cinco endpoints «vacíos» a la vez | `docs/api-reconocimiento-fase8.md:40`, `:32-33` | corregido | análisis asistido |
| A4 | Copia de SQLite sin el fichero `-wal` | Contenido de la base | Se leía el último checkpoint, no el estado actual | 6 h de diferencia entre las marcas de tiempo de `.db` y `.db-wal` | `docs/api-reconocimiento-fase8.md:41`, `:32-33` | corregido | análisis asistido |
| A5 | `cmd \|\| echo "sin sqlite3"` | «sin sqlite3» | El comando falló por la sintaxis del shell, no por falta del binario | `command -v sqlite3` por separado | `docs/api-reconocimiento-fase8.md:42`, `:32-33` | corregido | análisis asistido |
| A6 | `ps w` de busybox en el GL-RM1 | 5 procesos (el watchdog de rtty parecía muerto) | Había 162 procesos; sin argumentos solo lista los del terminal | `netstat -tnp` por conexión y PID | `docs/mejora6-endurecimiento-dispositivo.md:354-358` | corregido | |
| A7 | `awk '$9!="S"'` sobre la salida de `top` | Lista filtrada | No filtraba nada: la columna de estado no es la novena | No consta | `docs/mejora6-endurecimiento-dispositivo.md:359-361` | corregido | |
| A8 | Comprobación de que certificado y clave casaban (`[ "$A" = "$B" ]`) | Éxito | Comparaba dos cadenas vacías porque el `scp` previo no había llegado | No consta | `docs/INFORME-AUDITORIA-FASE8.md:358` | no consta | |
| A9 | `verify-hosts.sh` como control de la capacidad declarada en `resolucion-nombres.tsv` | Sin divergencias | Compara ternas `(host, nombre, ip)` con el fichero `hosts`: ni la alcanzabilidad del 443 (B19) ni el sujeto «contenedor» (M-2) | Prueba de acceso a IRIS desde el W11; medición dentro de n8n | `docs/HALLAZGO-headscale-politica-modo-file.md:137-139`; REGISTRO-MEDICIONES `:152-155` | no consta | |
| A14 | `git grep` sobre HEAD en busca del token del bot | Sin coincidencias; se aplazó la rotación | Ocho apariciones del token en HEAD | `git show HEAD:<fichero>` | REGISTRO-MEDICIONES `:1345-1349` (M-41) | corregido (token rotado, `:1356-1360`) | |
| A15 | Pruebas de las fases 2c-2f con `curl` desde el host | Flujo validado | El camino real Wazuh→n8n nunca funcionó (B2, B21) | Validación posterior sobre tráfico real | `fase2-orquestador/README.md:450` | corregido | |
| A16 | Verificación de la política de MinIO con `mc` | Prueba superada | El SDK de Python del orchestrator necesitaba `GetBucketLocation`: `AccessDenied` | Primera colección real | `fase5-velociraptor/SECURITY-NOTICE.md:250-256`; `docs/INFORME-P0-3.md:23-24` | corregido | |
| A17 | Verificación local de la purga del historial (P0-1 de `SECURITY-NOTICE.md`) | Cinco comprobaciones en verde | El commit `4cfd84c` seguía accesible por SHA en GitHub | Acceso directo al SHA en el servidor | `fase5-velociraptor/SECURITY-NOTICE.md:105-110` | corregido (repositorios recreados) | |
| A18 | `headscale policy check` y `policy get` tras editar la ACL | `Policy is valid`, `rc=0`; la regla nueva presente | La política cargada era la anterior: el modo `file` solo lee al arrancar | Netmap del nodo destino (`tailscale debug netmap`) | `docs/HALLAZGO-headscale-politica-modo-file.md:17-24`, `:45-64` | abierto (síntoma remediado, mecanismo igual, `:6`) | |
| A19 | `verify-hosts.sh --check-doc` | En verde | Una fila con la justificación copiada de otra y truncada | Revisión manual del texto | `docs/INFORME-P1-0-correcciones.md:104-118` | riesgo aceptado (límite escrito, `:116-118`) | |
| A20 | Revisión de credenciales y `verify-no-secrets.sh` frente a la contraseña de `rcuser` | Ningún secreto expuesto / sin hallazgos | Credencial con rol root en claro en tres ficheros versionados | Auditoría de cierre (A-21) | `docs/HALLAZGO-credencial-mongodb-2026-09-23.md:46-59` | no consta para los controles (credencial rotada, `:61-76`) | |
| A21 | `head -20` sobre `docker ps` para inventariar servicios | Inventario | Ocho servicios vivos cortados, entre ellos el de mayor impacto de la revisión | No consta | `docs/revision-credenciales-fases1-8.md:190-194` | corregido | |
| A23 | Salida del nodo Code usada como evidencia en el hook del KVM | El flujo «decidía» `403` | rttys recibía `200` | Medir el código HTTP que ve rttys | `docs/cierre-mejora1-hook.md:124-131` | corregido | |
| A24 | `grep` de busybox sobre binarios | Coincidencias | Devolvió cuatro de cinco, sin señal de truncamiento | No consta | `docs/cierre-mejora1-hook.md:144-146` | no consta | |
| A25 | Evaluación basada en `ps` de los planos de control del GL-RM1 | Sin plano de control externo | Conexión MQTT establecida con la infraestructura del fabricante | `netstat -tnp \| grep ESTABLISHED` | `docs/INFORME-AUDITORIA-FASE8.md:134`, `:350` | corregido | |
| A26 | Prueba negativa de la sonda: `pkill` a través de `ssh '...'` | Sistema caído (supuesto) | El patrón no se expandió y el proceso seguía vivo: se midió un sistema sano | Contradicción entre `ps` vacío y `netstat` con conexión | `docs/INFORME-AUDITORIA-FASE8.md:265`, `:354` | corregido | |
| A27 | `docker compose config --quiet` en el despliegue del KVM | «Sintaxis OK» | Compose fusionaba las listas de `ports` y el contenedor colisionaba consigo mismo | Diagnóstico del `address already in use` | `docs/INFORME-AUDITORIA-FASE8.md:216-218` | corregido (`!override`) | |
| A28 | Código de salida de `git check-ignore -v` como prueba de exclusión | Excluido | Con `-v` el código refleja coincidencia de patrón, negaciones incluidas | `git add --dry-run` | `docs/INFORME-AUDITORIA-FASE6.md:860`; `docs/INFORME-AUDITORIA-FASE8.md:332` | corregido | |
| A29 | `ls LICENSE* COPYING*` para buscar la licencia | Código distinto de 0: no hay licencia | `LICENSE.txt` existía; el código venía del patrón sin coincidencias | Verificación posterior | `docs/INFORME-AUDITORIA-FASE6.md:863` | corregido | |
| A30 | Verificación con `compose up` de la corrección de P1-11 (`INFORME-AUDITORIA-FASE6.md`) | `app` Healthy, `nginx` espera | En arranque en frío el servicio no levantaba: el demonio no honra `depends_on` | Prueba de arranque en frío | `docs/INFORME-AUDITORIA-FASE6.md:789-810` | corregido (unidad systemd) | |
| A32 | Consultas a IRIS mientras se borraban casos en paralelo (M-35) | `500` del caso #47; `cases_events` sin eventos de la automatización | Los objetos medidos se estaban borrando; el Workflow 2 funcionaba | `200` sobre un caso vivo; nueva consulta tras la sesión | REGISTRO-MEDICIONES `:1166-1189` | corregido | |
| A33 | Prueba negativa de `Comparar Hash` (M-38) | «La evidencia no acredita integridad», lo esperado | Leía el caso equivocado (B35): respondía igual con el hash bueno y con el manipulado | Comprobar por fuera que la evidencia tenía el hash correcto | REGISTRO-MEDICIONES `:1221-1238` | corregido (`:1240-1251`) | |
| A34 | Primera versión del saneado ampliado de `export-workflow.sh` (M-44) | Exportación saneada | Sustituía por `REEMPLAZAR` la expresión `=Bearer {{ $env.AGENT_TOKEN }}`, que no es un secreto | Diff de la exportación | REGISTRO-MEDICIONES `:1420-1446` | corregido | |
| A35 | Lectura del netmap con `grep -A 40` | Sin regla para DC01 | La tercera regla, cortada por el `grep`, concedía lo necesario | Lectura del dato completo | `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:122-124` | corregido | |
| A36 | `2>/dev/null` en comandos de `headscale` | Salida vacía («no hay claves») | Ocultaba errores de sintaxis | Contraste a tiempo | `docs/mejora6-endurecimiento-dispositivo.md:363-365` | evitado | |
| A37 | Primera consulta a `/same_check` | `false` para la MAC real | `false` significaba formato incorrecto, no ausencia de oráculo | Contraste a tiempo | `docs/mejora6-endurecimiento-dispositivo.md:365-367` | evitado | |
| A38 | `git push` durante la Fase 6 | `644edf8..99844be main -> main` | Empujó al remoto de backup, no al principal | `git log origin/main` | `docs/INFORME-AUDITORIA-FASE6.md:887-892` | corregido | |
| A39 | `git status`, verificación por comportamiento y `verify-no-secrets.sh` frente al override de MISP | Los tres en verde | La Fase C de MISP entera estaba en un fichero ignorado, fuera de cualquier remoto | Recorrido de los overrides del árbol | `docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:62-66`, `:409-416` | corregido (`misp/misp-docker/.gitignore:20`) | |
| A40 | `git ls-files` para saber si el compose del KVM estaba versionado | Sin resultado: «fuera del repositorio» | El fichero no existía en esa ruta; el comando no distingue las dos causas | `ls` y `git check-ignore` | `docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:314-320` | corregido | |

---

## 3. Familia B · El sistema observado

| Id | Caso | Qué informaba | Qué ocurría | Cómo se detectó | Fuente (fichero:línea) | Estado | Origen |
|---|---|---|---|---|---|---|---|
| B1 | Verificación HMAC Wazuh→n8n con caracteres no ASCII | `entregada (HTTP 200)` en el `integrations.log` del emisor: en modo `onReceived` n8n responde antes de verificar la firma | Toda alerta con un acento se descartaba en la verificación: 51 rechazos (cota superior) entre el 11-09 y el 23-09, frente a 591 entregas registradas como correctas; la documentación afirmaba que se firmaba sobre los bytes crudos | Par de control con una alerta con acento y otra ASCII | REGISTRO-MEDICIONES M-46; commit `9d69042`; `fase2-orquestador/README.md:493` | corregido (`9d69042`) | |
| B2 | Integración Wazuh→n8n | Error TLS genérico (con `CERT_NONE`) | `n8n.oob.local` resolvía a `127.0.0.1` dentro del contenedor: la integración nunca había entregado una alerta | No consta | `fase2-orquestador/README.md:144-145`, `:450` | corregido (`extra_hosts`) | |
| B3 | Telemetría del orchestrator | Cero eventos, indistinguible de cero colecciones | 21 días de `401` del indexador por una contraseña rotada; el aviso de `print()` no salía por el buffer de stdout | `PYTHONUNBUFFERED=1` hizo aparecer el aviso | `fase5-velociraptor/SECURITY-NOTICE.md:228-248`; `docs/INFORME-P0-3.md:20-22`, `:44` | corregido | |
| B4 | `zip_sha256` del endpoint `/velociraptor/collect` | `completed`, hash y `sha256.txt` | El hash era de `incidentid + host + ts`; el ZIP no se subía | Revisión de la Fase 5_4b | REGISTRO-MEDICIONES `:555-569`; `fase5-orchestrator-api/README.md:141-145`; `fase5-velociraptor/README.md:212-214` | corregido (`456fbf9`) | |
| B5 | Lectura del ZIP por gRPC (`read_file`, accessor `fs`) (M-17) | Respuesta sin error; hash `e3b0c442…` | Devolvía 0 bytes | Comparación con un `sha256sum` de referencia | REGISTRO-MEDICIONES `:619-625`; `fase5-velociraptor/README.md:413-419` | evitado | |
| B6 | Alta de evidencia en IRIS con un nombre de campo erróneo (M-27) | `status: success` | Evidencia creada con `file_hash: null` (`unknown = EXCLUDE`) | Prueba negativa deliberada | REGISTRO-MEDICIONES `:984-1002` | mitigado (`Comparar Hash` busca por hash) | |
| B7 | Nodo `Comparar Hash` (M-39) | Nada | Calculaba el veredicto y no lo publicaba en ningún canal | No consta | REGISTRO-MEDICIONES `:1261-1273` | corregido | |
| B8 | Webhook del hook de autorización del KVM | `200`, leído por rttys como aprobación | Un error interno de n8n cerraba la petición con `200`; ocurrió dos veces durante la construcción | Construcción del flujo | `docs/cierre-mejora1-hook.md:57-86`; `docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:278-284` | corregido (salidas de error cableadas; V5, `:86`) | |
| B9 | Contenedores `rustdesk-hbbs` y `rustdesk-hbbr` (incluye el caso de `iriswebapp_nginx`, antes B10) | `running`, `PortBindings` correctos, log `Listening on…` | Sin red ni puertos publicados: carrera de arranque contra la IP del tailnet | Prueba desde el consumidor (DC01) | `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:13-30`, `:74-86`, `:181-194` | corregido (arranque en frío `:252-257`; apagado no limpio pendiente, `:273-277`) | |
| B11 | Cliente RustDesk del DC | Servidor y clave correctos | El canal iba por `192.168.127.138`, la red corporativa | Captura de tráfico en `tailscale0` | `docs/README-fase4-validacion.md:282-287` | corregido | |
| B12 | Healthcheck de MongoDB (`rs.status().ok`) | `healthy` | Replica set sin primario, sin aceptar escrituras; Rocket.Chat arrancó en ese estado | Recuperación tras la rotación | `docs/HALLAZGO-credencial-mongodb-2026-09-23.md:108-115` | abierto (deuda declarada) | |
| B13 | Router de Headscale UI con `authelia@docker` | `200` | Traefik descartaba el middleware inexistente y servía sin autenticación | Código de respuesta | `docs/README-fase4-validacion.md:514-521`; `docs/README-fase4a-headscale-ui.md:148`; `docs/README-fase4-pendientes.md:150-157` | corregido | |
| B14 | Headscale con una ACL con bloque `tests` | Servidor arrancado | Arrancó sin política, en allow-all | `headscale policy check` (`unknown field "tests"`) | `docs/README-fase4-validacion.md:541-546`; `docs/README-fase4a-headscale.md:211-214`, `:241-243` | corregido | |
| B15 | Labels y parámetros editados en el compose sin recrear | Compose con la configuración nueva | Tres casos en una sesión: Headscale sin router, RustDesk sin `-k` (aceptaba clientes sin clave), UI sin Authelia | Comparación con el runtime | `docs/README-fase4-validacion.md:523-526`, `:276` | corregido | |
| B16 | `docker compose -f fase6-iris/docker-compose.yml up` desde la raíz | Contenedores recreados | Override ignorado; el puerto volvió a `0.0.0.0:4833` | `ss -tlnp` del guion de verificación | `docs/INFORME-AUDITORIA-FASE6.md:305-321`, `:885`; `fase6-iris/README.md:147-153` | corregido (controles derivados, `:319-321`) | |
| B17 | Token de la cuenta de servicio `orchestrator-bot` tras activar el doble factor | Ningún error visible | Token invalidado; la publicación de alertas se interrumpió | No consta | `fase1-infraestructura/README.md:188` | corregido (token con omisión de 2FA, `:185`) | |
| B18 | Docker crea un directorio vacío cuando falta el origen de un bind (incluye B20) | Montaje presente | n8n: `NODE_EXTRA_CA_CERTS` apuntaba a un directorio y Node lo ignoró 23 días (M-1). IRIS: `certificates/ldap/` vacío desde el despliegue, y `irisRootCACert.pem` recreado como directorio durante la propia remediación | Medición dentro del contenedor (M-1); auditoría de Fase 6 | REGISTRO-MEDICIONES `:124-137`; `docs/INFORME-AUDITORIA-FASE6.md:225-232`, `:761-787` | corregido (`4a97225`; Fase 6, `:234-240`) | |
| B19 | ACL de Headscale para el analista | Capacidad declarada en `resolucion-nombres.tsv` | `tag:analyst` nunca tuvo el 443 del orchestrator | Prueba de acceso a IRIS desde el W11 | `docs/HALLAZGO-headscale-politica-modo-file.md:117-135` | corregido (`:159-165`) | |
| B21 | `wazuh-integratord` sin bloque `<integration>` válido | `Clean exit.`, sin error visible | El demonio no arranca; el bloque se pierde en las recreaciones | No consta | `fase2-orquestador/README.md:116-120`, `:450`; `docs/README-fase2bcd-workflow-n8n.md:118` | mitigado (comprobación tras cada recreación) | |
| B22 | GL-RM1, vía de recuperación física (P0-2 de `INFORME-AUDITORIA-FASE8.md`) | Ping, HTTPS local y puerto 443 en verde | 54 días sin registro en rttys: token rotado en un solo extremo y destino `100.64.0.1` en lugar de la LAN | Auditoría de la Fase 8 | `docs/INFORME-AUDITORIA-FASE8.md:37`, `:52-56`, `:116`, `:340`, `:348`; `fase8-kvm/README.md:284` | corregido | |
| B23 | Instrumentación de estado de rttys (P1-5 de `INFORME-AUDITORIA-FASE8.md`) | `status` en línea; `device_event_logs` sin desconexión | `status` con 2 h 26 min de retraso; una desconexión provocada no quedó registrada | Construcción de la sonda | `docs/INFORME-AUDITORIA-FASE8.md:160-169` | mitigado (sonda por conexión `ESTABLISHED`, `:267-273`) | |
| B24 | Certificado del GL-RM1 en la vía de break-glass | HTTPS servido con normalidad | Certificado caducado en 1979; el firmware desactiva en el código la comprobación de caducidad | Auditoría de la Fase 8 | `docs/INFORME-AUDITORIA-FASE8.md:236-243`, `:352` | corregido (certificado del enclave); la comprobación del firmware sigue desactivada | |
| B25 | Credencial de MinIO en la Fase 5 (P0-3, serie global) | Ningún error | Sin `.env`, Compose aplicaba el valor por defecto publicado: almacén de evidencia con credencial pública | Auditoría de la Fase 5 y GitGuardian | `fase5-velociraptor/SECURITY-NOTICE.md:145-150`, `:162-167`; `docs/INFORME-P0-3.md:17-19` | corregido | |
| B26 | `security.certificate_validity_days: 730` de Velociraptor | Configuración declarada | Certificados emitidos con 365 días; el parámetro nunca surtió efecto | No consta | `fase5-velociraptor/SECURITY-NOTICE.md:112-119` | abierto («sin remediar») | |
| B27 | Ancla de confianza de IRIS (P0-C y P1-6 de `INFORME-AUDITORIA-FASE6.md`) | Montaje declarado y legible; verificación externa (`openssl s_client`, `curl` sin `-k`) en verde | La CA era la de desarrollo, sobre un inodo con `nlink = 0`, y ningún cliente TLS la consumía | Verificación de P0-C | `docs/INFORME-AUDITORIA-FASE6.md:183-215`, `:536-557`, `:913-922`; `fase6-iris/SECURITY-NOTICE.md:150-160` | corregido | |
| B28 | `docker compose up -d` sobre `iriswebapp_nginx` en estado `exited` | `Started` | Arrancado sin recrear, con el endpoint de red obsoleto: bucle de reinicio | `docker network inspect` | `docs/INFORME-AUDITORIA-FASE6.md:429-434`, `:886-892` | corregido (procedimiento de recreación, `:1025-1032`) | |
| B29 | Nodo AbuseIPDB y `Code CTI Context` (M-14, M-45) | `abuse_confidence: 0` | La credencial asignada era la de Rocket.Chat: `401` convertido en cero por `?? 0`; cada caso perdía 2 puntos de score | Consulta directa a la API | REGISTRO-MEDICIONES `:499-516`, `:841-856`, `:1448-1497` | corregido (`abuse_disponible` sigue sin llegar al triaje, `:1493-1497`) | |
| B30 | `Aviso Fallo IRIS` en ramas paralelas (M-13) | Nada | La carrera entre ramas hacía fallar el nodo de aviso; con `continueErrorOutput`, el fallo se perdía | No consta | REGISTRO-MEDICIONES `:480-497` | corregido | |
| B31 | Cuerpo del triaje n8n→`langgraph-agent` (M-15) | JSON válido | Tres campos llegaban vacíos desde siempre (marca de tiempo del evento y contexto MISP) | Flujo completo con alertas reales | REGISTRO-MEDICIONES `:518-529`, `:934-945` | abierto (1 de 3 corregido) | |
| B32 | `classification_id` por defecto en `Preparar Caso IRIS` (M-22) | Caso clasificado como «explotación de vulnerabilidad conocida» | Todo lo no clasificado recibía esa clasificación concreta y falsa | Caso #44 (alerta SCA) | REGISTRO-MEDICIONES `:693-711` | corregido (`cb9a8dd`) | |
| B33 | Rama de supresión de alertas de postura (M-33) | Sin War Room ni caso, lo esperado | La cadena forense seguía ejecutándose sobre el endpoint | Un `401` en `Verificar Evidencia` | REGISTRO-MEDICIONES `:1135-1151` | no consta | |
| B34 | Nodo `Anuncio en General` tras recablear (M-34) | Nada | El aviso dejó de publicarse | Comparación con ejecuciones anteriores | REGISTRO-MEDICIONES `:1153-1164` | no consta | |
| B35 | URL de `Verificar Evidencia` en modo *fixed* (M-37) | `200` con una lista de evidencias vacía | n8n envió la plantilla literal e IRIS devolvió otro caso | `object_last_update` con la fecha de instalación | REGISTRO-MEDICIONES `:1203-1219` | corregido (`:1240`) | |
| B36 | Cabecera HSTS del nginx de IRIS (M-9) | Cabecera presente | `max-age=31536000: includeSubDomains`: se descarta `includeSubDomains` | Lectura de la respuesta | REGISTRO-MEDICIONES `:253-260`; `fase6-iris/docker/nginx/nginx.conf:110`, `:140` | abierto | |
| B38 | Rechazo de firma HMAC en el Workflow 1 (M-21) | Nada: sin ejecución visible, sin mensaje, sin log | Con una alerta real, la alerta se habría perdido | Prueba con firma inválida | REGISTRO-MEDICIONES `:656-673` | no consta | |

---

## 4. Mecanismos

La unidad del argumento es el **mecanismo**, no la ocurrencia: las ocurrencias de
las secciones 2 y 3 son su evidencia. Cada ocurrencia se asigna a un mecanismo
principal. La asignación es una clasificación del autor, no de las fuentes.

| Mecanismo | Qué ocurre | Ocurrencias | n |
|---|---|---|---|
| **M1 · El acuse no es el efecto** | Un código de salida, un `200`, un «Started» o un «success» confirma la recepción o la sintaxis, no el resultado | A1, A2, A3, A5, A27, A28, A29, A34, A38, B1, B8, B21, B28 | 13 |
| **M2 · Lo declarado no es lo desplegado** | La configuración escrita no es la que corre, o no surte efecto | A18, B2, B9, B13, B14, B15, B16, B19, B26, B27, B33 | 11 |
| **M3 · La ausencia disfrazada de valor** | Un vacío, un cero o un valor por defecto plausible ocupa el lugar de un error | A8, A36, A37, A40, B4, B5, B6, B18, B25, B29, B31, B32 | 12 |
| **M4 · La comprobación no discrimina** | Se mide algo contiguo a lo que importa: correlacionado, pero distinto | A9, A15, A16, A17, A19, A20, A23, A26, A30, A33, A39, B11, B12, B22, B23, B24, B36 | 17 |
| **M5 · La señal no llega a nadie** | El fallo se produce, a veces incluso se registra, pero ningún consumidor lo recibe | B3, B7, B17, B30, B34, B38 | 6 |
| **M6 · La lectura parcial tomada por total** | Salida truncada, filtrada, de otro momento o de otro objeto | A4, A6, A7, A14, A21, A24, A25, A32, A35, B35 | 10 |
| | | **Total** | **69** |

**Observaciones.** M4 es el mecanismo más frecuente: se comprueba lo que es fácil
de medir en lugar de lo que importa. M5 solo aparece en la familia B: es el único
mecanismo que no depende del observador, sino de que el sistema no tenga a nadie
escuchando, y es el argumento directo para la prueba periódica de las
capacidades que no se usan a diario (B9).

**Asignaciones discutibles:** B2 (M2 o M4), B8 (M1 o M3), A33 (M4 o M6).

---

## 5. Recuento

| Familia | Casos |
|---|---|
| A · El observador | 34 |
| B · El sistema observado | 35 |
| **Total** | **69** |

Este total sustituye al «ocho» del `README.md` raíz. La versión inicial de este
catálogo contaba 72; el 2026-09-24 se trasladaron A22, A31 y B37 a
«Descartados», por coherencia con el propio criterio (ver allí). A30, A38, B4, B28
y B38 se mantienen tras revisión: en todas, lo que informaba el instrumento era un
éxito aparente. La unidad del argumento es el mecanismo (sección 4).

No se cuentan aparte B10 (subcaso de B9) ni B20 (tercera instancia de B18).

---

## 6. Descartados

| Candidato o caso | Motivo |
|---|---|
| A22 · `tailscale netcheck` con `Nearest DERP: unknown` (retirado de la tabla A) | Informa de fallo con el servicio sano: dirección contraria al criterio, como la sonda de `last_seen_at` (`docs/README-fase4-validacion.md:506-510`) |
| A31 · Volcado automatizado inicial de la auditoría de Fase 8 (retirado de la tabla A) | Es un análisis, no un instrumento; mismo motivo que «Errores de razonamiento del análisis» (`docs/INFORME-AUDITORIA-FASE8.md:363-371`) |
| B37 · `BASE_URL` de MISP en el puerto directo (retirado de la tabla B) | Desde el consumidor real (el W11) la rotura es visible; el acceso directo desde el Ubuntu es un riesgo abierto, no un fallo silencioso (`docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:97-117`) |
| A12 · IRIS devuelve `500` para un caso inexistente (M-29) | Fallo ruidoso: el `500` es un error visible; el problema fue la atribución (REGISTRO-MEDICIONES `:1011-1026`) |
| B10 · `iriswebapp_nginx` con el mismo fallo de bind | Mismo mecanismo que B9 y sin fallo observado en el consumidor: lo salvó la duración de su arranque (`HALLAZGO-rustdesk…:183-194`). Se anota dentro de B9 |
| B20 · «El fallo silencioso, capturado durante su propia remediación» | Es la tercera instancia de B18 (`INFORME-AUDITORIA-FASE6.md:768-772`) |
| M-3 · Authelia `302` → `200` con el HTML del login | Hipotético: la ruta se descartó antes de usarse (REGISTRO-MEDICIONES `:169-181`; `DECISION-n8n-iris-ruta-directa.md:74-81`) |
| M-8 · `is_from_api` invalidado por la cookie | Riesgo; al medirlo, el instrumento funcionaba (REGISTRO-MEDICIONES `:447-455`) |
| M-12 · `$env` sin resolver en nodos HTTP | Ruidoso («authorization failed»), aunque con un mensaje engañoso (`:457-478`) |
| M-28 · `cid` vacío → `401` | Ruidoso (`:1004-1009`) |
| M-30 · Puerto del host usado desde un contenedor | Ruidoso (`ECONNREFUSED`, `:1028-1040`) |
| M-18 · `COPY main.py .` | Ruidoso según la propia fuente (`:627-632`) |
| M-4 (corregida) · Fichero versionado con `$env` roto | Sin ocurrencia en el sistema: la instancia viva nunca estuvo mal (`:865-878`) |
| M-5 y M-41 · Hueco de `export-workflow.sh` sobre `parameters` | Límite de alcance del script, no un informe de éxito; el caso silencioso de M-41 es A14 |
| M-36 y M-43 · Vaciado manual de `staticData` olvidado | Omisión de procedimiento, no un instrumento ni un componente que informara de normalidad |
| M-25 · Campos «no aplica» vacíos | La fuente indica que un campo vacío no afirma nada falso (`:834-839`) |
| M-10 · `pushurl` doble | No falló ninguna función: los dos remotos recibían (`:262-271`) |
| Normalize Alert sin guarda para `data` | La fuente no lo describe como silencioso: lanzaba una excepción (`fase2-orquestador/README.md:214-215`) |
| Bucle `[emerg]` del nginx de IRIS | Ruidoso sin observador; la fuente lo distingue expresamente del fallo silencioso (`INFORME-AUDITORIA-FASE6.md:812-830`) |
| P1-9 de `INFORME-AUDITORIA-FASE6.md` · `MFA_ENABLED` inerte | Detectado por lectura de código antes de usarse; el registro engañoso se describe en condicional (`:482-513`) |
| P1-8 de `INFORME-AUDITORIA-FASE6.md` · `SECURITY_PASSWORD_SALT` sin consumir | No se incumple ninguna función: el hashing es bcrypt (`:626`, `:840`) |
| `wazuhtransport` sin aplicar | Configuración muerta; el efecto lo produce el ajuste global declarado (`REGISTRO-HALLAZGOS…:146-152`) |
| P1-1g · El analista pierde el acceso al dashboard de Wazuh | Visible al intentar el acceso (`TcpTestSucceeded: False`) (`REGISTRO-HALLAZGOS…:166-186`) |
| Desaparición del bloque `tests:` de la ACL | Según `README-fase4-validacion.md:541-546`, ese bloque no existe en v0.28, así que no se perdió ningún control en funcionamiento (`HALLAZGO-headscale…:181-194` dice lo contrario; ver dudas) |
| Regla `tag:kvm` sin nodo | Código muerto registrado; D1 sacó después el KVM del tailnet (`INFORME-P1-0-correcciones.md:163-171`; `INFORME-AUDITORIA-FASE8.md:74-76`) |
| P1-3 de `INFORME-AUDITORIA-FASE8.md` · TLS del canal rtty sin validar | Ruidoso: el sistema lo señala como advertencia en cada conexión (`:150-156`) |
| Sonda basada en `last_seen_at` | Habría dado una falsa alarma, un fallo ruidoso en la dirección contraria (`INFORME-AUDITORIA-FASE8.md:264`) |
| `AGENT_TOKEN` truncado | Ruidoso (`403`) (`README-fase4-validacion.md:553-557`, `:564-565`) |
| Primera rotación de MongoDB (`ReplicaSetNoPrimary`) | Ruidoso, con un mensaje engañoso (`HALLAZGO-credencial-mongodb…:85-100`) |
| `rc=2` de `verify-no-secrets.sh` | El código de retorno era visible; fue un error de invocación (`REGISTRO-HALLAZGOS…:329-334`) |
| `docker compose restart` sin fichero de configuración | Ruidoso: imprimió el error (`HALLAZGO-headscale…:239-243`) |
| Segundo remoto no contemplado en la purga | Inventario incompleto del plan, no un instrumento que informara (`SECURITY-NOTICE.md:99-104`) |
| V9 del diseño del hook, mal enunciada | La fuente no dice que se ejecutara y diera verde (`cierre-mejora1-hook.md:105-109`) |
| `$` sin duplicar en las unidades systemd | Descrito como trampa; la fuente no dice que ocurriera (`HALLAZGO-rustdesk…:227-229`) |
| P1-1 de `INFORME-AUDITORIA-FASE8.md` · `rtty-loop.sh` regenerado en cada arranque | No se registra ninguna edición perdida (`:146`; `mejora2-tls-canal-rtty.md:31-33`) |
| Errores de razonamiento del análisis | Hipótesis e inferencias, no instrumentos (`INFORME-AUDITORIA-FASE8.md:373`; `HALLAZGO-rustdesk…:118-128`; `HALLAZGO-credencial-mongodb…:117-128`) |
| `=` escrito a mano en la cabecera `Cookie` | Condicional; sin ocurrencia registrada (`webhook-kvm-hook-construccion.md:66-69`) |

---

## 7. Sin registro documental localizado

| Candidato | Términos buscados | Resultado |
|---|---|---|
| A10 · `headscale nodes list` muestra `online` sin que el plano de datos enrute | `nodes list`, `online` en `docs/*.md` y `*/README.md` | Las apariciones son usos de comprobación o nodos `offline` (`INFORME-P1-0-correcciones.md:151-158`). No hay ocurrencia de `online` con el plano de datos caído. Lo más próximo es B19 (tailnet operativo y 443 denegado) |
| A11 · El `200` o «Workflow was started» de n8n leído como prueba de ejecución | `Workflow was started`, `onReceived`, `responseMode` | Solo existe la propiedad de diseño (`fase2-orquestador/README.md:493`). No se ha localizado ninguna lectura errónea registrada; el mecanismo forma parte de B1 |
| A13 · `docker cp` de `database.sqlite` de n8n adelantándose a la escritura | `docker cp`, `database.sqlite` en `*.md` | Sin coincidencias sobre ese caso |

**B1** se registró formalmente el 2026-09-24 como M-46 de REGISTRO-MEDICIONES
(hallazgo A-2), con la medición del emisor (`integrations.log`) y del receptor
(`execution_entity`) día por día. La afirmación sobre `integrations.log`, que en
la primera versión de este catálogo no tenía fuente, queda medida allí.

---

## 8. Remedio por familia

**Familia A.** Contrastar con un segundo instrumento que mida lo mismo por otra
vía (`docs/mejora6-endurecimiento-dispositivo.md:369-371`). Verificar con la
misma herramienta que usa el sistema, no con otra
(`fase5-velociraptor/SECURITY-NOTICE.md:255-256`). Verificar el efecto y no la
ejecución: la detección vino siempre de comprobar el estado resultante, nunca
del código de retorno (`docs/INFORME-AUDITORIA-FASE6.md:889-896`). Un control
solo está verificado cuando responde de forma distinta ante entradas distintas
(REGISTRO-MEDICIONES `:1234-1238`); un control negativo sobre un nombre
inexistente da el tercer punto de comparación
(`docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:40-46`).

**Familia B.** Preguntar desde el consumidor: el fallo de B9 «solo aparece al
preguntar desde el consumidor» (`docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:83-86`).
Medir comportamiento y no estado declarado (`docs/INFORME-AUDITORIA-FASE8.md:354`),
y comprobar el código de respuesta en vez de leer la configuración
(`docs/README-fase4a-headscale-ui.md:148`). Que todo conector de salida llegue
a un nodo de respuesta (`docs/cierre-mejora1-hook.md:83-84`) y que la ausencia
de dato se distinga del cero (`abuse_disponible`, REGISTRO-MEDICIONES
`:1484-1487`). Para las capacidades que no se usan a diario, una prueba
periódica (`docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:88-94`).
