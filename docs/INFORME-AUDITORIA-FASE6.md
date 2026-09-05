# Informe de auditoría de seguridad — Fase 6 (DFIR-IRIS)

| Campo | Valor |
|---|---|
| Fase | 6 — Gestión de casos con DFIR-IRIS v2.4.27 |
| Fecha de auditoría | 3 de septiembre de 2026 |
| Remediación aplicada | 3–5 de septiembre de 2026 |
| Alcance | `fase6-iris/`, `docs/README-Fase6a.md`, `docs/README-Fase6b.md`, integración declarada en Fases 2/3/5 |
| Auditorías previas | Ninguna. P0-2 (2026-09-02) fue una remediación puntual de certificado |
| Revisión | v5 — cierre de los hallazgos técnicos. Incorpora P1-11, detectado en la verificación final |

---

## Resumen ejecutivo

La auditoría identificó **cinco hallazgos P0** y, en el curso de la remediación,
**once hallazgos P1** y cuatro P2.

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

**Estado de cierre.** Los tres P0 técnicos (C, D, E) quedan corregidos y
verificados por comportamiento. Los dos P0 documentales (A, B) tienen la
corrección redactada, pendiente de commit. De los once P1: cinco corregidos, uno
aceptado como riesgo documentado, cinco abiertos como deuda estructural.

Un resultado metodológico relevante: **la verificación de las remediaciones
produjo más hallazgos que la auditoría inicial**. Seis de los once P1 se
detectaron al comprobar que una corrección funcionaba, no al buscar defectos. El
último, P1-11, apareció en la verificación previa al commit, cuatro días después
de la auditoría. Y la propia auditoría incurrió en cinco errores de inferencia,
todos detectados por verificación posterior y documentados en la sección de
memoria por su valor argumental.

---

## Método

Tres bloques de verificación de solo lectura sobre el sistema en producción,
seguidos de cuatro bloques de remediación con verificación posterior, aplicando
el principio de **verificar comportamiento observable, no ficheros de
configuración**.

Fuentes de contraste: estado de git, sistema de ficheros del anfitrión, estado
interno del contenedor, respuesta del servicio en runtime, estado de la base de
datos, y código fuente vendorizado cuando determina el comportamiento efectivo.

Ninguna conclusión de este informe se apoya exclusivamente en inspección de
configuración. Las conclusiones de versiones anteriores que sí lo hacían fueron
detectadas y corregidas; ver la sección de memoria.

---

## Cuadro de hallazgos

| ID | Hallazgo | Sev. | Estado |
|---|---|---|---|
| P0-A | El README declara seis capacidades automatizadas inexistentes | P0 | Corrección redactada |
| P0-B | El `docker-compose.yml` documentado no corresponde al desplegado | P0 | Corrección redactada |
| P0-C | Ancla de confianza = CA demo pública, sobre inodo huérfano | P0 | **Corregido** |
| P0-D | Servicio publicado en `0.0.0.0:4833` sin proxy ni MFA | P0 | **Corregido** |
| P0-E | `SECRET_KEY` pública → forja de sesión administrativa | P0 | **Corregido** |
| P1-1 | 483 636 líneas vendorizadas sin NOTICE de licencia LGPL-3.0 | P1 | Abierto |
| P1-2 | Fase no reproducible desde el repositorio | P1 | Parcial |
| P1-3 | `rabbitmq:3-management-alpine` con etiqueta flotante | P1 | Abierto |
| P1-4 | API key documentada sin consumidor | P1 | Abierto |
| P1-5 | Imprecisiones en `SECURITY-NOTICE.md` | P1 | **Corregido** |
| P1-6 | La CA del enclave fuera de los almacenes de confianza | P1 | **Corregido** |
| P1-7 | La aplicación se ejecuta como `root` en el contenedor | P1 | **Riesgo aceptado** |
| P1-8 | `SECURITY_PASSWORD_SALT` declarada y no consumida | P1 | Documentado |
| P1-9 | `MFA_ENABLED` inerte en despliegues ya inicializados | P1 | **Corregido** |
| P1-10 | Cuenta administrativa única, sin acceso de emergencia | P1 | **Corregido** |
| P1-11 | La pila no converge a estado operativo tras reinicio del anfitrión | P1 | Abierto |
| P2-1 | `README.md` con modo `100755` | P2 | Corrección redactada |
| P2-2 | `SERVER_NAME` duplicado en `.env` | P2 | Abierto |
| P2-3 | `.gitignore` excluía las anclas de confianza públicas | P2 | **Corregido** |
| P2-4 | `IRIS_ADM_PASSWORD` persiste en `.env` | P2 | Abierto |
| — | Clave privada de CA demo en la historia de git | — | **Descartado** |
| — | API key real en documentación pública | — | **Descartado** |

---

# Hallazgos P0

## P0-E · Clave de firma de sesión pública

**Severidad:** P0 crítica. **Estado: corregido y verificado.**

### Condición

`IRIS_SECRET_KEY` e `IRIS_SECURITY_PASSWORD_SALT` contenían los valores
literales de la plantilla upstream `.env.model`, publicada en el repositorio de
DFIR-IRIS y presente también en este repositorio:

```
IRIS_SECRET_KEY=AVerySuperSecretKey-SoNotThisOne
IRIS_SECURITY_PASSWORD_SALT=ARandomSalt-NotThisOneEither
```

