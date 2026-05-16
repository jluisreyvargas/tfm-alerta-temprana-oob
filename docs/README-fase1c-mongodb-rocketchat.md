# Fase 1c — MongoDB 8.0 + Rocket.Chat 8.4.1

## Descripción

Esta fase despliega el canal de comunicación out-of-band del War Room. MongoDB 8.0 actúa como base de datos con Replica Set y autenticación via keyFile. Rocket.Chat 8.4.1 es el canal principal de comunicación para alertas e incidentes.

**Versiones desplegadas:**
- MongoDB: 8.0
- Rocket.Chat: 8.4.1

**Fecha de cierre:** Mayo 2026  
**Estado:** ✅ Operativo

---

## Arquitectura

```
Navegador → Traefik → chat.oob.local → Rocket.Chat :3000
                                             ↓
                                        MongoDB :27017
                                        (ReplicaSet rs0 + keyFile auth)
```

MongoDB está en una red interna `fase1-internal` — no es accesible desde fuera del enclave. Rocket.Chat tiene acceso a ambas redes: `oob-network` (Traefik) y `fase1-internal` (MongoDB).

---

## Estructura de ficheros

```
fase1-infraestructura/
├── docker-compose.yml
├── .env
└── mongodb/
    ├── mongo-keyfile                    ← keyFile de autenticación RS (en .gitignore)
    ├── mongo-keyfile.example            ← placeholder para el repo
    └── docker-entrypoint-keyfile.sh     ← script que arregla permisos del keyFile
```

---

## Problemas encontrados y soluciones (documentación crítica)

Esta fase requirió resolver varios problemas encadenados. Se documentan todos para referencia del TFM.

### Problema 1 — Versiones desactualizadas
**Causa:** La documentación inicial usaba MongoDB 6.0 y Rocket.Chat 6.12.0.  
**Solución:** Actualizar a MongoDB 8.0 y Rocket.Chat 8.4.1. Rocket.Chat 8.x requiere explícitamente MongoDB 8.0.

### Problema 2 — `security.keyFile is required when authorization is enabled with replica sets`
**Causa:** MongoDB 8.0 con `--auth` + `--replSet` exige obligatoriamente un keyFile para autenticación entre nodos del Replica Set. No hay forma de evitarlo aunque sea un solo nodo.  
**Solución:** Crear un keyFile con `openssl rand -base64 756` y montarlo en el contenedor.

### Problema 3 — `permissions on /etc/mongodb/mongo-keyfile are too open`
**Causa:** El sistema host usa LXD donde el UID 999 (mongodb en el contenedor) está mapeado a `lxd:systemd-journal`. El comando `sudo chown 999:999 mongo-keyfile` no funciona correctamente — el archivo sigue perteneciendo a `lxd:systemd-journal`.  
**Solución:** Usar un entrypoint script personalizado (`docker-entrypoint-keyfile.sh`) que copia el keyFile desde `/tmp/` y aplica `chown mongodb:mongodb` + `chmod 400` desde dentro del contenedor como root antes de arrancar mongod.

### Problema 4 — `MONGO_INITDB_ROOT_USERNAME` incompatible con `--keyFile`
**Causa:** La imagen oficial de MongoDB Docker no permite usar `MONGO_INITDB_ROOT_USERNAME` junto con `--keyFile` en el mismo arranque — el script de inicialización del contenedor falla porque MongoDB ya exige autenticación antes de crear el usuario.  
**Solución:** Arrancar MongoDB sin keyFile primero, crear manualmente el usuario y el RS con `mongosh`, y luego reactivar con keyFile via entrypoint script.

### Problema 5 — Verificación de email en Rocket.Chat 8.x
**Causa:** Rocket.Chat 8.x envía un código de verificación por email al registrar usuarios. Sin servidor SMTP configurado, el código se pierde.  
**Solución para laboratorio:**
```bash
docker exec -it mongodb mongosh admin \
  -u rcuser -p MongoOOB2026! \
  --authenticationDatabase admin \
  --quiet --eval '
use rocketchat;
db.rocketchat_settings.updateOne(
  {_id: "Accounts_EmailVerification"},
  {$set: {value: false}},
  {upsert: true}
);
db.users.updateMany(
  {},
  {$set: {"emails.0.verified": true}}
);'
```

### Problema 6 — Usuario admin en Rocket.Chat 8.x
**Causa:** Las variables de entorno `ROCKETCHAT_ADMIN_USER` ya no crean el usuario admin automáticamente en RC 8.x.  
**Solución:** El primer usuario que se registra en el Setup Wizard se convierte automáticamente en administrador.

---

## Procedimiento de despliegue validado

### Prerrequisitos
- Docker y Docker Compose instalados
- Red `oob-network` creada
- Red `fase1-internal` se crea automáticamente con el compose
- Traefik, Portainer y Authelia operativos (Fases 1a y 1b)
- `chat.oob.local` en `/etc/hosts`: `127.0.0.1 chat.oob.local`

