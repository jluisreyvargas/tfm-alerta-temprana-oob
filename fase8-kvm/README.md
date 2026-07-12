# 🖥️ Fase 8 — GLKVM self-hosted, acceso remoto seguro y control fuera de banda

<p align="center">
  <img src="https://img.shields.io/badge/Fase-8-1f6feb?style=for-the-badge" alt="Fase 8">
  <img src="https://img.shields.io/badge/Estado-Verificado-2ea043?style=for-the-badge" alt="Estado verificado">
  <img src="https://img.shields.io/badge/Stack-GLKVM%20%7C%20Traefik%20%7C%20Headscale%20%7C%20Tailscale-8250df?style=for-the-badge" alt="Stack">
  <img src="https://img.shields.io/badge/Acceso-OOB-orange?style=for-the-badge" alt="Acceso OOB">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Reverse%20Proxy-Traefik-24A1C1?style=flat-square" alt="Traefik">
  <img src="https://img.shields.io/badge/Auth-Authelia-FB542B?style=flat-square" alt="Authelia">
  <img src="https://img.shields.io/badge/Mesh%20VPN-Headscale-0A84FF?style=flat-square" alt="Headscale">
  <img src="https://img.shields.io/badge/Tunnel-Tailscale-242424?style=flat-square" alt="Tailscale">
  <img src="https://img.shields.io/badge/KVM-GL.iNet%20Comet-5c4ee5?style=flat-square" alt="GL.iNet Comet">
</p>

## 📌 Objetivo

Esta fase implementa un servicio **GLKVM Cloud self-hosted** para proporcionar acceso remoto fuera de banda a un dispositivo **GL.iNet KVM (Comet/GL-RM1)** desde el enclave del proyecto, integrándolo con la infraestructura existente basada en **Traefik**, **Authelia** y una malla privada **Headscale/Tailscale**.[cite:1][cite:3]

El resultado validado es un portal web propio accesible en `https://kvm.oob.local`, registro correcto del dispositivo KVM en la plataforma self-hosted, acceso **Remote SSH** operativo desde la interfaz GLKVM y acceso **Remote Control** operativo de forma directa a través de la IP Tailscale del dispositivo.[cite:1][cite:144]

## ✅ Alcance verificado

Se han verificado los siguientes puntos funcionales en laboratorio:

- Despliegue de `glkvm_cloud` y `coturn` mediante Docker Compose.[cite:1]
- Integración del servicio web con **Traefik** en `kvm.oob.local`.[cite:85]
- Protección del acceso web mediante **Traefik + file provider** y preparación para integración con Authelia.[cite:103][cite:114]
- Registro del dispositivo GL.iNet KVM en el servicio self-hosted.[cite:1]
- Conectividad del dispositivo a través de **Headscale/Tailscale** usando un `login-server` personalizado.[cite:249][cite:262]
- Funcionamiento del flujo **Remote SSH** desde la interfaz GLKVM.[cite:1]
- Funcionamiento del **control remoto directo** mediante IP Tailscale del KVM.[cite:160][cite:164]

## 🏗️ Arquitectura final

```text
┌────────────────────────────────────────────────────────────────────┐
│ Usuario                                                           │
│  Navegador → https://kvm.oob.local                                │
└────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────────┐
│ Ubuntu Server / VMware                                            │
│                                                                    │
│  Traefik  ──► Router kvm.oob.local ──► glkvm_cloud:8180           │
│     │                                                              │
│     └── dynamic middlewares (@file)                               │
│                                                                    │
│  Headscale  ◄──── cliente Tailscale del KVM                       │
│     │                                                              │
│     └── red overlay 100.64.0.0/10                                 │
│                                                                    │
│  coturn :3478                                                      │
│  rttys  :5912                                                      │
└────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────────┐
│ Dispositivo GL.iNet KVM                                           │
│  - Registro en GLKVM Cloud self-hosted                            │
│  - Cliente Tailscale apuntando a Headscale                        │
│  - Acceso directo por IP Tailscale                                │
└────────────────────────────────────────────────────────────────────┘
```

La plataforma GLKVM Cloud proporciona el plano de control del KVM, mientras que Headscale/Tailscale aporta una red privada overlay para alcanzar el dispositivo sin exponerlo directamente a internet.[cite:1][cite:253]

## 📂 Estructura de la fase

```text
fase8-kvm/
└── glkvm-cloud/
    └── docker-compose/
        ├── docker-compose.yml
        ├── .env
        ├── certificate/
        │   ├── glkvm.cer
        │   └── glkvm.key
        ├── database/
        │   └── schema.sql
        ├── scripts/
        │   └── docker-entrypoint.sh
        └── templates/
            ├── rttys.conf.template
            └── turnserver.conf.template
```

La carpeta `database/` debe contener `schema.sql`, ya que el contenedor `glkvm_cloud` inicializa su base de datos desde `/home/database/schema.sql`; si el fichero no existe, el servicio entra en bucle de reinicio.[cite:1]

## 🐳 Docker Compose validado

