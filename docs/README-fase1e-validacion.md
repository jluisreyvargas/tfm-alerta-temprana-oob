# Fase 1e — Validación Final e Infraestructura Base

## Descripción

Esta fase cierra la **Fase 1 completa** del TFM con la validación integral de todos los servicios desplegados en las subfases anteriores. Se verifica conectividad, estado de salud, autenticación y enrutamiento de cada componente del enclave out-of-band.

**Fecha de cierre:** Mayo 2026  
**Estado:** ✅ COMPLETADA  
**Tag Git:** `fase1-base`

---

## Servicios validados

| Servicio | Versión | URL de acceso | Resultado test |
|----------|---------|---------------|----------------|
| Traefik | v3.3 | http://localhost:8080 | 301 ✅ |
| Portainer | latest | https://portainer.oob.local | 200 ✅ |
| Authelia | v4.39.19 | https://auth.oob.local | 200 ✅ |
| MongoDB | 8.0 | interno (fase1-internal) | PRIMARY ✅ |
| Rocket.Chat | 8.4.1 | https://chat.oob.local | 200 ✅ |
| Wazuh Indexer | 4.14.0 | https://localhost:9200 | Up ✅ |
| Wazuh Manager | 4.14.0 | https://localhost:55000 | 401 (auth OK) ✅ |
| Wazuh Dashboard | 4.14.0 | https://wazuh.oob.local | 302 ✅ |
| Rocket.Chat Bot API | - | https://chat.oob.local/api/v1 | success ✅ |

---

## Problemas encontrados y soluciones

### Problema 1 — Traefik no cargaba el directorio `dynamic/`
**Causa:** El volumen `./traefik/dynamic:/etc/traefik/dynamic:ro` no estaba en el bloque `volumes:` del servicio Traefik en el `docker-compose.yml`.  
**Síntoma:** `servers transport not found wazuhtransport@file` en el router de Wazuh.  
**Solución:** Añadir el mount del directorio `dynamic/` al compose de Traefik:
```yaml
volumes:
  - ./traefik/dynamic:/etc/traefik/dynamic:ro
```

### Problema 2 — `serversTransport` no encontrado en Traefik v3
**Causa:** La referencia `wazuhtransport@file` en las labels de Docker no es resolvible en Traefik v3 cuando el transport se define en fichero — la API `/api/http/serversTransports` devuelve 404 en esta versión.  
**Solución:** Eliminar la referencia al transport en las labels y activar `insecureSkipVerify` de forma global en `traefik.yml`:
```yaml
serversTransport:
  insecureSkipVerify: true
```
Y simplificar las labels del dashboard de Wazuh eliminando la línea:
```yaml
# Eliminada:
- "traefik.http.services.wazuh.loadbalancer.serversTransport=wazuhtransport@file"
```

### Problema 3 — Wazuh via Traefik devolvía 404
**Causa:** Combinación del transport no encontrado (router `disabled`) + `insecureSkipVerify` no activo.  
**Solución:** Tras aplicar las dos correcciones anteriores, el router pasó a `status: enabled` y el acceso a `https://wazuh.oob.local` devolvió 302 (redirect al login).

---

## Comandos de validación completa

```bash
# 1. Estado de todos los contenedores
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# 2. Red oob-network — contenedores conectados
docker network inspect oob-network | python3 -m json.tool | grep -E "Name|IPv4"

# 3. Puertos activos en el host
sudo ss -tulpn | grep -E "80|443|4443|9443|9200|55000|1514" | sort

# 4. Test de URLs
curl -o /dev/null -w "Traefik:    %{http_code}\n" http://localhost:8080
curl -k -o /dev/null -w "Portainer: %{http_code}\n" https://localhost:9443
curl -k -o /dev/null -w "Authelia:  %{http_code}\n" https://auth.oob.local
curl -k -o /dev/null -w "RocketChat:%{http_code}\n" https://chat.oob.local
curl -k -o /dev/null -w "Wazuh dir: %{http_code}\n" https://localhost:4443
curl -k -o /dev/null -w "Wazuh TFK: %{http_code}\n" https://wazuh.oob.local

# 5. MongoDB PRIMARY
docker exec -it mongodb mongosh admin \
  -u rcuser -p MongoOOB2026! \
  --authenticationDatabase admin \
  --quiet --eval 'rs.status().members[0].stateStr'

# 6. Rocket.Chat bot API
curl -k -X POST https://chat.oob.local/api/v1/login \
  -H "Content-Type: application/json" \
  -d '{"user":"orchestrator-bot","password":"TU_PASSWORD_BOT"}' \
  | python3 -m json.tool | grep status
```

