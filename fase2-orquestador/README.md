# 🛡️ TFM — Sistema de Alerta Temprana Out-of-Band para Respuesta a Incidentes

> **Idea central:** cuando el entorno corporativo puede estar comprometido, no puedes depender de su correo, su AD o sus herramientas de colaboración. Este proyecto construye un **canal alternativo, aislado y controlado** para coordinar incidentes, solicitar aprobaciones y ejecutar acciones de respuesta con trazabilidad.

[![Estado](https://img.shields.io/badge/Estado-Fase%201%20completada-success)](./fase1-infraestructura/)
[![Stack](https://img.shields.io/badge/Stack-Python%20%7C%20Docker%20%7C%20Wazuh%20%7C%20Rocket.Chat-blue)](#stack-tecnol%C3%B3gico)
[![IA](https://img.shields.io/badge/IA-LangGraph%20%2B%20Ollama-purple)](#ia-ag%C3%A9ntica)

---

## Objetivo del proyecto

Construir un sistema **Out-of-Band** que permita responder a incidentes de seguridad sin depender de la infraestructura potencialmente afectada. La propuesta combina detección, comunicación, orquestación, automatización y trazabilidad en un único flujo operativo.

El sistema debe:

- Crear automáticamente **War Rooms** por incidente en Rocket.Chat.
- Recibir alertas desde **Wazuh** y clasificarlas.
- Aplicar **triage inteligente** con apoyo de IA agéntica.
- Enriquecer alertas con **CTI** y fuentes externas.
- Ejecutar acciones de respuesta con control y aprobación humana.
- Mantener trazabilidad completa del caso y de las evidencias.

---

## Arquitectura resumida

```text
[Red corporativa] → [Wazuh] → [Orquestador] → [IA agéntica] → [Rocket.Chat War Room]
                                   │                                │
                             [Velociraptor]                  [DFIR-IRIS Case]
                             [MinIO Evidence]                [OpenSearch Metrics]
                                   │
                   [Cloudflare Tunnel] → [Python Agent / DC]
```

---

## Stack tecnológico

| Capa | Tecnología | Uso |
|---|---|---|
| Detección | Wazuh SIEM/EDR | Alertas, telemetría y respuesta inicial |
| Comunicación OOB | Rocket.Chat | War Rooms, coordinación y bot de orquestación |
| Orquestación | FastAPI + PostgreSQL + Redis | Motor principal de decisión y workflows |
| IA agéntica | LangGraph + Ollama | Triage inteligente y apoyo a decisiones |
| Forensics | Velociraptor | Recolección remota y adquisición de evidencias |
| Evidence Store | MinIO | Almacenamiento S3-compatible de evidencias |
| Case Management | DFIR-IRIS | Gestión de casos, timeline y evidencias |
| Observabilidad | OpenSearch + Dashboards | Métricas, búsqueda y análisis |
| Acceso remoto OOB | RustDesk Server | Soporte remoto break-glass |
| Agentes DC | Python + cloudflared | Ejecución controlada sobre controladores de dominio |
| Gestión contenedores | Portainer | Administración visual de Docker |
| Autenticación | Authelia | MFA e identidad independiente del AD |
| Plan C | GL.iNet KVM | Acceso hardware on-prem de contingencia |

---

## Fases del proyecto

| Fase | Nombre | Estado | Descripción |
|---|---|---|---|
| [Fase 1](../fase1-infraestructura/) | Infraestructura Base | ✅ Completada | Base Docker, seguridad, comunicación y SIEM |
| [Fase 2](../fase2-orquestador/) | Orquestador MVP | ⬜ Pendiente | FastAPI + War Rooms + aprobaciones |
| [Fase 3](../fase3-agentic/) | IA Agéntica | ⬜ Pendiente | LangGraph + triage + CTI |
| [Fase 4](../fase4-breakglass-dc/) | Break-Glass + DC Scripts | ⬜ Pendiente | RustDesk + Cloudflare Tunnels + agentes |
| [Fase 5](../fase5-velociraptor/) | Forensics Automático | ⬜ Pendiente | Velociraptor + MinIO + pipeline de evidencias |
| [Fase 6](../fase6-dfir-iris/) | DFIR-IRIS Case Mgmt | ⬜ Pendiente | Casos, timeline, IOCs y trazabilidad |
| [Fase 7](../fase7-observabilidad/) | Observabilidad | ⬜ Pendiente | OpenSearch y métricas del sistema |
| [Fase 8](../fase8-kvm-hardening/) | KVM + Hardening | ⬜ Pendiente | Plan C hardware y endurecimiento final |

---

## Fase 1 — Infraestructura base

La Fase 1 deja operativa la base del enclave out-of-band. El objetivo es disponer de servicios de entrada, autenticación, comunicación, indexación y validación final completamente separados del entorno corporativo que pudiera estar afectado.

### Subfases de la Fase 1

| Subfase | Componente | Resultado |
|---|---|---|
| [Fase 1a](../docs/README-fase1a-traefik-portainer.md) | Traefik + Portainer | Reverse proxy, TLS y administración Docker operativos |
| [Fase 1b](../docs/README-fase1b-authelia.md) | Authelia | IdP independiente con MFA/TOTP y WebAuthn |
| [Fase 1c](../docs/README-fase1c-mongodb-rocketchat.md) | MongoDB + Rocket.Chat | Base de datos y canal OOB para el War Room |
| [Fase 1d](../docs/README-fase1d-wazuh.md) | Wazuh | SIEM/EDR single-node con dashboard |
| [Fase 1e](../docs/README-fase1e-validacion.md) | Validación final | Comprobación integral y tag `fase1-base` |

### Resultado técnico de la Fase 1

- Traefik expone los servicios principales mediante HTTPS y enruta por host.
- Portainer permite administrar contenedores de forma visual.
- Authelia aporta autenticación independiente con MFA.
- MongoDB 8.0 se ejecuta como replica set de un nodo con autenticación por keyFile.
- Rocket.Chat 8.4.1 actúa como canal de comunicación del War Room.
- Wazuh 4.14.0 cubre indexación, manager y dashboard.
- La validación final confirma que toda la infraestructura base responde como se espera.

### Validación consolidada

La fase se considera completada cuando los siguientes servicios están operativos:

- Traefik en `http://localhost:8080`.
- Portainer en `https://portainer.oob.local`.
- Authelia en `https://auth.oob.local`.
- Rocket.Chat en `https://chat.oob.local`.
- Wazuh en `https://wazuh.oob.local`.
- MongoDB en estado `PRIMARY` y aislado en red interna.

---

## Decisiones de diseño

- **Aislamiento de red:** el enclave OOB usa redes Docker separadas para reducir exposición y mantener límites claros entre servicios internos y externos.
- **IdP independiente:** Authelia evita depender del AD corporativo, que puede no ser confiable durante un incidente.
- **Canal de comunicación propio:** Rocket.Chat proporciona un espacio de coordinación controlado para War Rooms y automatización.
- **SIEM local:** Wazuh actúa como motor de detección y fuente de alertas sin depender de servicios externos.
- **Validación explícita:** cada subfase tiene README propio y pruebas reales documentadas para que la defensa del TFM sea reproducible.

---

## Documentación por subfase

- [README Fase 1a — Traefik + Portainer](../docs/README-fase1a-traefik-portainer.md)
- [README Fase 1b — Authelia](../docs/README-fase1b-authelia.md)
- [README Fase 1c — MongoDB + Rocket.Chat](../docs/README-fase1c-mongodb-rocketchat.md)
- [README Fase 1d — Wazuh](../docs/README-fase1d-wazuh.md)
- [README Fase 1e — Validación final](../docs/README-fase1e-validacion.md)

---

## Estado final de la fase

La Fase 1 queda cerrada con el tag Git `fase1-base`. Desde este punto el proyecto cuenta con una infraestructura base estable, validada y lista para el desarrollo del orquestador y el resto de fases del TFM.

---

## Siguiente paso

La siguiente fase del proyecto es **Fase 2 — Orquestador MVP**, donde se construirá el motor que conectará las alertas de Wazuh con Rocket.Chat y los primeros playbooks de respuesta.
