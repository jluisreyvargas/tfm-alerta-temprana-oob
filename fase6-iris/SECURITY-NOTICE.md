# Aviso de seguridad — certificado de desarrollo en la interfaz de DFIR-IRIS (P0-2)

## Resumen

No hubo fuga. El material implicado era público por origen: la CA de desarrollo
que el proyecto DFIR-IRIS distribuye en su repositorio, y un certificado de hoja
firmado por ella. El problema es haber usado ese material en un despliegue: la
interfaz de IRIS de la Fase 6 se sirvió durante más de dos meses con una CA y un
certificado cuya clave privada es de acceso público, y que además estaba
caducado y no correspondía a ningún nombre del despliegue.

Ficheros implicados en el repositorio (`fase6-iris/certificates/rootCA/`):

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
clave privada trackeado. El análisis posterior reclasificó el hallazgo: no era
una fuga de clave del proyecto, sino el uso de material de desarrollo ajeno cuya
clave ya era pública. La categoría pasó de fuga a problema de configuración.

## Corrección

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

## Causa raíz

El certificado correcto existía desde el 24 de agosto de 2026:
`generate-oob-ca.sh` incluye `iris.oob.local` en el SAN del wildcard desde esa
fecha, y el certificado se emitió, se guardó y se documentó. DFIR-IRIS nunca lo
consumió porque `.env` seguía apuntando a `iris_dev_cert.pem`. Nadie verificó
que la configuración produjera el comportamiento previsto. El sistema informaba
del problema en cada acceso, mediante el aviso de certificado del navegador; un
aviso que aparece siempre deja de leerse.

## Riesgos residuales

La interfaz de IRIS sigue publicada directamente en `0.0.0.0:4833`, sin Traefik
ni Authelia por delante, a diferencia de los servicios de las Fases 1 a 4. El
cambio de P0-2 corrige el certificado, no la exposición del puerto ni la
ausencia de autenticación en el borde.

## Alcance limitado

Ningún componente del proyecto consumía IRIS por API. La nota de la Fase 5 para
DFIR-IRIS está preparada pero no automatizada, así que el cambio de
`SERVER_NAME` no rompió ninguna integración.
