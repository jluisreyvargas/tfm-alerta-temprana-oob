# 📊 Fase 6 · DFIR-IRIS — Gestión de casos

> [!NOTE]
> **🎯 Objetivo de la fase**
> Desplegar DFIR-IRIS como sistema de gestión de casos del enclave OOB y validar
> que el ciclo completo de un incidente —caso, evidencias, línea temporal y
> cierre— es registrable con trazabilidad íntegra.

> [!IMPORTANT]
> **Alcance real de esta fase.** El despliegue está operativo y el ciclo de vida
> del caso ha sido **validado manualmente** (ver
> [`docs/README-Fase6b.md`](../docs/README-Fase6b.md)). La automatización de la
> integración con el orquestador **no está implementada**: la API key está
> aprovisionada y el procedimiento documentado, pero ningún componente del
> proyecto consume la API de IRIS. Ver [Trabajo futuro](#-trabajo-futuro).

> [!WARNING]
> Esta fase fue auditada el 3 de septiembre de 2026: cinco hallazgos P0, once P1
> y cuatro P2. Los cinco P0 están corregidos y verificados por comportamiento.
> Ver [`docs/INFORME-AUDITORIA-FASE6.md`](../docs/INFORME-AUDITORIA-FASE6.md) y
> [`SECURITY-NOTICE.md`](SECURITY-NOTICE.md).

---

## 📋 Estado

### Implementado y validado

- [x] 🐳 DFIR-IRIS v2.4.27 desplegado en Docker (5 contenedores)
- [x] 🔐 Certificado propio para `iris.oob.local`, firmado por la CA del enclave
- [x] 🔑 Ancla de confianza del enclave en la aplicación, con validación funcional
- [x] 📜 Bundle TLS saliente: 150 CAs públicas + CA del enclave
- [x] 🌐 Publicación restringida al tailnet (`100.64.0.1:4833`)
- [x] 🛡️ MFA obligatorio (TOTP), con cuenta de acceso de emergencia
- [x] 🔁 Arranque en frío determinista mediante unidad systemd
- [x] ✅ Script de verificación con 16 comprobaciones de comportamiento
- [x] 📝 Creación de caso y registro de evidencia — **validado manualmente**
- [x] 📅 Evento de línea temporal — **validado manualmente**
- [x] 🗝️ API key administrativa aprovisionada

### No implementado

- [ ] 🔗 Creación automática de caso desde el orquestador
- [ ] 🔄 Sincronización bidireccional por webhooks
- [ ] 📦 Adición automática de evidencias (Velociraptor, RustDesk, KVM)
- [ ] ✅ Cierre de caso con revocación automática de accesos
- [ ] 📈 Dashboard de métricas operacionales (Fase 7)

---

## 🏗️ Arquitectura desplegada

```text
                    tailnet 100.64.0.0/10
                            │
                    ┌───────▼────────┐
                    │  nginx :4833   │  iris_frontend
                    │  TLS enclave   │
                    └───────┬────────┘
                            │
              ┌─────────────▼─────────────┐
              │      app (gunicorn)       │  iris_frontend
              │      DFIR-IRIS v2.4.27    │  iris_backend
              └──────┬─────────────┬──────┘  oob-network
                     │             │
          ┌──────────▼───┐   ┌─────▼────────┐
          │  worker      │   │  rabbitmq    │  iris_backend
          │  (celery)    │◀──│  (broker)    │
          └──────┬───────┘   └──────────────┘
                 │
          ┌──────▼───────┐
          │  db          │  iris_backend
          │  PostgreSQL  │  oob-network
          └──────────────┘
```

---

## 🐳 Despliegue

### Estructura de ficheros compose

| Fichero | Origen | Función |
|---|---|---|
| `docker-compose.base.yml` | Upstream | Servicios, volúmenes y redes |
| `docker-compose.yml` | Upstream, adaptado | Imágenes fijadas en `v2.4.27`, adhesión a `oob-network` |
| `docker-compose.override.yml` | **Propio** | Puerto restringido al tailnet, bundle TLS, healthcheck, `rabbitmq` fijado |
| `.env` | Propio, no versionado | Credenciales y parámetros. Plantilla en `.env.example` |
| `systemd/tfm-fase6-iris.service` | **Propio** | Arranque en frío determinista |

El compose upstream no se modifica: las adaptaciones del enclave viven en el
override.

> [!CAUTION]
> **Ejecutar siempre desde `fase6-iris/`, nunca con `docker compose -f` desde
> otro directorio.** Compose carga `docker-compose.override.yml` automáticamente
> solo cuando descubre los ficheros por sí mismo. Con `-f` explícito el override
> queda fuera **sin emitir aviso**, y el servicio se recrea con la configuración
> de `base.yml` — lo que revierte la restricción de puerto y el bundle TLS.
> Ocurrió durante la remediación (ver informe, P0-D).
>
> Verificación previa a cualquier recreación:
> ```bash
> docker compose config | grep -E 'CA_BUNDLE|100\.64\.0\.1|service_healthy'
> ```

### Arranque

Normalmente no hace falta: la unidad systemd levanta la pila al arrancar el
anfitrión. Manualmente:

```bash
cd fase6-iris
docker compose up -d --wait
```

Tras cambiar `.env` o los montajes hace falta **recreación**, no reinicio:

```bash
docker compose up -d --force-recreate app worker nginx
```

> [!WARNING]
> **Dependencia de arranque.** El enlace a `100.64.0.1` requiere que la interfaz
> del tailnet esté activa. La unidad systemd ordena respecto a
> `tailscaled.service`; en arranque manual, comprobar antes:
> ```bash
> ip a show tailscale0 | grep 100.64.0.1
> ```

---

## ✅ Verificación

`scripts/verify-fase6.sh` comprueba 16 condiciones de **comportamiento
observable**: estado de los cinco contenedores, pertenencia a `iris_frontend`,
exposición del puerto, ancla de confianza y su validación funcional, tamaño del
bundle TLS, ausencia de constantes públicas en `.env`, MFA efectivo en base de
datos y número de cuentas enroladas.

```bash
./scripts/verify-fase6.sh   # 0 = todo OK, 1 = alguna comprobación falla
```

Ejecutar tras cualquier recreación de contenedores, tras un reinicio del
anfitrión y antes de cada commit que toque la fase.

Tres detecciones han sido acreditadas con prueba negativa —desconectando nginx de
la red, desactivando `enforce_mfa` y restituyendo la clave pública de upstream—,
comprobando en cada caso que el script devuelve `1` y vuelve a `0` al restaurar.

> [!NOTE]
> El script consulta la base de datos para el estado de MFA, **no el registro de
> arranque**. `MFA_ENABLED` en `.env` solo tiene efecto al inicializar una base
> de datos vacía; en un despliegue existente es inerte, y el log de arranque
> informaría de `MFA enabled` aunque el segundo factor no se estuviera exigiendo
> (ver informe, P1-9).

---

## ⚙️ Configuración

`.env` no se versiona. Copiar desde [`.env.example`](.env.example), que lleva las
variables de credencial vacías a propósito.

| Variable | Notas |
|---|---|
| `SERVER_NAME` | `iris.oob.local`. Debe aparecer una sola vez |
| `CERT_FILENAME` / `KEY_FILENAME` | Firmados por la CA del enclave; clave en modo `400`, propietario `www-data` |
| `INTERFACE_HTTPS_PORT` | `4833`. El override lo publica en `100.64.0.1` |
| `*_IMAGE_TAG` | `v2.4.27`. `rabbitmq` fijado a `3.13.7-management-alpine` en el override |
| `IRIS_SECRET_KEY` | `openssl rand -base64 48`. Firma la cookie de sesión de Flask |
| `IRIS_SECURITY_PASSWORD_SALT` | Residual: se carga pero **no se consume**. El hashing es bcrypt con salt por contraseña |
| `IRIS_AUTHENTICATION_TYPE` | `local`. Sin LDAP: el enclave no depende del AD corporativo |
| `IRIS_ADM_PASSWORD` | Comentada. Solo se aplica al inicializar una BD vacía |

> [!CAUTION]
> Los valores de `.env.model` (`AVerySuperSecretKey-SoNotThisOne`,
> `ARandomSalt-NotThisOneEither`) son constantes publicadas en el repositorio de
> DFIR-IRIS. `IRIS_SECRET_KEY` firma la cookie de sesión: dejarla con el valor
> por defecto permite falsificar una sesión administrativa sin credenciales.
> `verify-fase6.sh` lo comprueba en cada ejecución.

### PKI

CA del enclave: `fase1-infraestructura/traefik/certs/oob-rootCA.crt`
(`CN=OOB Enclave Root CA`).

| Ruta | Contenido |
|---|---|
| `certificates/web_certificates/iris_oob_cert.pem` | Certificado de servidor. SAN: `iris.oob.local`, `iris.local`, `localhost`, `127.0.0.1`, `192.168.127.138` |
| `certificates/web_certificates/iris_oob_key.pem` | Clave privada. No versionada |
| `certificates/rootCA/irisRootCACert.pem` | Ancla de confianza = CA del enclave |
| `certificates/rootCA/ca-bundle-oob.crt` | 150 CAs públicas + CA del enclave, para TLS saliente |
| `certificates/ldap/` | Vacío. Debe existir: si falta, Docker lo crea como `root` |

> [!IMPORTANT]
> Los directorios bajo `certificates/` **deben existir antes de arrancar**. Un
> bind mount cuyo origen no existe no produce error: Docker crea un directorio
> vacío propiedad de root y el servicio arranca sin el material. Este mecanismo
> dejó la aplicación confiando en la CA de desarrollo pública de DFIR-IRIS
> durante más de dos meses (ver informe, P0-C).

---

## 🌐 Acceso

`https://iris.oob.local:4833` desde el tailnet, con usuario, contraseña y TOTP.

Requiere `oob-rootCA.crt` en el almacén de confianza del cliente y que
`iris.oob.local` resuelva a `100.64.0.1`.

Cuentas: `administrator` (operación) y `breakglass` (emergencia, credencial
custodiada por separado). Ambas con MFA enrolado.

---

## 🔑 API key

La cuenta administrativa dispone de API key, aceptada como token Bearer en la
cabecera `Authorization`. Aprovisionada y documentada en
[`docs/README-Fase6a.md`](../docs/README-Fase6a.md).

**Ningún componente del proyecto la consume actualmente.**

---

## 🚨 Procedimientos de recuperación

### MFA no disponible en ambas cuentas

Si se pierde el dispositivo de segundo factor y ninguna cuenta puede completar el
login:

```bash
cd fase6-iris
docker exec iriswebapp_db psql -U postgres -d iris_db -c \
  'UPDATE server_settings SET enforce_mfa = false;'
docker compose up -d --force-recreate app worker
```

La recreación es **necesaria**: un cambio directo en base de datos no refresca
`app.config` en ningún proceso gunicorn. Tras recuperar el acceso, reenrolar y
reactivar `enforce_mfa` desde **Advanced → Server settings** — la interfaz deja
rastro en el registro de auditoría, el `UPDATE` directo no.

### nginx en bucle de reinicio

Síntoma: `host not found in upstream "app"` repetido en
`docker logs iriswebapp_nginx`.

```bash
docker network inspect iris_frontend --format '{{range .Containers}}{{.Name}} {{end}}'
```

Si `iriswebapp_nginx` no aparece, tiene un endpoint de red obsoleto. **Arrancarlo
no basta: hay que recrearlo.**

```bash
cd fase6-iris
docker compose up -d --force-recreate nginx
cd .. && ./scripts/verify-fase6.sh
```

### La pila no levanta tras reiniciar el anfitrión

```bash
systemctl status tfm-fase6-iris.service
journalctl -u tfm-fase6-iris.service -b --no-pager
sudo systemctl restart tfm-fase6-iris.service
```

La unidad ejecuta `docker compose down` seguido de `up -d --wait`. El `down`
elimina contenedores con endpoints de red obsoletos, que es la causa del fallo;
`restart: always` por sí solo no converge, porque reintenta sobre un contenedor
que sigue desconectado.

---

## 🔁 Arranque en frío

`systemd/tfm-fase6-iris.service` garantiza que la pila queda operativa tras un
reinicio sin intervención manual.

```bash
sudo cp systemd/tfm-fase6-iris.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now tfm-fase6-iris.service
```

Ordena respecto a `docker.service` y `tailscaled.service`, y usa `--wait` para
que systemd espere a los healthchecks: el estado de la unidad refleja el estado
real del servicio, no solo que el comando se lanzó.

> [!NOTE]
> **Por qué `down` + `up` y no solo `up`.** Tras un reinicio, un contenedor puede
> quedar restaurado con su adjunción de red perdida. `restart: always` reintenta
> indefinidamente sobre ese estado sin resolverlo, y `depends_on` no interviene:
> en el arranque del anfitrión orquesta el demonio Docker, que no honra esa
> directiva — solo lo hace Compose. El `down` fuerza endpoints nuevos.
>
> La primera corrección propuesta (healthcheck + `depends_on: service_healthy`)
> se verificó con `compose up` y **no resolvía el arranque en frío**. Solo la
> prueba de reinicio lo reveló. Ver informe, P1-11.

### Prueba de reinicio

Criterio de aceptación de la fase. Debe repetirse tras cualquier cambio en el
compose, el override o la unidad:

```bash
sudo reboot
# al volver, SIN tocar nada:
sleep 90
systemctl is-active tfm-fase6-iris.service    # active
./scripts/verify-fase6.sh                     # exit 0
```

---

## ⚠️ Consideraciones de seguridad

**Aplicado:**

- 🔐 Credenciales fuera del repositorio; plantilla con valores vacíos
- 🔑 PKI propia del enclave en ambos sentidos: certificado de servidor y ancla de confianza
- 🌐 Publicación restringida al tailnet, sin exposición IPv4 ni IPv6 en la red corporativa
- 🛡️ MFA obligatorio con cuenta de emergencia
- 📌 Etiquetas de imagen fijadas
- 🚫 Autenticación local, sin dependencia del AD corporativo

**Riesgo aceptado:**

- 👤 **La aplicación se ejecuta como `root` en el contenedor.** La imagen upstream
  de DFIR-IRIS no contempla ejecución sin privilegios: no declara `USER`, no crea
  usuario y sus volúmenes son `root:root`. Corregirlo exigiría bifurcar la
  imagen. Compensan el aislamiento de red, el MFA, la ausencia de claves públicas
  y que el contenedor no es privilegiado ni monta el socket de Docker. Ver
  informe, P1-7.

**Pendiente:**

- 🔗 MFA en el borde vía Traefik/Authelia como capa adicional (hoy es nativo de IRIS)

---

## 📦 Sobre el código de esta carpeta

`fase6-iris/` contiene el código fuente de **DFIR-IRIS v2.4.27 vendorizado**
(≈483 000 líneas, LGPL-3.0). Ver [`NOTICE`](NOTICE) y `LICENSE.txt`.

Ficheros propios del TFM: `README.md`, `SECURITY-NOTICE.md`, `NOTICE`,
`.env.example`, `docker-compose.override.yml`, `systemd/`, `certificates/rootCA/`.

El resto es código de terceros sin modificar, marcado `linguist-vendored` en
`.gitattributes`. Cualquier métrica de líneas de código del proyecto debe excluir
este directorio.

---

## 🔭 Trabajo futuro

### Automatización de la integración

La API key y los endpoints están disponibles; falta implementar en el
orquestador (Fase 2):

1. Creación de caso al abrir incidente, enlazado al War Room de Rocket.Chat
2. Volcado del campo `agent_reasoning` del agente de triaje (Fase 3)
3. Adición de artefactos de Velociraptor (Fase 5) como evidencias
4. Registro de sesiones de acceso remoto en la línea temporal (Fases 4 y 8)
5. Cierre de caso con revocación de accesos

El bundle TLS saliente (`ca-bundle-oob.crt`) es prerrequisito de los webhooks
salientes hacia servicios del enclave.

### Endurecimiento adicional

1. Traefik + Authelia por delante, como capa de borde complementaria al MFA nativo
2. Monitorización del estado de los contenedores desde la Fase 7, con prueba negativa

---

## ➡️ Siguiente fase

**Fase 7 — Observabilidad:** métricas operacionales sobre OpenSearch Dashboards.
