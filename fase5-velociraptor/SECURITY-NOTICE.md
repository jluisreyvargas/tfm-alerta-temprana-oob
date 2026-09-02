# Aviso de seguridad — exposición de material criptográfico de Velociraptor (P0-1)

## Resumen

El estado de runtime del servidor Velociraptor de la Fase 5 estuvo versionado en
un repositorio git público. Entre el material expuesto se encuentra:

| Material | Ruta en el repositorio |
|---|---|
| Clave privada de la CA del servidor (`CA.private_key`) | `fase5-velociraptor/velociraptor-config/server.config.yaml`, `fase5-velociraptor/velociraptor/server.config.yaml` |
| Certificado y clave privada del frontend (`Frontend.certificate`, `Frontend.private_key`) | mismos ficheros |
| Certificado y clave del gateway de la GUI (`GUI.gw_certificate`, `GUI.gw_private_key`) | mismos ficheros |
| `obfuscation_nonce` del servidor | mismos ficheros |
| Hash y salt del usuario de la GUI (`GUI.initial_users[].password_hash` / `password_salt`) | mismos ficheros |
| `Client.nonce` y `Client.ca_certificate` | `fase5-velociraptor/client.config.yaml`, `fase5-velociraptor/velociraptor-config/client.config.yaml`, `fase5-velociraptor/velociraptor-config/notebooks/Dashboards/Server.Monitor.Health/uploads/data/client.root.config.yaml` |
| Almacén de datos completo del servidor (claves de cliente, ACL, colecciones) | `fase5-velociraptor/velociraptor-config/` (árbol completo) |
| Instalador MSI con configuración de cliente embebida | `fase5-velociraptor/installer-windows/Org__root__velociraptor-v0.76.6-windows-amd64.msi` y una copia en `fase5-velociraptor/velociraptor-config/clients/server/collections/.../uploads/scope/` |

El repositorio tenía dos remotos publicados (`origin` y `backup`), cada uno en un
repositorio distinto de GitHub con el mismo historial. Ambos requieren purga.

## Ventana de exposición

- **Introducido:** 2026-06-21T19:55:04+02:00, en el commit `1149702`
  («docs(fase5): complete Velociraptor and MinIO documentation»).
- **Detectado y contenido:** 1 de septiembre de 2026, al poner en privado los
  repositorios.
- **Ventana:** aproximadamente 72 días.
- **Exposición observada:** 0 forks y 0 stars en el momento de la detección.

El commit que introdujo las claves privadas de la CA, del frontend y del
gateway de la GUI se llamaba «complete Velociraptor and MinIO documentation».

## Impacto

Con `CA.private_key` es posible emitir certificados de cliente válidos y
suplantar un endpoint inscrito ante este servidor Velociraptor. Un tercero con
acceso de red al frontend podría presentarse como un cliente legítimo, recibir
tareas de recolección y devolver resultados manipulados, o simplemente
establecer una sesión autenticada con la infraestructura de respuesta.

El resto del material (hash/salt de la GUI, `obfuscation_nonce`, claves de
frontend y gateway) amplía la superficie pero la clave de la CA es el elemento
determinante: invalida la cadena de confianza completa del despliegue.

## Alcance limitado

Entorno de laboratorio de un Trabajo Fin de Máster. El repositorio registraba 0
forks y 0 stars en el momento de la detección. No hay constancia de uso del
servidor Velociraptor fuera del laboratorio ni de endpoints inscritos que no
sean los tres clientes de prueba del propio proyecto.

## Remediación aplicada

1. **Rotación completa de la PKI de Velociraptor:** nueva CA, nuevos certificados
   de frontend y gateway, nuevo `obfuscation_nonce`, nuevas credenciales de la
   GUI.

   | | Huella SHA-256 de la CA |
   |---|---|
   | CA anterior | `8D:09:C6:90:22:7A:F5:26:AF:00:03:FB:79:C5:FF:A0:74:B2:A4:19:62:94:D2:14:59:97:22:0C:3C:D9:CA:9A` |
   | CA actual | `D6:89:B2:44:C8:C8:22:80:AA:47:1D:5F:44:86:A5:0E:B0:39:A1:F3:69:C2:DE:1E:56:1B:17:64:1E:0D:63:70` |

   Validez de la CA nueva: 2026-09-01 → 2036-08-29.

