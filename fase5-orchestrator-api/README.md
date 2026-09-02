# 🧠 Fase 5 · Orchestrator API

> [!CAUTION]
> Este componente estuvo afectado por el incidente **P0-3** (credenciales por
> defecto de MinIO en repositorio público, en uso real por ausencia de `.env`).
> Antes de desplegar, leer **[`fase5-velociraptor/SECURITY-NOTICE.md`](../fase5-velociraptor/SECURITY-NOTICE.md)**.
> Las credenciales de MinIO se toman ahora de `.env` (ver `.env.example`); el
> orchestrator usa el usuario dedicado `tfm-orchestrator`, no las credenciales root.

> Microservicio **FastAPI** que valida solicitudes de colección forense, selecciona perfiles permitidos y registra la evidencia en **MinIO**.

> [!NOTE]
> **🎯 Objetivo del componente**  
> Actuar como capa de orquestacion entre n8n (u otros consumidores), la logica de perfiles de coleccion y el almacenamiento de evidencia en MinIO, generando `manifest.json` y `sha256.txt` con trazabilidad completa.

> [!TIP]
> Este servicio NO ejecuta colecciones reales contra Velociraptor Server, pero implementa el **pipeline de control y evidencia** previsto en la Fase 5 del TFM.

---

## 📋 Estado

- [x] 🐳 FastAPI operativo en Docker
- [x] 🔌 Endpoint `POST /velociraptor/collect` funcional
- [x] 🛡️ Validacion de perfiles mediante allowlist
- [x] 🔗 Integracion con MinIO para almacenamiento de evidencia
- [x] 📄 Generacion de `manifest.json` con metadatos estructurados
- [x] 🔐 Generacion de `sha256.txt` para integridad
- [x] 🗂️ Escritura en bucket `evidence` con estructura por incidente/host/timestamp
- [ ] 🟡 ZIP real de coleccion desde Velociraptor (pendiente)
- [ ] 🟡 Integracion automatica con DFIR-IRIS (pendiente)

---

## 🎯 Objetivo

Este componente actua como **capa de orquestacion** entre n8n (u otros consumidores), la logica de perfiles de coleccion y el almacenamiento de evidencia en MinIO. Su responsabilidad principal es recibir una solicitud de coleccion, validar que el perfil este permitido, construir el manifiesto de evidencia y dejar trazabilidad estructurada para la Fase 5.

---

## 🏗️ Rol en la arquitectura

```mermaid
flowchart LR
  N8N[n8n webhook dfir-collect] --> API[FastAPI Orchestrator]
  API --> VAL[Validacion de profile]
  VAL --> MAN[Generacion manifest.json]
  MAN --> HASH[Generacion sha256.txt]
  HASH --> MINIO[Bucket evidence en MinIO]
  API --> RESP[Respuesta JSON a n8n]
```

El servicio implementa el **pipeline de control y evidencia** previsto en la fase, recibiendo la orden de coleccion, validando el perfil, generando los metadatos y persistiendolos en MinIO.

---

## 📁 Estructura del repositorio

```text
fase5-orchestrator-api/
├── main.py
├── requirements.txt
├── Dockerfile
├── docker-compose.yml
└── README.md
```

---

## 🔌 Endpoint principal

### `POST /velociraptor/collect`

Recibe una peticion de coleccion forense, valida el perfil y genera la estructura de evidencia.

#### Payload esperado

```json
{
  "incidentid": "INC-2026-042",
  "host": "HOST-DC01",
  "profile": "credential_dump_collection",
  "source": "n8n-fase5"
}
```

#### Campos

| Campo | Tipo | Obligatorio | Descripcion |
|---|---|---|---|
| `incidentid` | string | ✅ | Identificador del incidente |
| `host` | string | ✅ | Host objetivo |
| `profile` | string | ✅ | Perfil de coleccion permitido |
| `source` | string | ❌ | Origen del evento |

---

## 🧾 Modelo de datos

### Manifest (manifest.json)

```json
{
  "incident_id": "INC-2026-042",
  "host": "HOST-DC01",
  "collection_profile": "credential_dump_collection",
  "selected_by": "forensics_agent_v1",
  "started_at": "20260625T185518Z",
  "ended_at": "20260625T185518Z",
  "artifact_list": [
    "Windows.System.Pslist",
    "Windows.Memory.Acquisition"
  ],
  "zip_path": "s3://evidence/INC-2026-042/HOST-DC01/20260625T185518Z/velociraptor_collection.zip",
  "zip_sha256": "2fc7f85ceed2e4a1bc5081a1691d231961b1ba093a7ef8671f4da34f601080f9",
  "operator": "orchestrator_v1",
  "source": "n8n-fase5"
}
```

### Hash (sha256.txt)

```text
2fc7f85ceed2e4a1bc5081a1691d231961b1ba093a7ef8671f4da34f601080f9  velociraptor_collection.zip
```

