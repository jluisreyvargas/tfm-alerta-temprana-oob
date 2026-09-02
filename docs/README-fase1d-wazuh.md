# Fase 1d — Wazuh 4.14.0 Single-Node

## Descripción

Esta fase despliega **Wazuh** como motor de detección, análisis y respuesta a incidentes del enclave out-of-band. Se usa el despliegue single-node oficial de Wazuh en Docker, compuesto por tres servicios: Indexer (OpenSearch), Manager y Dashboard.

**Versión desplegada:** Wazuh 4.14.0  
**Fecha de cierre:** Mayo 2026  
**Estado:** ✅ Operativo

---

## Arquitectura

```
Navegador → Traefik → wazuh.oob.local → wazuh.dashboard :5601 (HTTPS interno)
                                              ↓
                                       wazuh.indexer :9200 (OpenSearch)
                                              ↑
                                       wazuh.manager :55000 (API REST)
                                       wazuh.manager :1514-1515 (agentes)
```

Wazuh corre en su propia red `single-node_default` más la red compartida `oob-network` para integrarse con Traefik.

---

## Estructura de ficheros

```
fase1-infraestructura/
└── wazuh/
    └── single-node/                         ← repo oficial wazuh/wazuh-docker v4.14.0
        ├── docker-compose.yml               ← modificado para Traefik y puerto 4443
        ├── generate-indexer-certs.yml       ← generación de certificados TLS
        └── config/
            ├── wazuh_indexer_ssl_certs/     ← certificados generados (en .gitignore)
            ├── wazuh_dashboard/
            │   ├── opensearch_dashboards.yml
            │   └── wazuh.yml
            └── wazuh_indexer/
                └── internal_users.yml
```

---

## Prerrequisito crítico — Ajuste del kernel

Wazuh Indexer (basado en OpenSearch/Elasticsearch) requiere un valor mínimo de `vm.max_map_count` en el kernel Linux. Sin este ajuste, el indexer falla al arrancar.

```bash
# Aplicar inmediatamente (sin reiniciar)
sudo sysctl -w vm.max_map_count=262144

# Hacer permanente (sobrevive reinicios)
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.d/99-wazuh.conf
sudo sysctl --system

# Verificar
sysctl vm.max_map_count
# → vm.max_map_count = 262144
```

---

## Problemas encontrados y soluciones

### Problema 1 — Conflicto de puerto 443 con Traefik
**Causa:** El `docker-compose.yml` oficial de Wazuh expone el dashboard en el puerto 443 del host, que Traefik ya ocupa desde la Fase 1a.  
**Solución:** Cambiar el mapping de puertos del dashboard de `443:5601` a `4443:5601`.

```yaml
ports:
  - 4443:5601    # ← era 443:5601
```

### Problema 2 — Usuario `admin` reservado por OpenSearch Security
**Causa:** El usuario `admin` es un usuario interno reservado de OpenSearch Security. No se puede cambiar su contraseña desde la UI de Wazuh Dashboard — devuelve `{"status":"FORBIDDEN","message":"Resource 'admin' is reserved."}`.  
**Estado actual:** El acceso operativo se hace con el usuario `admin` y la contraseña definida en `INDEXER_PASSWORD` dentro de `fase1-infraestructura/wazuh/single-node/.env` (fuera del control de versiones; ya no el valor por defecto público de la imagen), con el acceso restringido a red local. La creación de un usuario operativo dedicado se evaluó y no llegó a implementarse — ver «Decisiones de diseño».

> **Nota para TFM:** En producción se usaría `wazuh-passwords-tool.sh` ejecutado como root dentro del contenedor del indexer. La imagen de Wazuh Indexer está basada en Amazon Linux (no Debian) — el gestor de paquetes es `yum`, no `apt-get`.

### Problema 3 — Script `wazuh-passwords-tool.sh` requiere sudo no disponible
**Causa:** El script interno de Wazuh llama a `sudo` pero la imagen del indexer no tiene el paquete instalado.  
**Solución alternativa:**
```bash
# Instalar sudo dentro del contenedor
docker exec -u root -it single-node-wazuh.indexer-1 bash
yum install -y sudo
bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/wazuh-passwords-tool.sh \
  -u admin -p 'NUEVA_PASSWORD'
```