### Paso 1 — Genera el keyFile
```bash
mkdir -p ~/tfm-alerta-temprana-oob/fase1-infraestructura/mongodb
cd ~/tfm-alerta-temprana-oob/fase1-infraestructura/mongodb
openssl rand -base64 756 > mongo-keyfile
chmod 644 mongo-keyfile   # los permisos los gestiona el entrypoint script
```

### Paso 2 — Crea el entrypoint script
```bash
cat > docker-entrypoint-keyfile.sh << 'SCRIPTEOF'
#!/bin/bash
cp /tmp/mongo-keyfile /etc/mongodb/mongo-keyfile
chown mongodb:mongodb /etc/mongodb/mongo-keyfile
chmod 400 /etc/mongodb/mongo-keyfile
exec docker-entrypoint.sh "$@"
SCRIPTEOF
chmod +x docker-entrypoint-keyfile.sh
```

### Paso 3 — Arranca MongoDB (primera vez SIN keyFile para crear usuario)

Bloque temporal en `docker-compose.yml`:
```yaml
  mongodb:
    image: mongo:8.0
    container_name: mongodb
    restart: unless-stopped
    command: ["mongod", "--replSet", "rs0", "--bind_ip_all"]
    volumes:
      - mongodata:/data/db
      - mongoconfig:/data/configdb
    networks:
      - fase1-internal
    healthcheck:
      test: ["CMD", "mongosh", "--quiet", "--eval", "db.adminCommand('ping').ok"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s
```

```bash
docker compose up -d mongodb
# Espera a que aparezca "Waiting for connections"
```

### Paso 4 — Inicializa Replica Set y crea usuario
```bash
# Inicializa RS
docker exec -it mongodb mongosh --quiet --eval \
  'rs.initiate({_id:"rs0", members:[{_id:0, host:"mongodb:27017"}]})'

sleep 8

# Verifica PRIMARY
docker exec -it mongodb mongosh --quiet --eval \
  'rs.status().members[0].stateStr'
# → "PRIMARY"

# Crea usuario admin
docker exec -it mongodb mongosh admin --quiet --eval '
db.createUser({
  user: "rcuser",
  pwd: "MongoOOB2026!",
  roles: [
    {role: "root", db: "admin"},
    {role: "clusterAdmin", db: "admin"}
  ]
});'
# → { ok: 1 }
```

### Paso 5 — Activa keyFile (bloque definitivo en docker-compose.yml)
```yaml
  mongodb:
    image: mongo:8.0
    container_name: mongodb
    restart: unless-stopped
    user: root
    entrypoint: ["/etc/mongodb/docker-entrypoint-keyfile.sh"]
    command: ["mongod", "--replSet", "rs0", "--bind_ip_all", "--keyFile", "/etc/mongodb/mongo-keyfile"]
    volumes:
      - mongodata:/data/db
      - mongoconfig:/data/configdb
      - ./mongodb/mongo-keyfile:/tmp/mongo-keyfile:ro
      - ./mongodb/docker-entrypoint-keyfile.sh:/etc/mongodb/docker-entrypoint-keyfile.sh:ro
    networks:
      - fase1-internal
    healthcheck:
      test: ["CMD", "mongosh", "--quiet",
             "-u", "rcuser", "-p", "MongoOOB2026!",
             "--authenticationDatabase", "admin",
             "--eval", "rs.status().ok"]
      interval: 15s
      timeout: 10s
      retries: 10
      start_period: 60s
```

```bash
docker compose up -d --force-recreate mongodb
watch docker compose ps mongodb
# → Espera: Up X seconds (healthy)
```

### Paso 6 — Arranca Rocket.Chat
```yaml
  rocketchat:
    image: registry.rocket.chat/rocketchat/rocket.chat:${ROCKETCHAT_VERSION}
    container_name: rocketchat
    restart: unless-stopped
    depends_on:
      mongodb:
        condition: service_healthy
    environment:
      MONGO_URL: mongodb://${MONGO_INITDB_ROOT_USERNAME}:${MONGO_INITDB_ROOT_PASSWORD}@mongodb:27017/rocketchat?authSource=admin&replicaSet=rs0
      MONGO_OPLOG_URL: mongodb://${MONGO_INITDB_ROOT_USERNAME}:${MONGO_INITDB_ROOT_PASSWORD}@mongodb:27017/local?authSource=admin&replicaSet=rs0
      ROOT_URL: ${ROOT_URL}
      PORT: 3000
      DEPLOY_METHOD: docker
    volumes:
      - rocketchat_uploads:/app/uploads
    networks:
      - oob-network
      - fase1-internal
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.rocketchat.rule=Host(`chat.${ENCLAVE_DOMAIN}`)"
      - "traefik.http.routers.rocketchat.entrypoints=websecure"
      - "traefik.http.routers.rocketchat.tls=true"
      - "traefik.http.services.rocketchat.loadbalancer.server.port=3000"
      - "traefik.docker.network=oob-network"
```