> [!WARNING]
> El campo `zip_sha256` actualmente contiene un valor simulado en la respuesta de prueba, ya que el servicio todavia no genera el ZIP real de coleccion desde Velociraptor.

---

## 🛡️ Perfiles permitidos

Los perfiles se validan mediante **allowlist** para evitar ejecuciones arbitrarias, en linea con el enfoque de control estricto del proyecto.

| Profile | Artefactos asociados |
|---|---|
| `credential_dump_collection` | `Windows.System.Pslist`, `Windows.Memory.Acquisition` |
| `ransomware_triage` | `Windows.System.Pslist` |
| `lateral_movement_probe` | `Windows.Network.Netstat`, `Windows.System.Pslist` |
| `generic_high_signal_collection` | `Windows.System.Pslist` |

Si el perfil no esta permitido, el servicio devuelve `400 - Profile not allowed`.

---

## 🐳 Despliegue Docker

### docker-compose.yml

```yaml
services:
  orchestrator:
    build: .
    container_name: orchestrator
    restart: unless-stopped
    ports:
      - "8020:8000"
    networks:
      - oob-network
      - single-node_default

    env_file:
      - .env

    environment:
      MINIO_ENDPOINT: minio:9000
      MINIO_BUCKET: evidence
      MINIO_SECURE: "false"
      PYTHONUNBUFFERED: "1"

      # --- Fase 7: Observabilidad / Métricas ---
      OS_URL: https://single-node-wazuh.indexer-1:9200
      OS_USER: admin
      OS_PASS: ${OS_PASS}
      OS_INDEX: tfm-metrics-events

    volumes:
      - ../fase7-observabilidad/shared:/app/shared:ro

networks:
  oob-network:
    external: true
  single-node_default:
    external: true
```

> [!IMPORTANT]
> Este servicio debe compartir la red Docker `oob-network` con n8n y MinIO para resolver correctamente los nombres internos de contenedor. La red `single-node_default` le da acceso al indexador de Wazuh para las métricas de la Fase 7.

> [!NOTE]
> `MINIO_ACCESS_KEY` y `MINIO_SECRET_KEY` **no** aparecen en el compose: se
> cargan desde `.env` (`env_file`). Ver `.env.example`. Corresponden al usuario
> `tfm-orchestrator`, no a las credenciales root de MinIO.
> `PYTHONUNBUFFERED: "1"` es necesario para que los avisos de `metrics_client`
> lleguen a los logs sin quedar retenidos en el buffer de stdout.
> El volumen de la Fase 7 se monta en `:ro`.

---

## 🌐 Redes y puertos

| Elemento | Valor |
|---|---|
| **Contenedor** | `orchestrator` |
| **Imagen** | `fase5-orchestrator-api-orchestrator` |
| **Puerto interno** | `8000/tcp` |
| **Puerto publicado** | `8020:8000/tcp` |
| **Red principal** | `oob-network` |
| **Red adicional** | `single-node_default` |
| **Endpoint principal** | `POST /velociraptor/collect` |
| **Servicio relacionado** | `minio:9000` |
| **Bucket** | `evidence` |

---

## 🔐 Variables de entorno

| Variable | Origen | Descripcion |
|---|---|---|
| `MINIO_ENDPOINT` | compose | Endpoint interno del servicio MinIO (`minio:9000`) |
| `MINIO_ACCESS_KEY` | `.env` (sin valor por defecto) | Access key del usuario `tfm-orchestrator`. Ver `.env.example`. |
| `MINIO_SECRET_KEY` | `.env` (sin valor por defecto) | Secret key del usuario `tfm-orchestrator`. Ver `.env.example`. |
| `MINIO_BUCKET` | compose | Bucket de evidencia (`evidence`) |
| `MINIO_SECURE` | compose | Uso de HTTP/HTTPS hacia MinIO (`false`) |
| `OS_PASS` | `.env` (sin valor por defecto) | Contraseña del indexador de Wazuh (métricas Fase 7). Ver `.env.example`. |

> [!IMPORTANT]
> `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY` y `OS_PASS` se documentan **sin valor**:
> se definen en `.env` (excluido por `.gitignore`), nunca en el repositorio. La
> versión anterior no traía `.env`, de modo que docker-compose aplicaba el
> valor por defecto definido en el propio compose y la credencial documentada
> era la credencial en uso (P0-3).
>
> El orchestrator se autentica ahora con el usuario dedicado `tfm-orchestrator`
> y la política `evidence-writer`, limitada a `evidence/*` y **sin
> `s3:DeleteObject`**: puede escribir y leer evidencia, no borrarla. No usa las
> credenciales root de MinIO.

---

## 🔁 Flujo de procesamiento

1. n8n (u otro consumidor) envia una solicitud HTTP al endpoint `/velociraptor/collect`.
2. FastAPI valida el `profile` contra la allowlist.
3. Se genera un timestamp UTC.
4. Se construye el objeto `manifest` con los metadatos de la coleccion.
5. Se calcula el valor `zip_sha256` (actualmente simulado en pruebas).
6. Se generan los archivos `manifest.json` y `sha256.txt`.
7. Ambos se almacenan en el bucket `evidence` en MinIO.
8. El servicio devuelve una respuesta JSON con estado `queued` y la ubicacion logica de la evidencia.

