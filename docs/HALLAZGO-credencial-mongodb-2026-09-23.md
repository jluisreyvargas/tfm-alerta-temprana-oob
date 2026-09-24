# Hallazgo · Credencial de MongoDB con rol root en claro en ficheros versionados

**Fecha:** 2026-09-23 · **Fase:** 1 (infraestructura) · **Origen:** A-21 del
informe de auditoría de cierre (`docs/AUDITORIA-CIERRE-2026-09-23.md`) ·
**Estado:** credencial rotada y verificada por comportamiento; valor anterior
presente en el historial de git, no reescrito.

## Qué había

La contraseña del usuario `rcuser` de MongoDB figuraba en claro en tres
ficheros versionados:

| Fichero | Apariciones |
|---|---|
| `fase1-infraestructura/docker-compose.yml:91` (healthcheck de `mongodb`) | 1 |
| `docs/README-fase1c-mongodb-rocketchat.md` | 5 |
| `docs/README-fase1e-validacion.md:81` | 1 |

## Qué se midió

- **Privilegio.** `db.getSiblingDB("admin").getUser("rcuser").roles` →
  `root` y `clusterAdmin` sobre `admin`. Control total de la base de
  Rocket.Chat, es decir, del War Room.
- **Identidad.** `rcuser` es el valor de `MONGO_INITDB_ROOT_USERNAME` en
  `fase1-infraestructura/.env`. No es una cuenta auxiliar del healthcheck: es la
  misma que usa Rocket.Chat. (El informe de auditoría la describía como
  «usuario administrador root»; la gravedad era correcta, la identificación del
  usuario no.)
- **Vigencia.** `docker inspect --format '{{.State.Health.Status}}' mongodb` →
  `healthy`: el healthcheck se autenticaba con éxito, luego el literal
  versionado era la credencial en uso (D-3).

## Mecanismo

`MONGO_URL` y `MONGO_OPLOG_URL` de Rocket.Chat (`docker-compose.yml:107-108`)
**ya tomaban la credencial del `.env`** mediante
`${MONGO_INITDB_ROOT_USERNAME}` y `${MONGO_INITDB_ROOT_PASSWORD}`. El patrón
correcto existía y estaba aplicado. El healthcheck, tres líneas más arriba, lo
saltaba con el valor escrito directamente, y la documentación de las subfases 1c
y 1e reproducía los comandos con el mismo literal.

Es el tercer caso del patrón de credencial de arranque del proyecto: el valor
entra para que algo arranque en mayo, funciona, y sobrevive a todas las
revisiones posteriores.

## Dos controles ciegos al mismo objeto

1. **`docs/revision-credenciales-fases1-8.md`** afirmaba que ningún secreto
   revisado estaba expuesto en git. La revisión comparó el `.env` real con
   `.env.example`, no con los literales de los compose ni de la documentación.
   El objeto estaba fuera del universo que el método examinaba.
2. **`scripts/verify-no-secrets.sh`** no lo detecta: ninguna de sus reglas lo
   atrapa. El valor tenía forma de identificador —nombre del proyecto más año
   más un signo—, no de secreto. Las reglas buscan formas (cabeceras
   `Authorization`, cadenas largas de alta entropía), y un detector por forma
   encuentra lo que parece secreto, no lo que lo es.

Dos métodos independientes, cada uno correcto dentro de su alcance, ciegos al
mismo objeto por razones distintas.

## Remediación

1. Rotación en MongoDB con `db.changeUserPassword`, verificada con
   `connectionStatus` usando el valor nuevo antes de tocar ningún fichero.
2. `docker-compose.yml:91`: el literal se sustituye por
   `${MONGO_INITDB_ROOT_PASSWORD}`, igual que las líneas 107-108. Queda
   verificado por comportamiento que Compose interpola la variable en un
   healthcheck en forma exec (`["CMD", …]`): tras `--force-recreate`, el
   contenedor vuelve a `healthy`.
3. `.env` actualizado; `ROCKETCHAT_ADMIN_PASS` del mismo fichero no interviene
   (el compose no la referencia; la cuenta de administración vive en MongoDB
   desde el primer arranque).
4. Rocket.Chat recreado; arranque limpio y acceso por navegador con la cuenta
   de administración verificado.
5. Documentación de las subfases 1c y 1e: literal sustituido por el marcador
   `<CONTRASENA_RCUSER>`, con nota fechada.

**Historial de git no reescrito.** El valor anterior permanece en los commits
que tocaron estos ficheros. Un `push --force` no elimina los objetos huérfanos
en GitHub y exigiría borrar y recrear los repositorios. El riesgo lo neutraliza
la rotación; la sustitución en el árbol es higiene.

## La trampa de la rotación

La primera rotación **tumbó Rocket.Chat**, y el error apuntaba a otra parte.

El valor nuevo contenía un carácter reservado de URI. `mongosh` recibe la
contraseña como argumento y autenticaba sin problema; Rocket.Chat la recibe
**dentro de una URI** (`mongodb://usuario:CONTRASEÑA@mongodb:27017/...`), y el
driver partió la cadena por ese carácter. El síntoma:

type: 'ReplicaSetNoPrimary'
servers: Map(1) { '32:27017' => [ServerDescription] }
Topology is closed


Ni un solo `bad auth` o `Authentication failed` en el log. El driver había
tomado un fragmento de la contraseña como nombre de servidor. `rs.conf()` era
correcto (`mongodb:27017`, un miembro, `PRIMARY`). Un diagnóstico guiado por el
mensaje de error habría ido a reconfigurar un replica set que estaba sano.

Se resolvió con una segunda rotación a 48 caracteres hexadecimales
(`openssl rand -hex 24`). **Regla:** una contraseña que se consume dentro de una
URI de conexión debe ser alfanumérica, y antes de recrear hay que comprobar en
el `.env` la ausencia de caracteres no alfanuméricos y la longitud exacta. Ese
control se aplicó en la segunda rotación y habría evitado la primera.

## Hallazgo de segundo orden: el healthcheck mide otra cosa

El healthcheck de `mongodb` ejecuta `rs.status().ok`, que devuelve `1` también
con el replica set sin primario. Durante la recuperación, `mongodb` figuraba
`healthy` mientras no aceptaba escrituras, y `depends_on:
condition: service_healthy` dejó arrancar a Rocket.Chat en ese estado. El
instrumento informa correctamente de lo que mide; lo que mide no es lo que hace
falta saber. No se ha corregido; queda como deuda declarada.

## Errores de análisis durante la remediación

1. Se afirmó que `MONGO_URL` y `MONGO_OPLOG_URL` contenían la contraseña en
   literal porque un `grep` encontró `mongodb://` en esas líneas. Lo que había
   encontrado era el esquema de la URI; ambas usaban variables. Se concluyó
   sobre el contenido sin haberlo visto.
2. No se advirtió de la restricción de caracteres **antes** de generar el valor
   nuevo, pese a que el consumidor era conocido de antemano (Rocket.Chat,
   vía URI).
3. Se atribuyó el `ReplicaSetNoPrimary` a un `rs.conf()` con un host inválido
   registrado en la inicialización. `rs.conf()` era correcto; la causa estaba en
   el cliente.
