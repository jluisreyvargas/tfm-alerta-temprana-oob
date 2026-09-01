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

_(pendiente: fecha del primer commit que introdujo el material)_ a
_(pendiente: fecha de la puesta en privado del repositorio)_.

Para obtener la fecha de inicio, sin ejecutarlo aquí:

```
git log --diff-filter=A --format=%aI -1 -- fase5-velociraptor/velociraptor-config/server.config.yaml
```

Interpretación del resultado: `--diff-filter=A` restringe la búsqueda al commit
en el que el fichero fue **añadido** por primera vez; `--format=%aI` imprime la
fecha de autoría en ISO 8601 y `-1` se queda con la más antigua. La fecha
devuelta es el instante a partir del cual `server.config.yaml` —y con él
`CA.private_key`— quedó accesible en el historial. Conviene repetir el comando
para `fase5-velociraptor/client.config.yaml` y para
`fase5-velociraptor/installer-windows/` y tomar la más temprana de las tres.

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

1. Rotación completa de la PKI de Velociraptor: nueva CA, nuevos certificados de
   frontend y gateway, nuevo `obfuscation_nonce`, nuevas credenciales de la GUI.
2. Reinscripción de los tres clientes contra la nueva CA.
3. Exclusión del estado de runtime del control de versiones: el directorio
   `velociraptor-config/` y las configuraciones reales dejan de versionarse; en
   el repositorio viven solo plantillas sanitizadas en
   `fase5-velociraptor/config-templates/`. Ver `.gitignore`.
4. Purga del historial con `git filter-repo` (ver `scripts/purge-history.sh`) y
   `push --force` a los dos remotos.

## Causa raíz

El `.gitignore` del repositorio cubría `**/.env`, un patrón que sugiere que la
gestión de secretos estaba resuelta, pero que no cubre ninguno de los formatos
en los que Velociraptor persiste su material criptográfico: `.yaml` (las
configuraciones de servidor y cliente), `.db` (el almacén de datos) y `.msi`
(el instalador con configuración de cliente embebida). El estado de runtime se
añadió al repositorio como si fuera configuración. El repositorio nunca produjo
un error: `git add` y `git commit` aceptaron el material sin advertencia, y no
había ninguna comprobación que lo rechazara.

## Control preventivo

- `scripts/verify-no-secrets.sh`: recorre los ficheros trackeados y falla si
  encuentra bloques PEM de clave privada, campos `private_key` / `password_hash`
  / `password_salt` / `obfuscation_nonce` / `nonce` con valor, o cadenas base64
  largas en ficheros de configuración de la Fase 5.
- Reglas de `.gitignore` que excluyen `velociraptor-config/` completo (salvo un
  `.gitkeep`), las configuraciones reales (`server.config.yaml`,
  `client.config.yaml`, `client.root.config.yaml`, `api_client.yaml`), el
  directorio de instaladores y `*.msi`.
