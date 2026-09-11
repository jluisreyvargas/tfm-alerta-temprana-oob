# Revisión transversal de credenciales y superficie · fases 1 a 8

**Origen:** el §3 de `docs/credenciales-de-arranque.md` derivaba una regla de dos
hallazgos accidentales — un inventario de credenciales necesita dos ejes, qué
existe **y cuándo se creó**. Esta revisión aplica esa regla al enclave completo.

**Método:** inventario de claves, certificados y ficheros de entorno ordenados
por fecha de creación, revisados de más antiguo a más reciente. Para cada uno:
exposición en git, permisos, ámbito, y quién lo consume. Ningún valor de
credencial se transcribió en el proceso.

**Fecha:** 11 de septiembre de 2026.

---

## 1. Resultado

La regla funciona. De los cuatro hallazgos, **los cuatro son de mayo a agosto**, y
el de mayor impacto es el más antiguo de todo el proyecto.

| Fecha | Elemento | Resultado |
|---|---|---|
| 3 may | Certificado y publicación de Portainer | **Corregido** — §2 |
| 16 may | CA del instalador de Wazuh | Anotación — §4.1 |
| 16 may | Certificado de la API de Wazuh (55000) | Anotación — §4.2 |
| 24 may | MISP publicado en la LAN | **Pendiente** — §3 |
| 31 may | `db.sqlite` de Headscale en `644` | **Corregido** — §2.2 |
| 5 jun | `.env.example` de Fase 1 con valores | Anotación — §4.4 |

Ninguna clave ni fichero de entorno revisado está expuesto en git. Las
exclusiones están repartidas en cuatro `.gitignore` distintos y todas
funcionan.

---

## 2. Corregido

### 2.1 Portainer publicado en la LAN con acceso a `docker.sock`

**El hallazgo.** El contenedor `portainer` publicaba `0.0.0.0:9443` y montaba
`/var/run/docker.sock`. Cualquier equipo de `192.168.0.0/24` que llegara a su
contraseña obtenía control del demonio Docker: leer los secretos de todos los
contenedores, montar el sistema de ficheros del host, ejecutar como root.

El montaje era `:ro`, lo que limita menos de lo que parece — la restricción es
sobre el fichero del socket, no sobre las operaciones que la API permite.

**Por qué importa más que el resto.** Es la vía más corta a todo lo protegido en
las mejoras de Fase 8. Quien entre por ahí lee el token de rtty, la clave del
certificado del enclave, la base de Headscale y las credenciales de n8n sin tocar
el hook de autorización, el TLS del canal ni los permisos corregidos.

**Su certificado** es el más antiguo del proyecto: generado el 3 de mayo de 2026,
con cinco años de vigencia, y **sin subject ni issuer**. No es que no valide para
un nombre: es que no declara ninguno.

**Corrección aplicada.** Mapeo cambiado de `"9443:9443"` a `"127.0.0.1:9443:9443"`
en `fase1-infraestructura/docker-compose.yml`. Verificado: desde la LAN la
conexión no se establece; desde el host responde `200`.

El servicio se usa a diario, así que el acceso remoto pasa a ser por túnel SSH
(`ssh -N -L 9443:127.0.0.1:9443 jose@192.168.0.70`), sin pérdida de
funcionalidad.

### 2.2 Base de datos de Headscale legible por cualquier usuario

`fase4-breakglass-dc/headscale/lib/db.sqlite` estaba en `644`. Contiene los
nodos, sus claves públicas, los usuarios y **las preauthkeys** — incluida la que
se expiró ese mismo día.

Incoherente con las dos claves de su mismo directorio, `noise_private.key` y
`derp_server_private.key`, ambas en `600`. Una preauthkey protegida mediante
`expire` pero legible en la base por cualquier proceso del host no está muy
protegida.

Corregido a `600` los tres ficheros (`.db`, `-shm`, `-wal`). Verificado después:
Headscale sigue operativo con los tres nodos, porque el contenedor corre como
root.

