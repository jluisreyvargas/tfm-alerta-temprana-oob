# Registro de hallazgos — Fase C del P1-1a, sesión del 2026-09-12

**Estado de partida:** commit `759f77f`, `origin` y `backup` al día tras el push de
esta sesión.
**Método:** todo lo de este documento está medido por comportamiento. Las
secciones 4 y 5 registran lo descartado con el mismo detalle que lo confirmado,
porque un registro que solo guarda los aciertos no demuestra que el método
discrimine.

---

## 1. Lo que esta sesión ha cambiado en el sistema

| Acción | Verificación |
|---|---|
| Fila `w11 misp.oob.local` añadida a `docs/resolucion-nombres.tsv` | `awk`: 5 campos, `diff`: una sola línea |
| `git push backup main` | `git ls-remote backup main` = `git rev-parse HEAD` = `759f77f` |

Pendiente de aplicar: la fila equivalente en la tabla de
`docs/README-resolucion-nombres.md` (línea 97 es la análoga de MinIO) y el
`hosts` del W11. Hasta entonces `verify-hosts.sh --check-doc` devuelve 1 con una
única divergencia, acotada e identificada.

---

## 2. El estado real de MISP: la Fase C estaba hecha

El inventario que se tomó al abrir el hilo era del 10 de septiembre. El trabajo
de MISP se hizo el 11 a las 23:10, en otro hilo. Verificado hoy:

- Router `misp@docker`, `status: enabled`, con `secure-headers@file` y
  `authelia@file`, servicio a `https://172.18.0.10:443`.
- Etiquetas presentes en `.Config.Labels` del contenedor, con
  `scheme=https` y `port=443`.
- Regla de Authelia en `configuration.yml:34`, `two_factor`, `group:ir_lead`.
  También apareció una para `portainer.oob.local`, que el día 10 no existía.
- Los puertos directos ya están restringidos a `127.0.0.1:1280` y
  `127.0.0.1:12443` por el `ports: !override` del propio fichero.

**Lección de método:** se diseñó un plan completo sobre un inventario de dos días
antes. El `302` inesperado en el control negativo fue lo que lo destapó — y solo
porque el criterio incluía un control sobre un nombre inexistente
(`noexiste.oob.local`, que devolvió `404`). Sin ese tercer punto de comparación,
el `302` de `misp.oob.local` se habría leído como el catch-all
`HostRegexp(^.+$)` y el diagnóstico habría sido erróneo en la dirección
tranquilizadora.

---

## 3. Hallazgos vivos

### 3.1 — El override de MISP no está en ningún remoto

**Severidad: P1 (reproducibilidad con pérdida de remediación).**

`misp/misp-docker/docker-compose.override.yml` contiene **la totalidad** de la
Fase C de MISP: las nueve etiquetas de Traefik y el `ports: !override` que
restringe las publicaciones a loopback. Está ignorado por
`misp/misp-docker/.gitignore:11`, el `.gitignore` del upstream de misp-docker,
donde ese patrón existe para que el usuario no suba su configuración local.

En este proyecto el supuesto se invierte: ese fichero no es configuración local,
es la aportación. Un `git clone` en una máquina nueva reconstruye un MISP
publicado en todas las interfaces y sin router, y nada lo señala:
`git status` no lo lista, y el estado desplegado aquí es correcto, así que
cualquier verificación por comportamiento pasa.

**Alcance medido, no supuesto.** Recorridos los cuatro overrides del árbol:

| Fichero | Estado |
|---|---|
| `fase6-iris/docker-compose.override.yml` | versionado |
| `fase8-kvm/glkvm-cloud/docker-compose/docker-compose.override.yml` | versionado |
| `misp/misp-docker/docs/examples/stunnel/redis/...` | ignorado, **correctamente**: es del upstream |
| `misp/misp-docker/docker-compose.override.yml` | **ignorado, incorrectamente** |

Es un caso único con causa identificada, no una clase de artefactos. Los cuatro
árboles vendorizados tienen `.gitignore` propio, pero solo el de MISP oculta un
patrón que el proyecto necesita.

