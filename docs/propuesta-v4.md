# 🚨 Sistema de Alerta Temprana Out-of-Band para Respuesta a Incidentes v3
## Propuesta TFM actualizada con el estado real del proyecto

> Documento técnico y funcional del proyecto con arquitectura, fases, criterios de diseño y estado consolidado.

---

## 🧭 Resumen ejecutivo

Cuando el entorno corporativo puede estar comprometido, no puedes depender de correo, AD, VPN ni herramientas de colaboración internas. Este proyecto construye un canal alternativo, aislado y controlado para coordinar incidentes, solicitar aprobaciones y ejecutar acciones de respuesta con trazabilidad.[file:304]

La propuesta combina detección, comunicación, orquestación, automatización y trazabilidad en un único flujo operativo. El objetivo es disponer de un enclave Out-of-Band que permita responder a incidentes sin depender de la infraestructura potencialmente afectada.[file:304]

---

## 🎯 Objetivos del proyecto

- 🧩 Crear automáticamente War Rooms por incidente en Rocket.Chat.
- 📡 Recibir alertas desde Wazuh y clasificarlas.
- 🧠 Aplicar triage inteligente con apoyo de IA agéntica.
- 🔎 Enriquecer alertas con CTI y fuentes externas.
- ✅ Ejecutar acciones de respuesta con control y aprobación humana.
- 🧾 Mantener trazabilidad completa del caso y de las evidencias.[file:304]

---

## 🏗️ Arquitectura del enclave

| Capa | Tecnología | Uso |
|---|---|---|
| 🛎️ Detección | Wazuh | Alertas, telemetría y respuesta inicial.[file:304] |
| 💬 Comunicación OOB | Rocket.Chat | War Rooms, coordinación y bot de orquestación.[file:304] |
| 🧭 Orquestación | FastAPI + PostgreSQL + Redis | Motor principal de decisión y workflows.[file:304] |
| 🧠 IA agéntica | LangGraph + Ollama | Triage inteligente y apoyo a decisiones.[file:304] |
| 🧪 Forensics | Velociraptor | Recolección remota y adquisición de evidencias.[file:304] |
| 📦 Evidence Store | MinIO | Almacenamiento S3-compatible de evidencias.[file:304] |
| 📚 Case Management | DFIR-IRIS | Gestión de casos, timeline y evidencias.[file:304] |
| 📊 Observabilidad | OpenSearch Dashboards | Métricas, búsqueda y análisis.[file:304] |
| 🧰 Acceso remoto | RustDesk Server | Soporte remoto break-glass.[file:304] |
| 🌐 Conectividad DC | Python + Tailscale | Ejecución controlada en hosts Windows y DCs. |
| 🖥️ Gestión Docker | Portainer | Administración visual de contenedores.[file:304] |
| 🔐 Autenticación | Authelia | MFA e identidad independiente del AD.[file:304] |
| 🧯 Plan C | GL.iNet KVM | Acceso físico on-prem de contingencia.[file:304] |

---

## 📈 Estado por fases

| Fase | Nombre | Estado | Descripción |
|---|---|---|---|
| 1 | Infraestructura Base | ✅ Completada | Base Docker, seguridad, comunicación y SIEM.[file:292][file:304] |
| 2 | Orquestador MVP | ✅ Completada | FastAPI, War Rooms y aprobaciones.[file:304] |
| 3 | IA Agéntica | ✅ Completada | LangGraph, triage y CTI.[file:304] |
| 4 | Break-Glass DC Scripts | ✅ Completada | RustDesk, Tailscale y agentes Python.[file:304] |
| 5 | Forensics Automático | ⏳ Pendiente | Velociraptor, MinIO y pipeline de evidencias.[file:304] |
| 6 | DFIR-IRIS Case Mgmt | ⏳ Pendiente | Casos, timeline, IOCs y trazabilidad.[file:304] |
| 7 | Observabilidad | ⏳ Pendiente | OpenSearch y métricas del sistema.[file:304] |
| 8 | KVM Hardening | ⏳ Pendiente | Plan C hardware y endurecimiento final.[file:304] |

---

## 🔥 Fase 1 — Infraestructura Base

La Fase 1 deja operativa la base del enclave out-of-band. El objetivo es disponer de servicios de entrada, autenticación, comunicación, indexación y validación final completamente separados del entorno corporativo que pudiera estar afectado.[file:292][file:304]

### Subfases

| Subfase | Componente | Resultado |
|---|---|---|
| 🧩 Fase 1a | Traefik + Portainer | Reverse proxy, TLS y administración Docker operativos.
| 🔐 Fase 1b | Authelia | IdP independiente con MFA/TOTP y control de acceso.
| 💬 Fase 1c | MongoDB + Rocket.Chat | Base de datos y canal OOB para el War Room.
| 🛡️ Fase 1d | Wazuh | SIEM/EDR single-node con dashboard.
| ✅ Fase 1e | Validación final | Comprobación integral y tag `fase1-base`.

---

## 🚀 Fases 2 a 4

### 🧭 Fase 2 — Orquestador MVP
Motor central que conecta Wazuh con Rocket.Chat y gestiona el ciclo básico del incidente con FastAPI, PostgreSQL y Redis.

### 🤖 Fase 3 — IA Agéntica
Triage inteligente local con LangGraph y Ollama para enriquecer el análisis sin depender de servicios externos.[file:304]

### 🌐 Fase 4 — Break-Glass DC Scripts
Acceso remoto temporal y ejecución controlada de scripts en DCs/hosts Windows. La conectividad remota documentada es Tailscale, en sustitución de Cloudflare Tunnels.

---

## 🔬 Fases 5 a 8

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

## 🧾 Decisiones de diseño

- El enclave Out-of-Band usa redes Docker separadas para mantener límites claros entre servicios internos y externos.
- Authelia actúa como IdP propio independiente del AD corporativo.
- Rocket.Chat proporciona el canal de coordinación para War Rooms y automatización.
- Wazuh funciona como SIEM/EDR local sin depender de servicios externos.
- La documentación se organiza en README raíz, README de Fase 1 y README por subfase dentro de `docs/`.
- En la Fase 4 se usa Tailscale como conectividad remota documentada.

---

## 📦 Entregables esperados

- 📁 Repositorio GitHub con despliegue reproducible.
- 📄 README principal del proyecto.
- 📄 README de cada fase y subfase.
- ⚙️ Scripts, `docker-compose.yml` y configuraciones.
- 🗺️ Diagramas de arquitectura y flujos.
- 🧪 Evidencias de validación por fase.
- 📊 Métricas de evaluación del sistema y del triage agéntico.

---

## 🗂️ Estructura documental recomendada

- `README.md` en la raíz como índice maestro del proyecto.
- `docs/` con la propuesta y los README por fase.
- `fase1-infraestructura/README.md` como guía operativa específica de la Fase 1.

---

## 🔗 Referencias principales

- [📘 README Fase 1](../fase1-infraestructura/README.md)
- [📝 README raíz del proyecto](../README.md)
- [🧩 Fase 1a — Traefik + Portainer](./fase1a-traefik-portainer.md)
- [🔐 Fase 1b — Authelia](./fase1b-authelia.md)
- [💬 Fase 1c — MongoDB + Rocket.Chat](./fase1c-rocketchat.md)
- [🛡️ Fase 1d — Wazuh](./fase1d-wazuh.md)
- [✅ Fase 1e — Validación](./fase1e-validacion.md)

---

**TFM Alerta Temprana Out-of-Band**  
**Versión:** v3 actualizada · **Estado actual:** Fase 4 completada