---

## 3. Pendiente de aplicar · MISP publicado directamente en la LAN

**Estado.** MISP corre en cinco contenedores y publica `0.0.0.0:12443` y
`0.0.0.0:1280`, **sin pasar por Traefik**: no tiene etiquetas `traefik.enable`, y
una petición con `Host: misp.oob.local` al proxy devuelve `404`.

**Tres problemas en uno:**

- **Certificado `CN=localhost`**, autofirmado, caduca el 24 de mayo de 2027.
  Ningún cliente puede verificarlo. El analista accede por navegador y acepta la
  advertencia — en el enclave que existe para vigilar, eso enseña a ignorar
  avisos de certificado.
- **Redirección rota.** El puerto 1280 responde `301` hacia
  `https://192.168.0.70/`, sin puerto: quien entra por HTTP acaba en Traefik, no
  en MISP. MISP no sabe en qué puerto está publicado.
- **Fuera del SSO.** Wazuh y n8n pasan por `authelia@file`; MISP no.

**La intención estaba.** `misp.oob.local` figura en el SAN del certificado
comodín del enclave, emitido el 24 de agosto. Alguien previó que MISP iría detrás
de Traefik y la integración no llegó a hacerse. Es el mismo caso que
`glkvm-device.crt`: un artefacto emitido para algo que no se completó.

**Plan preparado, no aplicado.** Un `docker-compose.override.yml` en
`misp/misp-docker/` — para no tocar el compose del vendor — que:

- cambie los puertos publicados a `127.0.0.1`, conservando una vía de depuración
  local;
- añada router de Traefik para `misp.oob.local` con `secure-headers@file` y
  `authelia@file`, apuntando al puerto 443 interno con `scheme=https`, siguiendo
  el patrón del dashboard de Wazuh (MISP fuerza redirección a HTTPS, de modo que
  el puerto 80 interno daría bucle).

**Verificado que no rompe el flujo de enriquecimiento CTI.** El nodo de n8n que
consulta MISP usa `https://misp/attributes/restSearch` — un alias de red interno
declarado en el compose del vendor (`aliases: misp, misp.oob.local` en
`oob-network`). Esa petición no pasa por el puerto publicado ni por Traefik, así
que ni el cierre de puertos ni Authelia la afectan. Línea base registrada antes
de cualquier cambio: desde n8n, `misp` resuelve a `172.18.0.10`.

**Decisión pendiente.** El alias interno `misp.oob.local` y el router de Traefik
para ese mismo nombre coexistirían, resolviendo a destinos distintos según desde
dónde se pregunte. No rompe nada, pero es una ambigüedad que conviene decidir a
propósito: usar ese nombre en el router y aceptar la doble resolución, o dar otro
nombre de host al router.

---

## 4. Anotaciones sin acción

### 4.1 CA del instalador de Wazuh

`wazuh_indexer_ssl_certs/root-ca.key` y `root-ca-manager.key`, del 16 de mayo:
una CA autofirmada `OU=Wazuh, O=Wazuh, L=California` con **diez años de
vigencia**, generada por el instalador.

Verificado su ámbito en `ossec.conf`: la usa el manager para hablar con el
indexer vía filebeat. Tráfico entre contenedores del mismo host. **No es un
segundo ancla de confianza del enclave** — nada externo confía en ella.

Queda como anotación: una clave más que custodiar y una vigencia excesiva, con
alcance acotado. El directorio entero está excluido de git.

### 4.2 Certificado de demostración de la API de Wazuh

El puerto 55000, publicado en `0.0.0.0`, presenta `C=US, O=Wazuh, CN=wazuh.com`,
autofirmado, con **SAN `DNS:localhost` únicamente** y caducidad el 16 de mayo de
2027.

Como el de MISP y el de Portainer: certificado de fábrica que sobrevivió porque
el servicio funciona. No se encontró ningún consumidor en el repo —ni referencias
al puerto, ni `verify=False`— de modo que hoy no consta que nadie dependa de él.