### Problema 4 — Error de indentación YAML al añadir red `oob-network`
**Causa:** La propiedad `name:` se colocó dentro del bloque `networks:` del servicio en lugar del bloque global de redes.  
**Solución:** Estructura YAML correcta:

```yaml
# Dentro del servicio — solo lista de nombres
    networks:
      - default
      - oob-network

# Al final del fichero — definición con propiedades
networks:
  default:
    name: single-node_default
  oob-network:
    external: true
```

---

## Procedimiento de despliegue validado

### Paso 1 — Aplica ajuste de kernel
```bash
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.d/99-wazuh.conf
```

### Paso 2 — Clona el repositorio oficial de Wazuh
```bash
mkdir -p ~/tfm-alerta-temprana-oob/fase1-infraestructura/wazuh
cd ~/tfm-alerta-temprana-oob/fase1-infraestructura/wazuh
git clone https://github.com/wazuh/wazuh-docker.git --branch v4.11.0 .
cd single-node
```

> Nota: El tag clonado es v4.11.0 pero Docker descarga automáticamente las imágenes más recientes (4.14.0).

### Paso 3 — Genera certificados TLS
```bash
docker compose -f generate-indexer-certs.yml run --rm generator
ls -la config/wazuh_indexer_ssl_certs/
# Debe mostrar ficheros .pem y .key
```

### Paso 4 — Modifica docker-compose.yml

**Cambios aplicados:**
1. Puerto del dashboard: `443:5601` → `4443:5601`
2. Añadir redes `oob-network` al servicio `wazuh.dashboard`
3. Añadir labels de Traefik al servicio `wazuh.dashboard`
4. Añadir `oob-network` al bloque global de redes

Bloque final del servicio `wazuh.dashboard`:
```yaml
    networks:
      - default
      - oob-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.wazuh.rule=Host(`wazuh.oob.local`)"
      - "traefik.http.routers.wazuh.entrypoints=websecure"
      - "traefik.http.routers.wazuh.tls=true"
      - "traefik.http.routers.wazuh.service=wazuh"
      - "traefik.http.services.wazuh.loadbalancer.server.port=5601"
      - "traefik.http.services.wazuh.loadbalancer.server.scheme=https"
      - "traefik.http.services.wazuh.loadbalancer.serversTransport=wazuhtransport"
      - "traefik.docker.network=oob-network"
```

Bloque global de redes al final del fichero:
```yaml
networks:
  default:
    name: single-node_default
  oob-network:
    external: true
```

### Paso 5 — Añade serversTransport en Traefik
```bash
cat > ~/tfm-alerta-temprana-oob/fase1-infraestructura/traefik/dynamic/wazuh-transport.yml << 'EOF'
http:
  serversTransports:
    wazuhtransport:
      insecureSkipVerify: true
EOF
```

### Paso 6 — Añade wazuh.oob.local a /etc/hosts
```bash
echo "127.0.0.1   wazuh.oob.local" | sudo tee -a /etc/hosts
```

### Paso 7 — Arranca en orden estricto
```bash
cd ~/tfm-alerta-temprana-oob/fase1-infraestructura/wazuh/single-node

# 1. Indexer primero
docker compose up -d wazuh.indexer
sleep 30

# 2. Manager
docker compose up -d wazuh.manager
sleep 15

# 3. Dashboard
docker compose up -d wazuh.dashboard

# Verifica
docker compose ps
```

---

## Verificación

```bash
# Estado de los tres componentes
docker compose ps

# API del manager — usa la credencial de la API definida en
# fase1-infraestructura/wazuh/single-node/.env (API_PASSWORD), rotada respecto
# al valor por defecto público de la imagen. No la escribas en el comando.
curl -k -u "admin:${API_PASSWORD:?exporta API_PASSWORD antes de ejecutar}" \
  "https://localhost:55000/" | python3 -m json.tool

# Dashboard accesible
curl -k -o /dev/null -w "%{http_code}" https://localhost:4443
# → 200

# Via Traefik
curl -k -o /dev/null -w "%{http_code}" https://wazuh.oob.local
# → 200
```

