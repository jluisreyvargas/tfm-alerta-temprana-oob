# Informe — Remediación P0-1 (Fase 5, Velociraptor)

Preparación del repositorio para la rotación de PKI y la purga de historial. La
rotación de PKI, la reinscripción de clientes, la purga y los commits los ejecuta
el usuario a mano. Este informe describe únicamente lo que se ha dejado escrito.

## 1. Ficheros creados y modificados

### Creados

| Fichero | Justificación |
|---|---|
| `fase5-velociraptor/velociraptor-config/.gitkeep` | Mantiene el directorio del volumen de runtime en el árbol una vez su contenido queda excluido; documenta por qué está vacío. |
| `fase5-velociraptor/config-templates/server.config.template.yaml` | Plantilla sanitizada de `server.config.yaml`: preserva la topología (puertos, `bind_address`, `public_url`, rutas del datastore) y sustituye el material criptográfico por `<<GENERADO_EN_DESPLIEGUE>>`. 12 sustituciones. |
| `fase5-velociraptor/config-templates/client.config.template.yaml` | Ídem para `client.config.yaml`. 2 sustituciones (`Client.ca_certificate`, `Client.nonce`). |
| `scripts/verify-no-secrets.sh` | Control preventivo: recorre los ficheros trackeados y sale con 1 si detecta PEM de clave privada, campos `private_key`/`password_hash`/`password_salt`/`obfuscation_nonce`/`nonce` con valor, o base64 largo en ficheros de config de la Fase 5. Ejecutable. |
| `scripts/purge-history.sh` | Script de purga con `git filter-repo` (NO ejecutado). Comprueba `filter-repo`, backup mirror y árbol limpio; captura los remotos; confirma con `PURGAR`; purga; imprime los comandos de restauración de remotos y `push --force`; ejecuta verificaciones de cierre. Ejecutable. |
| `fase5-velociraptor/SECURITY-NOTICE.md` | Documento de incidente: material expuesto, ventana de exposición (marcadores a rellenar), impacto, alcance, remediación, causa raíz, control preventivo. |
| `fase5-velociraptor/INFORME-P0-1.md` | Este informe. |

### Modificados

| Fichero | Justificación |
|---|---|
| `.gitignore` | Bloque «Fase 5 · Velociraptor» añadido al final (líneas 60–82), sin reordenar lo existente: excluye `velociraptor-config/` completo (salvo `.gitkeep`), las configuraciones reales (`server.config.yaml`, `client.config.yaml`, `client.root.config.yaml`, `api_client.yaml`), `installer-windows/`, `*.msi` y el directorio huérfano `velociraptor/`. |
| `fase5-velociraptor/README.md` | Aviso de seguridad al inicio remitiendo a `SECURITY-NOTICE.md`; nueva sección «Reconstrucción de la configuración»; eliminación de los tokens residuales `[cite:916]`, `[file:720]` y `[file:722]` (mismo origen, otra herramienta); normalización a LF del bloque `mermaid` de la sección 2 (el `\r` en la línea de la valla impedía el render). El contenido técnico de las secciones 4–8 no se ha alterado salvo la retirada de esos tokens. |

Ningún cambio de git aplicado: no se ha ejecutado `git add`, `git rm`, `git commit`
ni `git push`, ni se ha tocado el índice.

## 2. Verificación de `.gitignore` (TAREA 2)

### `git check-ignore -v` (comando plano) — salida literal

```
$ git check-ignore -v fase5-velociraptor/velociraptor-config/server.config.yaml
(sin salida) — exit 1

$ git check-ignore -v fase5-velociraptor/installer-windows/Org__root__velociraptor-v0.76.6-windows-amd64.msi
(sin salida) — exit 1

$ git check-ignore -v fase5-velociraptor/velociraptor/api_client.yaml
(sin salida) — exit 1
```

Las tres devuelven «sin coincidencia» **no porque el patrón sea incorrecto, sino
porque `git check-ignore` no aplica `.gitignore` a ficheros que ya están
trackeados**. Empezarán a coincidir en cuanto el usuario los saque del índice
(`git rm --cached`, o la purga).

### `git check-ignore -v --no-index` — salida literal

