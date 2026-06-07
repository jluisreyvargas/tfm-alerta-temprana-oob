# 🛡️ TFM — Sistema de Alerta Temprana Out-of-Band para Respuesta a Incidentes

> **Principio fundamental:** Cuando el entorno corporativo puede estar comprometido,
> no puedes confiar en correo, AD, VPN ni Teams. Este proyecto crea un **canal alternativo completamente aislado**
> para coordinar incidentes, solicitar aprobaciones y ejecutar acciones de respuesta de forma controlada.

[![Estado](https://img.shields.io/badge/Estado-Fase%201%20en%20curso-yellow)](./fase1-infraestructura/)
[![Stack](https://img.shields.io/badge/Stack-Python%20%7C%20Docker%20%7C%20Wazuh%20%7C%20Rocket.Chat-blue)](#stack)
[![IA](https://img.shields.io/badge/IA-LangGraph%20%2B%20Ollama-purple)](#ia-ag%C3%A9ntica)

---

## 🎯 Objetivo del Proyecto

Construir un sistema **Out-of-Band** que, ante alertas críticas de Wazuh, automatiza:

- 💬 Creación de **War Rooms** en Rocket.Chat por incidente
- 🤖 **Triage inteligente** con IA Agéntica (LangGraph + LLM local)
- 🔍 **Enrichment CTI** automático (MISP, AbuseIPDB, VirusTotal)
- 🧯 **Acceso remoto break-glass** (RustDesk, TTL, credenciales efímeras)
- 🐍 **Ejecución de scripts en DCs** (W2025) via Cloudflare Tunnels
- 🦖 **Colección forense automática** (Velociraptor + MinIO)
- 🗂️ **Gestión de caso** (DFIR-IRIS) con trazabilidad total
- 🧩 **Plan C KVM** para servidores on-prem (GL.iNet)

**Todo bajo control propio** — VPS, Cloud o on-prem dedicado. Sin dependencias de servicios externos críticos.

---

## 🏗️ Arquitectura Resumida

```
[Red Corporativa] → [Wazuh] → [Orquestador] → [IA Agéntica] → [Rocket.Chat War Room]
                                    │                                    │
                              [Velociraptor]                      [DFIR-IRIS Case]
                              [MinIO Evidence]                   [OpenSearch Metrics]
                                    │
                    [CF Tunnel] → [Python Agent W2025 DC]
```

---

## 📦 Stack Tecnológico

| Capa | Tecnología | Deploy |
|---|---|---|
| Detección | Wazuh SIEM/EDR | Docker |
| Comunicación OOB | Rocket.Chat | Docker |
| Orquestador | FastAPI + PostgreSQL + Redis | Docker |
| IA Agéntica | LangGraph + Ollama (Mistral-7B) | Docker |
| Forensics | Velociraptor Server | Docker |
| Evidence Store | MinIO (S3-compatible) | Docker |
| Case Management | DFIR-IRIS | Docker |
| Observabilidad | OpenSearch + Dashboards | Docker |
| Acceso remoto OOB | RustDesk Server | Docker |
| Agentes DC | Python (FastAPI) + cloudflared | Windows Service |
| Gestión contenedores | Portainer | Docker |
| Autenticación | Authelia (MFA independiente AD) | Docker |
| Plan C | GL.iNet KVM | Hardware |

---

## 🗺️ Fases del Proyecto

| Fase | Nombre | Estado | Descripción |
|---|---|---|---|
| [Fase 1](./fase1-infraestructura/) | Infraestructura Base | 🟡 En curso | Docker, Portainer, Rocket.Chat, Wazuh, Authelia |
| [Fase 2](./fase2-orquestador-mvp/) | Orquestador MVP | ⬜ Pendiente | FastAPI + War Rooms + Aprobaciones |
| [Fase 3](./fase3-ia-agentica/) | IA Agéntica | ⬜ Pendiente | LangGraph + Triage Agent + CTI |
| [Fase 4](./fase4-breakglass-dc/) | Break-Glass + DC Scripts | ⬜ Pendiente | RustDesk + CF Tunnels + Python Agents |
| [Fase 5](./fase5-velociraptor/) | Forensics Automático | ⬜ Pendiente | Velociraptor + MinIO + Evidence Pipeline |
| [Fase 6](./fase6-dfir-iris/) | DFIR-IRIS Case Mgmt | ⬜ Pendiente | Case Management + Timeline + IOCs |
| [Fase 7](./fase7-observabilidad/) | Observabilidad | ⬜ Pendiente | OpenSearch + Dashboard de Métricas |
| [Fase 8](./fase8-kvm-hardening/) | KVM + Hardening | ⬜ Pendiente | Plan C KVM + mTLS + Hardening Final |

---

## 📚 Documentación

- 📄 [Propuesta TFM v3](./docs/propuesta_tfm_v3.md) — Documento completo del proyecto
- 🏗️ [Arquitectura detallada](./docs/arquitectura.md)
- 🤖 [Diseño IA Agéntica](./fase3-ia-agentica/README.md)
- 🌩️ [Cloudflare Tunnels + DC Agents](./fase4-breakglass-dc/README.md)

---

## 🚀 Inicio Rápido (Fase 1)

```bash
# 1. Clonar repositorio
git clone https://github.com/TU_USUARIO/tfm-alerta-temprana-oob.git
cd tfm-alerta-temprana-oob

# 2. Fase 1: Infraestructura base
cd fase1-infraestructura
cp .env.example .env
# Editar .env con tus credenciales
nano .env

# 3. Levantar servicios
docker compose up -d

# 4. Verificar estado
docker compose ps
```

---

## 📊 Métricas Objetivo

| Métrica | Objetivo |
|---|---|
| MTTA (Alerta → War Room) | < 60 segundos |
| MTTApprove | < 5 minutos |
| Precisión Triage Agente | > 80% vs. experto |
| Tasa deduplicación alertas | > 95% |

---

## 📝 Notas de Desarrollo

- Cada fase tiene su propio `README.md` con instrucciones detalladas de instalación y configuración.
- Los `docker-compose.yml` de cada fase son **independientes** pero comparten la red Docker `oob-network`.
- Los secretos y tokens se gestionan exclusivamente via variables de entorno (`.env`), nunca en código.
- Este repositorio es el entregable técnico del TFM — toda decisión de diseño está documentada.

---

**Autor:** _(tu nombre)_
**Máster en Ciberseguridad**
**Estado:** Fase 1 en curso — Mayo 2026
