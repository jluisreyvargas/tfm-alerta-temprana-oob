# Fase 2a — Despliegue de n8n como Orquestador de Respuesta

**Proyecto:** alerta-temprana-oob  
**Fase:** 2a  
**Fecha:** 2026-05-17  
**Estado:** ✅ Operativo

> [!NOTE]
> Las comprobaciones de este documento son de conectividad básica (Traefik/n8n), no un flujo de alerta real. Ninguna alerta de Wazuh atravesó el pipeline durante esta fase: la validación de extremo a extremo sobre tráfico real de Wazuh está documentada en `fase2-orquestador/README.md`.

## Descripción

Despliegue de n8n (workflow automation) como orquestador central del sistema de
respuesta a incidentes OOB. n8n actúa como motor de integración entre Wazuh
(detección) y Rocket.Chat (notificaciones), y ejecutará playbooks automáticos
de respuesta.

## Versiones

| Componente | Versión   | Imagen                          |
|------------|-----------|---------------------------------|
| n8n        | latest    | docker.n8n.io/n8nio/n8n:latest  |
| Licencia   | Free      | Self-hosted                     |

## Acceso

| Servicio | URL                        | Método          |
|----------|----------------------------|-----------------|
| n8n UI   | https://n8n.oob.local      | Traefik (TLS)   |

## Infraestructura

- **Red:** oob-network (externa, compartida con Fase 1)
- **Volumen persistente:** n8n_data → /home/node/.n8n
- **Reverse proxy:** Traefik v3.3 (heredado de Fase 1a)
- **Puerto interno:** 5678

## Configuración docker-compose.yml

```yaml
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    environment:
      - N8N_HOST=n8n.oob.local
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://n8n.oob.local/
      - N8N_ENCRYPTION_KEY=cambia_esta_clave_segura_32chars
      - GENERIC_TIMEZONE=Europe/Madrid
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - oob-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(`n8n.oob.local`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls=true"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"
      - "traefik.docker.network=oob-network"

volumes:
  n8n_data:

networks:
  oob-network:
    external: true
```

## Entrada /etc/hosts añadida

127.0.0.1 n8n.oob.local

## Validación

```bash
curl -k -o /dev/null -w "n8n: %{http_code}\n" https://n8n.oob.local
# Resultado esperado: n8n: 200
```

- ✅ Contenedor n8n arrancado y healthy
- ✅ Acceso vía Traefik en https://n8n.oob.local
- ✅ Cuenta admin registrada y licencia Free activada
- ✅ Dashboard operativo

## Arquitectura Fase 2 (visión completa)
Wazuh Manager
│ (custom integration script)
▼
n8n Webhook Node ← Fase 2b
│
├─ Set Node (extrae campos)
├─ IF Node (filtra por severidad)
├─ Rocket.Chat Node (notificación) ← Fase 2c/2d
└─ HTTP Request Node (respuesta activa) ← Fase 2e

## Siguientes pasos

- **Fase 2b:** Script de integración custom en Wazuh Manager
- **Fase 2c:** Workflow n8n — recepción y filtrado de alertas
- **Fase 2d:** Integración con Rocket.Chat
- **Fase 2e:** Playbooks de respuesta activa + tag fase2-orquestador
