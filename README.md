## 🚨✨ Sistema de Alerta Temprana Out-of-Band
## Respuesta a Incidentes con War Rooms, IA Agéntica y Trazabilidad Total

> **TFM — Documento principal del proyecto**  
> Un enclave seguro, aislado y operable para coordinar incidentes sin depender del entorno corporativo comprometido.

[![Estado](https://img.shields.io/badge/Estado-Actualizado-success)]()
[![Fase actual](https://img.shields.io/badge/Fase%20actual-Fase%204-blue)]()
[![Arquitectura](https://img.shields.io/badge/Arquitectura-Out--of--Band-purple)]()
[![Stack](https://img.shields.io/badge/Stack-Docker%20%2B%20Wazuh%20%2B%20Rocket.Chat%20%2B%20Authelia%20%2B%20Tailscale-orange)]()

---

## 🎯 Propósito

Construir un sistema Out-of-Band para responder a incidentes de seguridad sin depender de la infraestructura potencialmente afectada. La solución integra detección, comunicación, orquestación, automatización y trazabilidad en un único flujo operativo.[file:304]

### Objetivos clave
- 🧩 Crear War Rooms automáticamente en Rocket.Chat.
- 📡 Ingerir y clasificar alertas desde Wazuh.
- 🧠 Aplicar triage inteligente con IA agéntica.
- 🔎 Enriquecer eventos con CTI y fuentes externas.
- ✅ Ejecutar acciones de respuesta con aprobación humana.
- 🧾 Mantener trazabilidad completa de cada incidente y evidencia.[file:304]

---

## 🛡️ Principio base

Cuando el entorno corporativo puede estar comprometido, no conviene depender de correo, AD, VPN o herramientas internas. Por eso este proyecto crea un canal alternativo, aislado y controlado para coordinar incidentes, solicitar aprobaciones y ejecutar acciones con trazabilidad.[file:291][file:304]

---

## 🧱 Arquitectura resumida

| Capa | Tecnología | Rol |
|---|---|---|
| 🛎️ Detección | Wazuh | Alertas, telemetría y respuesta inicial.|
| 💬 Comunicación OOB | Rocket.Chat | War Rooms, coordinación y bot de orquestación.|
| 🧭 Orquestación | FastAPI + PostgreSQL + Redis | Motor de decisión y workflows.|
| 🧠 IA agéntica | LangGraph + Ollama | Triage inteligente y apoyo a decisiones.|
| 🧪 Forensics | Velociraptor | Recolección remota y adquisición de evidencias.|
| 📦 Evidence Store | MinIO | Almacenamiento S3-compatible de evidencias.|
| 📚 Case Management | DFIR-IRIS | Gestión de casos, timeline y evidencias.|
| 📊 Observabilidad | OpenSearch Dashboards | Métricas, búsqueda y análisis.|
| 🧰 Acceso remoto | RustDesk Server | Soporte remoto break-glass.|
| 🌐 Conectividad DC | Python + Tailscale | Ejecución controlada en hosts Windows y DCs. |
| 🖥️ Gestión Docker | Portainer | Administración visual de contenedores.|
| 🔐 Autenticación | Authelia | MFA e identidad independiente del AD.|
| 🧯 Plan C | GL.iNet KVM | Acceso físico on-prem de contingencia.|

---

## 📈 Estado del proyecto

| Fase | Nombre | Estado | Descripción |
|---|---|---|---|
| 1 | Infraestructura Base | ✅ Completada | Base Docker, seguridad, comunicación y SIEM.|
| 2 | Orquestador MVP | ✅ Completada | FastAPI, War Rooms y aprobaciones.|
| 3 | IA Agéntica | ✅ Completada | LangGraph, triage y CTI.|
| 4 | Break-Glass DC Scripts | ✅ Completada | RustDesk, Tailscale y agentes Python.|
| 5 | Forensics Automático | ⏳ Pendiente | Velociraptor, MinIO y pipeline de evidencias.|
| 6 | DFIR-IRIS Case Mgmt | ⏳ Pendiente | Casos, timeline, IOCs y trazabilidad.|
| 7 | Observabilidad | ⏳ Pendiente | OpenSearch y métricas del sistema.|
| 8 | KVM Hardening | ⏳ Pendiente | Plan C hardware y endurecimiento final.|

---

## 🔥 Fase 1 — Infraestructura Base

La Fase 1 deja operativa la base del enclave out-of-band. El objetivo es disponer de servicios de entrada, autenticación, comunicación, indexación y validación final completamente separados del entorno corporativo que pudiera estar afectado.

### Subfases y guías

| Subfase | Componente | Resultado | Guía |
|---|---|---|---|
| 🧩 Fase 1a | Traefik + Portainer | Reverse proxy, TLS y administración Docker operativos. | [📘 README](/docs/README-fase1a-traefik-portainer.md) |
| 🔐 Fase 1b | Authelia | IdP independiente con MFA/TOTP y control de acceso. | [📘 README](/docs/README-fase1b-authelia.md) |
| 💬 Fase 1c | MongoDB + Rocket.Chat | Base de datos y canal OOB para el War Room. | [📘 README](/docs/README-fase1c-mongodb-rocketchat.md) |
| 🛡️ Fase 1d | Wazuh | SIEM/EDR single-node con dashboard. | [📘 README](/docs/README-fase1d-wazuh.md) |
| ✅ Fase 1e | Validación final | Comprobación integral y tag `fase1-base`. | [📘 README](/docs/README-fase1e-validacion.md) |

---

## 🚀 Fases de evolución

### 🧭 Fase 2 — Orquestador MVP
Motor central que conecta Wazuh con Rocket.Chat y gestiona el ciclo básico del incidente con FastAPI, PostgreSQL y Redis.

### 🤖 Fase 3 — IA Agéntica
Triage inteligente local con LangGraph y Ollama para enriquecer el análisis sin depender de servicios externos.

### 🌐 Fase 4 — Break-Glass DC Scripts
Acceso remoto temporal y ejecución controlada de scripts en DCs/hosts Windows. La conectividad remota documentada es Tailscale, en sustitución de Cloudflare Tunnels.

### 🧪 Fase 5 — Forensics Automático
Velociraptor y MinIO para adquisición y custodia de evidencias.

### 📚 Fase 6 — DFIR-IRIS
Gestión formal del caso con timeline, evidencias y trazabilidad.

### 📊 Fase 7 — Observabilidad
OpenSearch Dashboards para métricas operacionales y calidad del sistema.

### 🧯 Fase 8 — KVM Hardening
Plan C de resiliencia con GL.iNet KVM y endurecimiento final.

---

## 🎯 Métricas objetivo

| Métrica | Objetivo |
|---|---|
| ⏱️ MTTA alerta → War Room | 60 segundos |
| ✅ MTTApprove | 5 minutos |
| 🧠 Precisión del triage agente | 80% vs experto humano |
| 🔁 Tasa de deduplicación | 95% |
| ⚙️ Script success rate | 98% |

---

## 📦 Entregables del TFM

- 📁 Repositorio GitHub con despliegue reproducible.
- 📄 README principal y README de cada fase.
- 🧾 Documentación técnica por fases y subfases.
- ⚙️ Scripts, `docker-compose.yml` y configuraciones del enclave.
- 🧪 Evidencia de pruebas y validación por fase.
- 🗺️ Diagramas de arquitectura, estados y flujos.
- 📊 Métricas de evaluación del sistema y del triage agéntico.

---

## 🗂️ Estructura de documentación

- `README.md` en la raíz como índice maestro del proyecto.
- `docs/` con la propuesta y los README de cada fase.
- `fase1-infraestructura/README.md` como guía operativa de la Fase 1.

---

## 🔗 Enlaces principales

- [📘 README Fase 1](./fase1-infraestructura/README.md)
- [📝 Propuesta TFM v3](./docs/propuesta_tfm_alerta_temprana_v3.md)
- [🧩 Fase 1a — Traefik + Portainer](./docs/README-fase1a-traefik-portainer.md)
- [🔐 Fase 1b — Authelia](./docs/README-fase1b-authelia.md)
- [💬 Fase 1c — MongoDB + Rocket.Chat](./docs/README-fase1c-mongodb-rocketchat.md)
- [🛡️ Fase 1d — Wazuh](./docs/README-fase1d-wazuh.md)
- [✅ Fase 1e — Validación](./docs/README-fase1e-validacion.md)

---

**TFM Alerta Temprana Out-of-Band**  
**Estado actual:** Fase 4 completada · documentación raíz actualizada.
