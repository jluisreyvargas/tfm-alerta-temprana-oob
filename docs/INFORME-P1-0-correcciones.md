# Informe — Correcciones tras el P1-0

Al cerrar el P1-0 aparecieron cuatro incoherencias en la documentación. Tres
tienen la misma forma: un documento que describe un estado que el sistema ya no
tiene. La cuarta (`dc01-tfm` en la declaración) es consecuencia directa de la
primera. Ninguna es un fallo de seguridad.

No se ha ejecutado `git commit`, `git push`, `git add` ni `git rm`. No se ha
tocado el índice, Docker ni ningún servicio. No se ha modificado `/etc/hosts` ni
ningún fichero fuera del repositorio.

## Hechos verificados en esta sesión

| Comprobación | Resultado |
|---|---|
| `fase4-breakglass-dc/headscale/config/config.yaml` | `magic_dns: true`, `base_domain: tailnet.internal` (líneas 59–60) |
| `tailscale dns status` | MagicDNS *enabled tailnet-wide*, sufijo `tailnet.internal` |
| `headscale nodes list` | 4 nodos: `orchestrator-tfm`, `dc01-tfm`, `glkvm`, `analyst-w11` |
| `getent hosts dc01-tfm` | `100.64.0.2   DC01-TFM` |
| `/etc/hosts` del orquestador | contiene aún `100.64.0.2  DC01-TFM` |
| `/etc/nsswitch.conf` | `hosts: files mdns4_minimal [NOTFOUND=return] dns` |

## Qué se corrigió, por fichero

### `docs/resolucion-nombres.tsv`

- **Eliminada la fila `ubuntu / dc01-tfm / 100.64.0.2`.** `dc01-tfm` es un nombre
  de nodo del tailnet y lo resuelve MagicDNS, no `/etc/hosts`. Declararlo en un
  control que verifica ficheros `hosts` obliga al control a exigir una entrada
  que, bien hecha la limpieza, no debe existir.
- Añadida al comentario de cabecera una línea que sitúa los nombres de nodo del
  tailnet fuera del alcance del control.
- La fila `dc01 / velociraptor.local` la había añadido el usuario en el commit
  `6153d9a`; su texto en el `.tsv` ya era correcto y no se toca aquí.

### `docs/README-resolucion-nombres.md`

- **Eliminada la fila `| ubuntu | dc01-tfm | … |`** de la tabla «Estado
  declarado» (espejo del `.tsv`).
- **Corregida la fila `| dc01 | velociraptor.local | … |`.** Estaba truncada a
  media cadena y arrastraba por copia la justificación de la fila del W11
  («GUI forense (:8889)», «Puesto de analista»), falsa para el DC. Ahora:
  `Velociraptor — frontend de agentes (:8001) | Ver Excepciones.`
- **Nueva subsección de excepciones** `### velociraptor.local en el DC01`, con el
  mismo formato que la de `hs.oob.local`: es la configuración del cliente
  Velociraptor de la máquina, fijada al reinscribir los agentes en el P0-1; su
  tráfico va a `192.168.127.138:8001` por el segmento corporativo; es coherente
  con la ACL, que no da al DC ningún destino en el tailnet salvo RustDesk. Se
  añade la consecuencia: **la colección forense no viaja por el canal
  out-of-band**; si ese segmento cae, Velociraptor deja de recolectar justo
  cuando se necesita. Asimetría respecto al break-glass de la Fase 4, que sí va
  por el tailnet. Documentado como limitación conocida.
- **Nueva sección `## Dos mecanismos de resolución`**: MagicDNS (nombres de
  nodo, `tailnet.internal`, verifica Headscale) frente a ficheros `hosts`
  (nombres de servicio `*.oob.local` y alias `.local`, verifica
  `verify-hosts.sh`), con tres consecuencias explícitas: el verificador solo
  cubre el segundo mecanismo; MagicDNS ya aporta parte de lo que daría un DNS
  propio pero solo para nombres de nodo; `base_domain` es `tailnet.internal`
  a propósito, para no colisionar con `oob.local`.
- **«Estado declarado»**: añadida la nota de que `--check-doc` compara solo la
  terna (host, nombre, ip) y **no** las columnas de texto — ver más abajo.
- **«Decisión — no se despliega DNS propio»**: reforzada, no cambiada, con el
  argumento de que MagicDNS ya cubre los nombres de nodo con garantías de
  resolver (respeta la ACL y la pertenencia al tailnet), y lo que queda por
  sincronizar a mano es solo el espacio `*.oob.local`.
- **«Referencias»**: añadido `config.yaml`; reformuladas las líneas de fase4b y
  fase4c para reflejar que MagicDNS está operativo.

