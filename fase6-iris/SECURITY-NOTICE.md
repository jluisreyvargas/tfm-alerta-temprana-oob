# Aviso de seguridad — certificado de desarrollo en la interfaz de DFIR-IRIS (P0-2)

> [!NOTE]
> **Revisión de 4 de septiembre de 2026.** La auditoría completa de la Fase 6
> (3 de septiembre) reveló que esta remediación fue **parcial**: corrigió el
> certificado que el servicio presenta, pero no el que la aplicación declaraba
> confiar. Se corrigen tres imprecisiones del texto original y se añade un
> [addendum](#addendum--hallazgos-posteriores-3-de-septiembre-de-2026). Informe
> completo en [`docs/INFORME-AUDITORIA-FASE6.md`](../docs/INFORME-AUDITORIA-FASE6.md).

## Resumen

No hubo fuga. El material implicado era público por origen: la CA de desarrollo
que el proyecto DFIR-IRIS distribuye en su repositorio, y un certificado de hoja
firmado por ella. El problema es haber usado ese material en un despliegue: la
interfaz de IRIS de la Fase 6 se sirvió durante más de dos meses con una CA y un
certificado cuya clave privada es de acceso público, y que además estaba
caducado y no correspondía a ningún nombre del despliegue.

Material implicado (`fase6-iris/certificates/rootCA/`):

| Elemento | subject | Validez | SHA-256 |
|---|---|---|---|
| CA raíz de desarrollo de DFIR-IRIS | `C=FR, ST=Some-State, O=DFIR-IRIS, CN=DFIR-IRIS-Root-CA` | 2022-01-18 → 2032-01-16 | `12:74:5C:EF:8E:36:96:14:76:6A:4D:14:D8:8F:A7:96:D6:65:F6:37:90:6D:99:B3:C1:49:A8:06:40:63:70:A2` |

`ST=Some-State` es el valor por defecto de OpenSSL y la fecha de emisión es más
de cuatro años anterior al proyecto. La clave privada de esta CA nunca fue
secreta.

## Condición

Sin ventana de exposición en el sentido de P0-1: no es un secreto que estuviera
expuesto durante un intervalo, sino una configuración incorrecta que existió de
forma permanente desde el despliegue de la Fase 6 (26 de junio de 2026) hasta su
corrección (2 de septiembre de 2026).

## Impacto

El TLS de la interfaz no ofrecía ninguna garantía. Cualquiera con acceso al
segmento de red podía suplantar el servicio o descifrar la sesión, al disponer
de la clave privada del certificado. A esto se suma que el certificado que
servía nginx llevaba caducado desde diciembre de 2022 y que su `CN`
(`iris.app.dev`) no correspondía a ningún nombre del despliegue.

Certificado servido por nginx antes de la corrección, verificado en runtime
contra `localhost:4833`:

| subject | Validez | SHA-256 |
|---|---|---|
| `C=FR, ST=Ile de France, L=Paris, O=CSIRT-FR Airbus, OU=Incident Response, CN=iris.app.dev` | 2021-12-09 → 2022-12-09 (caducado) | `81:EA:5F:35:05:CD:1C:5C:3A:5E:0D:1E:5E:FC:15:0C:6F:90:2A:2C:D6:64:6C:52:FD:9F:CD:F8:A8:EA:3B:08` |

## Detección

Lo encontró `scripts/verify-no-secrets.sh` durante la remediación P0-1, al
marcar `fase6-iris/certificates/rootCA/irisRootCAKey.pem` como bloque PEM de
clave privada **presente en el árbol de trabajo**.

> [!NOTE]
> **Corrección (2026-09-04).** La versión original de este documento describía el
> fichero como «trackeado». La verificación posterior demuestra que nunca entró
> en el historial de git:
>
> ```
> $ git log --all --oneline --name-status -- 'fase6-iris/certificates/*'
> (sin salida)
> $ git rev-list --objects --all | grep -i 'irisRootCAKey\|iris_dev_key'
> sin rastro
> ```
>
> La detección se produjo sobre el árbol de trabajo, no sobre el repositorio. En
> consecuencia, **la Fase 6 no requiere purga de historial** (`git filter-repo`),
> a diferencia de la Fase 5.

El análisis posterior reclasificó el hallazgo: no era una fuga de clave del
proyecto, sino el uso de material de desarrollo ajeno cuya clave ya era pública.
La categoría pasó de fuga a problema de configuración.

## Corrección aplicada (2 de septiembre de 2026)

Certificado propio emitido para `iris.oob.local`, firmado por la CA del enclave:

| subject | issuer | Validez | SHA-256 |
|---|---|---|---|
| `C=ES, O=TFM Enclave OOB, OU=Seguridad, CN=iris.oob.local` | `C=ES, O=TFM Enclave OOB, OU=Seguridad, CN=OOB Enclave Root CA` | 2026-09-02 → 2028-12-05 | `EC:EF:1E:80:FE:E6:13:56:77:AB:69:DE:70:EC:76:37:26:9E:17:37:BA:B8:CF:88:84:2C:BC:2B:22:18:24:F6` |

SAN: `iris.oob.local`, `iris.local`, `localhost`, `127.0.0.1`, `192.168.127.138`.

- **Certificado.** Firmado por la CA del enclave, 825 días de validez — el
  límite que acepta un navegador moderno para una hoja TLS, coherente con
  `DAYS_LEAF` de `fase1-infraestructura/traefik/generate-oob-ca.sh`.
- **`.env`.** Cuatro variables, cinco líneas: `KEY_FILENAME`, `CERT_FILENAME`,
  `SERVER_NAME` (aparecía dos veces, en las líneas 7 y 45; bash toma la última)
  e `IRIS_ADM_EMAIL`. `SERVER_NAME` pasa de `iris.local` a `iris.oob.local`,
  alineándose con el resto del enclave.
- **Permisos.** Los certificados de desarrollo tenían modo `664` y propietario
  `jose jose`, legibles por cualquier usuario del host. Los nuevos son `444`/`400`
  con propietario `www-data` (UID 33, el usuario con el que corre nginx).
- **Árbol de trabajo.** Los certificados de desarrollo y la CA raíz de DFIR-IRIS
  se retiraron del árbol.
- **`.gitignore` de `fase1-infraestructura/`.** La regla `*.crt` excluía también
  `oob-rootCA.crt`, el único certificado que debe ser público: sin él, quien
  clone el repositorio no puede reconstruir la confianza del enclave. Se
  añadieron negaciones para `oob-rootCA.crt` y `*.cnf`. Las claves privadas
  siguen cubiertas por `*.key` y `*.pem`.

## Verificación

- `openssl s_client` contra `oob-rootCA.crt`: `Verify return code: 0 (ok)`.
- `curl` sin `-k` a la interfaz: `302`.
- Acceso desde el navegador del W11 sin aviso de certificado.

> [!IMPORTANT]
> **Limitación de esta verificación.** Las tres comprobaciones observan el
> servicio desde el exterior y solo pueden validar el certificado que nginx
> **presenta**. Ninguna podía detectar el estado del ancla de confianza que la
> aplicación **declara**, que siguió siendo la CA de desarrollo. Ver el addendum.

## Causa raíz

El certificado correcto existía desde el 24 de agosto de 2026:
`generate-oob-ca.sh` incluye `iris.oob.local` en el SAN del wildcard desde esa
fecha, y el certificado se emitió, se guardó y se documentó. DFIR-IRIS nunca lo
consumió porque `.env` seguía apuntando a `iris_dev_cert.pem`. Nadie verificó
que la configuración produjera el comportamiento previsto. El sistema informaba
del problema en cada acceso, mediante el aviso de certificado del navegador; un
aviso que aparece siempre deja de leerse.

---

# Addendum — hallazgos posteriores (3 de septiembre de 2026)

La auditoría completa de la Fase 6 identificó tres cuestiones que este documento
no cubría.

## 1 · El ancla de confianza siguió siendo la CA de desarrollo

La corrección retiró el material de desarrollo del árbol de trabajo, pero **no
lo sustituyó**. El montaje declarado en `docker-compose.base.yml`

```yaml
- ./certificates/rootCA/irisRootCACert.pem:/etc/irisRootCACert.pem:ro
```

quedó apuntando a una ruta inexistente en el anfitrión. Dentro del contenedor el
fichero seguía presente sobre un inodo huérfano:

```
7544864 -rw-rw-r-- 0 1000 1000 1976 Sep  2 15:14 /etc/irisRootCACert.pem
                   ↑
                   nlink = 0
```

El contador de enlaces a cero indica que el inodo no tenía ninguna entrada de
directorio: el fichero había sido eliminado del anfitrión y sobrevivía solo
porque el espacio de nombres de montaje del contenedor lo mantenía abierto. La
huella coincidía con la de la CA de desarrollo listada al inicio de este
documento.

En el siguiente reinicio, Docker habría creado un directorio vacío en su lugar y
la aplicación habría arrancado sin ancla declarada, sin emitir error.

**Corregido el 3 de septiembre**: `certificates/rootCA/irisRootCACert.pem` es
ahora la CA del enclave (`AB:11:4F:F8:…`), verificada dentro del contenedor por
huella y por validación funcional de un certificado del enclave.

## 2 · La clave de firma de sesión era una constante pública

`IRIS_SECRET_KEY` conservaba el valor de `.env.model`
(`AVerySuperSecretKey-SoNotThisOne`), publicado en el repositorio de DFIR-IRIS.
Es la clave con la que Flask firma la cookie de sesión: permitía fabricar una
sesión administrativa válida sin credenciales, sobre un servicio publicado
entonces en `0.0.0.0:4833` sin proxy inverso ni MFA.

Era el hallazgo de mayor gravedad de la fase y este documento no lo recogía: su
apartado de riesgos residuales identificaba la exposición del puerto, pero no la
clave.

**Corregido el 3 de septiembre**: `IRIS_SECRET_KEY` rotada, verificada por
cambio de la firma de la cookie. `IRIS_SECURITY_PASSWORD_SALT` rotada el 4 de
septiembre; la verificación del código muestra que esta variable se carga pero no
se consume — el hashing de contraseñas es bcrypt con salt por contraseña.

## 3 · La exposición del puerto, corregida

El apartado de riesgos residuales señalaba correctamente que la interfaz seguía
publicada en `0.0.0.0:4833`, fuera de Traefik y Authelia.

**Corregido el 3 de septiembre** mediante `docker-compose.override.yml`, que
restringe la publicación a `100.64.0.1` (tailnet) y elimina también el enlace
IPv6 heredado. El acceso desde `192.168.127.0/24` queda cortado.

Pendiente: MFA en el borde, sea el nativo de IRIS (TOTP/WebAuthn) o Authelia por
delante.

---

# Lección

La remediación P0-2 corrigió lo que el servicio **presenta** y no lo que el
servicio **confía**. Ambos son TLS, ambos residen en el mismo directorio, y la
verificación aplicada —tres comprobaciones desde el exterior— solo podía observar
el primero.

Una remediación verificada exclusivamente desde fuera no puede detectar un fallo
dentro. La verificación debe cubrir cada superficie que el control pretende
proteger, no solo la más visible.

Esta lección refuerza la causa raíz ya identificada en el apartado
correspondiente, y la extiende: no basta con verificar que la configuración
produce el comportamiento previsto en el punto observado; hay que enumerar antes
qué puntos observar.
