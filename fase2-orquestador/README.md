# 🛡️ Fase 2 — Orquestación de Alertas Tempranas con Inteligencia Artificial

[![TFM](https://img.shields.io/badge/TFM-Alerta%20Temprana%20OOB-blue)](https://github.com/TU_USUARIO/tfm-alerta-temprana-oob)
[![Fase](https://img.shields.io/badge/Fase-2-orange)]()
[![Estado](https://img.shields.io/badge/Estado-Completado-success)]()
[![Python](https://img.shields.io/badge/Python-3.11+-blue.svg)]()
[![Docker](https://img.shields.io/badge/Docker-Compose-black)]()

---

## 📋 Tabla de Contenidos

- [Resumen del Objetivo](#-resumen-del-objetivo)
- [Objetivos Específicos](#-objetivos-específicos)
- [Arquitectura](#-arquitectura)
- [Stack Tecnológico](#-stack-tecnológico)
- [Subfases](#-subfases)
- [Instalación](#-instalación-y-configuración)
- [Uso](#-uso)
- [Resultados](#-resultados)
- [Referencias](#-referencias)

---

## 🎯 Resumen del Objetivo

La **Fase 2** del TFM de **Alerta Temprana Out-of-Band (OOB)** tiene como objetivo principal **desarrollar e implementar un sistema de orquestación automatizada de alertas de seguridad que integre Wazuh, n8n, Intelligence de Amenazas (CTI) y un Agente de IA**, permitiendo la detección temprana, valoración automatizada y respuesta inteligente ante incidentes de seguridad.

---

## 🎯 Objetivos Específicos

1. **Integración Wazuh-n8n** — Webhook para recibir alertas en tiempo real
2. **Enriquecimiento CTI** — AbuseIPDB, VirusTotal, MISP
3. **Orquestación n8n** — Flujos con múltiples HTTP Requests en paralelo
4. **Análisis IA** — Agente Mistral 7B para triage automatizado
5. **Notificación Rocket.Chat** — Mensajes formateados con orchestrator-bot
6. **Infraestructura Docker** — Traefik, MongoDB 8.0, Rocket.Chat 8.x

---

## 🏗️ Arquitectura
Wazuh → n8n → CTI (AbuseIPDB, VirusTotal, MISP) → Agente IA → Rocket.Chat

---

## 🛠️ Stack Tecnológico

| Categoría | Tecnología | Versión |
|-----------|------------|---------|
| SIEM | Wazuh | 4.x+ |
| Orquestación | n8n | 1.x+ |
| CTI — AbuseIPDB | API v2 | REST |
| CTI — VirusTotal | API v3 | REST |
| CTI — MISP | 2.4.x | Docker |
| IA | Mistral 7B | Local/Cloud |
| Chat | Rocket.Chat | 8.4.3 |
| DB | MongoDB | 8.0 |
| Proxy | Traefik | v3.3 |
| Gestión | Portainer | CE |

---

## 🔗 Subfases

| Subfase | Descripción | Enlace |
|---------|-------------|--------|
| **2.1** | Webhook Wazuh en n8n | [`/docs/README_Fase2.1.md`](/tree/main/docs/README_Fase2.1.md) |
| **2.2** | Integración CTI | [`/docs/README_Fase2.2.md`](/tree/main/docs/README_Fase2.2.md) |
| **2.3** | Agente de IA | [`/docs/README_Fase2.3.md`](/tree/main/docs/README_Fase2.3.md) |
| **2.4** | Rocket.Chat | [`/docs/README_Fase2.4.md`](/tree/main/docs/README_Fase2.4.md) |

---

## 🚀 Instalación

```bash
cd tfm-alerta-temprana-oob/fase2
cp .env.example .env
docker compose up -d
```

---

## 📖 Uso

```bash
curl -k -X POST https://n8n.local/webhook-test/wazuh-alerts \
  -H "Content-Type: application/json" \
  -d '{"rule": {"id": "5710"}, "data": {"srcip": "185.220.101.4"}}'
```

---

## ✅ Resultados

- Webhook Wazuh: ✅
- CTI integrado: ✅
- Agente IA: ✅
- Rocket.Chat: ✅
- Docker healthy: ✅

---

## 📚 Referencias

- [Wazuh Docs](https://documentation.wazuh.com/)
- [n8n Docs](https://docs.n8n.io/)
- [VirusTotal API](https://docs.virustotal.com/)
- [MISP Book](https://misp.gitbook.io/misp-book/)

---

**Última actualización**: 2026-06-07  
**Versión**: 2.0.0  
**Estado**: ✅ Completado