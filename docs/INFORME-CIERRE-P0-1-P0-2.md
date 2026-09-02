# Informe de cierre — P0-1 y P0-2

Las dos remediaciones técnicas (rotación de PKI de Velociraptor y sustitución del
certificado de desarrollo de DFIR-IRIS) estaban completas y verificadas antes de
esta sesión. Aquí se documenta el cierre: los avisos de seguridad, la corrección
de nombre de host en la Fase 6 y el ajuste de un falso positivo del detector de
secretos. No se ha aplicado ningún cambio de git ni se ha tocado el índice.

## 1. Ficheros creados y modificados

### Creados

| Fichero | Justificación |
|---|---|
| `fase6-iris/SECURITY-NOTICE.md` | Aviso de incidente P0-2, mismo formato que el de la Fase 5: resumen, condición, impacto, detección, corrección (tabla antes/después con huellas SHA-256), verificación, causa raíz, riesgos residuales. |
| `docs/INFORME-CIERRE-P0-1-P0-2.md` | Este informe. |

### Modificados en esta sesión

| Fichero | Justificación |
|---|---|
| `docs/README-Fase6a.md` | `iris.local` → `iris.oob.local` en las cinco líneas donde aparecía (tabla de variables, URL de acceso, validación). La explicación del `/etc/hosts` refleja ahora el estado real: ambos nombres resuelven a `127.0.0.1` en el host Ubuntu, y `iris.oob.local` se añadió también al `/etc/hosts` de W11 y DC01-TFM apuntando a `192.168.127.138`. Nota al inicio remitiendo a `fase6-iris/SECURITY-NOTICE.md`. |
| `fase6-iris/README.md` | URL de acceso a la interfaz: `https://<HOST>:4833` → `https://iris.oob.local:4833`. Aviso al inicio remitiendo a `SECURITY-NOTICE.md`. |
| `fase5-velociraptor/SECURITY-NOTICE.md` | Completados los marcadores de la ventana de exposición (introducido el 2026-06-21 en el commit `1149702`, contenido el 1 de septiembre de 2026, ~72 días). Añadidas las huellas SHA-256 de la CA anterior y la nueva, el comportamiento de reinscripción y el resultado de la purga (135 → 133 commits, pack de ~60,9 MB a 22,45 MiB). Dos secciones nuevas: «Hallazgos de enumeración durante la remediación» (el remoto `backup` no contemplado y los objetos huérfanos accesibles por SHA en GitHub) y «Hallazgo secundario sin remediar» (`security.certificate_validity_days: 730` sin efecto; certificados a 365 días que caducan el 1 de septiembre de 2027). |
| `scripts/verify-no-secrets.sh` | La regla `nonce` exigía solo la palabra seguida de cualquier carácter, lo que marcaba dos líneas de prosa (`fase3-agentic/README.md:407` y `fase5-velociraptor/INFORME-P0-1.md:114`). Ahora exige `nonce:` seguido de una cadena de al menos 16 caracteres base64 o hexadecimales. No se han añadido esos ficheros a ninguna lista de exclusión. Comprobado que la nueva forma sigue detectando un `nonce` real (base64 o hex, entre comillas o sin ellas). |

### Modificados por la remediación técnica, presentes en el árbol pero no tocados en esta sesión

| Fichero | Estado |
|---|---|
| `.gitignore` | Bloque «Fase 6 · DFIR-IRIS» añadido: `fase6-iris/certificates/rootCA/` y `fase6-iris/certificates/web_certificates/`. |
| `fase1-infraestructura/.gitignore` | Negaciones `!traefik/certs/oob-rootCA.crt` y `!traefik/certs/*.cnf`, para que el certificado público de la CA del enclave sí se pueda versionar sin exponer las claves privadas (`*.key`, `*.pem` siguen cubiertos). |
| `fase1-infraestructura/traefik/certs/` (sin trackear) | Material de la rotación P0-2: `iris-oob.crt`, `iris-oob.key`, `iris.cnf`, `oob-rootCA.{crt,key,srl}`, `oob-wildcard.{crt,key}`. Las claves privadas están ignoradas (`!!`); `oob-rootCA.crt` e `iris.cnf` quedan pendientes de `git add` como material público. |