Evaluando el patrón sin tener en cuenta el índice, las tres reglas coinciden:

```
.gitignore:71:fase5-velociraptor/**/server.config.yaml	fase5-velociraptor/velociraptor-config/server.config.yaml
.gitignore:77:fase5-velociraptor/installer-windows/	fase5-velociraptor/installer-windows/Org__root__velociraptor-v0.76.6-windows-amd64.msi
.gitignore:81:fase5-velociraptor/velociraptor/	fase5-velociraptor/velociraptor/api_client.yaml
```

Comprobación adicional sobre una ruta **no trackeada** bajo el directorio
excluido: `git check-ignore -v fase5-velociraptor/velociraptor-config/ZZZ.yaml`
→ `.gitignore:67:fase5-velociraptor/velociraptor-config/*` (exit 0). El `.gitkeep`
queda correctamente re-incluido por `.gitignore:68`.

### Observación

En el bloque, `*.msi` es un patrón **global**, no acotado a `fase5-velociraptor/`.
Los dos únicos `.msi` del repositorio están bajo esa carpeta, así que en la
práctica no cambia nada, pero conviene tenerlo presente. Se ha dejado tal cual se
especificó.

## 3. `verify-no-secrets.sh` en el estado actual

```
FALLO: 328 hallazgos sobre 1969 ficheros trackeados.
```

Se esperaba que fallara: los secretos siguen en el árbol. Confirma que el script
detecta.

### Por regla

| Regla | Hallazgos |
|---|---:|
| `base64>60` (acotada a `fase5-velociraptor/**` en `.yaml/.yml/.env/.conf/.json`) | 305 |
| `PEM PRIVATE KEY` (global) | 7 |
| `nonce` (global) | 6 |
| `private_key` (global) | 4 |
| `obfuscation_nonce` (global) | 2 |
| `password_hash` (global) | 2 |
| `password_salt` (global) | 2 |

### Por fichero (sin valores)

| Fichero | Hallazgos |
|---|---:|
| `fase5-velociraptor/velociraptor/server.config.yaml` | 135 |
| `fase5-velociraptor/velociraptor-config/server.config.yaml` | 135 |
| `fase5-velociraptor/client.config.yaml` | 18 |
| `fase5-velociraptor/velociraptor-config/client.config.yaml` | 18 |
| `fase5-velociraptor/velociraptor-config/notebooks/Dashboards/Server.Monitor.Health/uploads/data/client.root.config.yaml` | 18 |
| `fase5-velociraptor/velociraptor-config/clients/server/artifacts/Server.Utils.CreateMSI/F.D8RT56IDDU7CM.json` | 1 |
| `fase5-velociraptor/velociraptor-config/clients/server/collections/F.D8RT56IDDU7CM/notebook/N.F.D8RT56IDDU7CM-server/NC.D8RT5EHL5SQ70-D8RT5EGM2Q390/query_1.json` | 1 |
| `fase6-iris/certificates/rootCA/irisRootCAKey.pem` | 1 |
| `fase3-agentic/README.md` | 1 |

Todos los ficheros de `fase5-velociraptor/` de la tabla están dentro del alcance
de la purga. **Tras la purga, `verify-no-secrets.sh` seguirá reportando 2
hallazgos** que no pertenecen a P0-1:

- `fase6-iris/certificates/rootCA/irisRootCAKey.pem:1` — ver sección 5.
- `fase3-agentic/README.md:407` — falso positivo: la regla `nonce` engancha la
  frase en prosa «Dato favorable al nonce:». No es material sensible.

## 4. Peso de los blobs que la purga elimina del historial

Blobs binarios de más de 1 MB dentro de las rutas de purga
(`velociraptor-config/`, `velociraptor/`, `client.config.yaml`,
`installer-windows/`):

