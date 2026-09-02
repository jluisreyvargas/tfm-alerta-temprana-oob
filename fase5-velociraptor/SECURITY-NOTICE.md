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
