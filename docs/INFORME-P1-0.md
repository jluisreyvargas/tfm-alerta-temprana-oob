# Informe — P1-0 (resolución de nombres: declaración y control de divergencia)

## Alcance

Se decidió no desplegar un DNS propio y mantener la resolución por ficheros
`hosts`, atacando la causa real de los defectos D1–D3: no existía ningún
mecanismo que detectara cuando las tres copias (`ubuntu`, `w11`, `dc01`)
divergían. La limpieza de los `hosts` (Fase B) ya la aplicó el usuario. Este
trabajo declara el estado deseado y construye el control que lo verifica.

No se ha ejecutado `git add`, `git commit`, `git push` ni `git rm`. No se ha
tocado el índice, Docker ni ningún servicio. No se ha modificado `/etc/hosts`
ni ningún fichero fuera del repositorio. No se ha borrado ningún fichero del
árbol de trabajo.

## Ficheros creados

| Fichero | Contenido |
|---|---|
| `docs/README-resolucion-nombres.md` | Documento declarativo: principio, dos reglas, tabla de estado por (host, nombre), sección de excepciones (`hs.oob.local` en el DC01), defectos históricos D1–D3 con sus evidencias de runtime, nota operativa de edición en Windows, procedimiento de alta de un nombre, y la decisión «no se despliega DNS propio» en formato de mejora evaluada. |
| `docs/resolucion-nombres.tsv` | Fuente de verdad legible por máquina: una fila por par (host, nombre) con IP, servicio y justificación. Es lo que lee el script. |
| `scripts/verify-hosts.sh` | Control de divergencia. Compara cada `hosts` real con el `.tsv` y falla (exit 1) si no coinciden. |

## Ficheros modificados

| Fichero | Cambio |
|---|---|
| `README.md` | Un punto nuevo en «Principios de diseño»: resolución alineada con la segmentación, con enlace al documento y al script. |
| `docs/README-fase4b-tailnet.md` | Ampliada la nota «Resolución de nombres» del Paso 6: la resolución por `hosts` es parte del modelo de segmentación (D3), con remisión al documento y al script. |

## Decisiones de diseño

### 1. El estado esperado vive en un `.tsv` adyacente, no en el propio Markdown

El documento debía ser la fuente de verdad, pero parsear su tabla Markdown desde
bash es frágil: depende del formato de la tabla, del alineado de las celdas y de
que no aparezca otra tabla con columnas parecidas (el documento tiene una en la
sección de excepciones). Se optó por un `docs/resolucion-nombres.tsv` con una
fila por (host, nombre): TAB como separador, `#` para comentarios. El script lee
de ahí.

Para que no haya dos fuentes de verdad que se desincronicen en silencio:

- El documento **referencia** el `.tsv` como fuente autoritativa y su tabla
  «Estado declarado» se declara explícitamente derivada de él.
- `verify-hosts.sh --check-doc` compara los trípletes (host, nombre, ip) del
  `.tsv` con las filas de la tabla del README y falla si difieren. Es un paso
  del procedimiento de alta. Verificado ahora: coinciden.

### 2. Formato de intercambio con los hosts Windows: líneas crudas del `hosts`

No hay acceso a `w11` ni `dc01` desde el Ubuntu. `verify-hosts.sh --emit w11`
imprime un comando PowerShell de una línea (`Get-Content ... | Where-Object`)
que **solo lee** el `hosts` remoto y vuelca sus líneas no comentadas. El usuario
lo ejecuta allí, pega la salida en un fichero, lo trae, y
`verify-hosts.sh --check w11 <fichero>` lo compara.

El formato de intercambio son las líneas del `hosts` tal cual: no se inventa
ningún formato intermedio que pudiera divergir entre el emisor y el parser, y el
mismo `awk` parsea `/etc/hosts` y el fichero pegado. El comando de recogida no
modifica nada, en respuesta directa a la nota operativa (un
`Get-Content | Set-Content` sobre el propio `hosts` lo bloquea y tumba la
resolución de todo el enclave).

### 3. Alcance del verificador: `*.oob.local` + nombres declarados

Para «presente y no declarado», el script solo señala nombres `*.oob.local`.
Los alias `.local` de servicios que no pasan por Traefik (`velociraptor.local`,
`minio.local`), el nombre `VelociraptorServer`, `localhost` y la pila IPv6 se
listan como informativos y no cuentan como divergencia. Sin este acotado, cada
ejecución ahogaría el hallazgo real (el `chat` duplicado) en ruido de entradas
del sistema. Para «declarado y ausente», «IP distinta» y «duplicado», el chequeo
es por coincidencia exacta de nombre, así que cubre cualquier nombre que se
declare en el `.tsv` aunque no sea `.oob.local` (es el caso de
`velociraptor.local` en `w11` y de `dc01-tfm` en `ubuntu`).

### 4. Se añadió `dc01-tfm` a la declaración del host `ubuntu`

El resumen de partida hablaba de «once nombres». `dc01-tfm` → `100.64.0.2` en el
`/etc/hosts` del Ubuntu no es uno de ellos, pero es una entrada real, documentada
en `README-fase4c-dcagent.md` (el orquestador llama al agente del DC por ese
nombre) y es exactamente la clase de entrada —nombre de nodo del tailnet— que
D2 corrompió al duplicarse. Declararla la pone bajo vigilancia. **A revisar**: si
se prefiere dejarla fuera, basta con borrar esa fila del `.tsv` y la
correspondiente de la tabla del README.