| Bytes | Ruta |
|---:|---|
| 27 414 528 | `fase5-velociraptor/installer-windows/Org__root__velociraptor-v0.76.6-windows-amd64.msi` |
| 27 414 528 | `fase5-velociraptor/velociraptor-config/public/daf1d8c0fdaddbaf2780894b893d995ad5d3f0ede077ff5668ae879666941f31` |
| 3 021 272 | `fase5-velociraptor/velociraptor-config/logs/VelociraptorGUI_info.log.202606150000` (versión 1) |
| 3 002 550 | `fase5-velociraptor/velociraptor-config/logs/VelociraptorGUI_info.log.202606150000` (versión 2) |
| **60 852 878** | **total en blobs > 1 MB** |

Además, 223 ficheros trackeados dentro de esas rutas (≈ 80 MB en el árbol
actual, sumando el estado de runtime completo: `.db`, `.json`, `.chunk`, logs).
La copia del MSI en
`…/clients/server/collections/F.D8RT56IDDU7CM/uploads/scope/` deduplica con el
blob del instalador.

## 5. Campos sensibles fuera de las listas de la TAREA 3

Un único campo, encontrado por lista blanca y sustituido:

- **`GUI.links[0].icon_url`** en `server.config.yaml` — cadena de 978 caracteres
  `data:image/svg…` (icono embebido de un enlace de la interfaz). **No es
  material criptográfico**, pero no figura en la lista de conservar ni en la de
  sustituir, y supera el umbral de «base64 de más de 40 caracteres». Sustituido
  por `<<GENERADO_EN_DESPLIEGUE>>` en la plantilla.

El barrido no encontró ningún otro valor PEM o base64 largo fuera de los bloques
criptográficos ya listados.

### Fuera del alcance de P0-1, detectado durante la verificación

- **`fase6-iris/certificates/rootCA/irisRootCAKey.pem`** — clave privada de la CA
  raíz de DFIR-IRIS, trackeada. Es una segunda exposición, en otra fase, con su
  propia cadena de confianza. No se ha tocado (`.gitignore`, script de purga y
  `SECURITY-NOTICE.md` siguen siendo solo de Velociraptor). Requiere su propia
  decisión: rotación de la CA de IRIS y purga de `fase6-iris/certificates/` del
  historial.

## 6. Acciones pendientes para el usuario, en orden

1. **Revisar los cambios.** `git status --porcelain`, `git diff`, y leer
   `scripts/verify-no-secrets.sh` y `scripts/purge-history.sh` completos.
2. **Sacar del índice lo ahora ignorado** (el usuario toca el índice, no yo):
   `git rm -r --cached fase5-velociraptor/velociraptor-config/`
   (y volver a añadir `.gitkeep`),
   `git rm -r --cached fase5-velociraptor/velociraptor/`,
   `git rm --cached fase5-velociraptor/client.config.yaml`,
   `git rm -r --cached fase5-velociraptor/installer-windows/`.
   Comprobar con `verify-no-secrets.sh` y con `git check-ignore -v` (que ya
   coincidirá).
3. **Rotación de la PKI de Velociraptor — Fase D del plan.** Nueva CA, nuevos
   certificados de frontend y gateway, nuevo `obfuscation_nonce`, nuevas
   credenciales de la GUI. Alinear la topología con
   `config-templates/server.config.template.yaml`.
4. **Reinscripción de los tres clientes — Fase E del plan**, contra la nueva CA.
5. **Backup previo a la purga.** `mkdir -p ~/tfm-backups && git clone --mirror . ~/tfm-backups/repo-mirror-pre-purga.git`. `purge-history.sh` aborta si no lo encuentra.
6. **Purga del historial — Fase F del plan.** `scripts/purge-history.sh` (pide
   escribir `PURGAR`). Al terminar imprime, para lanzar a mano, un
   `git remote add` + `git push --force` por cada remoto (`origin` y `backup`);
   cada repositorio conserva el material expuesto hasta ese `push --force`.
7. **Aplicar el commit de la parte no destructiva a mano.** Plantillas,
   `.gitkeep`, `.gitignore`, los dos scripts, `SECURITY-NOTICE.md`, este informe
   y los cambios de `README.md`. Este commit puede hacerse antes de la purga; la
   purga reescribe igualmente todos los SHA.
8. **Rellenar la ventana de exposición** en `SECURITY-NOTICE.md` con la salida de
   `git log --diff-filter=A --format=%aI -1 -- …` (el propio documento indica los
   ficheros a consultar).