---

## Puertos activos

| Puerto | Servicio | Protocolo | Uso |
|--------|----------|-----------|-----|
| 9200 | wazuh.indexer | HTTPS | OpenSearch API |
| 1514 | wazuh.manager | TCP | Recepción de logs de agentes |
| 1515 | wazuh.manager | TCP | Registro de agentes |
| 514 | wazuh.manager | UDP | Syslog |
| 55000 | wazuh.manager | HTTPS | API REST de Wazuh |
| 4443 | wazuh.dashboard | HTTPS | UI Web (host) |
| 5601 | wazuh.dashboard | HTTPS | UI Web (contenedor interno) |

---

## Credenciales

| Usuario | Contraseña | Uso |
|---------|------------|-----|
| `admin` | ver `INDEXER_PASSWORD` en `wazuh/single-node/.env` | Usuario reservado OpenSearch — acceso operativo y de emergencia |
| `kibanaserver` | ver `DASHBOARD_PASSWORD` en `wazuh/single-node/.env` | Comunicación interna dashboard↔indexer |
| `wazuh-wui` | ver `API_PASSWORD` en `wazuh/single-node/.env` | Comunicación interna manager↔dashboard API |

> Los tres secretos que la imagen de Wazuh trae en claro como credenciales de
> demo (indexador, dashboard, API del manager) se rotaron y se toman de
> `fase1-infraestructura/wazuh/single-node/.env` (`INDEXER_PASSWORD`,
> `DASHBOARD_PASSWORD`, `API_PASSWORD`), fuera del control de versiones. Ver
> `fase5-velociraptor/SECURITY-NOTICE.md` (P0-3).

> ⚠️ Los valores concretos viven solo en el `.env` de la fase (fuera del control de versiones). En producción, rotarlos con `wazuh-passwords-tool.sh`.

---

## Decisiones de diseño

- **Single-node vs multi-node:** Para el laboratorio TFM un nodo es suficiente. La arquitectura es idéntica a producción — solo cambia el número de nodos del indexer.
- **Puerto 4443 para el dashboard:** Evita conflicto con Traefik que ocupa el 443. El acceso via `wazuh.oob.local` a través de Traefik mantiene el principio out-of-band.
- **`insecureSkipVerify: true` en Traefik:** Necesario porque Wazuh Dashboard usa sus propios certificados TLS internos (self-signed generados en el paso de certs). Traefik actúa como terminador TLS externo.

### Usuario operativo dedicado para el acceso a Wazuh — evaluado, no implementado

**Control evaluado.** Crear un usuario dedicado con rol `all_access` en
OpenSearch Security, separado del usuario `admin`, para el acceso operativo al
Wazuh Dashboard y a la API del indexador.

**Amenaza que cubriría.** El usuario `admin` de OpenSearch Security es interno y
reservado: su nombre no cambia y su ámbito es total. Un usuario operativo
distinto permitiría revocar o rotar el acceso del día a día sin tocar la cuenta
`admin`, acotar privilegios por rol, y atribuir acciones en los logs a una
identidad que no sea la cuenta de superusuario.

**Control equivalente actual.** El acceso se hace con `admin` y la contraseña
definida en `INDEXER_PASSWORD` (`fase1-infraestructura/wazuh/single-node/.env`,
fuera del control de versiones), rotada respecto al valor por defecto público de
la imagen y restringida a red local. Cubre la confidencialidad y la rotación de
la credencial; no cubre la separación de privilegios ni la atribución.

**Decisión.** No implementado. El usuario `admin` reservado no es modificable
desde la UI de Wazuh Dashboard (`Resource 'admin' is reserved`), y el usuario
dedicado no llegó a crearse por la vía alternativa. Sigue siendo la práctica
correcta y queda como mejora pendiente; en el estado actual no existe tal
usuario y el acceso operativo es la propia cuenta `admin`.

---

## Próxima fase

**Fase 1e — Validación final y tag `fase1-base`**

Checklist completo de todos los servicios, pruebas de conectividad entre componentes y creación del tag Git `fase1-base` que marca la infraestructura base como estable.