### 5. Comparación de nombres insensible a mayúsculas

El `/etc/hosts` del Ubuntu tiene `DC01-TFM`; el `.tsv` declara `dc01-tfm`. La
resolución de nombres es insensible a mayúsculas, así que el script normaliza a
minúsculas ambos lados. Sin esto, daría un falso `FALTA` + `NO DECLARADO`.

## Verificación estática

```
$ bash -n scripts/verify-hosts.sh
sintaxis OK

$ ./scripts/verify-hosts.sh --check-doc
check-doc: el .tsv y la tabla del README declaran los mismos (host,nombre,ip).
exit=0
```

Prueba de las cuatro detecciones con un `hosts` sintético de `w11` (regresión
D1 + IP de tailnet + nombre ausente): el script marca `IP DISTINTA` en
`hs.oob.local`, `FALTA` en `iris.oob.local` y `NO DECLARADO` en
`velociraptor.oob.local`, y devuelve exit 1. La detección de `DUPLICADO` queda
cubierta por la ejecución real sobre el Ubuntu (abajo).

## Salida literal de `verify-hosts.sh` sobre el Ubuntu

```
== verificación de resolución de nombres ==
host declarado : ubuntu
hosts real     : /etc/hosts
declaración    : docs/resolucion-nombres.tsv

  OK             traefik.oob.local           127.0.0.1
  OK             portainer.oob.local         127.0.0.1
  OK             auth.oob.local              127.0.0.1
  DUPLICADO      chat.oob.local              2 veces: 127.0.0.1,127.0.0.1
  OK             wazuh.oob.local             127.0.0.1
  OK             n8n.oob.local               127.0.0.1
  OK             misp.oob.local              127.0.0.1
  OK             iris.oob.local              127.0.0.1
  OK             kvm.oob.local               127.0.0.1
  OK             hs.oob.local                192.168.127.138
  OK             dc01-tfm                    100.64.0.2
  (fuera de alcance) iris.local              -> 127.0.0.1
  (fuera de alcance) minio.local             -> 127.0.0.1
  (fuera de alcance) velociraptor.local      -> 127.0.0.1

RESULTADO ubuntu: divergencia(s) detectada(s) — corregir el hosts (no lo hace este script).
```

Exit code 1.

## Divergencias detectadas y no corregidas

| Host | Divergencia | Acción del usuario |
|---|---|---|
| ubuntu | `chat.oob.local` declarado una vez, presente dos (ambas a `127.0.0.1`) en `/etc/hosts`, líneas 4 y 6 | Eliminar una de las dos líneas `127.0.0.1   chat.oob.local` de `/etc/hosts`. Editar como root; no hace falta `flushdns` en Linux. Reejecutar `scripts/verify-hosts.sh` y confirmar «sin divergencias». |

Los tres nombres «(fuera de alcance)» no son divergencias: son alias `.local`
locales legítimos (Velociraptor y MinIO se sirven en sus propios puertos, no vía
Traefik). El script los muestra para que su presencia sea visible, sin fallar
por ellos.

## Acciones pendientes, en orden

1. **Corregir el `chat.oob.local` duplicado** en `/etc/hosts` del Ubuntu y
   reejecutar `scripts/verify-hosts.sh` hasta exit 0.
2. **Verificar `w11`**: `scripts/verify-hosts.sh --emit w11`, ejecutar la salida
   en el W11 (PowerShell), pegar el resultado en un fichero, traerlo y
   `scripts/verify-hosts.sh --check w11 <fichero>`. Esperado según la
   declaración: `velociraptor.local`, `hs`, `auth`, `chat`, `n8n`, `iris`, `kvm`
   → `192.168.127.138`; nada de `traefik`/`portainer`/`wazuh`/`misp`; sin
   `velociraptor.oob.local` (D1).
3. **Verificar `dc01`**: igual con `--emit dc01` / `--check dc01`. Esperado:
   únicamente `hs.oob.local` → `192.168.127.138`, sin duplicar (D2), sin
   `kvm`/`iris` (D3).
4. **Revisar la decisión 4** (inclusión de `dc01-tfm` en la declaración del
   Ubuntu): aceptarla o retirar la fila del `.tsv` y de la tabla del README.
5. **Confirmar los valores inferidos de la tabla**: la justificación de
   `hs.oob.local` → `192.168.127.138` en el Ubuntu (por qué no loopback) se ha
   redactado a partir del uso de `--login-server` en la Fase 4b; si hay un
   motivo más preciso, ajustarlo en el `.tsv` y en el README.
6. **Antes del P1-1**: por cada uno de los seis servicios nuevos tras Traefik,
   seguir el procedimiento de alta del documento (editar `.tsv` → actualizar
   tabla → editar `hosts` de los hosts afectados → `verify-hosts.sh` +
   `--check-doc`).

## `git status --porcelain`

```
 M README.md
 M docs/README-fase4b-tailnet.md
?? docs/INFORME-P1-0.md
?? docs/README-resolucion-nombres.md
?? docs/resolucion-nombres.tsv
?? scripts/verify-hosts.sh
```