Merece revisarse antes de mayo de 2027, cuando caduque.

### 4.3 Indexer publicado en `0.0.0.0:9200`

No estaba en el inventario de superficie. Responde `401`: exige credencial.
Anotado por completitud del inventario.

### 4.4 `.env.example` de Fase 1 con valores en todas las variables

Contra el principio establecido en Fase 5 —plantillas con valores vacíos para
forzar asignación explícita—, el `.env.example` de Fase 1 trae valor en las doce
variables, incluidos los tres secretos de Authelia y la contraseña de Mongo. Está
versionado en GitHub.

**Verificado que ninguno sobrevivió al `.env` real:** los cinco valores sensibles
difieren del ejemplo, y los tres de Authelia tienen 64 caracteres, consistente con
secretos generados.

Aquí funcionó. Pero la plantilla sigue invitando a copiar, y el matiz del
reconocimiento de Fase 8 aplica: valores vacíos **y** validación en la carga —
sin la segunda mitad, el vacío sólo aplaza el problema hasta el punto de uso.
Vaciar esos campos es trabajo de cinco minutos.

---

## 5. Observaciones que no son hallazgos pero cuentan

**El inventario de servicios estaba incompleto.** RocketChat, MongoDB, Portainer
y los cinco contenedores de MISP no aparecían en las primeras revisiones porque
un `head -20` sobre `docker ps` los cortaba. Ocho servicios vivos fuera del
inventario, uno de ellos el de mayor impacto de esta revisión. Un listado truncado
es otro instrumento que devuelve algo plausible en lugar de un error.

**Los certificados de fábrica son cuatro, no uno.** Portainer (3 may, sin subject),
Wazuh API (16 may, `CN=wazuh.com`), MISP (24 may, `CN=localhost`) y rttys (28 ago,
la CA raíz como certificado de servidor, corregido en la mejora 2). Ninguno fue
elegido; los cuatro los puso un instalador y los cuatro funcionaban.

**El comentario de `traefik/dynamic/tls.yml` ya describía el problema.** Escrito en
agosto, explica que sin certificado propio Traefik sirve uno de relleno que nadie
puede verificar, «lo que obliga a desactivar la verificación TLS en toda la
cadena». Es exactamente el caso de `glkvm.cer` y del `-x` de rtty, encontrado un
mes después. El conocimiento estaba escrito en el repositorio y no se aplicó donde
hacía falta.

**Piezas a medias, ninguna peligrosa, todas del mismo tipo:** `glkvm-device.crt`
emitido y sin usar; `misp.oob.local` en el certificado comodín sin router que lo
use; `wazuhtransport` declarado en el fichero dinámico y no referenciado por el
router de Wazuh. Configuraciones preparadas para un paso siguiente que no se dio.

---

## 6. Lo que confirma sobre el patrón

`docs/credenciales-de-arranque.md` §3 formulaba el patrón con dos casos. Esta
revisión añade dos más y una variante:

**Confirmación.** Portainer (3 may) y MISP (24 may) son anteriores a la CA del
enclave (24 ago) y a las decisiones de arquitectura que contradicen. Funcionaban.
Ninguna revisión por fases los examinó porque no pertenecen a ninguna fase: se
levantaron para poner el proyecto en marcha.

**Variante nueva.** Portainer no es sólo una credencial vieja: es **superficie**
vieja. El patrón no se limita a claves y certificados — también cubre puertos
publicados, servicios auxiliares y herramientas de gestión levantadas al principio
«para trabajar cómodo». Esas son, además, las que más privilegio suelen tener.

**Corolario práctico.** Al inventario por eje temporal hay que añadir los puertos
publicados y los servicios auxiliares, no sólo los ficheros de credenciales. La
pregunta útil no es sólo «qué claves hay y de cuándo», sino «qué se levantó antes
de que hubiera arquitectura, y sigue ahí».
