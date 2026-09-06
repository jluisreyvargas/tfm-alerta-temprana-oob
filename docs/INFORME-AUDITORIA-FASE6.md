# Informe de auditoría de seguridad — Fase 6 (DFIR-IRIS)

| Campo | Valor |
|---|---|
| Fase | 6 — Gestión de casos con DFIR-IRIS v2.4.27 |
| Fecha de auditoría | 3 de septiembre de 2026 |
| Remediación aplicada | 3–6 de septiembre de 2026 |
| Alcance | `fase6-iris/`, `docs/README-Fase6a.md`, `docs/README-Fase6b.md`, integración declarada en Fases 2/3/5 |
| Auditorías previas | Ninguna. P0-2 (2026-09-02) fue una remediación puntual de certificado |
| Revisión | v6 — cierre de la fase. Todos los P0 y todos los P1 resueltos, aceptados o documentados |

---

## Resumen ejecutivo

La auditoría identificó **cinco hallazgos P0**, **once P1** y **cuatro P2**.

El de mayor gravedad (P0-E) permitía obtener una sesión administrativa en
DFIR-IRIS sin credenciales, sin fuerza bruta y sin interactuar con el formulario
de autenticación, mediante falsificación de la cookie de sesión de Flask. La
clave de firma era una constante literal publicada en el repositorio de
DFIR-IRIS. El servicio estaba publicado en todas las interfaces del anfitrión sin
proxy inverso ni MFA (P0-D), por lo que la cadena era alcanzable desde la red
corporativa `192.168.127.0/24`.

Implicación sobre la tesis: el sistema que custodia la alerta original, el
razonamiento del agente de triaje, las evidencias forenses y la línea temporal
del incidente era tomable desde exactamente la red respecto de la cual el enclave
debe permanecer independiente.

**Estado de cierre.** Los cinco P0 quedan corregidos. De los once P1: ocho
corregidos y verificados, uno aceptado como riesgo documentado, dos abiertos como
mejoras no bloqueantes. De los cuatro P2, tres corregidos.

Dos resultados metodológicos:

- **La verificación produjo más hallazgos que la búsqueda.** Seis de los once P1
  se detectaron al comprobar que una remediación funcionaba, no al buscar
  defectos.
- **Una corrección verificada resultó no serlo.** El healthcheck propuesto para
  P1-11 se validó con `docker compose up` y no resolvía el arranque en frío. Solo
  la prueba de reinicio del anfitrión lo reveló, y obligó a un diagnóstico y una
  corrección distintos.

La propia auditoría incurrió en ocho errores de inferencia, todos del mismo tipo
y todos detectados por verificación posterior. Se documentan en la sección de
memoria por su valor argumental.

---

## Método

Bloques de verificación de solo lectura sobre el sistema en producción, seguidos
de bloques de remediación con verificación posterior, aplicando el principio de
**verificar comportamiento observable, no ficheros de configuración**.

Fuentes de contraste: estado de git, sistema de ficheros del anfitrión, estado
interno del contenedor, respuesta del servicio en runtime, estado de la base de
datos, código fuente vendorizado cuando determina el comportamiento efectivo, y
—para P1-11— reinicio real del anfitrión.

Todas las comprobaciones quedaron consolidadas en `scripts/verify-fase6.sh`, con
tres detecciones acreditadas mediante prueba negativa.

---

## Cuadro de hallazgos

| ID | Hallazgo | Sev. | Estado |
|---|---|---|---|
| P0-A | El README declara seis capacidades automatizadas inexistentes | P0 | **Corregido** |
| P0-B | El `docker-compose.yml` documentado no corresponde al desplegado | P0 | **Corregido** |
| P0-C | Ancla de confianza = CA demo pública, sobre inodo huérfano | P0 | **Corregido** |
| P0-D | Servicio publicado en `0.0.0.0:4833` sin proxy ni MFA | P0 | **Corregido** |
| P0-E | `SECRET_KEY` pública → forja de sesión administrativa | P0 | **Corregido** |
| P1-1 | Código vendorizado sin NOTICE de licencia LGPL-3.0 | P1 | **Corregido** |
| P1-2 | Fase no reproducible desde el repositorio | P1 | **Corregido** |
| P1-3 | `rabbitmq:3-management-alpine` con etiqueta flotante | P1 | **Corregido** |
| P1-4 | API key documentada sin consumidor | P1 | Abierto |
| P1-5 | Imprecisiones en `SECURITY-NOTICE.md` | P1 | **Corregido** |
| P1-6 | La CA del enclave fuera de los almacenes de confianza | P1 | **Corregido** |
| P1-7 | La aplicación se ejecuta como `root` en el contenedor | P1 | **Riesgo aceptado** |
| P1-8 | `SECURITY_PASSWORD_SALT` declarada y no consumida | P1 | Documentado |
| P1-9 | `MFA_ENABLED` inerte en despliegues ya inicializados | P1 | **Corregido** |
| P1-10 | Cuenta administrativa única, sin acceso de emergencia | P1 | **Corregido** |
| P1-11 | La pila no converge a estado operativo tras reinicio | P1 | **Corregido** |
| P2-1 | `README.md` con modo `100755` | P2 | **Corregido** |
| P2-2 | `SERVER_NAME` duplicado en `.env` | P2 | **Corregido** |
| P2-3 | `.gitignore` excluía las anclas de confianza públicas | P2 | **Corregido** |
| P2-4 | `IRIS_ADM_PASSWORD` persiste en `.env` | P2 | **Corregido** |
| — | Clave privada de CA demo en la historia de git | — | **Descartado** |
| — | API key real en documentación pública | — | **Descartado** |

Abiertos al cierre: **P1-4** (la API key no tendrá consumidor hasta que se
implemente la automatización, que es trabajo futuro declarado) y **P1-8**
(documentado; la variable pertenece al código vendorizado y no procede
eliminarla).

---

# Hallazgos P0

## P0-E · Clave de firma de sesión pública

**Severidad:** P0 crítica. **Estado: corregido y verificado.**

### Condición