Sin rotar desde el despliegue de la fase (26 de junio de 2026). La remediación
P0-2 del 2 de septiembre no los alteró.

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
(`len=64`), verificada por comportamiento observable:

```
antes:  ...apnH4w.KyMYJhpsUWh3Vh1bixB5nczytbI
ahora:  ...apnOlQ.4GkdXNEgS5jlh-Gr-9FdQ5DS7hI
```

**4 de septiembre.** `IRIS_SECURITY_PASSWORD_SALT` rotada (`len=44`), precedida
de volcado completo de la base de datos como vía de recuperación.

**Verificación de cierre:** acceso desde el navegador del W11 con las
credenciales previas a la rotación, correcto. Confirma simultáneamente que la
clave rotada está en uso y que el salt no participaba en el hashing.

### Corrección de una afirmación de la versión v1

> [!IMPORTANT]
> La v1 atribuía al salt público la pérdida de protección de los hashes frente a
> tablas precomputadas. **La afirmación era incorrecta.**
>
> `SECURITY_PASSWORD_SALT` se carga en configuración y no se consume en ningún
> punto (dos únicas apariciones, ambas de carga). El hashing es flask-bcrypt,
> que genera salt aleatorio por contraseña e incrustado en el hash. Confirmado
> sobre la base de datos: prefijo `$2b$`.
>
> La gravedad de P0-E residía enteramente en `IRIS_SECRET_KEY`. Ver P1-8 y la
> sección de memoria.

---

## P0-C · Ancla de confianza sobre inodo huérfano

**Severidad:** P0. **Estado: corregido y verificado.**

### Condición

P0-2 sustituyó el certificado que nginx **presenta** y retiró del árbol el
material de desarrollo. No sustituyó el que la aplicación **declara confiar**.

El directorio origen del montaje no existía en el anfitrión:

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

```yaml
ports:
  - "${INTERFACE_HTTPS_PORT:-443}:${INTERFACE_HTTPS_PORT:-443}"
```

```
LISTEN 0 4096  0.0.0.0:4833  0.0.0.0:*
LISTEN 0 4096     [::]:4833     [::]:*
```

IPv4 e IPv6, todas las interfaces, sin Traefik ni Authelia.

Tercer servicio del proyecto con este patrón, junto a Velociraptor (Fase 5) y
OpenSearch Dashboards (Fase 7).

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

MFA obligatorio activado el 4 de septiembre (ver P1-9), lo que cierra el
hallazgo por completo: aislamiento de red más segundo factor.

### Incidente de reversión silenciosa

Durante la remediación de P1-6, la ejecución de
`docker compose -f fase6-iris/docker-compose.yml up -d --force-recreate` desde el
directorio raíz **revirtió esta corrección sin emitir aviso**.

Causa: Compose carga `docker-compose.override.yml` automáticamente solo cuando
descubre los ficheros por sí mismo. Con `-f` explícito, el override queda fuera
salvo que se enumere. El servicio se recreó con la configuración de `base.yml`,
volviendo a `0.0.0.0:4833`.

Detectado porque `ss -tlnp | grep 4833` formaba parte del guion de verificación,
no porque el sistema informara. Restaurado ejecutando desde `fase6-iris/`.

**Control derivado:** todas las operaciones de compose de esta fase se ejecutan
desde `fase6-iris/`, nunca con `-f` desde otro directorio.
`docker compose config` es la verificación previa: renderiza la fusión efectiva.

### Dependencia operativa

El enlace a `100.64.0.1` requiere que la interfaz del tailnet esté activa. Si
Headscale no ha levantado, nginx fallará al enlazar el puerto. Documentado en el
README de la fase. Ver también P1-11.

---

## P0-A · El README declara seis capacidades automatizadas inexistentes

**Severidad:** P0 para la defensa. **Estado: corrección redactada, pendiente de commit.**

### Evidencia

```
$ grep -rn --include='*.json' --include='*.py' -iE 'iris\.oob|iriswebapp|/api/case|iris_api' \
    fase2-orquestador/ fase3-agentic/ fase5-orchestrator-api/
(sin salida)
```

Las únicas apariciones de «iris» en los flujos de n8n son literales de texto en
un nodo `IRIS Reference`, sin llamada HTTP:

```
"iris_status": "manual_case_created"
"Evidencia y timeline ya registrados en IRIS"
```

El propio payload declara que el caso se creó manualmente.

`fase6-iris/` no contiene código propio: los 245 ficheros `.py` son vendorizados
sin modificar.

### Documentación contradictoria

| Documento | Afirma |
|---|---|
| `fase6-iris/README.md` | Seis capacidades automatizadas implementadas |
| `docs/README-Fase6a.md` | Despliegue validado; API key para «uso previsto en Fase 6b» |
| `docs/README-Fase6b.md` | Caso, evidencia y timeline validados **manualmente** |
| `fase6-iris/SECURITY-NOTICE.md` | Ningún componente consume IRIS por API |

Los tres últimos son coherentes y honestos. El primero no sobrevive a un `grep`
durante la defensa.

### Corrección

README reescrito: estado dividido en «implementado y validado» / «no
implementado», automatización trasladada a trabajo futuro con los pasos
concretos, y la validación manual presentada como el resultado que es —
viabilidad demostrada, que es defendible.

---

## P0-B · El compose documentado no corresponde al desplegado

**Estado: corrección redactada.** Misma causa raíz que P0-A.