2. **Reinscripción de los tres clientes** (W11, DC01-TFM, ubuntuserver),
   reinstalados con MSI y configuración regenerados. El cliente Linux rechazó el
   servidor con `x509: certificate signed by unknown authority` hasta recibir la
   CA nueva: es la demostración de comportamiento de que la rotación surtió
   efecto. Los `client_id` no cambian — derivan de la clave pública del
   endpoint, que nunca estuvo expuesta.
3. **Exclusión del estado de runtime del control de versiones:** el directorio
   `velociraptor-config/` y las configuraciones reales dejan de versionarse; en
   el repositorio viven solo plantillas sanitizadas en
   `fase5-velociraptor/config-templates/`. Ver `.gitignore`.
4. **Purga del historial** con `git filter-repo` (ver `scripts/purge-history.sh`)
   sobre cinco rutas: de 135 a 133 commits — dos quedaron vacíos («Ignore
   velociraptor generated files» y «Update fase5 velociraptor data»). El pack
   pasó de ~60,9 MB en blobs a 22,45 MiB. Detalle de la propagación a los
   remotos en «Hallazgos de enumeración durante la remediación».

## Causa raíz

El `.gitignore` del repositorio cubría `**/.env`, un patrón que sugiere que la
gestión de secretos estaba resuelta, pero que no cubre ninguno de los formatos
en los que Velociraptor persiste su material criptográfico: `.yaml` (las
configuraciones de servidor y cliente), `.db` (el almacén de datos) y `.msi`
(el instalador con configuración de cliente embebida). El estado de runtime se
añadió al repositorio como si fuera configuración. El repositorio nunca produjo
un error: `git add` y `git commit` aceptaron el material sin advertencia, y no
había ninguna comprobación que lo rechazara.

## Hallazgos de enumeración durante la remediación

Dos incidencias del propio proceso de purga. Comparten patrón: la operación se
ejecutó correctamente sobre el inventario disponible, y el inventario estaba
incompleto.

- **Segundo remoto no contemplado.** El plan inicial solo consideraba `origin`.
  Existía un segundo remoto, `backup` (`tfm-alerta-temprana-oob-backup`), con el
  mismo historial completo. Se descubrió por la decoración de refs en la salida
  de un `git log` ejecutado con otro propósito, no por una comprobación
  dirigida. La purga y el `push --force` tuvieron que aplicarse también a ese
  repositorio.
- **Objetos huérfanos en el servidor.** Tras el `push --force`, el commit
  `4cfd84c` seguía siendo accesible por SHA directo en GitHub. La purga local
  estaba verificada con cinco comprobaciones en verde y el material seguía
  disponible en el servidor: la verificación local dio en verde midiendo el
  sistema equivocado. Se resolvió borrando y recreando ambos repositorios en
  GitHub; el commit devuelve ahora `404`.

## Hallazgo secundario sin remediar

Los certificados de frontend y de la GUI del servidor Velociraptor se emitieron
con 365 días de validez, pese a `security.certificate_validity_days: 730` en la
configuración. El valor aplicado es el default del producto. La misma
discrepancia existía en la configuración anterior, generada en junio, de modo
que el parámetro nunca surtió efecto. Los certificados actuales caducan el 1 de
septiembre de 2027.

## Control preventivo

- `scripts/verify-no-secrets.sh`: recorre los ficheros trackeados y falla si
  encuentra bloques PEM de clave privada, campos `private_key` / `password_hash`
  / `password_salt` / `obfuscation_nonce` con valor, `nonce` seguido de una
  cadena con aspecto de secreto (≥ 16 caracteres base64 o hexadecimales), o
  cadenas base64 largas en ficheros de configuración de la Fase 5.
- Reglas de `.gitignore` que excluyen `velociraptor-config/` completo (salvo un
  `.gitkeep`), las configuraciones reales (`server.config.yaml`,
  `client.config.yaml`, `client.root.config.yaml`, `api_client.yaml`), el
  directorio de instaladores y `*.msi`.

---

# Aviso de seguridad — credenciales por defecto de MinIO en repositorio público (P0-3)

## Naturaleza