`IRIS_SECRET_KEY` e `IRIS_SECURITY_PASSWORD_SALT` contenían los valores
literales de `.env.model`, plantilla publicada en el repositorio de DFIR-IRIS y
presente también en este repositorio:

```
IRIS_SECRET_KEY=AVerySuperSecretKey-SoNotThisOne
IRIS_SECURITY_PASSWORD_SALT=ARandomSalt-NotThisOneEither
```

Sin rotar desde el despliegue (26 de junio de 2026). La remediación P0-2 del 2 de
septiembre no los alteró.

### Evidencia en runtime

Cookie de sesión firmada de Flask, formato `payload.timestamp.firma`:

```
Set-Cookie: session=eyJjc3JmX3Rva2VuIjoiN2I3ZGNkOWEwNjMzOWUyMmZhMzVkNTZmZjBiM2RmZjI0ZDU4ZDc4YiJ9.apnH4w.KyMYJhpsUWh3Vh1bixB5nczytbI; Secure; HttpOnly; Path=/; SameSite=Lax
```

Vínculo entre variable y clave de firma (`configuration.py`):

```
117:  'IRIS_SECRET_KEY': 'SECRET_KEY',
281:  SECRET_KEY = config.load('IRIS', 'SECRET_KEY')
```

### Cadena de explotación

| Eslabón | Prueba |
|---|---|
| Servicio alcanzable desde la red corporativa | `0.0.0.0:4833`, sin proxy ni MFA (P0-D) |
| La sesión se firma con `SECRET_KEY` | `Set-Cookie` en formato Flask con firma HMAC |
| `SECRET_KEY` procede de `IRIS_SECRET_KEY` | `configuration.py:281` |
| `IRIS_SECRET_KEY` es una constante pública | comparación con `.env.model` |

`Secure`, `HttpOnly` y `SameSite=Lax` no mitigan este vector: impiden el robo de
la cookie, no su fabricación externa.

### Remediación aplicada

**3 de septiembre.** `IRIS_SECRET_KEY` rotada con `openssl rand -base64 48`
(`len=64`). Verificación por comportamiento — la firma de la cookie cambia:

```
antes:  ...apnH4w.KyMYJhpsUWh3Vh1bixB5nczytbI
ahora:  ...apnOlQ.4GkdXNEgS5jlh-Gr-9FdQ5DS7hI
```

**4 de septiembre.** `IRIS_SECURITY_PASSWORD_SALT` rotada (`len=44`), precedida
de volcado completo de la base de datos.

**Verificación de cierre:** acceso desde el navegador del W11 con las
credenciales previas a la rotación, correcto.

**Control permanente:** `verify-fase6.sh` compara ambas variables contra
`.env.model` en cada ejecución. Acreditado con prueba negativa: al restituir la
constante pública, el script devuelve `FALLO IRIS_SECRET_KEY es la constante
publica de upstream` y código 1.

### Corrección de una afirmación de la versión v1

> [!IMPORTANT]
> La v1 atribuía al salt público la pérdida de protección de los hashes frente a
> tablas precomputadas. **La afirmación era incorrecta.**
>
> `SECURITY_PASSWORD_SALT` se carga en configuración y no se consume en ningún
> punto. El hashing es flask-bcrypt, que genera salt aleatorio por contraseña e
> incrustado en el hash. Confirmado sobre la base de datos: prefijo `$2b$`.
>
> La gravedad de P0-E residía enteramente en `IRIS_SECRET_KEY`. Ver P1-8.

---

## P0-C · Ancla de confianza sobre inodo huérfano

**Severidad:** P0. **Estado: corregido y verificado.**

### Condición

P0-2 sustituyó el certificado que nginx **presenta** y retiró del árbol el
material de desarrollo. No sustituyó el que la aplicación **declara confiar**.

```
$ ls -la fase6-iris/certificates/rootCA/
ls: cannot access 'fase6-iris/certificates/rootCA/': No such file or directory
```

### Evidencia en runtime

```
$ docker exec iriswebapp_app ls -li /etc/irisRootCACert.pem
7544864 -rw-rw-r-- 0 1000 1000 1976 Sep  2 15:14 /etc/irisRootCACert.pem
```

**`nlink = 0`**: el inodo no tenía ninguna entrada de directorio. El fichero fue
eliminado del anfitrión y sobrevivía solo porque el espacio de nombres de montaje
del contenedor lo mantenía abierto.

Certificado extraído — CA de desarrollo de DFIR-IRIS:

```
subject=C = FR, ST = Some-State, O = DFIR-IRIS, CN = DFIR-IRIS-Root-CA
sha256 Fingerprint=12:74:5C:EF:8E:36:96:14:76:6A:4D:14:D8:8F:A7:96:D6:65:F6:37:90:6D:99:B3:C1:49:A8:06:40:63:70:A2
```

Coincide con la huella que `SECURITY-NOTICE.md` documenta como material retirado.

### Cronología

| Hora local (2026-09-02) | Evento |
|---|---|
| 15:14 | mtime de `irisRootCACert.pem` |
| 18:54 | arranque del contenedor con el montaje |
| 18:59 | mtime de `certificates/` — eliminación de `rootCA/` del anfitrión |

### El mismo fallo, ya consumado

```
drwxr-xr-x 1 root root 0 Jun 26 16:07 /iriswebapp/certificates/ldap/
```

`root:root`, tamaño 0, fechado el día del despliegue. Docker no encontró el
origen y creó el directorio vacío, en silencio.

### Remediación y verificación

```bash
mkdir -p fase6-iris/certificates/rootCA fase6-iris/certificates/ldap
cp fase1-infraestructura/traefik/certs/oob-rootCA.crt \
   fase6-iris/certificates/rootCA/irisRootCACert.pem
docker compose up -d --force-recreate app worker nginx
```