El despliegue funcional utiliza un `docker-compose.yml` con dos servicios: `rttys` (GLKVM Cloud) y `coturn` (TURN/WebRTC), conectados a una red interna propia y a la red externa `oob-network` para ser consumidos por Traefik.[cite:1][cite:85]

### Servicio `rttys`

Características validadas:

- Expone `5912/tcp` para la conexión del dispositivo KVM al servicio `rtty`.[cite:1]
- Expone `10443/tcp` para el proxy HTTP interno que usa GLKVM para el control remoto.[cite:1]
- Publica el Web UI interno en `8180`, consumido por Traefik dentro de Docker sin mapearlo al host.[cite:1][cite:97]
- Usa labels explícitas de Traefik con `traefik.docker.network=oob-network`.[cite:85][cite:108]

### Servicio `coturn`

- Expone `3478/tcp` y `3478/udp` para el componente WebRTC/TURN usado por el control remoto del dispositivo.[cite:1]

## 🔐 Integración con Traefik

La integración con Traefik se apoya en el proveedor Docker y en un proveedor `file` para middlewares dinámicos.[cite:85][cite:114]

### Configuración estática relevante

En `fase1-infraestructura/traefik/traefik.yml` se usa:

```yaml
providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: oob-network
  file:
    directory: /etc/traefik/dynamic
    watch: true
```

Esta configuración indica a Traefik que resuelva los servicios Docker usando la red `oob-network` y cargue middlewares desde `/etc/traefik/dynamic`.[cite:85][cite:114]

### Labels validadas en `rttys`

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.docker.network=oob-network"
  - "traefik.http.routers.kvm.rule=Host(`kvm.oob.local`)"
  - "traefik.http.routers.kvm.entrypoints=websecure"
  - "traefik.http.routers.kvm.tls=true"
  - "traefik.http.routers.kvm.middlewares=secure-headers@file"
  - "traefik.http.services.kvm.loadbalancer.server.port=8180"
```

El uso de `@file` es importante: los middlewares definidos en `middlewares.yml` no pertenecen al provider Docker, sino al provider de archivos. Referenciarlos como `@docker` provoca que el router quede deshabilitado con error `middleware does not exist`.[cite:103][cite:106]

## 🧱 Middleware dinámico validado

El fichero `fase1-infraestructura/traefik/dynamic/middlewares.yml` debe tener sintaxis YAML correcta. Una indentación errónea hace que Traefik descarte la configuración dinámica completa.[cite:103][cite:98]

Versión válida utilizada:

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

    authelia:
      forwardAuth:
        address: "http://authelia:9091/api/authz/forward-auth"
        trustForwardHeader: true
        authResponseHeaders:
          - "Remote-User"
          - "Remote-Groups"
          - "Remote-Name"
          - "Remote-Email"
```

## 🌐 Dominio de acceso

Se validó que el dominio del KVM debía alinearse con la política de cookies y control de acceso de Authelia dentro de `*.oob.local`. Por ello, el acceso final se fijó en `kvm.oob.local` en lugar de `kvm.local`.[cite:1]

Esto mantiene coherencia con el resto de servicios del enclave (`n8n.oob.local`, `chat.oob.local`, `wazuh.oob.local`) y evita problemas de sesión cruzada o reglas de acceso fuera del dominio permitido.[cite:1]

## 🧩 Problemas reales encontrados y resolución

### 1. Middleware inexistente en Traefik

**Síntoma:** `middleware "authelia@docker" does not exist`.[cite:106]

**Causa:** el middleware estaba definido en `middlewares.yml`, por tanto pertenecía al provider `file`, no a Docker.[cite:103][cite:114]

**Resolución:** cambiar la referencia a `authelia@file` o, durante la validación base, usar temporalmente `secure-headers@file`.[cite:103]

### 2. Router deshabilitado por error YAML

**Síntoma:** Traefik mostraba errores de parseo en `middlewares.yml`.[cite:98]

**Causa:** indentación incorrecta en el YAML del provider dinámico.[cite:98][cite:103]

**Resolución:** reescritura completa del fichero con indentación válida.[cite:98]

### 3. `glkvm_cloud` no arrancaba

**Síntomas observados:**

- `SQL logic error: no such table: devices`
- `init schema failed error="open /home/database/schema.sql: no such file or directory"`
- `unable to open database file: out of memory (14)` [cite:1]

**Causa real:** el servicio requiere la ruta `/home/database` con un `schema.sql` presente. Montar un volumen vacío o una ruta sin ese fichero rompe la inicialización del servicio.[cite:1]

**Resolución:** mantener una carpeta `database/` local con `schema.sql` y montarla en `/home/database`.[cite:1]

### 4. El dispositivo no podía alcanzar el servidor self-hosted de forma estable

**Causa:** uso inicial de IP pública y luego necesidad de incorporar una malla privada para el laboratorio.[cite:159][cite:163]

**Resolución:** integración del dispositivo con Headscale/Tailscale y uso del nodo Ubuntu como punto de entrada controlado.[cite:253][cite:249]

## 🔗 Integración con Headscale / Tailscale