Las credenciales por defecto de MinIO (el par usuario / contraseña que trae la
imagen y que la documentación del proyecto reproducía) estaban escritas en
cinco ubicaciones del repositorio público (`fase5-velociraptor/env.example`,
`fase5-velociraptor/docker-compose.yml`, `fase5-orchestrator-api/README.md` en
dos puntos, y el bloque de compose incrustado en ese mismo README).

No era solo documentación. La Fase 5 no incluía un `.env` en
`fase5-velociraptor/`, de modo que docker-compose aplicaba el valor por defecto
definido en el propio compose (la forma `${VAR:-valor}`). La credencial
documentada era la credencial en uso. Un valor por defecto convirtió la
ausencia de configuración en un almacén de evidencia con credencial pública,
sin que el sistema produjera ningún error.

MinIO guarda la evidencia forense del enclave. Publica su API en
`0.0.0.0:9000` y su consola en `0.0.0.0:9001`, sin TLS.

## Detección

Doble, independiente:

- La auditoría interna de la Fase 5.
- GitGuardian, el 2026-09-02 a las 17:25 UTC, minutos después de un push.

## Cadena de impacto

El endpoint `POST /velociraptor/collect` del orchestrator no exige
autenticación. El perfil `credential_dump_collection` incluye
`Windows.Memory.Acquisition`, que se ejecuta contra el controlador de dominio.
La evidencia resultante se deposita en el bucket `evidence` de MinIO. Con la
contraseña por defecto publicada, el eslabón final de esa cadena —el almacén de
la evidencia recogida sobre el DC— quedaba abierto con una credencial trivial
que figuraba en el propio repositorio.

## Corrección aplicada

1. **Rotación de las credenciales root de MinIO.** Los defaults `:-` de
   `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` en los servicios `minio` y
   `minio-init` de `docker-compose.yml` se sustituyen por la forma `:?`, que
   aborta el arranque con un mensaje explícito si la variable falta, en lugar
   de caer a un valor conocido.
2. **Usuario dedicado `tfm-orchestrator`** con la política `evidence-writer`,
   limitada a `evidence/*` y **sin `s3:DeleteObject`**. El orchestrator deja de
   usar credenciales root. La política tuvo que ampliarse con
   `s3:GetBucketLocation` y los permisos de subida multiparte tras la primera
   colección real (ver hallazgo 3).
3. **Eliminación de los defaults inseguros en el código Python.** En
   `fase5-orchestrator-api/main.py` y en
   `fase7-observabilidad/shared/metrics_client.py`, las llamadas de la forma
   `os.getenv("MINIO_SECRET_KEY", <contraseña por defecto>)` y
   `os.getenv("OS_PASS", <contraseña por defecto del indexador>)` pasan a
   `os.environ[...]`: sin variable no hay arranque, y no hay valor de reserva.
4. **Volumen de la Fase 7 montado en `:ro`** en el compose del orchestrator.
5. **`PYTHONUNBUFFERED=1`** en el compose del orchestrator (ver hallazgo 2).
6. **Eliminación de `fase7-observabilidad/shared/__pycache__/metrics_client.cpython-311.pyc`**,
   que estaba trackeado y contenía el usuario y la contraseña por defecto del
   indexador en su tabla de constantes.
7. **Normalización de finales de línea** de `main.py` de CRLF a LF.

## Verificaciones

| Prueba | Resultado |
|---|---|
| Autenticación con la credencial anterior | `The Access Key Id you provided does not exist` |
| Usuario dedicado: escritura y lectura en `evidence/*` | Correctas |
| Usuario dedicado: intento de borrado | `Access Denied` |
| Colección extremo a extremo (`POST /velociraptor/collect`) | HTTP 200 |
| Evidencia previa a la rotación | 4 objetos intactos |
| `verify-no-secrets.sh` con las reglas vigentes en la remediación | 0 hallazgos |

La regla de credenciales conocidas se añadió a `verify-no-secrets.sh` *después*
de estas verificaciones y llevó el detector de 0 a 54 hallazgos. La resolución
—reformular la documentación propia para describir en lugar de citar la
credencial, y excluir de esa regla (solo de esa) el árbol vendorizado de Wazuh
y los marcadores de posición de los ficheros de ejemplo— está en
`docs/INFORME-hallazgos-detector.md`. El detector vuelve a `exit 0` sin haber
dejado de mirar la documentación propia.