```
$ docker exec iriswebapp_app openssl x509 -in /etc/irisRootCACert.pem \
    -noout -subject -fingerprint -sha256
subject=C=ES, O=TFM Enclave OOB, OU=Seguridad, CN=OOB Enclave Root CA
sha256 Fingerprint=AB:11:4F:F8:A6:08:F2:9F:FB:C5:59:5F:54:B3:AC:6C:4E:65:4D:FB:C4:9B:0F:0E:68:21:28:14:19:EC:82:5C

$ docker exec iriswebapp_app ls -li /etc/irisRootCACert.pem
7957908 -r--r--r-- 1 1000 1000 1992 Sep  3 19:33 /etc/irisRootCACert.pem

$ docker exec iriswebapp_app openssl verify -CAfile /etc/irisRootCACert.pem \
    /home/iris/certificates/web_certificates/iris_oob_cert.pem
/home/iris/certificates/web_certificates/iris_oob_cert.pem: OK
```

Inodo nuevo con `nlink = 1`, ancla del enclave, y validación funcional. La
verificación acredita que el ancla **se usa con éxito**, no solo que está
presente.

### Observación sobre la propagación de montajes

El `chown` de `certificates/ldap/` se reflejó en el contenedor en marcha; el `cp`
del certificado no. Un bind mount vincula inodos, no rutas: sustituir un fichero
crea un inodo distinto que el montaje existente no observa.

---

## P0-D · Publicación sin restricción de interfaz ni MFA

**Severidad:** P0. **Estado: corregido.** Habilitante de P0-E.

### Condición

```
LISTEN 0 4096  0.0.0.0:4833  0.0.0.0:*
LISTEN 0 4096     [::]:4833     [::]:*
```

IPv4 e IPv6, todas las interfaces, sin Traefik ni Authelia. Tercer servicio del
proyecto con este patrón, junto a Velociraptor (Fase 5) y OpenSearch Dashboards
(Fase 7).

### Remediación aplicada

`fase6-iris/docker-compose.override.yml`:

```yaml
services:
  nginx:
    ports: !override
      - "100.64.0.1:${INTERFACE_HTTPS_PORT:-443}:${INTERFACE_HTTPS_PORT:-443}"
```

`!override` sustituye la lista heredada, eliminando también el enlace IPv6.

```
$ ss -tlnp | grep 4833
LISTEN 0 4096  100.64.0.1:4833  0.0.0.0:*
```

MFA obligatorio activado el 4 de septiembre (P1-9): aislamiento de red más
segundo factor.

### Incidente de reversión silenciosa

Durante la remediación de P1-6, la ejecución de
`docker compose -f fase6-iris/docker-compose.yml up -d --force-recreate` desde el
directorio raíz **revirtió esta corrección sin emitir aviso**.

Compose carga `docker-compose.override.yml` automáticamente solo cuando descubre
los ficheros por sí mismo. Con `-f` explícito, el override queda fuera salvo que
se enumere. El servicio se recreó con la configuración de `base.yml`, volviendo a
`0.0.0.0:4833`.

Detectado porque `ss -tlnp | grep 4833` formaba parte del guion de verificación,
no porque el sistema informara.

**Controles derivados:** todas las operaciones de compose se ejecutan desde
`fase6-iris/`; `docker compose config` es la verificación previa; y
`verify-fase6.sh` comprueba la exposición en cada ejecución.

---

## P0-A y P0-B · Documentación que no corresponde al despliegue

**Estado: corregidos.**

`fase6-iris/README.md` declaraba seis capacidades automatizadas —creación de
caso, webhooks bidireccionales, evidencias, línea temporal, cierre con
revocación— de las que ninguna existe:

```
$ grep -rn --include='*.json' --include='*.py' -iE 'iris\.oob|iriswebapp|/api/case|iris_api' \
    fase2-orquestador/ fase3-agentic/ fase5-orchestrator-api/
(sin salida)
```

Las únicas apariciones de «iris» en los flujos de n8n son literales de texto en
un nodo `IRIS Reference`, sin llamada HTTP. El propio payload declara
`"iris_status": "manual_case_created"`.

El bloque de configuración describía además un compose ficticio
(`iris/webapp:latest`, servicio `iris-api:8080` inexistente,
`POSTGRES_PASSWORD=iris_pass` en claro) y un comando de validación contra un
endpoint del orquestador que no existe.

Tres documentos eran coherentes y honestos —`README-Fase6a.md`,
`README-Fase6b.md` y `SECURITY-NOTICE.md`, que afirma explícitamente que ningún
componente consume IRIS por API—; solo el README de la fase contradecía la
realidad.

**Corrección:** README reescrito con el estado dividido en «implementado y
validado» / «no implementado», el compose real, sin credenciales, y la
automatización trasladada a trabajo futuro con los pasos concretos. La validación
manual se presenta como el resultado que es: viabilidad demostrada.

---

# Hallazgos P1

## P1-11 · La pila no converge a estado operativo tras reinicio del anfitrión

**Estado: corregido y verificado con prueba de reinicio.** Detectado el 5 de
septiembre en la verificación previa al commit.

### Condición inicial

Tras un reinicio del anfitrión, `iriswebapp_nginx` quedó en bucle de reinicio
indefinido:

```
$ docker ps -a --filter name=iriswebapp
iriswebapp_nginx      Restarting (1) 27 seconds ago
iriswebapp_app        Up 43 minutes
...

$ docker logs --tail=2 iriswebapp_nginx
2026/09/05 21:16:01 [emerg] 1#1: host not found in upstream "app" in /etc/nginx/nginx.conf:146
2026/09/05 21:16:02 [emerg] 1#1: host not found in upstream "app" in /etc/nginx/nginx.conf:146
```

El diagnóstico decisivo fue la composición de la red, no los logs:

```
$ docker network inspect iris_frontend --format '{{range .Containers}}{{.Name}} {{end}}'
iriswebapp_rabbitmq iriswebapp_app
```

`nginx` ausente de una red que el compose sí le asigna. El renderizado con
`docker compose config` confirma que la configuración es correcta: el defecto
está en la reincorporación tras el reinicio.

### Primera corrección — verificada y refutada

Se añadió un `healthcheck` a `app` y `depends_on: condition: service_healthy` en
`nginx`, razonando que el fallo era de orden de arranque.