**Remediación, con la convención que el proyecto ya tiene.** En
`fase6-iris/.gitignore` existe el precedente probado —`!.env.example` con su
comentario y su referencia al `NOTICE`—, así que la excepción va en el
`.gitignore` del árbol vendorizado, no en el raíz:

```
# Divergencia respecto a upstream: este override NO es configuracion local del
# usuario, es la aportacion del proyecto. Contiene las etiquetas de Traefik y la
# restriccion de los puertos a loopback del P1-1a Fase C. Sin versionarlo, un
# clone reconstruye MISP publicado en 0.0.0.0 y sin router, sin error visible.
!docker-compose.override.yml
```

Verificar después con `git check-ignore -v` y `git status --short`, no dar por
hecho que la negación funciona.

### 3.2 — `BASE_URL` apunta al puerto directo (criterio V6 en rojo)

**Severidad: P1.**

`misp/misp-docker/.env:64` sigue en `https://misp.oob.local:12443`. Medido en
runtime:

```
curl -H 'Host: misp.oob.local' https://127.0.0.1:12443/
  →  location: https://misp.oob.local:12443/users/login
```

Un navegador que entre por `https://misp.oob.local` pasa Authelia, recibe ese
302 y sale hacia el puerto directo, por fuera del proxy. La pantalla de login
aparece igual y el servicio parece protegido.

**Lo que hoy lo contiene no es `BASE_URL`, es el binding a loopback.** Desde el
W11 ese 302 no llega a ninguna parte, así que el bypass no es alcanzable desde la
red; el analista solo ve la navegación romperse. Desde el propio Ubuntu sí
funciona. El control depende de que nadie retire el `ports: !override`, y ese
fichero es justamente el que no está versionado (3.1).

Remediación: sustituir por `https://misp.oob.local`, con el patrón seguro
(`tmp=$(mktemp); sed ... > "$tmp" && cat "$tmp" > .env && rm "$tmp"`), un `diff`
que muestre exactamente un par de líneas, y recrear `misp-core`. `.env` está
ignorado (`misp/misp-docker/.gitignore:7`), verificado, así que el cambio no
entra al repositorio — contrapartida a anotar: el valor correcto existirá solo en
este host, lo que pide una línea en `template.env`, que sí está versionado.

Registrar el digest antes de recrear:
`sha256:1f3d254c1bd4568833d796b9da88e3b79526df4cd9acfa59b8ba5d0fef725aca`. La
imagen es `:latest`.

### 3.3 — P1-1f: `insecureSkipVerify` global en el borde

**Severidad: P1 (arquitectural).**

`fase1-infraestructura/traefik/traefik.yml:35`:

```yaml
serversTransport:
  insecureSkipVerify: true
```

Sin ámbito. Traefik no verifica el certificado de ningún backend HTTPS. El borde
termina un certificado verificable de cara al cliente y abre un tramo no
autenticado por detrás, para los once routers a la vez. Contradice el argumento
del ancla de confianza del enclave.

Se agrava con `traefik/dynamic/wazuh-transport.yml`, que declara un
`serversTransports.wazuhtransport` con `insecureSkipVerify: true`. **Verificado
que no se aplica a nada:** el servicio `wazuh@docker` no lleva campo
`serversTransport` en la API, y `grep` sobre los composes de las fases 1, 5 y 6
no encuentra ninguna referencia a `wazuhtransport`. Wazuh funciona por el ajuste
global. Existe un control con nombre, acotado a un servicio, que no se aplica a
nada y cuya sola presencia sugiere al lector que la excepción está acotada.

Es el mecanismo del middleware comentado de Wazuh, invertido: allí la intención
se escribió y no se activó; aquí la excepción se escribió acotada y el efecto
real es general. Y es el mismo defecto que el `allowUnauthorizedCerts: true` del
nodo MISP de n8n, un nivel más arriba.

**La dependencia no es teórica en MISP.** Su certificado interno es
`CN=localhost` autofirmado (`Verify return code: 18`), así que un transporte que
verificara de verdad no podría funcionar contra este backend sin reemitirlo.
Cualquier remediación del P1-1f tiene que resolver eso, no solo cambiar el flag.

Orden propuesto: después de la Fase E.

### 3.4 — P1-1g: el analista perdió el acceso al dashboard de Wazuh