| README | Realidad |
|---|---|
| `iris/webapp:latest`, `iris/api` | `ghcr.io/dfir-iris/iriswebapp_app:v2.4.27` |
| Servicio `iris-api:8080` | No existe |
| `POSTGRES_PASSWORD=iris_pass` | Procede de `.env` |
| Única red `oob-network` | `iris_backend` + `iris_frontend` + `oob-network` |
| Sin certificados | Tres montajes en `app` y `worker` |

`iris_pass` es una credencial en claro en fichero versionado y público — mismo
patrón que el P0 de la Fase 7.

---

# Hallazgos P1

## P1-11 · La pila no converge a estado operativo tras reinicio del anfitrión

**Estado: abierto.** Detectado el 5 de septiembre, durante la verificación previa
al commit.

### Condición

Tras un reinicio del anfitrión, `iriswebapp_nginx` quedó en bucle de reinicio
indefinido. El contenedor no se reincorporó a la red `iris_frontend`, por lo que
no podía resolver el upstream `app`:

```
$ docker ps -a --filter name=iriswebapp --format 'table {{.Names}}\t{{.Status}}'
iriswebapp_nginx      Restarting (1) 27 seconds ago
iriswebapp_worker     Up 43 minutes
iriswebapp_app        Up 43 minutes
iriswebapp_rabbitmq   Up 43 minutes
iriswebapp_db         Up 43 minutes

$ docker logs --tail=4 iriswebapp_nginx
2026/09/05 21:15:13 [emerg] 1#1: host not found in upstream "app" in /etc/nginx/nginx.conf:146
2026/09/05 21:16:13 [emerg] 1#1: host not found in upstream "app" in /etc/nginx/nginx.conf:146
```

El diagnóstico decisivo fue la composición de la red, no los logs:

```
$ docker network inspect iris_frontend --format '{{range .Containers}}{{.Name}} {{end}}'
iriswebapp_rabbitmq iriswebapp_app
```

`nginx` ausente de una red en la que el compose sí lo declara. El renderizado con
`docker compose config` confirma que la configuración es correcta —`nginx` lista
`iris_frontend` y `oob-network`—, de modo que el defecto está en la
reincorporación tras el reinicio, no en la definición.

### Impacto

`restart: always` no converge cuando la causa es la ausencia de red: reintenta
cada 60 segundos y falla siempre, indefinidamente. El servicio estuvo caído desde
las 21:07 del 5 de septiembre hasta la intervención manual.

Es una variante del fallo silencioso con una diferencia relevante: **el sistema
sí emite errores**, claros y repetidos, en un log que nadie consulta. El estado
agregado —cuatro de cinco contenedores `Up`, el quinto «reiniciando»— no resulta
alarmante a simple vista.

En un enclave OOB el impacto es mayor que en otro servicio. El sistema de gestión
de casos debe estar disponible precisamente cuando algo ha ido mal, y aquí un
reinicio del anfitrión lo dejó inoperativo sin intervención. Sin monitorización
del estado de los contenedores, podría permanecer caído durante días — el mismo
patrón de degradación no observada que afectó a la vía de recuperación física del
GL-RM1 en la Fase 8.

### Remediación propuesta

1. `healthcheck` en `app` con `depends_on: condition: service_healthy` en
   `nginx`, de modo que el orden de arranque sea determinista. El contenedor
   `nginx` ya expone estado `healthy`, luego el mecanismo está disponible.
2. Monitorización del estado de los cinco contenedores como parte de la
   observabilidad de la Fase 7, con prueba negativa: detener un contenedor y
   comprobar que la alerta se dispara.
3. **Prueba de reinicio como criterio de aceptación de la fase**: reiniciar el
   anfitrión y verificar, sin intervención manual, que el Anexo B pasa completo.

El punto 3 es el que convierte el hallazgo en control. Ninguna de las fases del
proyecto documenta hasta ahora una prueba de arranque en frío.

## P1-9 · `MFA_ENABLED` inerte en despliegues ya inicializados

**Estado: corregido.** Reformulado tras la investigación.

### Condición

La formulación inicial —«MFA disponible sin activar»— era incompleta. El análisis
del código revela algo más grave.

`MFA_ENABLED` tiene un único consumidor:

```
post_init.py:1665:  ..., enforce_mfa=app.config.get("MFA_ENABLED", False))
```

dentro de:

```python
def create_safe_server_settings():
    if not ServerSettings.query.count():
        create_safe(db.session, ServerSettings, ..., enforce_mfa=...)
```

La guarda `if not ServerSettings.query.count()` limita la ejecución a bases de
datos vacías. En un despliegue ya inicializado —el de esta fase lo está desde el
26 de junio— **definir `IRIS_MFA_ENABLED=True` no tiene efecto alguno**.

El login lee otra fuente:

```
login_routes.py:268:  if app.config['SERVER_SETTINGS']['enforce_mfa'] is True and is_oidc is False:
```

`enforce_mfa` es una columna de `server_settings` (`models.py:803`), poblada una
sola vez.

### Agravante: el registro de arranque induce a error

```
configuration.py:489:  log.info(f'MFA {"enabled" if MFA_ENABLED else "disabled"}')
```

Este registro refleja la variable de entorno, no el estado efectivo. Con
`IRIS_MFA_ENABLED=True` sobre una base de datos existente, el sistema habría
registrado `MFA enabled` mientras el login seguía sin exigir segundo factor.