Verificado con `docker compose up`: `app` alcanzó `Healthy` en 33,5 s y Compose
esperó a ese estado antes de arrancar `nginx`. La corrección funcionaba **en ese
escenario**.

La prueba de reinicio del anfitrión la refutó:

```
$ ./scripts/verify-fase6.sh
  FALLO iriswebapp_nginx: exited
  FALLO iriswebapp_nginx NO esta en iris_frontend
  FALLO no escucha en 100.64.0.1:4833
RESULTADO: FALLO
```

**Causa del error de razonamiento:** `depends_on` es una construcción de Compose,
no del demonio Docker. Al reiniciar el anfitrión, es el demonio quien restaura
los contenedores según su política `restart:`, y en ese camino `depends_on` —y
con él `service_healthy`— se ignora por completo.

El healthcheck es correcto y útil para `compose up`, pero nunca podía resolver el
arranque en frío.

### Diagnóstico definitivo

La secuencia real del arranque en frío:

| Hora | Evento |
|---|---|
| ~11:00 | Docker restaura nginx; sirve correctamente, healthcheck en `302` |
| 11:01:28 | Muere con `exit=128` al procesar el SIGTERM del apagado anterior |
| 11:00–11:16 | nginx `exited`, fuera de `iris_frontend`. Servicio caído |
| 11:16 | `docker compose up -d` lo **arranca sin recrear** → endpoint de red obsoleto → bucle |

Dos conclusiones. Primera: `restart: always` no converge, porque reintenta un
contenedor cuya adjunción de red ya no existe. Segunda: `up` sobre un contenedor
`exited` lo arranca pero no lo recrea, de modo que tampoco restituye la red — hace
falta `--force-recreate`.

El mensaje `unlink() "/var/run/nginx.pid" failed (13: Permission denied)` que
aparecía en los logs es cosmético: `/var/run` es propiedad de root y www-data no
puede borrar el PID al terminar. No guarda relación con el fallo.

### Corrección aplicada

Unidad systemd `fase6-iris/systemd/tfm-fase6-iris.service`:

```ini
[Unit]
Requires=docker.service
After=docker.service tailscaled.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/jose/tfm-alerta-temprana-oob/fase6-iris
ExecStart=/usr/bin/docker compose down --remove-orphans
ExecStart=/usr/bin/docker compose up -d --wait --wait-timeout 180
ExecStop=/usr/bin/docker compose down
```

`down` antes de `up` elimina los contenedores con endpoints obsoletos en lugar de
reintentar sobre ellos; los datos residen en volúmenes con nombre y no se ven
afectados. `--wait` hace que systemd espere a los healthchecks, de modo que el
estado de la unidad refleja el estado real del servicio. `After=tailscaled` cubre
la dependencia del enlace a `100.64.0.1`.

### Verificación por prueba de reinicio

```
$ systemctl is-active tfm-fase6-iris.service
active
$ systemctl show tfm-fase6-iris.service -p ExecMainStatus
ExecMainStatus=0
$ ./scripts/verify-fase6.sh; echo "exit=$?"
[16 comprobaciones OK]
RESULTADO: OK
exit=0
```

Sin intervención manual. La prueba de reinicio queda establecida como **criterio
de aceptación de la fase**, a repetir tras cualquier cambio en el compose, el
override o la unidad.

## P1-9 · `MFA_ENABLED` inerte en despliegues ya inicializados

**Estado: corregido.**

`MFA_ENABLED` tiene un único consumidor:

```
post_init.py:1665:  ..., enforce_mfa=app.config.get("MFA_ENABLED", False))
```

dentro de `create_safe_server_settings()`, bajo la guarda
`if not ServerSettings.query.count()`. En un despliegue ya inicializado
**definir `IRIS_MFA_ENABLED=True` no tiene efecto alguno**.

El login lee otra fuente: `login_routes.py:268` consulta
`app.config['SERVER_SETTINGS']['enforce_mfa']`, columna de `server_settings`
poblada una sola vez.

### Agravante: el registro de arranque induce a error

```
configuration.py:489:  log.info(f'MFA {"enabled" if MFA_ENABLED else "disabled"}')
```

Refleja la variable de entorno, no el estado efectivo. Con `IRIS_MFA_ENABLED=True`
sobre una base de datos existente, el sistema registraría `MFA enabled` mientras
el login no exige segundo factor.

Es la forma más engañosa del patrón: un control que **informa activamente de estar
activo cuando no lo está**. Un criterio de verificación basado en ese registro
habría producido un falso positivo, y ese criterio llegó a proponerse durante la
auditoría antes de ser descartado.

### Remediación aplicada

Vía correcta: casilla `enforce_mfa` en **Advanced → Server settings**, que
actualiza la base de datos y refresca `app.config`
(`manage_srv_settings_routes.py:141`). Se prefiere al `UPDATE` directo por dejar
rastro en el registro de auditoría de IRIS.

Secuencia, con la cuenta de emergencia creada primero (P1-10): volcado de la base
de datos verificado con `grep 'breakglass'` sobre el fichero → activación →
enrolamiento TOTP de `breakglass` primero, la cuenta prescindible → enrolamiento
de `administrator`.

```
$ psql -tAc 'SELECT "user", mfa_setup_complete FROM "user";'
administrator|t
breakglass|t
```

`verify-fase6.sh` consulta la base de datos, no el registro de arranque.
Acreditado con prueba negativa.

## P1-6 · La CA del enclave fuera de los almacenes de confianza

**Estado: corregido y verificado.** Detectado al verificar P0-C.

`docker-compose.base.yml` monta `irisRootCACert.pem` en `/etc/irisRootCACert.pem`
y **ningún componente lo consume**:

| Vía | Estado inicial |
|---|---|
| `/etc/ssl/certs/ca-certificates.crt` | Sin la CA del enclave (150 CAs públicas) |
| `/usr/local/share/ca-certificates/` | Vacío |
| `certifi` | Bundle público (136 CAs), sin la CA |
| `REQUESTS_CA_BUNDLE`, `SSL_CERT_FILE`, `CURL_CA_BUNDLE` | No definidas |
| `Dockerfile`, `configuration.py`, `iris-entrypoint.sh` | Sin referencia al fichero |

