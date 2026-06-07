# ✅ Fase 1 — Infraestructura Base del Enclave Out-of-Band

> **Estado:** ✅ Completada
> **Objetivo:** levantar la base del enclave con Docker, seguridad, comunicación y SIEM.

[![Estado](https://img.shields.io/badge/Estado-Completada-brightgreen)]()
[![Fase](https://img.shields.io/badge/Fase%201-Completada-brightgreen)]()

---

## 🎯 Objetivo de la fase

La Fase 1 deja operativa la infraestructura inicial del proyecto. El objetivo es disponer de servicios de entrada, autenticación, comunicación, administración de contenedores y detección completamente separados del entorno corporativo que pudiera estar afectado.[file:292][file:293]

---

## 🧱 Subfases

| Subfase | Componente | Resultado | README |
|---|---|---|---|
| Fase 1a | Traefik + Portainer | Reverse proxy, TLS y administración Docker operativos. | [README-fase1a-traefik-portainer.md](../docs/README-fase1a-traefik-portainer.md) |
| Fase 1b | Authelia | IdP independiente con MFA/TOTP y control de acceso. | [README-fase1b-authelia.md](../docs/README-fase1b-authelia.md) |
| Fase 1c | MongoDB + Rocket.Chat | Base de datos y canal OOB para el War Room. | [README-fase1c-mongodb-rocketchat.md](../docs/README-fase1c-mongodb-rocketchat.md) |
| Fase 1d | Wazuh | SIEM/EDR single-node con dashboard. | [README-fase1d-wazuh.md](../docs/README-fase1d-wazuh.md) |
| Fase 1e | Validación final | Comprobación integral y tag `fase1-base`. | [README-fase1e-validacion.md](../docs/README-fase1e-validacion.md) |

---

## 📁 Estructura de esta fase

```text
fase1-infraestructura/
├── README.md
├── .env
├── .env.example
├── .gitignore
├── docker-compose.yml
├── traefik/
│   ├── traefik.yml
│   ├── acme.json
│   └── dynamic/
│       └── middlewares.yml
├── authelia/
│   ├── configuration.yml
│   └── users_database.yml
├── rocketchat/
└── wazuh/
```

---

## 🚀 Instalación paso a paso

### Paso 1 — Requisitos previos

- Ubuntu 24.04 LTS.
- Docker Engine oficial instalado.
- Red Docker `oob-network` creada.
- Proyecto clonado en `/home/jose/tfm-alerta-temprana-oob`.

Comprobación:
```bash
docker --version
docker compose version
docker network ls | grep oob-network
```

---

### Paso 2 — Arranque de la Fase 1a

```bash
cd /home/jose/tfm-alerta-temprana-oob/fase1-infraestructura

touch traefik/acme.json
chmod 600 traefik/acme.json

docker compose up -d traefik portainer
```

Verificación:
```bash
docker compose ps
ss -tulpn | grep -E ':80|:443|:9443'
docker compose logs traefik | tail -20
```

Portainer debe responder en `https://IP_DEL_SERVIDOR:9443`.

---

### Paso 3 — Arranque de la Fase 1b

Añadir Authelia al `docker-compose.yml`, configurar secretos en `.env` y crear los ficheros `configuration.yml` y `users_database.yml`.

Comprobación:
```bash
docker compose up -d authelia
docker compose logs -f authelia
```

Authelia debe quedar accesible en `https://auth.<dominio>`.

---

### Paso 4 — Arranque de la Fase 1c

Levantar MongoDB y Rocket.Chat.

```bash
docker compose up -d mongodb
# inicializar replica set si corresponde
docker compose up -d rocketchat
```

Rocket.Chat debe quedar accesible en `https://chat.<dominio>`.

---

### Paso 5 — Arranque de la Fase 1d

Clonar `wazuh-docker`, generar certificados y levantar el stack single-node.

```bash
cd /home/jose/tfm-alerta-temprana-oob/fase1-infraestructura/wazuh
# clonar repo oficial si no existe
# docker compose -f generate-indexer-certs.yml run --rm generator
# docker compose up -d wazuh.indexer
# docker compose up -d wazuh.manager
# docker compose up -d wazuh.dashboard
```

---

### Paso 6 — Validación final de la Fase 1e

```bash
docker compose ps
cd wazuh/single-node && docker compose ps
```

Validaciones mínimas:
- Traefik corriendo.
- Portainer accesible.
- Authelia funcional.
- Rocket.Chat operativo.
- Wazuh dashboard operativo.

---

## ✅ Checklist de validación

- [x] Docker Engine oficial instalado.
- [x] Red `oob-network` creada.
- [x] Traefik y Portainer operativos.
- [x] Authelia funcionando.
- [x] Rocket.Chat accesible.
- [x] Wazuh desplegado.
- [x] Fase cerrada con tag `fase1-base`.

---

## 🔄 Siguiente fase

**Fase 2 — Orquestador MVP**

---

**TFM Alerta Temprana Out-of-Band | Fase 1**
**Última actualización:** Junio 2026