Es la forma más engañosa del patrón documentado en esta fase: no es un control
ausente ni un control sin efecto, sino un control que **informa activamente de
estar activo cuando no lo está**. Un criterio de verificación basado en ese
registro habría producido un falso positivo, y ese criterio fue efectivamente
propuesto durante esta auditoría antes de ser descartado.

### Remediación aplicada (2026-09-04)

Vía correcta: casilla `enforce_mfa` en **Advanced → Server settings**, que
actualiza la base de datos y refresca `app.config`
(`manage_srv_settings_routes.py:141`). Se prefiere a un `UPDATE` directo por
dejar rastro en el registro de auditoría de IRIS.

Secuencia aplicada, con la cuenta de emergencia creada primero (P1-10):

1. Volcado de la base de datos, verificado con `grep 'breakglass'` sobre el fichero
2. Activación de `enforce_mfa` → confirmado `t` en base de datos
3. Enrolamiento TOTP de `breakglass` primero — la cuenta prescindible
4. Enrolamiento TOTP de `administrator`

```
$ psql -tAc 'SELECT "user", mfa_setup_complete FROM "user";'
administrator|t
breakglass|t
```

### Riesgo residual

Ambas cuentas exigen ahora TOTP. La pérdida del dispositivo de segundo factor
bloquea el servicio. Procedimiento de recuperación en el Anexo C.

## P1-6 · La CA del enclave fuera de los almacenes de confianza

**Estado: corregido y verificado.** Detectado al verificar P0-C.

### Condición

`docker-compose.base.yml` monta `irisRootCACert.pem` en `/etc/irisRootCACert.pem`
y **ningún componente lo consume**:

| Vía | Estado inicial |
|---|---|
| `/etc/ssl/certs/ca-certificates.crt` | Sin la CA del enclave (150 CAs públicas) |
| `/usr/local/share/ca-certificates/` | Vacío |
| `certifi` | Bundle público (136 CAs), sin la CA |
| `REQUESTS_CA_BUNDLE`, `SSL_CERT_FILE`, `CURL_CA_BUNDLE` | No definidas |
| `Dockerfile`, `configuration.py`, `iris-entrypoint.sh` | Sin referencia al fichero |

Los clientes TLS de la aplicación —`requests`, `urllib`, y los módulos MISP,
IntelOwl y WebHooks— no confiaban en la PKI del enclave para tráfico saliente,
con el riesgo asociado de que se resolviera deshabilitando la verificación,
reproduciendo el `insecureSkipVerify` de la Fase 7.

Nota de alcance: dado que el fichero anterior tampoco tenía consumidor, la CA
demo nunca llegó a emplearse para validar nada. El impacto de P0-C se concreta en
que el ancla declarada era material público, no en un uso efectivo de esa CA.

### Remediación aplicada

Se descartó montar en `/usr/local/share/ca-certificates/`: aunque
`update-ca-certificates` existe en la imagen, el entrypoint no lo ejecuta, y una
corrección que dependa de un paso manual tras cada recreación es el mismo patrón
de fallo silencioso que documenta esta fase.

Bundle concatenado construido en el anfitrión, versionable y auditable, montado y
declarado en el override para `app` y `worker` con `REQUESTS_CA_BUNDLE`,
`SSL_CERT_FILE` y `CURL_CA_BUNDLE`.

Se concatena sobre el bundle público en lugar de sustituirlo: apuntar solo a la
CA del enclave rompería la verificación de destinos externos.

### Verificación

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

El error de coincidencia de nombre **es el resultado positivo**: la cadena de
certificado validó contra el bundle. Un fallo de confianza habría producido
`CERTIFICATE_VERIFY_FAILED`.

## P1-10 · Cuenta administrativa única

**Estado: corregido.**

`administrator` era la única cuenta del sistema. La pérdida de su credencial, o
un enrolamiento de MFA fallido, habrían dejado el servicio inaccesible.
Contradecía el patrón de acceso de emergencia de la Fase 4.

Creada la cuenta `breakglass` con rol administrativo y credencial custodiada por
separado, **antes** de activar MFA — el orden importaba:
`modal_add_user.html:145` modifica el formulario de alta cuando `enforce_mfa`
está activo.

Acceso verificado en sesión independiente antes de continuar.

## P1-7 · La aplicación se ejecuta como root · RIESGO ACEPTADO

**Estado: riesgo aceptado y documentado.**

```
$ docker exec iriswebapp_app ps -eo user,uid,comm
root  0  iris-entrypoint
root  0  gunicorn
root  0  gunicorn
```

La imagen de DFIR-IRIS v2.4.27 no contempla ejecución sin privilegios: el
Dockerfile no declara `USER`, no crea usuario y no ajusta propiedad; el entrypoint
no crea directorios ni permisos; y los volúmenes `downloads`, `user_templates` y
`server_data`, más `/iriswebapp`, son `root:root`.

Corregirlo exigiría `chown` de los tres volúmenes, entrada en `/etc/passwd` para
el uid, y verificación de que ninguna dependencia llama a `pwd.getpwuid()`. Eso
supone bifurcar la imagen vendorizada, contradiciendo el criterio de mantener
`fase6-iris/` alineado con upstream. Una corrección parcial rompería la escritura
en esos volúmenes con fallo diferido y silencioso — al exportar un caso, no al
arrancar.

**Controles compensatorios:** aislamiento de red al tailnet (P0-D), MFA
obligatorio (P1-9), sin claves públicas en uso (P0-E), contenedor no privilegiado
y sin socket de Docker montado.