Los clientes TLS de la aplicación no confiaban en la PKI del enclave para tráfico
saliente, con el riesgo de que se resolviera deshabilitando la verificación —
reproduciendo el `insecureSkipVerify` de la Fase 7.

Se descartó montar en `/usr/local/share/ca-certificates/`: aunque
`update-ca-certificates` existe en la imagen, el entrypoint no lo ejecuta, y una
corrección que dependa de un paso manual tras cada recreación es el mismo patrón
de fallo silencioso que documenta esta fase.

Bundle concatenado construido en el anfitrión, versionable y auditable, montado y
declarado en el override para `app` y `worker`. Se concatena sobre el bundle
público en lugar de sustituirlo: apuntar solo a la CA del enclave rompería la
verificación de destinos externos.

```
$ docker exec iriswebapp_app python3 -c "
import ssl; print('CAs cargadas:', len(ssl.create_default_context().get_ca_certs()))"
CAs cargadas: 151
```

Prueba funcional con petición HTTPS real:

```
requests.exceptions.SSLError: ... CertificateError("hostname 'nginx' doesn't match
either of 'iris.oob.local', 'iris.local', 'localhost', '127.0.0.1', '192.168.127.138')
```

El error de coincidencia de nombre **es el resultado positivo**: la cadena validó
contra el bundle. Un fallo de confianza habría producido
`CERTIFICATE_VERIFY_FAILED`.

## P1-10 · Cuenta administrativa única

**Estado: corregido.**

`administrator` era la única cuenta. La pérdida de su credencial, o un
enrolamiento de MFA fallido, habrían dejado el servicio inaccesible.

Creada `breakglass` con rol administrativo y credencial custodiada por separado,
**antes** de activar MFA: `modal_add_user.html:145` modifica el formulario de
alta cuando `enforce_mfa` está activo.

Riesgo residual: ambas cuentas exigen TOTP. Procedimiento de recuperación en el
README y en el Anexo C.

## P1-7 · La aplicación se ejecuta como root · RIESGO ACEPTADO

```
$ docker exec iriswebapp_app ps -eo user,uid,comm
root  0  iris-entrypoint
root  0  gunicorn
```

La imagen de DFIR-IRIS v2.4.27 no contempla ejecución sin privilegios: el
Dockerfile no declara `USER`, no crea usuario y no ajusta propiedad; el entrypoint
no crea directorios ni permisos; los volúmenes `downloads`, `user_templates` y
`server_data`, más `/iriswebapp`, son `root:root`.

Corregirlo exigiría `chown` de los tres volúmenes, entrada en `/etc/passwd` para
el uid, y verificación de que ninguna dependencia llama a `pwd.getpwuid()`. Eso
supone bifurcar la imagen vendorizada. Una corrección parcial rompería la
escritura en esos volúmenes con fallo diferido y silencioso —al exportar un caso,
no al arrancar.

**Controles compensatorios:** aislamiento de red al tailnet, MFA obligatorio, sin
claves públicas en uso, contenedor no privilegiado y sin socket de Docker
montado.

Se documenta junto a los demás riesgos aceptados del proyecto
(`insecureSkipVerify` global en Traefik, Portainer en 9443).

## P1-8 · `SECURITY_PASSWORD_SALT` declarada y no consumida

**Estado: documentado.**

Se carga en configuración y ningún componente la utiliza. El hashing es
flask-bcrypt con salt aleatorio por contraseña incrustado en el hash (`$2b$`).

Control declarado, presente en `.env`, cargado en tiempo de ejecución y sin
efecto. Indujo el error de inferencia de la v1 de este informe.

No procede eliminarla: la carga pertenece al código vendorizado. Documentado en
el README y en `.env.example` para que futuras auditorías no le atribuyan
garantías inexistentes.

## P1-1, P1-2, P1-3, P1-5 · Corregidos

**P1-1 · Licencia.** `LICENSE.txt` ya existía en el directorio. Se añade `NOTICE`
con la atribución LGPL-3.0, el inventario de ficheros propios del TFM y la
divergencia respecto a upstream, más `.gitattributes` marcando `source/`,
`docker/` y `tests/` como `linguist-vendored`.

**P1-2 · Reproducibilidad.** `.env.example` con las variables de credencial
**vacías**, no con placeholders — la lección de P0-3 en la Fase 5: un valor por
defecto documentado acaba siendo el valor en uso. Requirió una negación
`!.env.example` en `fase6-iris/.gitignore`, único fichero que gobierna ese
directorio: la regla `.env*` heredada de upstream lo excluía, y una negación desde
el `.gitignore` raíz no surte efecto sobre ficheros bajo un `.gitignore` anidado.
Se versionan también el override, la unidad systemd y `verify-fase6.sh`. El flujo
de n8n vigente ya estaba versionado.

**P1-3 · Etiqueta flotante.** `rabbitmq` fijado a `3.13.7-management-alpine`,
comprobando primero con `rabbitmqctl version` que era la versión ya en ejecución:
fijar una versión distinta de la que llevaba meses funcionando habría introducido
un cambio no verificado bajo apariencia de endurecimiento.

**P1-5 · `SECURITY-NOTICE.md`.** Tres correcciones incorporadas como notas
fechadas y addendum, preservando el texto original: el término «trackeado»
sustituido por «presente en el árbol de trabajo» con la evidencia de git; la
constatación de que la aplicación siguió declarando la CA de desarrollo como
ancla; y la incorporación de P0-E a los riesgos.

## P1-4 · API key documentada sin consumidor

**Estado: abierto, no bloqueante.** Aprovisionada (columna `api_key` en la tabla
`user`) y documentada. Tendrá consumidor cuando se implemente la automatización,
declarada como trabajo futuro.

---

# Hallazgos P2

