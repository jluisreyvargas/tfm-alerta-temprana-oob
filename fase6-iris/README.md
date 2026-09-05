# 📊 Fase 6 · DFIR-IRIS — Gestión de casos

> [!NOTE]
> **🎯 Objetivo de la fase**
> Desplegar DFIR-IRIS v2.4.27 dentro del enclave OOB y validar que soporta el
> ciclo de vida completo de un caso de incidente: creación, evidencias, línea
> temporal y cierre.

> [!IMPORTANT]
> **Alcance real de esta fase.** El ciclo de caso está **validado manualmente**.
> La automatización desde el orquestador **no está implementada**: ningún
> componente de las Fases 2, 3 o 5 consume la API de IRIS. La API key está
> aprovisionada y el procedimiento documentado, pero no hay integración
> programática. Ver [Estado](#-estado) y [Trabajo futuro](#-trabajo-futuro).

> [!WARNING]
> Esta fase fue auditada el 3 de septiembre de 2026 con cinco hallazgos P0.
> Tres están corregidos, uno mitigado y dos permanecen abiertos.
> Ver [`docs/INFORME-AUDITORIA-FASE6.md`](../docs/INFORME-AUDITORIA-FASE6.md)
> y [`SECURITY-NOTICE.md`](SECURITY-NOTICE.md).

---

## 📑 Índice

- [Estado](#-estado)
- [Arquitectura desplegada](#-arquitectura-desplegada)
- [Servicios](#-servicios)
- [Configuración](#-configuración)
- [Certificados y PKI](#-certificados-y-pki)
- [Validación realizada](#-validación-realizada)
- [Seguridad](#-seguridad)
- [Trabajo futuro](#-trabajo-futuro)
- [Documentación relacionada](#-documentación-relacionada)

---

## 📌 Estado

### Implementado y verificado

- [x] 🐳 DFIR-IRIS v2.4.27 desplegado en Docker (5 contenedores)
- [x] 🔐 Certificado de servidor emitido por la CA del enclave
- [x] 🌐 Acceso web funcional en `https://iris.oob.local:4833`
- [x] 🔑 API key administrativa aprovisionada
- [x] 📝 Creación de caso validada manualmente
- [x] 📦 Nota de evidencia registrada manualmente
- [x] 📅 Evento de línea temporal registrado manualmente
- [x] 🔒 Publicación restringida al tailnet (`100.64.0.1`)

### No implementado

- [ ] ⚙️ Creación automática de caso al abrir incidente
- [ ] 🔗 Sincronización bidireccional por webhooks IRIS ↔ Orquestador
- [ ] 📤 Adición programática de evidencias y artefactos
- [ ] 🕐 Línea temporal alimentada automáticamente
- [ ] ✅ Cierre de caso con revocación automática de accesos
- [ ] 🛡️ Publicación tras Traefik con Authelia (MFA en el borde)

> [!NOTE]
> La ausencia de automatización es verificable:
> ```bash
> grep -rn --include='*.json' --include='*.py' -iE 'iris\.oob|iriswebapp|/api/case' \
>   fase2-orquestador/ fase3-agentic/ fase5-orchestrator-api/
> ```
> El flujo de n8n registra el estado `manual_case_created`, sin llamada HTTP a
> IRIS.

---

## 🏗️ Arquitectura desplegada

```text
                    tailnet 100.64.0.0/10
                            │
                            ▼
                  ┌───────────────────┐
                  │  iriswebapp_nginx │  100.64.0.1:4833 (TLS)
                  └─────────┬─────────┘
                            │  iris_frontend
                  ┌─────────▼─────────┐
                  │  iriswebapp_app   │  gunicorn :8000
                  └────┬─────────┬────┘
                       │         │  iris_backend
          ┌────────────▼──┐   ┌──▼──────────────────┐
          │ iriswebapp_db │   │ iriswebapp_rabbitmq │
          │ PostgreSQL    │   │ AMQP                │
          └───────────────┘   └──────────┬──────────┘
                                         │
                              ┌──────────▼──────────┐
                              │ iriswebapp_worker   │
                              │ Celery              │
                              └─────────────────────┘

Red adicional: oob-network (externa, compartida con el resto del enclave)
```

---

## 🐳 Servicios

Definidos en `docker-compose.yml` + `docker-compose.base.yml` (vendorizados de
DFIR-IRIS) y `docker-compose.override.yml` (propio del proyecto).

| Contenedor | Imagen | Redes | Puertos |
|---|---|---|---|
| `iriswebapp_nginx` | `ghcr.io/dfir-iris/iriswebapp_nginx:v2.4.27` | `iris_frontend`, `oob-network` | `100.64.0.1:4833` |
| `iriswebapp_app` | `ghcr.io/dfir-iris/iriswebapp_app:v2.4.27` | `iris_backend`, `iris_frontend`, `oob-network` | — |
| `iriswebapp_worker` | `ghcr.io/dfir-iris/iriswebapp_app:v2.4.27` | `iris_backend`, `oob-network` | — |
| `iriswebapp_db` | `ghcr.io/dfir-iris/iriswebapp_db:v2.4.27` | `iris_backend`, `oob-network` | — |
| `iriswebapp_rabbitmq` | `rabbitmq:3-management-alpine` ⚠️ | `iris_backend`, `iris_frontend`, `oob-network` | — |

> [!WARNING]
> ⚠️ `rabbitmq:3-management-alpine` usa etiqueta flotante (hallazgo P1-3).
> Pendiente de fijar versión, junto con el resto de servicios del proyecto.

### Override propio

`docker-compose.override.yml` restringe la publicación del puerto al tailnet.
Sin él, nginx escucharía en `0.0.0.0` y `[::]`, alcanzable desde la red
corporativa (hallazgo P0-D, corregido):

```yaml
services:
  nginx:
    ports: !override
      - "100.64.0.1:${INTERFACE_HTTPS_PORT:-443}:${INTERFACE_HTTPS_PORT:-443}"
```

> [!CAUTION]
> Si la interfaz del tailnet no está activa al arrancar, Docker fallará al
> enlazar el puerto y el contenedor no subirá. Verificar antes:
> ```bash
> ip a show | grep 100.64.0.1
> ```

---

## ⚙️ Configuración

Variables en `.env` (no versionado). Plantilla en
[`.env.example`](.env.example).

| Grupo | Variables | Notas |
|---|---|---|
| Imágenes | `*_IMAGE_NAME`, `*_IMAGE_TAG` | Fijadas a `v2.4.27` |
| Base de datos | `POSTGRES_*` | Credenciales propias, no las de la plantilla upstream |
| Aplicación | `IRIS_SECRET_KEY`, `IRIS_SECURITY_PASSWORD_SALT` | Ver aviso siguiente |
| Autenticación | `IRIS_AUTHENTICATION_TYPE=local`, `IRIS_ADM_*` | Autenticación local, sin LDAP ni OIDC |
| Red | `SERVER_NAME=iris.oob.local`, `INTERFACE_HTTPS_PORT=4833` | |
| TLS | `KEY_FILENAME`, `CERT_FILENAME` | Certificado del enclave |

> [!CAUTION]
> **`IRIS_SECURITY_PASSWORD_SALT` conserva el valor de la plantilla upstream**
> (hallazgo P0-E, pendiente). Su rotación invalida todos los hashes de
> contraseña existentes, incluido el de `administrator`, y requiere un
> procedimiento de reseteo validado previamente. `IRIS_SECRET_KEY` sí fue
> rotada el 3 de septiembre de 2026.

### Despliegue

```bash
cd fase6-iris
cp .env.example .env      # completar los valores marcados
docker compose up -d
```

Para aplicar cambios de configuración se usa `--force-recreate`, no `restart`:
un `restart` conserva la configuración con la que se creó el contenedor.

```bash
docker compose up -d --force-recreate app worker nginx
```

---

## 🔐 Certificados y PKI

Tres montajes de certificados en `app` y `worker`:

| Origen | Destino | Función |
|---|---|---|
| `certificates/rootCA/irisRootCACert.pem` | `/etc/irisRootCACert.pem` | Ancla de confianza declarada |
| `certificates/` | `/home/iris/certificates/` | Certificados accesibles a la aplicación |
| `certificates/ldap/` | `/iriswebapp/certificates/ldap/` | Certificados LDAP (sin uso: autenticación local) |

Adicionalmente, nginx monta `certificates/web_certificates/` con el par
`iris_oob_cert.pem` / `iris_oob_key.pem`.

### Estado de la PKI

- ✅ **Certificado de servidor**: emitido para `iris.oob.local`, firmado por la
  CA del enclave. Verificable con:
  ```bash
  openssl verify -CAfile ../fase1-infraestructura/traefik/certs/oob-rootCA.crt \
    certificates/web_certificates/iris_oob_cert.pem
  ```
- ✅ **Ancla de confianza**: `oob-rootCA.crt` del enclave, desde el 3 de
  septiembre de 2026. Anteriormente era la CA de desarrollo pública de DFIR-IRIS
  (hallazgo P0-C, corregido).
- ⚠️ **Almacenes de confianza del sistema**: la CA del enclave **no** está
  instalada en `/etc/ssl/certs/` ni referenciada por `REQUESTS_CA_BUNDLE`. Los
  clientes TLS de la aplicación no la usan por defecto (hallazgo P1-6,
  pendiente).

> [!CAUTION]
> Los directorios de origen de los bind mounts deben existir antes de arrancar.
> Si faltan, Docker los crea como directorios vacíos propiedad de `root`, sin
> emitir error, y la aplicación arranca sin el control correspondiente. Este
> comportamiento se materializó dos veces en esta fase y está documentado en el
> informe de auditoría.

---

## ✅ Validación realizada

Ejecutada manualmente a través de la interfaz web. Detalle completo en
[`docs/README-Fase6b.md`](../docs/README-Fase6b.md).

| Elemento | Método | Resultado |
|---|---|---|
| Creación de caso | Interfaz web | ✅ Caso creado con metadatos del incidente |
| Nota de evidencia | Interfaz web | ✅ Registrada con hash SHA-256 del artefacto |
| Evento de línea temporal | Interfaz web | ✅ Registrado con marca temporal |
| API key | Interfaz web | ✅ Aprovisionada para la cuenta administrativa |
| Acceso TLS | Navegador desde W11 (`100.64.0.4`) | ✅ Sin aviso de certificado |

### Verificación del estado tras la remediación

```bash
# Ancla de confianza — esperado: CN = OOB Enclave Root CA
docker exec iriswebapp_app openssl x509 -in /etc/irisRootCACert.pem \
  -noout -subject -fingerprint -sha256

# Validación funcional del ancla
docker exec iriswebapp_app openssl verify -CAfile /etc/irisRootCACert.pem \
  /home/iris/certificates/web_certificates/iris_oob_cert.pem

# Exposición — esperado: solo 100.64.0.1
ss -tlnp | grep 4833
```

---

## ⚠️ Seguridad

### Corregido (2026-09-03)

| ID | Hallazgo |
|---|---|
| P0-C | Ancla de confianza era la CA de desarrollo pública de DFIR-IRIS, sobre un inodo huérfano |
| P0-D | Servicio publicado en `0.0.0.0:4833` y `[::]:4833`, sin proxy inverso ni MFA |
| P0-E (parcial) | `IRIS_SECRET_KEY` era una constante pública → forja de cookie de sesión administrativa |

### Pendiente

| ID | Hallazgo | Prioridad |
|---|---|---|
| P0-E | `IRIS_SECURITY_PASSWORD_SALT` sigue siendo la constante pública | Alta — requiere ventana |
| P1-6 | CA del enclave fuera de los almacenes de confianza del contenedor | Media |
| P1-7 | La aplicación se ejecuta como `root` dentro del contenedor | Media |
| P0-D | Publicación tras Traefik con Authelia | Media |
| P1-1 | 483 636 líneas vendorizadas sin `NOTICE` de licencia LGPL-3.0 | Baja |

### Consideraciones de diseño

- 🔐 Credenciales en `.env`, fuera del control de versiones
- 🔒 Autenticación local; sin dependencia de Active Directory corporativo,
  coherente con el principio de independencia del enclave
- 📝 Auditoría interna: cada evento del caso queda registrado con marca temporal
- 🗂️ Evidencias en modo append: se añaden, no se modifican

---

## 🚀 Trabajo futuro

1. **Rotación de `IRIS_SECURITY_PASSWORD_SALT`** con procedimiento de reseteo
   validado sobre copia de la base de datos.
2. **Integración programática** desde el orquestador, usando la API key
   aprovisionada: creación de caso, evidencias, línea temporal y cierre. Es el
   trabajo que el estado actual de la fase deja preparado pero no ejecutado.
3. **Publicación tras Traefik con Authelia**, alineando la fase con los
   servicios de las Fases 1 a 4.
4. **Instalación de la CA del enclave** en los almacenes de confianza del
   contenedor, con bundle concatenado para no romper la verificación de
   destinos externos.
5. **Ejecución sin privilegios** (`user:` en el override), previa prueba.

---

## 📚 Documentación relacionada

| Documento | Contenido |
|---|---|
| [`docs/README-Fase6a.md`](../docs/README-Fase6a.md) | Despliegue, configuración y API key |
| [`docs/README-Fase6b.md`](../docs/README-Fase6b.md) | Validación del caso y trazabilidad |
| [`docs/INFORME-AUDITORIA-FASE6.md`](../docs/INFORME-AUDITORIA-FASE6.md) | Auditoría de seguridad completa |
| [`SECURITY-NOTICE.md`](SECURITY-NOTICE.md) | Aviso de certificado de desarrollo (P0-2) |
| [`README-Iris.md`](README-Iris.md) | README original de DFIR-IRIS (upstream) |

> [!NOTE]
> El código bajo `fase6-iris/source/`, `docker/`, `deploy/`, `tests/` y
> `upgrades/` es DFIR-IRIS v2.4.27 vendorizado sin modificaciones, licenciado
> bajo LGPL-3.0. Los únicos ficheros propios del proyecto son este `README.md`,
> `SECURITY-NOTICE.md`, `.env.example` y `docker-compose.override.yml`.
