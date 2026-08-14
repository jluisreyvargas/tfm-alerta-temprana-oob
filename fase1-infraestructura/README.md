# 🏗️ Fase 1 · Infraestructura Base

> [!NOTE]
> **🎯 Objetivo de la fase**  
> Desplegar la infraestructura base del enclave out-of-band con los servicios esenciales: Rocket.Chat, Wazuh, Authelia y la red Docker privada para comunicación inter-servicios.

> [!TIP]
> Esta fase establece los cimientos del proyecto: un entorno completamente aislado para coordinar incidentes cuando el entorno corporativo puede estar comprometido.

## 📋 Estado

- [x] 🐳 Docker y Docker Compose en VPS/servidor dedicado
- [x] 🧭 Portainer para gestión visual de contenedores
- [x] 💬 Rocket.Chat para coordinación out-of-band
- [x] 🛡️ Wazuh para detección SIEM/EDR
- [x] 🔐 Authelia como IdP con MFA independiente del AD
- [x] 🌐 Red Docker privada para comunicación inter-servicios
- [ ] 📚 Documentación de variables de entorno y secretos

## 🏗️ Arquitectura del Enclave

```text
┌─────────────────────────────────────────────────────┐
│           ENCLAVE OUT-OF-BAND (VPS/Cloud)           │
│                                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │ Rocket.Chat │  │   Wazuh     │  │  Authelia   │ │
│  │   :3000     │  │  :55000     │  │   :9091     │ │
│  └─────────────┘  └─────────────┘  └─────────────┘ │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │         Red Docker Privada (oob-network)    │   │
│  └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

> [!IMPORTANT]
> **Principio fundamental:** Todo el proyecto se basa en arquitectura Out-of-Band. El operador controla todos los servicios y dónde se ejecutan (VPS, Cloud, on-prem). **Cero dependencias de servicios externos críticos.**

## 🔧 Componentes Desplegados

### 💬 Rocket.Chat
- **Función:** Coordinación out-of-band, aprobaciones, bots
- **Puerto:** `3000`
- **Estado:** Siempre activo

### 🛡️ Wazuh
- **Función:** Detección SIEM/EDR, disparo de automatizaciones
- **Puertos:** `1514-1515`, `55000`, `514/udp`
- **Estado:** Siempre activo

### 🔐 Authelia
- **Función:** IdP con MFA independiente del AD corporativo
- **Puerto:** `9091`
- **Estado:** Siempre activo

### 🧭 Portainer
- **Función:** Gestión visual de contenedores Docker
- **Puerto:** `9443`
- **Estado:** Recomendado

## ⚙️ Configuración Aplicada

### Variables de Entorno

Crear archivo `.env` en la raíz del proyecto:

```bash
# Rocket.Chat
ROOT_URL=https://rocketchat.tudominio.com
PORT=3000

# Wazuh
WAZUH_MANAGER_HOST=0.0.0.0
WAZUH_API_PORT=55000

# Authelia
AUTHelia_HOST=0.0.0.0
AUTHelia_PORT=9091
```

### Red Docker

```yaml
networks:
  oob-network:
    driver: bridge
```

## ✅ Validación Funcional

### Verificar contenedores

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### Acceder a servicios

- **Rocket.Chat:** `http://<HOST>:3000`
- **Wazuh Dashboard:** `https://<HOST>:4443`
- **Authelia:** `http://<HOST>:9091`
- **Portainer:** `https://<HOST>:9443`

### Probar red interna

```bash
docker network inspect oob-network
```

## ⚠️ Consideraciones de Seguridad

- 🔐 **Authelia** provee MFA independiente del AD: los analistas se autentican incluso si el AD está comprometido
- 🌐 **Control total de servicios:** todos corren en infraestructura bajo control del operador
- 🔒 **Red privada:** comunicación inter-servicios aislada del exterior
- 🛡️ **Wazuh:** primera línea de detección de amenazas

## 🚀 Próximos Pasos

1. ➕ Desplegar Orquestador (Fase 2)
2. 🤖 Integrar IA Agéntica (Fase 3)
3. 🔗 Configurar Cloudflare Tunnels (Fase 4)
4. 📊 Implementar DFIR-IRIS (Fase 6)
5. 📈 Desplegar OpenSearch Dashboards (Fase 7)