| ID | Hallazgo | Estado |
|---|---|---|
| P2-1 | `README.md` con modo `100755` | Corregido al reescribir el fichero |
| P2-2 | `SERVER_NAME` duplicado (líneas 7 y 45) | Eliminada la línea 45 |
| P2-3 | `.gitignore` excluía `certificates/rootCA/` completo | Sustituido por exclusión de material privado más negaciones explícitas |
| P2-4 | `IRIS_ADM_PASSWORD` residual en `.env` | Comentada, con nota de que solo aplica al inicializar |

**P2-3, detalle.** La regla excluía el directorio entero, impidiendo versionar el
ancla restaurada en P0-C y el bundle de P1-6 —ambos certificados públicos, sin
clave privada. Como era patrón de directorio, git no descendía a evaluar
negaciones. Verificado con `git add --dry-run`, que propone solo los dos
certificados públicos, y con `git check-ignore` sobre la clave privada, que sigue
excluida.

---

# Sospechas descartadas

**Clave privada de CA demo en la historia de git.** `git log` y `git rev-list`
sobre `fase6-iris/certificates/*` no devuelven nada. Elimina la necesidad de
purga de historia para la Fase 6.

**API key en documentación pública.** `docs/README-Fase6a.md` describe su uso sin
publicar el valor.

**Cadena de certificado de servidor.** `openssl verify` contra `oob-rootCA.crt`:
`OK`.

**Credenciales de base de datos.** `POSTGRES_PASSWORD` (17) y
`POSTGRES_ADMIN_PASSWORD` (23) no coinciden con la plantilla upstream.

**El salt público no comprometía los hashes.** Verificado sobre código y base de
datos: bcrypt con salt por contraseña.

---

# Control de verificación permanente

`scripts/verify-fase6.sh` consolida 16 comprobaciones de comportamiento
observable. Devuelve 0 si todas pasan, 1 si alguna falla.

| # | Comprobación | Hallazgo que cubre |
|---|---|---|
| 1–5 | Los cinco contenedores en estado `running` | P1-11 |
| 6–7 | `app` y `nginx` presentes en `iris_frontend` | P1-11 (causa raíz) |
| 8–9 | Escucha en `100.64.0.1:4833`, sin `0.0.0.0` ni IPv6 | P0-D |
| 10 | Huella del ancla = CA del enclave | P0-C |
| 11 | El ancla valida un certificado del enclave | P0-C |
| 12 | Bundle TLS con ≥151 CAs | P1-6 |
| 13–14 | `IRIS_SECRET_KEY` y salt distintos de `.env.model` | P0-E |
| 15 | `enforce_mfa = t` en base de datos | P1-9 |
| 16 | ≥2 cuentas con MFA enrolado | P1-10 |

## Pruebas negativas

Un verificador que nunca ha fallado no está verificando nada. Tres detecciones
fueron acreditadas induciendo el estado degradado y comprobando que el script lo
señala:

| Prueba | Acción | Resultado |
|---|---|---|
| Red (P1-11) | `docker network disconnect iris_frontend iriswebapp_nginx` | `FALLO iriswebapp_nginx NO esta en iris_frontend`, exit 1 |
| MFA (P1-9) | `UPDATE server_settings SET enforce_mfa = false` | `FALLO enforce_mfa = f`, exit 1 |
| Clave pública (P0-E) | Restituir `AVerySuperSecretKey-SoNotThisOne` en `.env` | `FALLO IRIS_SECRET_KEY es la constante publica de upstream`, exit 1 |

Cada prueba fue revertida y el script volvió a `exit 0`.

---

# Hallazgos para la memoria

## El fallo silencioso, capturado durante su propia remediación

La Fase 6 ofrece el mejor ejemplar del argumento central del trabajo —**los
controles ausentes se manifiestan como operación aparentemente normal, no como
error**— porque el mecanismo quedó registrado en tres instancias sucesivas, la
tercera provocada por el acto de corregirlo.

| Instancia | Fecha y hora | Manifestación |
|---|---|---|
| Degradación consumada | 26 jun, 18:07 | `certificates/ldap/` creado vacío como `root:root`. Descubierta dos meses después |
| Degradación en tránsito | 2 sep, 18:59 | `irisRootCACert.pem` sobre inodo con `nlink = 0` |
| Degradación provocada por la remediación | 3 sep, 16:59 | Docker recreó `irisRootCACert.pem` como directorio `root:root` tras el `mkdir -p` de la corrección |

El comando de remediación reactivó el mecanismo: Docker, procesando la lista de
montajes del contenedor en marcha, creó el origen ausente como directorio de
root. El intento de copiar el certificado falló con un mensaje que no describía
la causa:

```
cp: cannot create regular file
  '.../certificates/rootCA/irisRootCACert.pem/oob-rootCA.crt': Permission denied
```

Supera al precedente de Traefik descartando un middleware inexistente: el estado
degradado quedó fijado en disco con marca temporal, es verificable por terceros a
partir de la evidencia preservada, y documenta que **el acto de remediar puede
disparar el fallo que se pretende corregir**.

## Una corrección verificada que no corregía

P1-11 documenta el ciclo completo, y es el hallazgo metodológicamente más
valioso de la fase:

| Paso | Resultado |
|---|---|
| Hipótesis: healthcheck + `depends_on: service_healthy` | Verificada con `compose up`: `app` alcanza `Healthy` en 33,5 s y `nginx` espera |
| Prueba de arranque en frío | **Refutada**: el servicio no levanta |
| Diagnóstico corregido | `depends_on` es de Compose; el demonio no lo honra al restaurar contenedores |
| Corrección: unidad systemd con `down` + `up --wait` | Verificada en caliente |
| Segunda prueba de arranque en frío | **Confirmada**: `exit 0` sin intervención |

La primera corrección era razonable, estaba verificada, y era inútil para el
escenario que importaba. La verificación no era falsa: era válida en `compose up`
y no en el arranque del anfitrión, que son dos orquestadores distintos sobre los
mismos contenedores.