**Severidad: P2 (capacidad retirada sin decisión escrita).**

Medido desde el W11:

```
Test-NetConnection 192.168.127.138 -Port 4443
  PingSucceeded    : True
  TcpTestSucceeded : False
Resolve-DnsName wazuh.oob.local  →  sin resultado
```

Y no existe fila `w11 wazuh.oob.local` en `docs/resolucion-nombres.tsv`. El
puesto de analista no tiene ninguna ruta al dashboard.

No es un fallo de la Fase C de Wazuh: cerrar el 4443 hizo lo correcto. El
problema es que antes del cierre el analista llegaba por IP sin necesitar
nombre, así que la decisión de la Fase A —«son superficies de operador, no de
análisis»— resolvía si hacía falta comodidad de nombre, no si el acceso debía
conservarse. El cierre cambió el estado y la decisión no se revisó.

**Variante nueva del patrón del TFM, que merece su propio párrafo en la
memoria.** Aquí no hay ningún control mal escrito ni ninguna intención sin
implementar. Los dos artefactos son correctos por separado y en su momento. El
defecto está en que el segundo no revisó el supuesto del primero. Es la misma
forma que la composición del P0-6 con la exclusión del KVM de Authelia, pero
separada en el tiempo en vez de en el espacio.

Puede seguir siendo correcto que el analista no toque Wazuh. Entonces es una
retirada de capacidad y necesita estar escrita, con la misma lógica que la
excepción del KVM: lo que separa una asimetría deliberada de un olvido es que
esté documentada.

### 3.5 — `DECISION-p0-6-pospuesto.md` describe un estado que ya no existe

**Severidad: P2 (divergencia documental, sin efecto en el sistema).**

El P0-6 **está cerrado**, con verificación por comportamiento completa y
documentada en `docs/cierre-mejora1-hook.md` (commit `a214052`). La condición 1
de la decisión exigía la misma prueba que lo descubrió, y el cierre la registra
invertida: `operador2` sin grupo, `GET /connect/zsb25f8` → `403` donde antes
había `302`.

El cierre va además más allá de lo que la condición 1 pedía, con dos criterios
que no estaban exigidos y que sí discriminan:

- **V3** — `admin` accede por intersección de grupos, no por exención. Es la
  forma en que un hook de autorización se vacía sin fallar: un rol privilegiado
  que salta el modelo en vez de satisfacerlo.
- **V4** — con n8n detenido, `403`. Mide el comportamiento del control cuando su
  propio evaluador no está.

Lo único pendiente es documental: el documento del 9 de septiembre sigue
afirmando que el P0-6 permanece abierto y que la Mejora 1 se abordará después de
la Fase E, sin remitir a su cierre. Remediación: una cabecera de estado en
`DECISION-p0-6-pospuesto.md` que apunte a `cierre-mejora1-hook.md`, conservando
el cuerpo — el valor del documento es justamente haber dejado escrita la decisión
de posponer, y reescribirlo borraría esa trazabilidad.

**Verificado que el `README.md` no lo menciona**, así que la divergencia no se
propaga: aparecía en la búsqueda de referencias cruzadas por el otro término del
patrón, no por el P0-6.

### 3.5.1 — Colisión de identificadores en el P1-6

`docs/cierre-mejora1-hook.md` §7 registra como **P1-6** la rotación pendiente del
`token` del dispositivo GL-RM1, volcado en claro en `/home/rttys.conf` durante la
construcción del hook. El hilo del P1-1a arrastra como **P1-6** la corrección de
`server_urls` en las plantillas de Velociraptor.

Dos hallazgos distintos con el mismo identificador, en documentos distintos.
Cerrar uno haría parecer cerrado el otro. Hay que renumerar uno de los dos antes
de que eso ocurra.

### 3.5.2 — El webhook del hook falla abierto ante error interno

Registrado en `docs/cierre-mejora1-hook.md` §3; no se reproduce aquí. Se anota en
este registro **por su forma**, porque pertenece a la misma familia que el resto
de instancias de la tesis: un control de autorización cuyo denegar-por-defecto se
convierte en permitir cuando el evaluador falla por dentro. Falla cerrado ante
error de red y ante no-200, y abierto ante excepción propia del orquestador.