## 2. Salida de `verify-no-secrets.sh` tras el ajuste

```
$ ./scripts/verify-no-secrets.sh

OK: 0 hallazgos sobre 1749 ficheros trackeados.
$ echo $?
0
```

El detector pasa en verde. Antes del ajuste reportaba `FALLO: 2 hallazgos` —los
dos falsos positivos de prosa—; el material real de Velociraptor ya no estaba en
el árbol tras la purga.

## 3. Apariciones de `iris.local` que quedan en el repositorio

| Ruta | Motivo de conservarla |
|---|---|
| `docs/README-Fase6a.md:84` | Deliberado. Documenta que el `/etc/hosts` del host Ubuntu conserva `iris.local` junto a `iris.oob.local`, ambos a `127.0.0.1`, por compatibilidad. Refleja el estado real del despliegue. |
| `fase6-iris/source/app/blueprints/case/templates/case_assets.html` (2) | Código vendorizado de DFIR-IRIS. Datos de ejemplo del CSV de importación de activos («Computer of Mme Michu», «Xcas server»). No es configuración del proyecto. |
| `fase6-iris/source/app/iris_engine/demo_builder.py` (4) | Código vendorizado. Correos de usuarios de demostración (`{username}@iris.local`) que genera el constructor de datos de demo de IRIS. |
| `fase6-iris/source/app/static/assets/js/iris/case.asset.js` (2) | Código vendorizado. El mismo CSV de ejemplo que `case_assets.html`, embebido en el JS de la interfaz. |

Las ocho apariciones en `fase6-iris/source/` pertenecen al árbol vendorizado de
DFIR-IRIS y no se tocan: modificarlas divergiría del upstream sin ganancia.

## 4. Acciones pendientes para el usuario, en orden

1. **Revisar los cambios.** `git diff` sobre los cuatro ficheros modificados en
   esta sesión, los dos `SECURITY-NOTICE.md` y la regla nueva de
   `verify-no-secrets.sh`.
2. **Preparar el commit de cierre.** Añadir a mano la parte de documentación (los
   cuatro modificados y los dos nuevos) junto con la parte técnica ya en el
   árbol: `.gitignore`, `fase1-infraestructura/.gitignore`, y como material
   público `fase1-infraestructura/traefik/certs/oob-rootCA.crt` y
   `fase1-infraestructura/traefik/certs/iris.cnf`. **No** añadir ningún `.key`
   ni `.pem`.
3. **Aplicar el commit** manualmente.
4. **Confirmar el estado de los remotos de P0-1.** Por el hallazgo de objetos
   huérfanos, el cierre exige que los dos repositorios de GitHub se hayan
   borrado y recreado; comprobar que el commit `4cfd84c` devuelve `404` por SHA
   directo en ambos.
5. **Anotar la renovación pendiente.** Los certificados de frontend y GUI de
   Velociraptor caducan el 1 de septiembre de 2027 (hallazgo secundario de
   P0-1, sin remediar). El TLS de IRIS caduca el 5 de diciembre de 2028.

## Nota

`fase5-velociraptor/INFORME-P0-1.md`, sección 3, contiene una previsión que ha
quedado desfasada: anticipaba que `verify-no-secrets.sh` seguiría reportando dos
hallazgos tras la purga (la clave de la CA de IRIS y el falso positivo de
`fase3-agentic/README.md`). El primero se purgó y quedó excluido por `.gitignore`
en P0-2; el segundo lo resuelve el ajuste de la regla de esta sesión. El detector
pasa ahora en verde. Se deja como observación, sin modificar ese informe.