**Lección:** verificar un control no basta si no se verifica *en el escenario en
que debe actuar*. La pregunta no es «¿funciona?» sino «¿funciona cuando ocurre
aquello contra lo que protege?». Es la misma estructura de la prueba negativa,
aplicada al contexto en lugar de al estado.

## El error que sí se manifiesta, y tampoco se ve

Tras el reinicio, nginx escribió el mismo error cada sesenta segundos durante
horas:

```
[emerg] 1#1: host not found in upstream "app" in /etc/nginx/nginx.conf:146
```

Aquí el sistema **no** falla en silencio: informa con precisión, señala fichero y
línea, y lo repite indefinidamente. Y aun así el servicio estuvo caído sin que
nadie lo advirtiera, porque el estado agregado —cuatro contenedores `Up` y uno
«reiniciando»— no resulta alarmante, y porque nadie lee los logs de un servicio
que no está usando.

La conclusión matiza la tesis y la refuerza: el problema no es únicamente que los
controles ausentes no produzcan error, sino que **la señal de error solo tiene
valor si existe un observador**. Un error escrito en un log no consultado y una
ausencia de error son operativamente equivalentes.

## Controles declarados, presentes y sin efecto

Cuatro instancias de una variante difícil de detectar: el control no está
ausente, está presente y no hace nada.

| Control | Evidencia a favor de su existencia | Efecto real |
|---|---|---|
| Ancla `/etc/irisRootCACert.pem` (P1-6) | Declarado en el compose, visible en `docker inspect`, presente y legible en el contenedor | Ningún cliente TLS lo lee |
| `SECURITY_PASSWORD_SALT` (P1-8) | Declarado en `.env`, cargado en `configuration.py:283` | No se consume; el hashing es bcrypt |
| `MFA_ENABLED` (P1-9) | Variable documentada, interruptor en configuración, **registro de arranque que confirma su estado** | Solo aplica sobre base de datos vacía |
| `certificates/ldap/` (P0-C) | Montaje declarado, directorio presente en el contenedor | Vacío desde el primer arranque |

El tercero es el más peligroso: el sistema **informa activamente de que el control
está activo**. En los cuatro casos, una auditoría documental los habría dado por
correctos; el primero incluso resiste la inspección del sistema de ficheros del
contenedor.

## El auditor incurrió repetidamente en el error que audita

Esta auditoría cometió ocho errores de inferencia, todos del mismo tipo —atribuir
comportamiento a partir de una declaración visible sin comprobar el
comportamiento efectivo— y todos detectados por verificación posterior:

| Inferencia | Basada en | Realidad |
|---|---|---|
| El salt público comprometía los hashes | El nombre de la variable | No se consume; bcrypt con salt por contraseña |
| `enforce_mfa` sería un atributo de grupo | La existencia de tablas de grupos | Columna de `server_settings`, ajuste global |
| La imagen prevé un usuario sin privilegios | Ficheros con uid 1000 en el contenedor | Son bind mounts del anfitrión |
| `git check-ignore -v` indica exclusión por su código de salida | Convención de códigos de salida | Con `-v` el código refleja coincidencia de patrón, incluidos los de negación |
| `docker compose -f` carga el override | Comportamiento por defecto de Compose | `-f` desactiva el descubrimiento automático |
| El healthcheck resolvería el arranque en frío | El síntoma (orden de arranque) | `depends_on` no lo honra el demonio |
| No existía fichero de licencia | `ls LICENSE* COPYING*` con código ≠ 0 | `LICENSE.txt` sí existía; el código venía del patrón inexistente |
| Los commits de documentación no llegaron a `origin` | `origin/main` en un commit de Fase 8 | Ya estaban incluidos en ese commit |

Tres tuvieron consecuencia operativa: el primero llevó a planificar la rotación
del salt como intervención de riesgo cuando era trivial; el quinto revirtió una
remediación ya cerrada; el sexto produjo una corrección que no corregía.

El valor argumental es doble. Refuerza la tesis en lugar de debilitarla: el sesgo
no depende de la competencia ni de la atención, sino de que **la configuración es
visible y el comportamiento no**. Y demuestra que el método funciona: los ocho
fueron detectados por el propio procedimiento de verificación, antes de causar
daño irreversible.

Una auditoría que no puede equivocarse no está verificando nada.

## El éxito reportado describe lo que la herramienta hizo, no lo que se pretendía

Tres operaciones distintas de esta fase devolvieron éxito haciendo algo distinto
de lo esperado:

| Operación | Salida | Efecto real |
|---|---|---|
| `docker compose -f fichero.yml up` | Contenedores recreados correctamente | Override ignorado; restricción de puerto revertida |
| `docker compose up -d` sobre contenedor `exited` | `Started` | Arrancado sin recrear; endpoint de red obsoleto conservado |
| `git push` | `644edf8..99844be main -> main` | Empujado al remoto de backup, no al principal |

Ninguna produjo error ni advertencia. En los tres casos la herramienta ejecutó
correctamente lo que se le pidió, que no era lo que se quería. La detección
provino siempre de comprobar el estado resultante —`ss`, `docker network
inspect`, `git log origin/main`—, nunca del código de retorno.

Es la formulación más general del argumento del trabajo: **el éxito reportado por
una herramienta describe lo que la herramienta hizo, no lo que se pretendía que
hiciera**. Verificar el efecto y no la ejecución es lo único que los distingue.

## La verificación produce más hallazgos que la búsqueda

Seis de los once P1 —P1-6, P1-7, P1-8, P1-9, P1-10, P1-11— se detectaron al
comprobar que una remediación funcionaba, no al buscar defectos.

La comprobación de P0-C reveló que la CA no estaba en ningún almacén (P1-6) y que
la aplicación corre como root (P1-7); la de P0-E, que el salt no se consume
(P1-8); la investigación previa a activar MFA, que su interruptor documentado es
inerte (P1-9) y que solo existía una cuenta (P1-10); y la verificación previa al
commit, cuatro días después, que la pila no sobrevive a un reinicio (P1-11).