Los demás pendientes del cierre (paginación de `/api/devices`, C5 sobre la cookie
de Authelia en el bridge, guardado de ejecuciones con la cookie del operador, y
la higiene de sesiones y ficheros temporales) viven en ese documento y no se
duplican aquí. Dos con efecto mientras estén abiertos:

- El flujo auxiliar `echo` de n8n devuelve las cabeceras que recibe, sin
  autenticación, dentro de `oob-network`. Cualquier contenedor de esa red puede
  recuperar la cookie de SSO de quien pase por ahí.
- El `token` del dispositivo volcado en claro (3.5.1) es material de
  autenticación del GL-RM1, no un valor de prueba.

### 3.6 — Menores del `.gitignore` raíz

- El bloque `scripts/hosts-*.txt` está **duplicado literalmente**, comentario
  incluido. Sin efecto funcional; señal de dos ediciones no revisadas.
- `*.msi` es un patrón global escrito para la fase 5. Verificado que el único MSI
  del árbol lo cubre ya la regla de directorio de la línea 77, así que es
  redundante, no peligroso. Mismo patrón que el `serversTransport` global frente
  a `wazuhtransport`, en pequeño y sin consecuencia.
- `fase1-infraestructura/wazuh/.gitignore` no termina en salto de línea. Es donde
  un `>>` futuro corrompería el último patrón.

---

## 4. Descartado por medición en esta sesión

Sospechas propias que los datos no sostienen. Se dejan escritas con su causa.

**El compose del KVM no está sin versionar: no existe en esa ruta.** Se buscó
`fase8-kvm/glkvm-cloud/docker-compose.yml` y `git ls-files` no lo encontró. La
conclusión «está fuera del repositorio» era errónea porque la ausencia en el
índice tiene dos causas —fichero no versionado, o fichero inexistente— que el
comando no distinguía. `ls` devolvió `No such file or directory` y
`git check-ignore` devolvió 1 (no ignorado). El compose real vive en
`fase8-kvm/glkvm-cloud/docker-compose/` y está versionado, override incluido.

**Los `.env.pre-*` de IRIS no son un hueco del control.** Los cuatro ficheros
(`.env.model`, `.env.pre-limpieza`, `.env.pre-p0-2`, `.env.pre-p0-e`) están
ignorados por una regla del `.gitignore` raíz escrita a propósito, con comentario
y con el mecanismo anticipado: «La regla `**/.env` no las cubre por el sufijo».
La exclusión es deliberada y correcta. Lo único que queda es higiene del host:
borrarlas cuando no sirvan. No están en ningún remoto.

**`rc=2` de `verify-no-secrets.sh` era un error de uso, no del script.** No
acepta rutas: solo `--staged`, `--selftest`, `--help` o nada. La línea 129
rechaza cualquier otro argumento con un mensaje explícito a stderr, que el
`2>&1 >/dev/null` de la invocación se comió. El script distingue 0, 1 y 2 a
propósito y documenta los tres en su cabecera. Está mejor construido que la
invocación que lo cuestionó.

**El MSI de Velociraptor está correcto.** `grep -a -o` sobre
`Org__root__velociraptor-v0.76.6-windows-amd64.msi` devuelve una única URL:
`https://velociraptor.local:8001/`. Apunta al frontend de agentes, no a la GUI.
La sospecha de que el artefacto de reinscripción llevara el `:8889` embebido
—que habría hecho insuficiente corregir solo las plantillas `.yaml`— queda
descartada.

**El `.p1-1-pendiente` de IRIS no es trabajo a medias.** Sus 4 líneas están
íntegramente contenidas en el `docker-compose.override.yml` activo
(`grep -F -x -c -v`: 0 líneas ausentes). Es un duplicado, no una alternativa: se
retira con `git rm`, no hay decisión que tomar. Y el
`${INTERFACE_HTTPS_PORT:-443}` que parecía un valor por defecto peligroso
resuelve a `4833`, declarado en `fase6-iris/.env:44`.