---

## 🗂️ Estructura de evidencias en MinIO

```text
evidence/
└── INC-2026-042/
    └── HOST-DC01/
        └── 20260625T185518Z/
            ├── manifest.json
            └── sha256.txt
```

Esto deja preparada la base para el siguiente paso del proyecto: añadir el ZIP real de coleccion y registrar la evidencia automaticamente en DFIR-IRIS.

---

## 🧪 Validacion funcional

### Lanzar coleccion

```bash
curl -X POST http://localhost:8020/velociraptor/collect \
  -H "Content-Type: application/json" \
  -d '{
    "incidentid": "INC-2026-042",
    "host": "HOST-DC01",
    "profile": "credential_dump_collection",
    "source": "n8n-fase5"
  }'
```

### Verificar evidencias en MinIO

```bash
mc ls minio/evidence/INC-2026-042/HOST-DC01/
```

### Resultado esperado

- `manifest.json` con metadatos completos
- `sha256.txt` con hash del ZIP
- Estructura de directorios por incidente/host/timestamp

---

## ⚠️ Consideraciones de seguridad

- 🔐 **MinIO:** credenciales del usuario dedicado `tfm-orchestrator` cargadas desde `.env` (nunca en el repositorio). Política `evidence-writer`: acceso limitado a `evidence/*`, **sin `s3:DeleteObject`**.
- 🔒 **SHA-256:** hash de cada ZIP para integridad de la evidencia
- 📝 **Manifest:** metadatos completos de cada coleccion para trazabilidad
- 🗂️ **Evidence Store:** estructura clara por incidente/host/timestamp
- 🛡️ **Allowlist:** validacion estricta de perfiles para evitar ejecuciones arbitrarias

> [!WARNING]
> **Riesgos residuales conocidos tras el P0-3** (ver `fase5-velociraptor/SECURITY-NOTICE.md`):
> - Quitar `s3:DeleteObject` impide el borrado pero **no la sobrescritura**: una clave existente puede reemplazarse sin dejar rastro. Hace falta versionado o bloqueo de objetos en el bucket.
> - `incidentid` y `host` llegan sin validar en el payload y se usan para construir la clave del objeto: es posible escribir en rutas arbitrarias del bucket.
> - MinIO publica su API (`0.0.0.0:9000`) y su consola (`0.0.0.0:9001`) sin TLS.

---

## 🚧 Limitaciones conocidas

| Limitacion | Impacto | Estado |
|---|---|---|
| ZIP real de coleccion | El servicio no genera el ZIP real desde Velociraptor | 🟡 Pendiente |
| Hash real del ZIP | El campo `zip_sha256` contiene valor simulado | 🟡 Pendiente |
| Integracion con DFIR-IRIS | No se registra la evidencia automaticamente en IRIS | 🟡 Pendiente |
| Bucket sin versionado | Quitar `s3:DeleteObject` no impide la sobrescritura de un manifiesto | 🔴 Pendiente (P0-3) |
| `incidentid` / `host` sin validar | Se usan sin sanear para construir la clave del objeto en MinIO | 🔴 Pendiente (P0-3) |

---

## 🚀 Prximos pasos

1. 🟡 Añadir generacion real del ZIP de coleccion desde Velociraptor Server
2. 🟡 Calcular hash SHA-256 real del ZIP generado
3. 🟡 Integrar con DFIR-IRIS para registro automatico de evidencias (Fase 6)
4. 🔴 Activar versionado / bloqueo de objetos en el bucket `evidence` (P0-3)
5. 🔴 Validar `incidentid` y `host` antes de construir la clave del objeto (P0-3)
6. 🟡 Añadir validacion de integridad de evidencias (verificar hash)

---

## 🧠 Resultado

Este componente ya cumple el papel de **orquestador tcnico de evidencia** dentro de la Fase 5: recibe la orden, valida el perfil, construye metadatos trazables y los persiste en MinIO, dejando el sistema preparado para una futura integracion completa con Velociraptor Server y DFIR-IRIS.

---

## 📊 Estado actual

| Elemento | Estado |
|---|---|
| FastAPI operativo | ✅ |
| Endpoint `/velociraptor/collect` | ✅ |
| Validacion de perfiles | ✅ |
| Integracion con MinIO | ✅ |
| Generacion de `manifest.json` | ✅ |
| Generacion de `sha256.txt` | ✅ |
| Escritura en bucket `evidence` | ✅ |
| ZIP real de Velociraptor | 🟡 Pendiente |
| Integracion automatica con DFIR-IRIS | 🟡 Pendiente |

---

**Repositorio:** `fase5-orchestrator-api`  
**Fase del TFM:** Fase 5 - Forensics Automatizado  
**Proyecto:** `tfm-alerta-temprana-oob`