El esfuerzo de auditoría rinde más aplicado a verificar lo que se cree correcto
que a buscar lo que se sospecha incorrecto. La búsqueda está limitada por lo que
el auditor imagina; la verificación, no.

## Remediación parcial que aparenta ser completa

P0-2 corrigió el certificado que el servicio presenta y documentó la corrección
con rigor. No corrigió el que el servicio declara confiar. Ambos son TLS, ambos
residen en el mismo directorio, y la verificación aplicada —`openssl s_client`,
`curl` sin `-k`, navegador sin aviso— solo podía observar el primero.

Una remediación verificada exclusivamente desde el exterior no puede detectar un
fallo en el interior. La verificación debe cubrir cada superficie que el control
pretende proteger, y eso exige enumerar antes qué superficies existen.

## Independencia del enclave: refutación empírica y corrección

El principio rector sostiene que el enclave debe permanecer operativo e íntegro
aunque la infraestructura corporativa esté comprometida. La Fase 6 lo refutaba en
su propio despliegue: el sistema que custodia el registro completo del incidente
era tomable con una única petición HTTP desde la red corporativa, mediante una
constante publicada en un repositorio público.

Las remediaciones cortan la cadena en sus dos eslabones, restituyen la PKI del
enclave como ancla de confianza declarada y funcional, y añaden segundo factor
obligatorio.

P1-11 añade una dimensión ortogonal: la **disponibilidad**. Un sistema que no
converge a estado operativo tras un reinicio no está disponible cuando se le
necesita, con independencia de lo robusto que sea su control de acceso. La prueba
de arranque en frío queda incorporada como criterio de aceptación, y es la primera
del proyecto.

El hallazgo no invalida el principio; documenta que **un principio arquitectónico
no se implementa por enunciarlo**, y que su verificación exige comprobar cada
servicio contra el modelo de amenaza y el escenario de fallo que el principio
define.

El patrón de exposición directa de puertos afecta a Velociraptor, OpenSearch
Dashboards y DFIR-IRIS. Los tres son pilas completas de terceros incorporadas con
su propio compose, frente a los servicios desplegados de forma nativa tras
Traefik. La hipótesis —que el compose de terceros arrastra sus supuestos de
publicación y estos sobreviven a la integración— es coherente con los tres casos y
merece contrastarse con el resto del despliegue antes de sostenerla en la memoria.

---

# Anexo A — Evidencia preservada

`docs/evidencias/fase6-p0c/`

| Fichero | Contenido |
|---|---|
| `estado-runtime.txt` | `ls -li` del inodo huérfano y del montaje LDAP degradado, huella DER, cadena de custodia y registro de la tercera instancia (09-03 16:59) |
| `irisRootCACert-demo.pem` | CA demo de DFIR-IRIS extraída del contenedor en ejecución |
| `mounts.json` | Montajes de `iriswebapp_app` en el momento de la auditoría |

| Tipo | Valor |
|---|---|
| Huella SHA-256 del certificado (DER) | `12:74:5C:EF:8E:36:96:14:76:6A:4D:14:D8:8F:A7:96:D6:65:F6:37:90:6D:99:B3:C1:49:A8:06:40:63:70:A2` |
| SHA-256 del fichero PEM (custodia) | `c2be036d5c9945c12860324b725bd636ac33d6ea8a00d064e83bdd5aecdb81ed` |

Respaldos generados durante la remediación, **no versionables**:

- `fase6-iris/.env.pre-p0-2`, `.env.pre-p0-e`, `.env.pre-limpieza`
- `~/iris_db-pre-salt-20260904-0924.sql`
- `~/iris_db-pre-mfa-20260904-1500.sql` (con `breakglass` ya creada, verificado)

---

# Anexo B — Verificación de estado

```bash
cd ~/tfm-alerta-temprana-oob
./scripts/verify-fase6.sh; echo "exit=$?"
```

16 comprobaciones. Ejecutar tras cualquier recreación de contenedores, tras un
reinicio del anfitrión y antes de cada commit que toque la fase.

Verificación previa a cualquier recreación —renderiza la fusión efectiva del
compose:

```bash
cd fase6-iris
docker compose config | grep -E 'CA_BUNDLE|100\.64\.0\.1|service_healthy'
```

Prueba de arranque en frío, criterio de aceptación de la fase:

```bash
sudo reboot
# al volver, SIN tocar nada:
sleep 90
systemctl is-active tfm-fase6-iris.service    # active
./scripts/verify-fase6.sh                     # exit 0
```

---

# Anexo C — Procedimientos de recuperación

Documentados también en `fase6-iris/README.md`.

## MFA no disponible en ambas cuentas

```bash
cd ~/tfm-alerta-temprana-oob/fase6-iris
docker exec iriswebapp_db psql -U postgres -d iris_db -c \
  'UPDATE server_settings SET enforce_mfa = false;'
docker compose up -d --force-recreate app worker
```

La recreación es necesaria: un cambio directo en base de datos no refresca
`app.config`. Tras recuperar el acceso, reenrolar y reactivar desde la interfaz.

## nginx en bucle de reinicio

```bash
docker network inspect iris_frontend --format '{{range .Containers}}{{.Name}} {{end}}'
# si nginx no aparece, tiene endpoint de red obsoleto: recrear, no arrancar
cd ~/tfm-alerta-temprana-oob/fase6-iris
docker compose up -d --force-recreate nginx
```

## La pila no levanta tras reiniciar

```bash
systemctl status tfm-fase6-iris.service
journalctl -u tfm-fase6-iris.service -b --no-pager
sudo systemctl restart tfm-fase6-iris.service
```

Ejecutar siempre desde `fase6-iris/`: con `-f` desde otro directorio, el override
no se carga y la restricción de puerto se pierde.

---

*Auditoría realizada el 3 de septiembre de 2026 sobre el despliegue en
producción, con remediación aplicada y verificada entre los días 3 y 6. Todos los
hallazgos están respaldados por evidencia observable y reejecutable. Ocho
conclusiones basadas en inferencia fueron detectadas y corregidas durante el
proceso; quedan documentadas en la sección de memoria.*