**El backend HTTP de MISP no es viable, y se probó en las dos mitades.** Se
midió el puerto 80 con `X-Forwarded-Proto: https` más `X-Forwarded-Port: 443`
(control positivo) y sin cabeceras (control negativo, con el estado de partida ya
conocido: 301). Ambos devuelven `301 → https://misp.oob.local/`. La redirección
no depende de la cabecera, así que apuntar Traefik al 80 produciría un bucle. Es
lo que obliga al `scheme=https` y, con ello, la dependencia del 3.3.

---

## 5. El P1-6 de Velociraptor, con el alcance ya reducido

Se mantiene como bloqueante antes de cerrar el 8889, pero es más pequeño de lo
que decía el documento de traspaso.

**La configuración realmente montada** es
`fase5-velociraptor/velociraptor-config/server.config.yaml`, con `server_urls`
correcto a `:8001` y `public_url:
https://velociraptor.local:8889/app/index.html`, que hay que corregir a
`https://velociraptor.oob.local/app/index.html` o Velociraptor generará enlaces a
un puerto cerrado. El otro `server.config.yaml`
(`fase5-velociraptor/velociraptor/`) no lo monta ningún volumen del compose y
está ignorado por el `.gitignore` raíz como directorio huérfano.

**Los dos ficheros a corregir** son
`fase5-velociraptor/client.config.yaml:11` y
`config-templates/client.config.template.yaml:17`, ambos con
`https://velociraptor.local:8889/`. El MSI no entra (sección 4).

Menor: `fase5-velociraptor/docker-compose.yml` tiene modo `rwxrw-rw-`, escribible
por cualquier usuario local, y es el fichero que define los bindings que la Fase
D va a cerrar.

---

## 6. Orden de remediación propuesto

1. **Versionar el override de MISP** (3.1). Va primero porque hasta que el
   fichero esté en un remoto, cualquier percance en este host borra la Fase C
   entera de MISP.
2. **`BASE_URL`** (3.2), con V6 como criterio de cierre y V7/V8 revalidados
   después.
3. **Fila del README y `hosts` del W11**, para poder hacer V7 desde el navegador.
4. `git rm fase6-iris/docker-compose.override.yml.p1-1-pendiente`.
5. **Cabecera de estado en `DECISION-p0-6-pospuesto.md`** remitiendo a
   `cierre-mejora1-hook.md` (3.5), y **renumerar uno de los dos P1-6** (3.5.1).
6. Continuar la Fase C: Velociraptor GUI (con el P1-6 antes), luego IRIS, y el
   dashboard de Traefik al final.
7. **P1-1f** (3.3) y **P1-1g** (3.4) después de la Fase E.

---

## 7. Aportación al TFM

Esta sesión añade dos instancias y una del método.

**El artefacto que documenta la remediación y el que la implementa son el mismo
fichero, y solo existe en un disco.** El override de MISP es la versión más
completa del patrón hasta ahora: no es que el control esté mal escrito, es que
está bien escrito y fuera del alcance de todo lo que el proyecto usa para
comprobar que existe. `git status` no lo ve porque está ignorado; la verificación
por comportamiento no lo ve porque el estado desplegado es correcto;
`verify-no-secrets.sh` no lo ve porque recorre ficheros trackeados. Tres
controles independientes, todos en verde, y el trabajo desaparece con el host.

**Una decisión correcta que dejó de serlo por un cambio en otro sitio** (3.4). Las
instancias anteriores del patrón eran sincrónicas: una intención escrita y no
activada, un `except` ciego, un control sin cliente. Esta es diacrónica. Los dos
artefactos son correctos por separado y el defecto nace de la secuencia. Sugiere
que el inventario de decisiones necesita, como el de credenciales, un segundo eje
—no solo qué se decidió, sino bajo qué supuesto— porque es el supuesto lo que
caduca.

**El control negativo de tres puntos.** El diagnóstico de esta sesión se salvó
por incluir un nombre que con seguridad no tenía router. Con dos puntos
(`misp` y `minio`, ambos `302`) la conclusión habría sido «el catch-all responde
a todo» y el plan habría seguido adelante sobre un servicio ya configurado. El
tercer punto convirtió una coincidencia en una discriminación. Generalizable: un
control negativo que no incluye un caso donde el mecanismo sospechado **no**
puede actuar no distingue entre la hipótesis y su alternativa.