El laboratorio no usa el control-plane oficial de Tailscale, sino un despliegue local de **Headscale**. Esto obliga a que el cliente Tailscale del dispositivo GL.iNet use un `login-server` personalizado, porque la GUI estándar de GL.iNet está orientada a Tailscale oficial y no a un coordinador autoalojado.[cite:250][cite:251][cite:262]

### Configuración relevante de Headscale

El servicio se ejecuta en Docker y usa SQLite como backend, con prefijo `100.64.0.0/10` y `MagicDNS` sobre `oob.local`.[cite:253]

Aspecto clave validado:

- `server_url` no puede apuntar a `http://headscale:8090` si el cliente es externo a Docker, porque ese nombre solo es resoluble dentro de la red interna del contenedor.[cite:253]
- Para el alta inicial del KVM, el servidor Ubuntu necesitó una segunda interfaz accesible en el mismo segmento LAN del dispositivo (`192.168.0.x`).[cite:265][cite:267]

### Modificación operativa de `gl_tailscale`

El cliente Tailscale del dispositivo KVM solo pudo darse de alta correctamente editando el script `/usr/bin/gl_tailscale` para introducir:

- `--login-server=http://<IP_LAN_UBUNTU>:8090`
- `--authkey=<PREAUTH_KEY>` [cite:262][cite:249]

Durante la validación, el mensaje `backend error: handling register with auth key: auth-key not found` indicó que la preauth key usada no existía o había caducado; la solución fue generar una nueva key en Headscale y reutilizarla en el alta del nodo KVM.[cite:346][cite:342]

## 🧪 Flujo funcional validado

El flujo final validado fue el siguiente:

1. El usuario accede a `https://kvm.oob.local` y autentica en la web self-hosted de GLKVM Cloud.[cite:1]
2. El dispositivo GL.iNet KVM aparece registrado correctamente en el panel.[cite:1]
3. La opción **Remote SSH** funciona mediante la ruta `#/rtty/<device-id>` del frontal web.[cite:1]
4. El acceso **Remote Control** funciona al conectar directamente con la IP Tailscale del dispositivo KVM.[cite:160][cite:164]

## ⚠️ Limitación documentada

La funcionalidad **Remote Control** lanzada desde la propia interfaz web de GLKVM Cloud no queda completamente operativa detrás del reverse proxy actual. El portal genera una URL como:

```text
https://<device-id>.kvm.oob.local/web/<device-id>/https/127.0.0.1:443/?rttysid=...
```

pero esa ruta no se resuelve correctamente en el despliegue actual con Traefik y self-hosting, mientras que el acceso directo al dispositivo por Tailscale sí funciona.[cite:351][cite:352]

### Impacto

- **Remote SSH:** operativo desde la UI.
- **Remote Control vía UI:** no operativo de forma estable en el reverse proxy actual.
- **Remote Control directo por Tailscale:** operativo y validado.[cite:160][cite:164][cite:352]

## 🔮 Mejora futura a investigar

Queda identificada como línea de trabajo futura la adaptación de Traefik para soportar correctamente el flujo `/web/<device-id>/https/127.0.0.1:443` generado por GLKVM Cloud.[cite:351][cite:352]

Las líneas de investigación recomendadas son:

- Revisar si GLKVM Cloud espera cabeceras `X-Forwarded-*` específicas del reverse proxy.[cite:362]
- Añadir una regla dedicada en Traefik para el subdominio dinámico `<device-id>.kvm.oob.local`.[cite:351][cite:352]
- Validar si Authelia o los middlewares de seguridad interfieren con esa ruta específica.[cite:103][cite:351]
- Confirmar si versiones futuras de GLKVM Cloud mejoran el soporte nativo tras reverse proxies.[cite:352]

## 🛠️ Operación básica

### Levantar el servicio

```bash
cd ~/tfm-alerta-temprana-oob/fase8-kvm/glkvm-cloud/docker-compose
docker compose up -d
```

### Ver logs de GLKVM Cloud

```bash
docker logs -f glkvm_cloud
```

### Ver logs de coturn

```bash
docker logs -f glkvm_coturn
```

### Verificar router en Traefik

```bash
curl -s http://localhost:8080/api/http/routers | python3 -m json.tool | grep -B 3 -A 15 '"name": "kvm@docker"'
```

### Verificar nodos en Headscale

```bash
docker exec -it headscale headscale nodes list
```

## 🧭 Resultado de la fase

Esta fase queda completada con un despliegue **self-hosted y funcional** de GLKVM Cloud integrado en el entorno del proyecto, con acceso web por `kvm.oob.local`, registro del dispositivo KVM, conectividad overlay mediante Headscale/Tailscale y acceso remoto validado tanto por web (Remote SSH) como por canal directo Tailscale (Remote Control).[cite:1][cite:253][cite:164]

La única limitación abierta y documentada es la compatibilidad total del flujo **Remote Control** desde la interfaz web detrás de Traefik, que se mantiene como mejora futura claramente acotada y técnicamente identificada.[cite:351][cite:352]
