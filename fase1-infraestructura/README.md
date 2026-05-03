# 🏗️ Fase 1 — Infraestructura Base del Enclave Out-of-Band

> **Objetivo:** Levantar el enclave de respuesta con los servicios core completamente dockerizados,
> acceso por MFA independiente del AD corporativo y gestión visual de contenedores.

[![Estado](https://img.shields.io/badge/Estado-En%20Curso-yellow)]()

---

## 📋 Servicios de esta Fase

| Servicio | Imagen Docker | Puerto | Descripción |
|---|---|---|---|
| **Rocket.Chat** | `rocket.chat:latest` | 3000 | Canal de coordinación out-of-band |
| **MongoDB** | `mongo:6` | 27017 (interno) | Base de datos Rocket.Chat |
| **Wazuh Manager** | `wazuh/wazuh-manager:4.x` | 1514, 1515, 55000 | SIEM/EDR central |
| **Wazuh Dashboard** | `wazuh/wazuh-dashboard:4.x` | 443 | UI de Wazuh |
| **Portainer** | `portainer/portainer-ce:latest` | 9443 | Gestión de contenedores |
| **Authelia** | `authelia/authelia:latest` | 9091 | MFA / IdP independiente del AD |
| **Traefik** | `traefik:v3` | 80, 443 | Reverse proxy + TLS automático |

---

## 🗂️ Estructura de archivos

```
fase1-infraestructura/
├── README.md                    ← Este archivo
├── docker-compose.yml           ← Todos los servicios de Fase 1
├── .env.example                 ← Variables de entorno (copiar a .env)
├── traefik/
│   ├── traefik.yml
│   └── dynamic/
├── authelia/
│   ├── configuration.yml
│   └── users_database.yml
├── wazuh/
│   └── config/
└── rocketchat/
    └── scripts/
```

---

## ⚡ Prerrequisitos

- Docker Engine >= 24.x
- Docker Compose >= 2.x (plugin v2)
- Portainer ya instalado (opcional si usas el `docker-compose.yml` de esta fase)
- Dominio propio o IP pública del VPS
- Puertos abiertos: 80, 443, 3000, 9443

### Verificar instalación Docker

```bash
docker --version          # Docker version 24.x+
docker compose version    # Docker Compose version v2.x+
```

---

## 🚀 Instalación paso a paso

### 1. Preparar variables de entorno

```bash
cp .env.example .env
nano .env
```

Variables mínimas a configurar:

```env
# Dominio del enclave (sin https://)
ENCLAVE_DOMAIN=oob.tudominio.com

# Rocket.Chat
ROCKETCHAT_ADMIN_USER=admin
ROCKETCHAT_ADMIN_PASS=CAMBIAR_PASSWORD_FUERTE

# Authelia (MFA)
AUTHELIA_JWT_SECRET=CAMBIAR_JWT_SECRET_ALEATORIO_32CHARS
AUTHELIA_SESSION_SECRET=CAMBIAR_SESSION_SECRET_ALEATORIO_32CHARS
AUTHELIA_STORAGE_ENCRYPTION_KEY=CAMBIAR_STORAGE_KEY_32CHARS

# Wazuh
WAZUH_INDEXER_PASSWORD=CAMBIAR_WAZUH_PASSWORD

# Portainer
PORTAINER_ADMIN_PASSWORD=CAMBIAR_PORTAINER_PASSWORD
```

### 2. Levantar servicios

```bash
# Crear red Docker compartida entre todas las fases
docker network create oob-network

# Levantar Fase 1
docker compose up -d

# Verificar estado
docker compose ps
docker compose logs -f
```

### 3. Verificar Rocket.Chat

```bash
# Logs de Rocket.Chat (puede tardar 2-3 minutos en arrancar)
docker compose logs -f rocketchat

# Acceder: https://oob.tudominio.com:3000
# O con Traefik: https://chat.oob.tudominio.com
```

### 4. Configurar Authelia (MFA)

```bash
# Generar hash de contraseña para users_database.yml
docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password 'TU_PASSWORD'
```

Editar `authelia/users_database.yml`:
```yaml
users:
  analista1:
    displayname: "Analista DFIR 1"
    password: "$argon2id$v=19$m=65536,t=3,p=4$..." # hash generado arriba
    email: analista1@tudominio.com
    groups:
      - ir_team
```

### 5. Configurar Wazuh

```bash
# Acceder al dashboard Wazuh
# https://wazuh.oob.tudominio.com (usuario: admin)

# Añadir agentes desde el dashboard
# O via comando en el endpoint a monitorizar:
curl -s https://packages.wazuh.com/4.x/install.sh | sudo bash -s -- --agent --manager-ip TU_IP_ENCLAVE
```

---

## ✅ Checklist de validación Fase 1

- [ ] Docker + Compose operativos en el servidor
- [ ] Portainer accesible en `https://IP:9443`
- [ ] Rocket.Chat accesible + admin configurado
- [ ] Wazuh Manager arriba + Dashboard accesible
- [ ] Al menos 1 agente Wazuh enviando eventos
- [ ] Authelia configurado + MFA funcionando para acceder al enclave
- [ ] Traefik con TLS activo (certificados Let's Encrypt)
- [ ] Red Docker `oob-network` creada
- [ ] `.env` con todos los secretos (nunca committear al repo)
- [ ] `.gitignore` con `.env` incluido

---

## 🔄 Transición a Fase 2

Una vez completada la Fase 1, el siguiente paso es implementar el **Orquestador MVP** (Fase 2):
- FastAPI + PostgreSQL + Redis
- Endpoint `POST /wazuh/alert` para ingesta de alertas
- Creación automática de War Room en Rocket.Chat
- Comandos `/approve` y `/reject`

Ver [Fase 2 README](../fase2-orquestador-mvp/README.md).

---

## 🐛 Troubleshooting

### Rocket.Chat no arranca
```bash
# Verificar MongoDB está sano
docker compose logs mongodb

# Rocket.Chat necesita MongoDB corriendo antes de arrancar
docker compose restart rocketchat
```

### Wazuh Dashboard no carga
```bash
# Puede tardar 3-5 minutos en indexar
docker compose logs wazuh-indexer
docker compose logs wazuh-dashboard
```

### Portainer pide password pero no lo acepta
```bash
# Si el volumen ya existe, resetear admin:
docker volume rm fase1_portainer_data
docker compose up -d portainer
```

---

**Fase 1 | TFM Alerta Temprana Out-of-Band**
**Última actualización:** Mayo 2026