Se documenta junto a los demás riesgos aceptados del proyecto
(`insecureSkipVerify` global en Traefik, Portainer en 9443).

> [!NOTE]
> **Corrección de la v3.** Aquella versión afirmaba que la imagen «se construyó
> previendo un usuario sin privilegios que nunca se activa», deduciéndolo de
> ficheros con uid 1000 dentro del contenedor. La verificación posterior muestra
> que todos esos ficheros son bind mounts del anfitrión: el uid 1000 es el
> usuario del host, no un usuario latente de la imagen.

## P1-8 · `SECURITY_PASSWORD_SALT` declarada y no consumida

**Estado: documentado.**

La variable se carga en configuración y ningún componente la utiliza. El hashing
es flask-bcrypt con salt aleatorio por contraseña incrustado en el hash (`$2b$`).

Es un control declarado, presente en `.env`, cargado en tiempo de ejecución y sin
efecto. Su presencia indujo el error de inferencia de la v1 de este informe.

No procede eliminarla: la carga pertenece al código vendorizado. Se documenta en
el README que es residual y no interviene en el hashing, para que futuras
auditorías no le atribuyan garantías inexistentes.

## P1-5 · Imprecisiones en `SECURITY-NOTICE.md`

**Estado: corregido.**

1. `irisRootCAKey.pem` se describía como «trackeado»; nunca entró en el
   historial de git. Corregido a «presente en el árbol de trabajo», con la
   evidencia y la conclusión de que la Fase 6 no requiere purga.
2. Se añade que la aplicación siguió declarando la CA de desarrollo como ancla.
3. Se añade P0-E a los riesgos, ausente del apartado original.

Incorporadas como notas fechadas y addendum, preservando el texto original: la
evolución del entendimiento queda registrada.

## P1-1 · Código vendorizado sin NOTICE de licencia

**Estado: abierto.** El commit `a07dc0d` convirtió el submódulo en directorio
normal: 1160 ficheros, 483 636 inserciones. Rompe la coherencia con el resto de
fases, invalida métricas de código propio e incorpora LGPL-3.0 sin atribución.

**Remediación:** submódulo fijado en `v2.4.27`, o `NOTICE` explícito y
`.gitattributes` con `linguist-vendored`.

## P1-2 · Reproducibilidad

**Estado: parcial.**

Resuelto: `docker-compose.override.yml` y las anclas públicas
(`irisRootCACert.pem`, `ca-bundle-oob.crt`) son ahora versionables (ver P2-3).

Pendiente: `.env.example` propio, script de emisión del certificado del enclave,
y versionado del flujo de n8n vigente. De los ocho JSON en
`fase2-orquestador/n8n/`, solo `workflows/wazuh-alert-handler.json` está
versionado.

**Observación:** `wf-antes-rotacion-2026-08-23.json`, no versionado, contiene
claves de credencial. Conviene añadir `fase2-orquestador/n8n/*.json` a
`.gitignore` con excepción para `workflows/`.

## P1-3 · Etiqueta de imagen flotante

`rabbitmq:3-management-alpine` sin versión fijada.

## P1-4 · API key documentada sin consumidor

Aprovisionada (columna `api_key` en la tabla `user`) y documentada en
`docs/README-Fase6a.md`. Ningún componente la consume.

---

# Hallazgos P2

| ID | Hallazgo | Estado |
|---|---|---|
| P2-1 | `README.md` con modo `100755` | Se corrige al reescribir el fichero |
| P2-2 | `SERVER_NAME` duplicado en `.env` (líneas 7 y 45) | Abierto |
| P2-3 | `.gitignore` excluía `certificates/rootCA/` completo | **Corregido** |
| P2-4 | `IRIS_ADM_PASSWORD` persiste en `.env` | Abierto |

**P2-3, detalle.** La regla `fase6-iris/certificates/rootCA/` excluía el
directorio entero, impidiendo versionar el ancla restaurada en P0-C y el bundle
de P1-6 — ambos certificados públicos, sin clave privada. Como era patrón de
directorio, git no descendía a evaluar negaciones.

Sustituida por exclusión de material privado (`*Key.pem`, `*.key`) más negaciones
explícitas. Verificado con `git add --dry-run`, que propone solo los dos
certificados públicos, y con `git check-ignore` sobre la clave privada, que sigue
excluida.

---

# Sospechas descartadas

**Clave privada de CA demo en la historia de git.** `git log` y `git rev-list`
sobre `fase6-iris/certificates/*` no devuelven nada. Elimina la necesidad de
purga de historia para la Fase 6.

**API key en documentación pública.** `docs/README-Fase6a.md` describe su uso sin
publicar el valor. La única cadena larga es un hash SHA-256 de evidencia.

**Cadena de certificado de servidor.** `openssl verify` contra `oob-rootCA.crt`:
`OK`.

**Credenciales de base de datos.** `POSTGRES_PASSWORD` (17) y
`POSTGRES_ADMIN_PASSWORD` (23) no coinciden con la plantilla upstream.

**El salt público no comprometía los hashes.** Verificado sobre código y base de
datos: bcrypt con salt por contraseña.

---

# Plan de remediación

## Bloque 1 — Corte de la cadena de explotación · COMPLETADO (09-03)

1. ~~Rotar `IRIS_SECRET_KEY`~~ — verificado por cambio de firma de cookie
2. ~~Restaurar el ancla de confianza~~ — verificado por huella y `openssl verify`
3. ~~Restringir la publicación al tailnet~~ — verificado con `ss`

