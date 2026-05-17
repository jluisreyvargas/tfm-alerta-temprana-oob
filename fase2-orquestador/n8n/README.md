# n8n — Orquestador de Respuesta a Incidentes

## Descripción

n8n es la plataforma de automatización de workflows self-hosted que actúa como
orquestador central del sistema OOB (Out-of-Band) de respuesta a incidentes.
Recibe alertas de Wazuh vía webhook y ejecuta playbooks automáticos de respuesta,
incluyendo notificaciones a Rocket.Chat y acciones activas de contención.

## Versión

- **Imagen:** `docker.n8n.io/n8nio/n8n:latest`
- **Licencia:** Free (Self-hosted)
- **Puerto interno:** 5678
- **URL:** https://n8n.oob.local

## Requisitos previos

- Red Docker `oob-network` creada (Fase 1)
- Traefik v3.3 operativo (Fase 1a)
- Entrada `127.0.0.1 n8n.oob.local` en `/etc/hosts`

## Despliegue

```bash
# Generar encryption key segura
openssl rand -hex 32

# Editar docker-compose.yml y sustituir N8N_ENCRYPTION_KEY
# con el valor generado arriba

# Levantar el servicio
docker compose up -d

# Verificar estado
docker compose ps
curl -k -o /dev/null -w "n8n: %{http_code}\n" https://n8n.oob.local
```

## Variables de entorno

| Variable | Valor | Descripción |
|----------|-------|-------------|
| `N8N_HOST` | `n8n.oob.local` | Hostname del servicio |
| `N8N_PORT` | `5678` | Puerto interno |
| `N8N_PROTOCOL` | `https` | Protocolo |
| `WEBHOOK_URL` | `https://n8n.oob.local/` | URL base para webhooks |
| `N8N_ENCRYPTION_KEY` | `<openssl rand -hex 32>` | Clave de cifrado (¡cambiar!) |
| `GENERIC_TIMEZONE` | `Europe/Madrid` | Zona horaria |

## Estructura de archivos

n8n/
├── docker-compose.yml # Definición del servicio
└── README.md # Este archivo

## Volúmenes

| Volumen | Destino en contenedor | Contenido |
|---------|-----------------------|-----------|
| `n8n_data` | `/home/node/.n8n` | Workflows, credenciales, configuración |

## Integración en el sistema OOB

Wazuh Manager
│ custom-n8n script (/var/ossec/integrations/)
▼
n8n Webhook → Filtrado por severidad
├──▶ Rocket.Chat #alertas (notificación)
└──▶ Respuesta activa (bloqueo IP, etc.)


## Workflows implementados

| Workflow | Estado | Fase |
|----------|--------|------|
| Recepción alertas Wazuh | ⏳ Pendiente | 2b/2c |
| Notificación Rocket.Chat | ⏳ Pendiente | 2d |
| Playbook bloqueo de IP | ⏳ Pendiente | 2e |

## Seguridad

- Acceso solo vía Traefik (TLS self-signed)
- `N8N_ENCRYPTION_KEY` nunca debe commitearse en texto plano
- Añadir `.env` al `.gitignore` si se usan variables de entorno externas

## Troubleshooting

| Problema | Causa probable | Solución |
|----------|---------------|----------|
| HTTP 502 en n8n.oob.local | Contenedor no arrancado | `docker compose up -d` |
| Webhook no recibe datos | URL incorrecta en Wazuh | Verificar `WEBHOOK_URL` |
| Workflows no persisten | Volumen no montado | Verificar `n8n_data` en `docker volume ls` |