### `docs/README-fase4c-dcagent.md`

Reescrita la sección «Resolución de nombres en el orquestador». Describía un
estado superado: que MagicDNS no funcionaba porque `base_domain` colisionaba con
`oob.local`, que la configuración endurecida lo corregía pero «está escrita y
todavía no aplicada», y que por eso «esta entrada manual sigue siendo
necesaria», con instrucciones de `sudo nano /etc/hosts` para añadir
`100.64.0.2   dc01-tfm`.

Nueva estructura, sin borrar el histórico (el razonamiento sobre la colisión de
`base_domain` se conserva en pasado): **el problema** → **cómo se resolvió**
(Paso 8: `base_domain: tailnet.internal`, `magic_dns: true`, aplicado) →
**estado actual verificado (2026-09-04)** → **cómo se resuelve hoy** (MagicDNS;
no se añade `dc01-tfm` a `hosts`). Retiradas las instrucciones de edición de
`/etc/hosts`. Añadida una nota de que queda una línea `100.64.0.2  DC01-TFM`
sobrante en el `/etc/hosts` del orquestador, de la época en que MagicDNS no
funcionaba, y conviene retirarla.

### `docs/README-fase4-pendientes.md`

El pendiente §8.1 «No hay resolución de nombres propia del enclave» seguía
listado como abierto. Se conserva el texto y se le añade debajo un blockquote
**Parcialmente resuelto (2026-09-04, P1-0)** —mismo tratamiento que el hallazgo E
del P0-3, marcar sin borrar—: MagicDNS operativo para nombres de nodo, entrada
manual de `dc01-tfm` ya redundante, nombres de servicio `*.oob.local` en `hosts`
por diseño y vigilados por `verify-hosts.sh`.

### `scripts/verify-hosts.sh`

- Cabecera: tres líneas nuevas que dejan claro que **no** vigila MagicDNS.
- `usage()`: sustituido el `sed -n '2,40p'` fijo por un `awk` que imprime el
  bloque de cabecera hasta el primer renglón no comentado. Las tres líneas
  nuevas habían desplazado el rango fijo y `--help` se comía el `set -euo
  pipefail`. Sin cambio de lógica de verificación.

## Por qué `--check-doc` no detectó la justificación errónea

`--check-doc` construye, para el `.tsv` y para la tabla del README, la lista
ordenada de ternas `host  nombre  ip` (el `awk` extrae solo esos tres campos) y
las compara con `diff`. Las columnas *servicio* y *justificación* no se leen
nunca.

La fila rota `dc01 / velociraptor.local` tenía el host, el nombre y la IP
correctos, así que su terna coincidía con la del `.tsv` y `--check-doc` quedaba
en verde pese a que la justificación estaba copiada de la fila del W11 y la línea
estaba truncada.

**Limitación de alcance.** El control garantiza que los dos ficheros coinciden en
*qué resuelve dónde*, no en *por qué*. La revisión del texto es manual. Queda
escrito en el propio documento («Estado declarado»).

## ¿La fila `dc01-tfm` llegó a validarse contra el `/etc/hosts` real?

**Sí.** La ejecución del P1-0 imprimió `OK   dc01-tfm   100.64.0.2`. No fue una
ausencia tolerada ni una captura antigua:

- El `/etc/hosts` del orquestador contiene `100.64.0.2  DC01-TFM` — la entrada
  manual que documentaba `README-fase4c-dcagent.md`, de antes de que MagicDNS
  funcionara. **Sigue ahí a fecha de hoy** (2026-09-04), no se ha modificado
  `/etc/hosts` en este trabajo.
- `parse_hosts()` y `declared_for()` pasan los nombres por `tolower()`, así que
  `DC01-TFM` casó con el declarado `dc01-tfm`, y la IP coincidía.
- El script **no** tolera ausencias: en `compare()`, un nombre declarado y no
  presente produce `FALTA` y `problems++` → exit 1. Si esa línea no hubiera
  estado, el P1-0 habría fallado con `FALTA dc01-tfm`.

`getent hosts dc01-tfm` responde hoy desde `/etc/hosts` (en `nsswitch.conf`,
`files` precede a `dns`), y por eso devuelve la grafía del fichero, `DC01-TFM`;
MagicDNS resolvería el mismo `100.64.0.2` si la línea no estuviera.