## Bloque 2 — Rotación del salt · COMPLETADO (09-04)

4. ~~Volcado de la base de datos~~
5. ~~Verificar el mecanismo de hashing antes de rotar~~ — bcrypt confirmado
6. ~~Rotar el salt~~ — login verificado desde el W11

## Bloque 3 — MFA y acceso de emergencia · COMPLETADO (09-04)

7. ~~Crear cuenta `breakglass`~~ — acceso verificado
8. ~~Activar `enforce_mfa`~~ — vía interfaz, confirmado en base de datos
9. ~~Enrolar TOTP en ambas cuentas~~ — secundaria primero

## Bloque 4 — Confianza TLS y privilegios · COMPLETADO (09-04)

10. ~~Bundle concatenado y variables de entorno~~ — 151 CAs, validación funcional
11. ~~Evaluar ejecución sin privilegios~~ — riesgo aceptado, documentado
12. ~~Corregir `.gitignore`~~ — anclas públicas versionables

## Bloque 5 — Documentación · PENDIENTE DE COMMIT

13. `fase6-iris/README.md` reescrito
14. `fase6-iris/SECURITY-NOTICE.md` corregido
15. Commit de: override, anclas públicas, evidencias de P0-C, este informe
16. `.env.example` propio y versionado del flujo de n8n vigente
17. Documentar el procedimiento de break-glass de MFA en el README

## Bloque 6 — Robustez operativa (P1-11)

18. `healthcheck` en `app` y `depends_on: service_healthy` en `nginx`
19. Monitorización del estado de contenedores en la Fase 7, con prueba negativa
20. Prueba de reinicio en frío como criterio de aceptación de la fase

## Bloque 7 — Deuda estructural

21. Submódulo fijado o `NOTICE` + `.gitattributes` (P1-1)
22. Fijar `rabbitmq:3-management-alpine` (P1-3)
23. `SERVER_NAME` duplicado (P2-2), `IRIS_ADM_PASSWORD` residual (P2-4)

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

La tercera es la más significativa. El comando de remediación reactivó el
mecanismo: Docker, procesando la lista de montajes del contenedor en marcha, creó
el origen ausente como directorio de root. El intento de copiar el certificado
falló con un mensaje que no describía la causa:

```
cp: cannot create regular file
  '.../certificates/rootCA/irisRootCACert.pem/oob-rootCA.crt': Permission denied
```

Supera al precedente de Traefik descartando un middleware inexistente: el estado
degradado quedó fijado en disco con marca temporal, es verificable por terceros a
partir de la evidencia preservada, y documenta que **el acto de remediar puede
disparar el fallo que se pretende corregir**.

## La reversión silenciosa de una remediación verificada

P0-D fue corregido, verificado con `ss` y dado por cerrado. Al día siguiente,
durante la remediación de P1-6, la ejecución de
`docker compose -f fase6-iris/docker-compose.yml up -d --force-recreate` desde el
directorio raíz revirtió la corrección.

Compose carga `docker-compose.override.yml` automáticamente solo cuando descubre
los ficheros por sí mismo. Con `-f` explícito, el override queda fuera salvo que
se enumere. El servicio se recreó sin él, volviendo a `0.0.0.0:4833`. Sin aviso,
sin error, con los contenedores en estado saludable.

Es una variante nueva del patrón, sobre la herramienta de despliegue en lugar del
sistema desplegado: **una remediación correcta y verificada puede revertir en
silencio por una diferencia en cómo se invoca la herramienta**. Se detectó porque
la comprobación de exposición formaba parte del guion de verificación, no porque
algo lo señalara.

Corolario operativo: la verificación de una remediación no puede ser un acto
único. Debe reejecutarse tras cualquier operación sobre el servicio, y por eso
este informe incluye el Anexo B.

## El error que sí se manifiesta, y tampoco se ve

P1-11 aporta el contraejemplo que completa el argumento. Tras un reinicio del
anfitrión, nginx quedó en bucle de reinicio y escribió el mismo error cada
sesenta segundos durante horas:

```
[emerg] 1#1: host not found in upstream "app" in /etc/nginx/nginx.conf:146
```

Aquí el sistema **no** falla en silencio: informa con precisión, señala el
fichero y la línea, y lo repite indefinidamente. Y aun así el servicio estuvo
caído sin que nadie lo advirtiera, porque el estado agregado —cuatro contenedores
`Up` y uno «reiniciando»— no resulta alarmante, y porque nadie lee los logs de un
servicio que no está usando.

La conclusión matiza la tesis y la refuerza: el problema no es únicamente que los
controles ausentes no produzcan error. Es que **la señal de error, produzca o no
el sistema, solo tiene valor si existe un observador**. Un error escrito en un log
no consultado y una ausencia de error son operativamente equivalentes. Por eso la
remediación propuesta no es mejorar el mensaje, sino añadir la comprobación
—healthcheck, monitorización con prueba negativa, y prueba de arranque en frío
como criterio de aceptación.

## Controles declarados, presentes y sin efecto

La Fase 6 acumula cuatro instancias de una variante difícil de detectar: el
control no está ausente, está presente y no hace nada.

