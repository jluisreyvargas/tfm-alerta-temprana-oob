# ✅ Fase 1a — Traefik + Portainer (COMPLETADA)

> **Estado:** ✅ Completada y validada
> **Sistema:** Ubuntu 24.04.4 LTS (Noble Numbat) — kernel 6.8.0-111-generic
> **Docker Engine:** 29.4.2 (instalación oficial .deb — NO snap)
> **Fecha de cierre:** Mayo 2026

---

## 🎯 Objetivo de esta fase

Levantar la base del enclave out-of-band con:
- **Traefik v3.3** como reverse proxy con TLS automático (Let's Encrypt)
- **Portainer CE** como gestor visual de contenedores Docker
- **Red Docker `oob-network`** compartida entre todas las fases del proyecto

---

## ⚠️ Problemas encontrados y resueltos

Documenta los problemas reales para que sirvan de referencia en la defensa del TFM.

### Problema 1 — Docker snap instalado en paralelo con Docker Engine .deb
**Síntoma:** `exec /entrypoint.sh: operation not permitted` en Traefik y Portainer.
**Causa:** Ubuntu 24.04 tenía el snap de Docker de Canonical (`snap.docker.dockerd`) activo junto al Docker Engine oficial. El perfil AppArmor del snap bloqueaba `no-new-privileges` y la ejecución de entrypoints.
**Solución:**
```bash
sudo snap stop docker
sudo snap remove --purge docker
# Eliminar perfiles AppArmor residuales del snap
sudo apparmor_parser -R /var/lib/snapd/apparmor/profiles/snap.docker.dockerd
sudo apparmor_parser -R /var/lib/snapd/apparmor/profiles/snap.docker.docker
sudo apparmor_parser -R /var/lib/snapd/apparmor/profiles/snap.docker.compose
sudo apparmor_parser -R /var/lib/snapd/apparmor/profiles/snap-update-ns.docker
sudo rm -f /var/lib/snapd/apparmor/profiles/snap.docker.*
sudo rm -f /var/lib/snapd/apparmor/profiles/snap-update-ns.docker
sudo systemctl restart docker
```

### Problema 2 — Red `oob-network` desaparece tras reboot
**Síntoma:** `network oob-network declared as external, but could not be found`
**Causa:** Las redes Docker externas no son persistentes entre reinicios si no están en un Compose activo.
**Solución:** Crear un servicio systemd que la recrea automáticamente al arranque (ver Paso 3 de esta guía).

### Problema 3 — Traefik v3.2 + Docker 29.x incompatibilidad de API
**Síntoma:** `client version 1.24 is too old. Minimum supported API version is 1.40`
**Causa:** Docker 29 subió la API mínima a 1.44, pero Traefik v3.2 negocia internamente con API 1.24.
**Solución:** Actualizar a **Traefik v3.3** (bug corregido) y añadir `min-api-version` al daemon Docker.

---

## 📁 Archivos de esta fase

```
fase1-infraestructura/
├── docker-compose.yml          ← Traefik + Portainer (+ servicios de fases 1b-1c)
├── .env                        ← Variables de entorno (NO subir a Git)
├── .env.example                ← Plantilla de variables (sí subir a Git)
├── .gitignore                  ← Exclusiones Git
├── traefik/
│   ├── traefik.yml             ← Configuración estática de Traefik
│   ├── acme.json               ← Certificados TLS (NO subir a Git, chmod 600)
│   └── dynamic/
│       └── middlewares.yml     ← Middlewares de seguridad
├── authelia/                   ← (Fase 1b)
├── rocketchat/                 ← (Fase 1c)
└── wazuh/                      ← (Fase 1d)
```

---

## 🚀 Instalación paso a paso

### Paso 0 — Prerrequisitos

**Docker Engine oficial (NO snap):**
```bash
# Verificar instalación correcta
docker --version        # Docker version 29.4.x
which docker            # /usr/bin/docker (no /snap/bin/docker)
snap list | grep docker # debe estar vacío

# Si snap list muestra docker, eliminarlo:
sudo snap stop docker && sudo snap remove --purge docker
```

**Instalar Docker Engine .deb oficial si no está:**
```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg   -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture)   signed-by=/etc/apt/keyrings/docker.asc]   https://download.docker.com/linux/ubuntu   $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" |   sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io                     docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER
newgrp docker
```

---

### Paso 1 — Clonar/inicializar el repositorio

```bash
cd /home/jose
git clone https://github.com/TU_USUARIO/tfm-alerta-temprana-oob.git
cd tfm-alerta-temprana-oob

# Crear estructura de carpetas de Fase 1
mkdir -p fase1-infraestructura/{traefik/dynamic,authelia,rocketchat,wazuh,portainer}
```

---

### Paso 2 — Crear archivos de configuración

**`fase1-infraestructura/.gitignore`:**
```gitignore
.env
traefik/acme.json
authelia/db.sqlite3
authelia/notification.txt
wazuh/single-node/config/wazuh_indexer/certs/
*.pem
*.key
*.crt
```

**`fase1-infraestructura/.env`** (copiar de `.env.example` y editar):
```bash
cp fase1-infraestructura/.env.example fase1-infraestructura/.env
nano fase1-infraestructura/.env
```

Variables mínimas para Fase 1a:
```env
ENCLAVE_DOMAIN=oob.tudominio.com
ACME_EMAIL=tu@email.com
PORTAINER_VERSION=latest
```

**`fase1-infraestructura/traefik/traefik.yml`:**
```yaml
api:
  dashboard: true
  insecure: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"

certificatesResolvers:
  letsencrypt:
    acme:
      email: tu@email.com          # cambiar por tu email real
      storage: /etc/traefik/acme.json
      httpChallenge:
        entryPoint: web

providers:
  docker:
    endpoint: "unix:///run/docker.sock"
    exposedByDefault: false
    network: oob-network
  file:
    directory: /etc/traefik/dynamic
    watch: true

log:
  level: INFO
```

**`fase1-infraestructura/traefik/dynamic/middlewares.yml`:**
```yaml
http:
  middlewares:
    secure-headers:
      headers:
        sslRedirect: true
        stsSeconds: 31536000
        contentTypeNosniff: true
        browserXssFilter: true
        referrerPolicy: "same-origin"
```

**`fase1-infraestructura/docker-compose.yml`** (versión Fase 1a):
```yaml
networks:
  oob-network:
    external: true

services:

  traefik:
    image: traefik:v3.3        # v3.3+ requerido para Docker 29.x
    container_name: traefik
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro
      - ./traefik/acme.json:/etc/traefik/acme.json
      - ./traefik/dynamic:/etc/traefik/dynamic:ro
    networks:
      - oob-network

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    ports:
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - portainer_data:/data
    networks:
      - oob-network

volumes:
  portainer_data:
```

**`/etc/docker/daemon.json`** — compatibilidad API Docker 29.x con Traefik:
```json
{
  "min-api-version": "1.24"
}
```
```bash
sudo nano /etc/docker/daemon.json
# Añadir el contenido de arriba y guardar
sudo systemctl restart docker
```

---

### Paso 3 — Crear la red Docker y persistirla entre reinicios

```bash
# Crear la red
docker network create oob-network

# Servicio systemd para que sobreviva reboots
sudo tee /etc/systemd/system/docker-oob-network.service << 'EOF'
[Unit]
Description=Crear red Docker oob-network para enclave OOB
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'docker network ls | grep -q oob-network || docker network create oob-network'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable docker-oob-network
sudo systemctl start docker-oob-network
```

---

### Paso 4 — Preparar acme.json y levantar servicios

```bash
cd /home/jose/tfm-alerta-temprana-oob/fase1-infraestructura

# acme.json debe existir con permisos 600 (obligatorio para Traefik)
touch traefik/acme.json
chmod 600 traefik/acme.json
ls -la traefik/acme.json    # debe mostrar: -rw------- (jose jose)

# Levantar Traefik y Portainer
docker compose up -d traefik portainer
```

---

### Paso 5 — Verificación final

```bash
# Estado de contenedores
docker compose ps
# Resultado esperado:
# portainer   Up   0.0.0.0:9443->9443/tcp
# traefik     Up   0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp

# Puertos en escucha
ss -tulpn | grep -E ':80|:443|:9443'

# Logs limpios de Traefik (solo INF, sin ERR)
docker compose logs traefik | tail -10
# Esperado:
# INF Starting provider *docker.Provider
# INF Starting provider *file.Provider
# INF Starting provider *acme.ChallengeTLSALPN

# Acceso a Portainer
echo "Portainer disponible en: https://$(hostname -I | awk '{print $1}'):9443"
```

---

## ✅ Checklist de validación Fase 1a

- [x] Docker Engine .deb oficial instalado (no snap)
- [x] snap de Docker eliminado + perfiles AppArmor limpiados
- [x] `/etc/docker/daemon.json` con `min-api-version: 1.24`
- [x] Red `oob-network` creada + servicio systemd para persistirla
- [x] `traefik/acme.json` creado con chmod 600
- [x] Traefik v3.3 arrancando sin errores ERR en logs
- [x] Portainer accesible en `https://IP:9443`
- [x] Puertos 80, 443 y 9443 en escucha
- [x] Commit en Git con tag `fase1a-ok`

---

## 🔄 Siguiente fase

**Fase 1b — Authelia (MFA independiente del AD)**
Ver: [`docs/fase1b-authelia.md`](./fase1b-authelia.md)

---

## 📎 Referencias

- [Traefik v3 Docker Compose + Let's Encrypt](https://linuxblog.xyz/posts/traefik-3-docker-compose/)
- [Bug Traefik + Docker 29 API version](https://github.com/traefik/traefik/issues/12253)
- [Portainer CE Install on Linux](https://docs.portainer.io/start/install-ce/server/docker/linux)
- [Eliminar Docker snap Ubuntu 24.04](https://discourse.ubuntu.com/t/replacing-snap-docker-with-normal-docker/57256)

---
**TFM Alerta Temprana Out-of-Band | Fase 1a**
**Última actualización:** Mayo 2026