## Tres hallazgos aparecidos durante el diagnóstico

Los tres son variantes del mismo patrón: un control ausente o inefectivo no se
manifiesta como un error, sino como operación normal.

1. **La telemetría del orchestrator llevaba 21 días caída.** El contenedor
   arrastraba en `OS_PASS` la contraseña por defecto del indexador desde antes
   de que esa contraseña se rotara. El último evento indexado con `source: orchestrator`
   era del 2026-08-12 a las 19:58 UTC; la remediación lo restauró el
   2026-09-02. No hubo pérdida de datos: solo se ejecutaron dos colecciones en
   todo el periodo, ambas anteriores al corte. Lo relevante es otra cosa: cero
   eventos del orchestrator es indistinguible de cero colecciones. La ausencia
   de señal no distingue entre «no ocurrió nada» y «no puedo informar de lo que
   ocurrió». El fallo se habría manifestado en el peor momento posible, cuando
   por fin hiciera falta una colección real.

2. **El aviso existía y no llegaba.** `metrics_client.py` captura la excepción
   y emite `print(f"[metrics_client] WARN: ...")`. Alguien escribió ese aviso
   pensando exactamente en este caso. No aparecía en los logs porque Python
   bufferiza stdout cuando no es un terminal y el contenedor no tenía
   `PYTHONUNBUFFERED`. Dos capas de silencio: una intencionada (el `except`,
   correcto para que un fallo de telemetría no rompa la colección forense) y
   otra accidental. Con `PYTHONUNBUFFERED=1` el aviso apareció de inmediato y
   señaló el 401 exacto. En la remediación, ese `print` se sustituyó por
   `logging.warning()`, que respeta la configuración de la aplicación y no
   depende del buffer de stdout.

3. **La verificación con `mc` no predijo el comportamiento del cliente real.**
   La prueba de la política pasó con `mc`, y la primera colección real falló
   con `AccessDenied` sobre el recurso `/evidence`. El SDK de Python de MinIO
   invoca `GetBucketLocation` antes de escribir; `mc` no lo necesita del mismo
   modo. Hubo que ampliar la política con `s3:GetBucketLocation` y los permisos
   de subida multiparte. Verificar con una herramienta distinta de la que usa
   el sistema puede dar verde sobre un control que no funciona.

## Decisión de no purgar el historial

Las credenciales por defecto de MinIO permanecen en commits antiguos. No se
reescribe el historial, y es una decisión razonada, no una omisión:

- Son una credencial trivial y pública que un atacante probaría de todos
  modos. Una vez rotada, su presencia en commits antiguos no aporta riesgo.
- Una tercera reescritura del historial cambiaría todos los SHA sin beneficio
  proporcionado.
- El contraste con el P0-1 es explícito: allí había claves privadas RSA y
  ~60 MB de binarios con configuración de cliente embebida, material cuya
  exposición no se neutraliza rotando una contraseña. Aquí no.

Riesgo aceptado y razonado.

## Riesgos residuales

- **Sobrescritura.** El usuario `tfm-orchestrator` no puede borrar objetos,
  pero sí sobrescribirlos. Comprobado experimentalmente: un `mc cp` sobre una
  clave existente reemplazó el contenido sin error. Para una cadena de custodia
  la distinción entre borrado y sobrescritura no existe —un manifiesto
  sobrescrito está tan destruido como uno borrado, con el agravante de que el
  borrado deja un hueco visible y la sobrescritura no deja rastro—. Quitar
  `s3:DeleteObject` es necesario pero no suficiente: hace falta versionado o
  bloqueo de objetos en el bucket.
- **`incidentid` y `host` sin validar.** Llegan sin sanear en el payload y se
  usan para construir la clave del objeto, de modo que es posible escribir en
  rutas arbitrarias del bucket y pisar el manifiesto de otro incidente.
- **MinIO sin TLS y publicado en `0.0.0.0`** (`:9000` API, `:9001` consola).
- **`minio/minio:latest` sin fijar versión** en un almacén de evidencia
  forense: el dígito de la imagen puede cambiar bajo los pies del despliegue.