**Consecuencia y motivo de la retirada.** Mantener `dc01-tfm` en la declaración
ataba el control a una línea redundante: el día que alguien la elimine de
`/etc/hosts` —la limpieza correcta, porque MagicDNS ya cubre el nombre—
`verify-hosts.sh` empezaría a fallar con `FALTA` sobre un nombre que resuelve
perfectamente. Retirada de la declaración en esta ronda. **Acción pendiente del
usuario**: eliminar la línea `100.64.0.2  DC01-TFM` del `/etc/hosts` del
orquestador.

## Hallazgo para el bloque de Fase 8 — nodo `glkvm`

No corregido, solo registrado.

`headscale nodes list`:

```
ID | Hostname | Name  | User    | Tags | IP addresses | Connected | Last seen
3  | glkvm    | glkvm | tfm-oob | (—)  | 100.64.0.3   | offline   | 2026-07-13 15:46:18
```

- **Offline desde 2026-07-13.** 53 días a fecha de hoy. Sin monitorización de
  disponibilidad del tailnet (pendiente ya listado en §8.1 de
  `README-fase4-pendientes.md`).
- **Sin tag.** El nodo está en el usuario `tfm-oob`, no en `tagged-devices`, y
  la columna Tags está vacía. `tailscale status` ni siquiera lo lista como peer.
- **La ACL define reglas para `tag:kvm` que no se le aplican.**
  `acl.hujson` declara `"tag:kvm": ["tfm-oob@"]` en `tagOwners` y la regla
  `{ "action": "accept", "src": ["tag:analyst"], "dst": ["tag:kvm:443,80,22"] }`.
  Ningún nodo lleva `tag:kvm`, así que esa regla no concede acceso a nada. El
  Plan C por tailnet está declarado pero no operativo; el acceso principal al
  KVM es por red cableada.
- Acción cuando `glkvm` reconecte: `headscale nodes tag --identifier 3 -t
  tag:kvm` (ya anotado en §8.1). Hasta entonces, la regla `tag:kvm` de la ACL es
  código muerto.

## Salida de `verify-hosts.sh` tras los cambios

### 1 · Ubuntu (`/etc/hosts` real)

```
== verificación de resolución de nombres ==
host declarado : ubuntu
hosts real     : /etc/hosts
declaración    : docs/resolucion-nombres.tsv

  OK             traefik.oob.local           127.0.0.1
  OK             portainer.oob.local         127.0.0.1
  OK             auth.oob.local              127.0.0.1
  OK             chat.oob.local              127.0.0.1
  OK             wazuh.oob.local             127.0.0.1
  OK             n8n.oob.local               127.0.0.1
  OK             misp.oob.local              127.0.0.1
  OK             iris.oob.local              127.0.0.1
  OK             kvm.oob.local               127.0.0.1
  OK             hs.oob.local                192.168.127.138
  (fuera de alcance) iris.local              -> 127.0.0.1
  (fuera de alcance) minio.local             -> 127.0.0.1
  (fuera de alcance) velociraptor.local      -> 127.0.0.1

RESULTADO ubuntu: sin divergencias.
```

exit 0. (El `chat.oob.local` duplicado del P1-0 lo corrigió el usuario; ya no
aparece. `DC01-TFM`, sin punto y no declarado, se ignora en silencio.)

### 2 · `--check-doc`

```
check-doc: el .tsv y la tabla del README declaran los mismos (host,nombre,ip).
```

exit 0.

### 3 · `--check w11` y `--check dc01`

Contra muestras construidas a partir de la declaración (no son los `hosts`
reales de esas máquinas; sirven para confirmar que la declaración es
autoconsistente). El usuario debe repetirlo con `--emit` / `--check` sobre los
`hosts` reales.

```
RESULTADO w11: sin divergencias.      (velociraptor.local, hs, auth, chat, n8n, iris, kvm → 192.168.127.138)
RESULTADO dc01: sin divergencias.     (hs, velociraptor.local → 192.168.127.138)
```

ambos exit 0.

## Acciones pendientes del usuario, en orden

1. Eliminar la línea `100.64.0.2  DC01-TFM` del `/etc/hosts` del orquestador
   (redundante; MagicDNS resuelve `dc01-tfm`). Reejecutar `verify-hosts.sh`:
   debe seguir en exit 0.
2. Verificar los `hosts` reales de `w11` y `dc01` con `--emit` / `--check`.
3. Etiquetar `glkvm` como `tag:kvm` cuando reconecte, o asumir explícitamente
   que la regla `tag:kvm` de la ACL queda inactiva.

## `git status --porcelain`

```
 M docs/README-fase4-pendientes.md
 M docs/README-fase4c-dcagent.md
 M docs/README-resolucion-nombres.md
 M docs/resolucion-nombres.tsv
 M scripts/verify-hosts.sh
?? docs/INFORME-P1-0-correcciones.md
```