| Control | Evidencia a favor de su existencia | Efecto real |
|---|---|---|
| Ancla `/etc/irisRootCACert.pem` (P1-6) | Declarado en el compose, visible en `docker inspect`, presente y legible en el contenedor | Ningún cliente TLS lo lee |
| `SECURITY_PASSWORD_SALT` (P1-8) | Declarado en `.env`, cargado en `configuration.py:283` | No se consume; el hashing es bcrypt |
| `MFA_ENABLED` (P1-9) | Variable documentada, interruptor en configuración, **registro de arranque que confirma su estado** | Solo aplica sobre base de datos vacía; inerte en despliegues existentes |
| `certificates/ldap/` (P0-C) | Montaje declarado, directorio presente en el contenedor | Vacío desde el primer arranque |

El tercero es el más peligroso: el sistema **informa activamente de que el control
está activo**. Un criterio de verificación basado en el registro de arranque
habría producido un falso positivo, y ese criterio fue efectivamente propuesto
durante esta auditoría antes de ser descartado.

En los cuatro casos, una auditoría documental los habría dado por correctos. El
primero incluso resiste la inspección del sistema de ficheros del contenedor.

## El auditor incurrió repetidamente en el error que audita

Esta auditoría cometió cinco errores de inferencia, todos del mismo tipo —
atribuir comportamiento a partir de una declaración visible sin comprobar el
comportamiento efectivo — y todos detectados por verificación posterior:

| Inferencia | Basada en | Realidad |
|---|---|---|
| El salt público comprometía los hashes | El nombre de la variable | No se consume; bcrypt con salt por contraseña |
| `enforce_mfa` sería un atributo de grupo | La existencia de tablas de grupos | Es columna de `server_settings`, ajuste global |
| La imagen prevé un usuario sin privilegios | Ficheros con uid 1000 en el contenedor | Son bind mounts del anfitrión; la imagen corre como root |
| `git check-ignore -v` indica exclusión por código de salida | Convención de códigos de salida | Con `-v`, el código refleja coincidencia de patrón, incluidos los de negación |
| `docker compose -f` carga el override | Comportamiento por defecto de Compose | `-f` desactiva el descubrimiento automático |

Dos tuvieron consecuencia operativa: el primero llevó a planificar la rotación
del salt como intervención de riesgo cuando era trivial; el quinto revirtió una
remediación ya cerrada.

El valor argumental es doble. Primero, refuerza la tesis en lugar de debilitarla:
el sesgo no depende de la competencia ni de la atención, sino de que **la
configuración es visible y el comportamiento no**. Segundo, demuestra que el
método propuesto funciona: los cinco errores fueron detectados por el propio
procedimiento de verificación, antes de causar daño irreversible.

Una auditoría que no puede equivocarse no está verificando nada.

## Remediación parcial que aparenta ser completa

P0-2 corrigió el certificado que el servicio presenta y documentó la corrección
con rigor. No corrigió el que el servicio declara confiar. Ambos son TLS, ambos
residen en el mismo directorio, y la verificación aplicada —`openssl s_client`,
`curl` sin `-k`, navegador sin aviso— solo podía observar el primero.

Una remediación verificada exclusivamente desde el exterior no puede detectar un
fallo en el interior. La verificación debe cubrir cada superficie que el control
pretende proteger, y eso exige enumerar antes qué superficies existen.

## La verificación produce más hallazgos que la búsqueda

Seis de los once P1 de esta fase —P1-6, P1-7, P1-8, P1-9, P1-10, P1-11— se
detectaron al comprobar que una remediación funcionaba, no al buscar defectos.

El patrón se repite: la comprobación de P0-C reveló que la CA no estaba en ningún
almacén (P1-6) y que la aplicación corre como root (P1-7); la de P0-E reveló que
el salt no se consume (P1-8); la investigación previa a activar MFA reveló que su
interruptor documentado es inerte (P1-9) y que solo existía una cuenta (P1-10); y
la verificación previa al commit, cuatro días después, reveló que la pila no
sobrevive a un reinicio del anfitrión (P1-11).

Sugiere que el esfuerzo de auditoría rinde más aplicado a verificar lo que se
cree correcto que a buscar lo que se sospecha incorrecto. La búsqueda está
limitada por lo que el auditor imagina; la verificación, no.

## Independencia del enclave: refutación empírica y corrección

El principio rector sostiene que el enclave debe permanecer operativo e íntegro
aunque la infraestructura corporativa esté comprometida. La Fase 6 lo refutaba en
su propio despliegue: el sistema que custodia el registro completo del incidente
era tomable con una única petición HTTP desde la red corporativa, mediante una
constante publicada en un repositorio público.

Las remediaciones cortan la cadena en sus dos eslabones, restituyen la PKI del
enclave como ancla de confianza declarada y funcional, y añaden segundo factor
obligatorio.

P1-11 añade una segunda dimensión al principio, ortogonal a la seguridad: la
**disponibilidad** del enclave. Un sistema que no converge a estado operativo tras
un reinicio no está disponible cuando se le necesita, con independencia de lo
robusto que sea su control de acceso.

El hallazgo no invalida el principio; documenta que **un principio arquitectónico
no se implementa por enunciarlo**, y que su verificación exige comprobar cada
servicio contra el modelo de amenaza y el escenario de fallo que el principio
define.

El patrón de exposición directa de puertos afecta a Velociraptor, OpenSearch
Dashboards y DFIR-IRIS. Los tres corresponden a pilas completas de terceros
incorporadas con su propio compose, frente a los servicios desplegados de forma
nativa tras Traefik. La hipótesis —que el compose de terceros arrastra sus
supuestos de publicación y estos sobreviven a la integración— es coherente con
los tres casos y merece contrastarse con el resto del despliegue antes de
sostenerla en la memoria.

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

