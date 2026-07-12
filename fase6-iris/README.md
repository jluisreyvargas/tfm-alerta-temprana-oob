# 🛡️ Fase 6 — DFIR-IRIS: Case Management e Integración Forense

> **Objetivo general:** desplegar DFIR-IRIS como plataforma de gestión de casos e incidentes, integrarla con la evidencia generada en la Fase 5 (Velociraptor + MinIO) y dejar la trazabilidad completa de un caso real listo para las siguientes fases del TFM.

---

## 📑 Índice

- [🎯 Objetivo](#-objetivo)
- [🏗️ Arquitectura](#-arquitectura)
- [🐳 Despliegue](#-despliegue)
- [🌐 Acceso y configuración](#-acceso-y-configuración)
- [🗂️ Caso validado](#-caso-validado)
- [📝 Evidencia y timeline](#-evidencia-y-timeline)
- [🔗 Integración con Fase 5](#-integración-con-fase-5)
- [✅ Estado de validación](#-estado-de-validación)
- [📄 Subfases documentadas](#-subfases-documentadas)
- [➡️ Siguiente fase](#-siguiente-fase)

---

## 🎯 Objetivo

La Fase 6 introduce **DFIR-IRIS** como capa de *case management* del proyecto TFM `alerta-temprana-oob`, con el fin de centralizar la gestión de incidentes, evidencias y trazabilidad forense generada por las fases previas de orquestación y colección automática.

Esta fase conecta directamente con el flujo ya validado en la Fase 5: **Velociraptor → n8n → MinIO**, añadiendo ahora una capa de gestión formal del incidente dentro de IRIS.

---

## 🏗️ Arquitectura

```mermaid
flowchart LR
    A[🚨 Alerta / Incidente] --> B[🧠 n8n Orquestador]
    B --> C[🔍 Velociraptor Collection]
    C --> D[📦 MinIO Evidence Storage]
    D --> E[🗂️ DFIR-IRIS Case]
    E --> F[📝 Notas + Timeline]
    F --> G[📊 Fase 7 - Métricas]
```

La plataforma se despliega mediante **Docker Compose**, con los siguientes servicios:

| Servicio | Función |
|---|---|
| `iriswebapp_app` | Aplicación principal de IRIS |
| `iriswebapp_worker` | Procesado asíncrono de tareas |
| `iriswebapp_db` | Base de datos PostgreSQL |
| `iriswebapp_rabbitmq` | Cola de mensajería interna |
| `iriswebapp_nginx` | Frontal HTTPS |

---

## 🐳 Despliegue

El despliegue se realizó con la versión oficial **v2.4.27** del proyecto `dfir-iris/iris-web`, usando `docker-compose.base.yml` como referencia y un fichero de overrides propio del TFM.

### Incidencias resueltas durante el despliegue

- 🔴 **Contenedor `nginx` en estado `restarting`** → causado por conflicto de puerto `443` ya asignado en el host.
- 🔴 **`Bind for 0.0.0.0:443 failed: port is already allocated`** → resuelto ajustando la variable `INTERFACE_HTTPS_PORT` en el `.env` en lugar de sobrescribir manualmente el bloque `ports`.
- 🟢 **Resultado final:** IRIS accesible correctamente vía navegador.

---

## 🌐 Acceso y configuración

| Variable | Valor |
|---|---|
| `SERVER_NAME` | `iris.local` |
| `INTERFACE_HTTPS_PORT` | `4833` |
| `IRIS_AUTHENTICATION_TYPE` | `local` |
| `IRIS_ADM_USERNAME` | `administrator` |

**URL de acceso:**

```text
https://iris.local:4833
```

La autenticación de la API se realiza mediante **API Key** de usuario, disponible en el perfil de administrador dentro de IRIS.

---

## 🗂️ Caso validado

Se creó un caso real de prueba para validar el flujo completo del incidente:

| Campo | Valor |
|---|---|
| **Case name** | `#2 - INC-2026-042` |
| **Case description** | `Test Case TFM` |
| **Customer** | `IrisInitialClient` |
| **SOC ID** | `1` |
| **Case ID** | `2` |
| **Case UUID** | `f4a408e0-a8f7-4cec-bcaa-afe8220b0b2e` |

---

## 📝 Evidencia y timeline

### 🧾 Nota de evidencia forense

Se documentó la evidencia generada en la Fase 5 dentro de una nota asociada al caso:

- **Incident ID:** `INC-2026-042`
- **Host:** `HOST-DC01`
- **Profile:** `credential_dump_collection`
- **Artefactos:** `Windows.System.Pslist`, `Windows.Memory.Acquisition`
- **Ruta MinIO:** `evidence/INC-2026-042/HOST-DC01/20260625T185518Z/`
- **Hash SHA-256:** `2fc7f85ceed2e4a1bc5081a1691d231961b1ba093a7ef8671f4da34f601080f9`
- **Operator:** `orchestrator_v1`
- **Source:** `n8n-fase5`

### 🕒 Evento de timeline

Se registró el primer hito cronológico del incidente:

- **Título:** `Alerta recibida — SSH Brute Force`
- **Descripción:** alerta Wazuh recibida y triage inicial realizado, dando origen al caso `INC-2026-042`.

---

## 🔗 Integración con Fase 5

Esta fase no sustituye el flujo de Fase 5, sino que lo **extiende**. La evidencia generada por el orquestador (`manifest.json`, `sha256.txt`, ZIP de colección) queda ahora referenciada dentro de IRIS como parte formal del caso, cerrando el ciclo:

```text
🚨 Alerta → 🧠 n8n → 🔍 Velociraptor → 📦 MinIO → 🗂️ IRIS Case
```

---

## ✅ Estado de validación

| Elemento | Estado |
|---|---|
| Despliegue de IRIS en Docker | ✅ |
| Acceso web HTTPS | ✅ |
| Autenticación local + API Key | ✅ |
| Creación de caso | ✅ (manual) |
| Nota de evidencia | ✅ |
| Evento de timeline | ✅ |
| Creación de caso vía API | ⚠️ pendiente (endpoints variables según versión) |

---

## 📄 Subfases documentadas

- 📘 [`README-Fase6a.md`](../docs/README-Fase6a.md) — Despliegue de DFIR-IRIS
- 📗 [`README-Fase6b.md`](../docs/README-Fase6b.md) — Validación del caso y trazabilidad

---

## ➡️ Siguiente fase

Con el caso `INC-2026-042` ya trazado en IRIS, el proyecto avanza hacia la **Fase 7 — Observabilidad + Métricas**, donde se reutilizará la infraestructura ya existente (`Wazuh Indexer` / OpenSearch) para indexar eventos de triage, colección y gestión de casos, sin necesidad de desplegar un nuevo motor de búsqueda.