---

## Redes Docker

| Red | Tipo | Servicios conectados |
|-----|------|----------------------|
| `oob-network` | Externa, bridge | traefik, portainer, authelia, rocketchat, wazuh.dashboard |
| `fase1-internal` | Interna, bridge | mongodb, rocketchat |
| `single-node_default` | Interna, bridge | wazuh.indexer, wazuh.manager, wazuh.dashboard |

MongoDB **no está** en `oob-network` — solo accesible desde `fase1-internal`.  
Wazuh Dashboard está en **ambas redes**: `single-node_default` (para comunicarse con indexer/manager) y `oob-network` (para ser enrutado por Traefik).

---

## Puertos activos en el host

| Puerto | Protocolo | Servicio | Descripción |
|--------|-----------|---------|-------------|
| 80 | TCP | Traefik | Redirect HTTP → HTTPS |
| 443 | TCP | Traefik | HTTPS entrada principal |
| 4443 | TCP | Wazuh Dashboard | Acceso directo (evita conflicto con Traefik) |
| 9443 | TCP | Portainer | UI Portainer |
| 9200 | TCP | Wazuh Indexer | OpenSearch API |
| 55000 | TCP | Wazuh Manager | API REST |
| 1514-1515 | TCP | Wazuh Manager | Registro y recepción de agentes |
| 514 | UDP | Wazuh Manager | Syslog |

---

## Configuración final de Traefik

### `traefik.yml` — cambios acumulados en Fase 1e

```yaml
global:
  checkNewVersion: false
  sendAnonymousUsage: false

log:
  level: INFO

api:
  dashboard: true
  insecure: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: oob-network
  file:
    directory: /etc/traefik/dynamic
    watch: true

serversTransport:
  insecureSkipVerify: true    # Necesario para Wazuh Dashboard (self-signed interno)
```

---

## Inventario de credenciales por servicio

| Servicio | Usuario | Notas |
|----------|---------|-------|
| Portainer | admin | Configurado en Fase 1a |
| Authelia | jose | MFA via TOTP |
| Rocket.Chat | rc_admin | Primer usuario = admin |
| Rocket.Chat Bot | orchestrator-bot | Token guardado en gestor de secretos |
| MongoDB | rcuser | Auth admin + clusterAdmin |
| Wazuh Dashboard | wazuh-admin | Usuario operativo (admin es reservado) |
| Wazuh API | wazuh-wui | Comunicación interna manager↔dashboard |

---

## Decisiones de diseño documentadas

- **`insecureSkipVerify: true` global en Traefik:** Wazuh Dashboard usa certificados TLS self-signed generados internamente. En un entorno de laboratorio cerrado esto es aceptable. En producción se usarían certificados firmados por la CA interna del enclave.
- **Puerto 4443 para Wazuh Dashboard:** Mantiene el acceso directo sin pasar por Traefik como fallback de administración, mientras que `wazuh.oob.local` es el acceso principal via Traefik.
- **MongoDB fuera de `oob-network`:** Principio de mínima exposición — MongoDB solo es accesible por Rocket.Chat a través de la red interna `fase1-internal`.
- **`wazuh-admin` en lugar de `admin`:** El usuario `admin` de OpenSearch Security es reservado y no modificable via UI. Se crea un usuario operativo dedicado con rol `all_access`.

---

## Tags Git de Fase 1

| Tag | Descripción |
|-----|-------------|
| `fase1a` | Traefik v3.3 + Portainer operativos |
| `fase1b` | Authelia v4.39.19 MFA/IdP operativo |
| `fase1c` | MongoDB 8.0 + Rocket.Chat 8.4.1 operativos |
| `fase1d` | Wazuh 4.14.0 single-node operativo |
| `fase1-base` | **Infraestructura base completa y validada** |

---

## Próxima fase

**Fase 2 — Orquestador de Respuesta a Incidentes**

El orquestador es el cerebro del sistema — recibe alertas de Wazuh, toma decisiones de respuesta automática y coordina acciones via Rocket.Chat. Componentes principales:
- Motor de decisión (n8n o Python custom)
- Integración Wazuh → Orquestador via webhooks
- Integración Orquestador → Rocket.Chat via API bot
- Playbooks de respuesta automatizada
- Sistema de aprobación humana para acciones críticas