```bash
docker compose up -d rocketchat
docker compose logs -f rocketchat
# Espera: "SERVER RUNNING"
```

### Paso 7 — Configuración inicial Rocket.Chat
1. Accede a `http://localhost:3000` o `https://chat.oob.local`
2. Registra el primer usuario — se convierte automáticamente en admin:
   - Username: `rc_admin`
   - Email: `admin@oob.local`
3. Deshabilita verificación de email (ver Problema 5)
4. Crea canales privados: `#alerts`, `#war-room`, `#ir-approvals`
5. Crea usuario `orchestrator-bot` con role `bot`
6. Activa `orchestrator-bot` desde Administration → Users
7. Genera Personal Access Token del bot:
   - `Administration → Settings → Accounts → Personal Access Tokens` → Enable: ON
   - Login como `orchestrator-bot` → My Account → Security → Personal Access Tokens
   - Nombre: `orchestrator-token` → marcar "Ignore Two Factor Authentication"
   - **Guardar User ID y Token** — solo se muestran una vez

---

## Variables de entorno (`.env`)

```env
# === ROCKET.CHAT ===
ROCKETCHAT_VERSION=8.4.1
ROOT_URL=http://chat.oob.local

# === MONGODB ===
MONGO_INITDB_ROOT_USERNAME=rcuser
MONGO_INITDB_ROOT_PASSWORD=MongoOOB2026!
```

---

## Redes Docker

| Red | Tipo | Uso |
|-----|------|-----|
| `oob-network` | Externa (creada en Fase 1a) | Traefik ↔ Rocket.Chat |
| `fase1-internal` | Interna (creada en este compose) | Rocket.Chat ↔ MongoDB |

MongoDB **no está expuesto** a `oob-network` — solo accesible desde `fase1-internal`.

---

## Verificación

```bash
# Estado contenedores
docker compose ps mongodb rocketchat

# MongoDB PRIMARY con auth
docker exec -it mongodb mongosh admin \
  -u rcuser -p MongoOOB2026! \
  --authenticationDatabase admin \
  --quiet --eval 'rs.status().members[0].stateStr'
# → "PRIMARY"

# Rocket.Chat responde
curl -k -o /dev/null -w "%{http_code}" https://chat.oob.local
# → 200

# Canales creados
curl -k -H "X-Auth-Token: TU_TOKEN" \
     -H "X-User-Id: TU_USER_ID" \
     https://chat.oob.local/api/v1/channels.list | python3 -m json.tool | grep name
```

---

## Canales creados

| Canal | Tipo | Propósito |
|-------|------|-----------|
| `#alerts` | Privado | Alertas automáticas entrantes de Wazuh via Orquestador |
| `#war-room` | Privado | Coordinación del equipo durante el incidente |
| `#ir-approvals` | Privado | Solicitudes de aprobación del Orquestador |

---

## Credenciales y tokens (guardar en gestor de secretos)

```
RC_ADMIN_USER=rc_admin
RC_ADMIN_EMAIL=admin@oob.local
RC_BOT_USERNAME=orchestrator-bot
RC_BOT_TOKEN=<guardado en gestor de secretos>
RC_BOT_USER_ID=<guardado en gestor de secretos>
RC_INTERNAL_URL=http://rocketchat:3000
RC_EXTERNAL_URL=https://chat.oob.local
```

> ⚠️ Nunca commitear tokens ni contraseñas reales. Usar `.gitignore` y gestores de secretos.

---

## Decisiones de diseño

- **MongoDB con keyFile obligatorio:** MongoDB 8.0 + `--auth` + `--replSet` requiere keyFile sin excepción. Se usa entrypoint script para gestionar permisos en entornos con mapping de UIDs (LXD).
- **Red interna `fase1-internal`:** MongoDB no expuesto a la red general del enclave — solo Rocket.Chat puede conectar a MongoDB.
- **Single-node Replica Set:** Suficiente para laboratorio. La arquitectura de RS permite que Rocket.Chat use oplog para reactividad. En producción se ampliaría a 3 nodos.
- **Sin SMTP en laboratorio:** La verificación de email se deshabilita en MongoDB. Para producción se añadiría Mailhog (lab) o servidor SMTP interno.
- **Personal Access Token del bot:** El token del `orchestrator-bot` es el mecanismo de integración con el Orquestador (Fase 2). Se genera con "Ignore Two Factor Authentication" para permitir llamadas programáticas.

---

## Próxima fase

**Fase 1d — Wazuh Single-Node**

Motor de detección y colección forense. Requiere:
1. Ajuste de kernel: `vm.max_map_count=262144`
2. Clonar repo oficial `wazuh/wazuh-docker v4.11.0`
3. Generar certificados TLS con `generate-indexer-certs.yml`
4. Arranque ordenado: indexer → manager → dashboard