La huella DER es el identificador canónico del certificado. El hash del fichero
acredita la integridad de la copia. Son valores distintos y no intercambiables.

Respaldos generados durante la remediación, **no versionables** (contienen
credenciales o datos de casos):

- `fase6-iris/.env.pre-p0-2` — previo a la corrección de certificado
- `fase6-iris/.env.pre-p0-e` — previo a la rotación de `IRIS_SECRET_KEY`
- `~/iris_db-pre-salt-20260904-0924.sql` — previo a la rotación del salt
- `~/iris_db-pre-mfa-20260904-1500.sql` — previo a la activación de MFA, con la
  cuenta `breakglass` ya creada (verificado)

---

# Anexo B — Verificación de estado

Reejecutable. **Debe ejecutarse desde `fase6-iris/` para las operaciones de
compose**, y tras cualquier recreación de contenedores o reinicio del anfitrión.

```bash
cd ~/tfm-alerta-temprana-oob

# P1-11 · los cinco contenedores operativos (PRIMERO: si nginx reinicia, lo demás no aplica)
docker ps -a --filter name=iriswebapp --format 'table {{.Names}}\t{{.Status}}'
docker network inspect iris_frontend --format '{{range .Containers}}{{.Name}} {{end}}'
# esperado: 5 contenedores Up; iris_frontend con app, nginx y rabbitmq

# P0-D · exposición (reejecutar tras CUALQUIER operación sobre nginx)
ss -tlnp | grep 4833                          # esperado: solo 100.64.0.1

# P0-E · ninguna constante pública en uso
for v in IRIS_SECRET_KEY IRIS_SECURITY_PASSWORD_SALT; do
  a=$(grep "^$v=" fase6-iris/.env       | cut -d= -f2-)
  m=$(grep "^$v=" fase6-iris/.env.model | cut -d= -f2-)
  [ "$a" = "$m" ] && echo "$v: DEFAULT PUBLICO — CORREGIR" || echo "$v: propio (len=${#a})"
done

# P0-C · ancla de confianza, inodo y validación funcional
docker exec iriswebapp_app openssl x509 -in /etc/irisRootCACert.pem \
  -noout -subject -fingerprint -sha256        # esperado: AB:11:4F:F8:...
docker exec iriswebapp_app ls -li /etc/irisRootCACert.pem   # esperado: nlink 1
docker exec iriswebapp_app openssl verify -CAfile /etc/irisRootCACert.pem \
  /home/iris/certificates/web_certificates/iris_oob_cert.pem

# P1-6 · bundle de confianza
docker exec iriswebapp_app python3 -c \
  "import ssl; print('CAs:', len(ssl.create_default_context().get_ca_certs()))"  # 151

# P1-9 · MFA efectivo (NO fiarse del registro de arranque)
docker exec iriswebapp_db psql -U postgres -d iris_db -tAc \
  'SELECT enforce_mfa FROM server_settings;'  # esperado: t

# P1-10 · cuentas y estado de enrolamiento
docker exec iriswebapp_db psql -U postgres -d iris_db -tAc \
  'SELECT "user", active, mfa_setup_complete FROM "user";'

# P2-3 · anclas públicas versionables, clave privada excluida
git add --dry-run fase6-iris/certificates/
git check-ignore fase6-iris/certificates/rootCA/irisRootCAKey.pem; echo "exit=$? (0=ignorado, ok)"

# P0-A · integración (esperado: sin salida hasta que se implemente)
grep -rn --include='*.json' --include='*.py' -iE 'iris\.oob|iriswebapp|/api/case|iris_api' \
  fase2-orquestador/ fase3-agentic/ fase5-orchestrator-api/

# Fusión efectiva del compose, ANTES de cualquier recreación
cd fase6-iris && docker compose config | grep -E 'CA_BUNDLE|100\.64\.0\.1'
```

# Anexo C — Procedimientos de recuperación

## Break-glass de MFA

Si el segundo factor deja de estar disponible en ambas cuentas:

```bash
cd ~/tfm-alerta-temprana-oob/fase6-iris
docker exec iriswebapp_db psql -U postgres -d iris_db -c \
  'UPDATE server_settings SET enforce_mfa = false;'
docker compose up -d --force-recreate app worker
```

La recreación es necesaria: un cambio directo en base de datos no refresca
`app.config` en ningún proceso. Tras recuperar el acceso, reenrolar y reactivar
`enforce_mfa` desde la interfaz.

## nginx en bucle de reinicio tras arranque en frío (P1-11)

Síntoma: `host not found in upstream "app"` repetido cada 60 segundos.

```bash
docker network inspect iris_frontend --format '{{range .Containers}}{{.Name}} {{end}}'
# si nginx no aparece:
cd ~/tfm-alerta-temprana-oob/fase6-iris
docker compose up -d --force-recreate app worker nginx
ss -tlnp | grep 4833
```

Ejecutar siempre desde `fase6-iris/`: con `-f` desde otro directorio, el override
no se carga y la restricción de puerto se pierde.

---

*Auditoría realizada el 3 de septiembre de 2026 sobre el despliegue en
producción, con remediación aplicada y verificada entre los días 3 y 5. Todos los
hallazgos están respaldados por evidencia observable y reejecutable. Cinco
conclusiones basadas en inferencia fueron detectadas y corregidas durante el
proceso; quedan documentadas en la sección de memoria.*
