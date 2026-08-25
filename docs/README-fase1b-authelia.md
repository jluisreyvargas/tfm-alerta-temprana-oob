# Fase 1b — Authelia MFA/IdP Out-of-Band

## Descripción

Esta fase implementa **Authelia** como proveedor de identidad (IdP) independiente del Active Directory corporativo, garantizando que la autenticación del enclave de respuesta a incidentes no dependa de infraestructura potencialmente comprometida. Se configura autenticación de doble factor (2FA) con soporte para TOTP y WebAuthn.

**Versión desplegada:** Authelia v4.39.19  
**Fecha de cierre:** Mayo 2026  
**Estado:** ✅ Operativo

---

## Arquitectura

```
Navegador → Traefik (reverse proxy) → forward-auth → Authelia :9091
                                                          ↓
                                              users_database.yml (local)
                                                          ↓
                                              db.sqlite3 (sesiones/TOTP/WebAuthn)
```

Authelia **no expone puerto al host** — solo es accesible a través de Traefik (principio out-of-band). Para acceso de laboratorio directo se puede exponer temporalmente el puerto 9091.

---

## Estructura de ficheros

```
fase1-infraestructura/
├── docker-compose.yml
├── .env
└── authelia/
    ├── configuration.yml       ← configuración principal
    ├── users_database.yml      ← usuarios y hashes de contraseña
    ├── db.sqlite3              ← base de datos de sesiones/TOTP (generada en runtime)
    └── notification.txt        ← enlace de registro 2FA (generado en runtime)
```

---

## Configuración aplicada

### `authelia/configuration.yml`

```yaml
server:
  address: tcp://0.0.0.0:9091/

log:
  level: info

identity_validation:
  reset_password: {}    # jwt_secret via variable de entorno

totp:
  issuer: TFM-OOB-Lab

authentication_backend:
  file:
    path: /config/users_database.yml

access_control:
  default_policy: deny
  rules:
    - domain: 'chat.oob.local'
      subject: 'group:ir_lead'
      policy: two_factor

session:
  cookies:
    - domain: oob.local
      authelia_url: https://auth.oob.local
      default_redirection_url: https://chat.oob.local
      expiration: 3600
      inactivity: 1800

storage:
  local:
    path: /config/db.sqlite3

notifier:
  filesystem:
    filename: /config/notification.txt
```

> [!NOTE]
> **Corrección.** Esta sección presentaba tres valores que no coinciden con la `configuration.yml` real:
> - **`webauthn`**: el bloque completo mostrado más arriba nunca se aplicó — la configuración real no declara ningún bloque `webauthn`. La tabla "Estado de métodos 2FA" más abajo lo daba por habilitado; no lo está.
> - **`access_control.rules[0].domain`**: era `'*.oob.local'` (todo el enclave); el valor real es `'chat.oob.local'` — la política solo protege Rocket.Chat, el único servicio detrás de Authelia (ver `fase1-infraestructura/README.md`).
> - **`access_control.rules[0].subject`**: era `'group:irlead'`; el valor real es `'group:ir_lead'` (con guión bajo), igual que en `users_database.yml` — ver la nota de corrección más abajo.
> - **`session.cookies[0].default_redirection_url`**: era `https://portainer.oob.local`; el valor real es `https://chat.oob.local`. Tiene sentido: Portainer nunca estuvo detrás de Authelia, así que redirigir ahí tras autenticarse no encajaba con el único servicio protegido. Ver también la nota en "Error 4" más abajo.

### `authelia/users_database.yml`

```yaml
users:
  jose:
    displayname: "Jose - IR Lead"
    password: "$argon2id$v=19$m=65536,t=3,p=4$HASH_GENERADO"
    email: jose@oob.local
    groups:
      - ir_lead
      - ir_team
```

> ⚠️ **Nunca commitear el hash real** — el archivo `users_database.yml` está en `.gitignore`. Usar `users_database.yml.example` con valor de placeholder.

> [!NOTE]
> **Corrección.** Los nombres de grupo eran `irlead`/`irteam` (sin guión bajo); el `users_database.yml.example` real usa `ir_lead`/`ir_team`, coherente con el `subject: 'group:ir_lead'` de `access_control`. El fichero real también incluye más campos de claims OIDC vacíos (`given_name`, `family_name`, etc.) que este ejemplo simplificado omite, y `email: jose@localhost` en lugar de `jose@oob.local`.

### Variables de entorno (`.env`)

```env
ENCLAVE_DOMAIN=oob.local
AUTHELIA_JWT_SECRET=<hex-32-bytes>
AUTHELIA_SESSION_SECRET=<hex-32-bytes>
AUTHELIA_STORAGE_ENCRYPTION_KEY=<hex-32-bytes>
```

> Los secrets deben generarse con `openssl rand -hex 32`. Formato hexadecimal obligatorio — Base64 causa errores de interpolación en Docker Compose.

### Bloque en `docker-compose.yml`

```yaml
  authelia:
    image: authelia/authelia:latest
    container_name: authelia
    restart: unless-stopped
    volumes:
      - ./authelia:/config
    environment:
      - AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET=${AUTHELIA_JWT_SECRET}
      - AUTHELIA_SESSION_SECRET=${AUTHELIA_SESSION_SECRET}
      - AUTHELIA_STORAGE_ENCRYPTION_KEY=${AUTHELIA_STORAGE_ENCRYPTION_KEY}
    networks:
      - oob-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.authelia.rule=Host(`auth.${ENCLAVE_DOMAIN}`)"
      - "traefik.http.routers.authelia.entrypoints=websecure"
      - "traefik.http.routers.authelia.tls=true"
      - "traefik.http.services.authelia.loadbalancer.server.port=9091"
```

---

## `/etc/hosts` requerido (laboratorio local)

```
127.0.0.1   auth.oob.local
127.0.0.1   portainer.oob.local
127.0.0.1   chat.oob.local
127.0.0.1   wazuh.oob.local
```

---

## Problemas encontrados y soluciones

### Error 1 — `invalid interpolation format`
**Causa:** Secrets en formato Base64 (con `+`, `/`, `=`) pegados directamente en `docker-compose.yml` dentro de `${}`.  
**Solución:** Generar secrets con `openssl rand -hex 32` y almacenarlos solo en `.env`. El compose referencia `${NOMBRE_VARIABLE}`, nunca el valor.

### Error 2 — `domain 'local' is not a valid cookie domain`
**Causa:** Authelia 4.38+ requiere que el dominio de cookie tenga al menos un punto.  
**Solución:** Cambiar `domain: local` a `domain: oob.local` en la sección `session.cookies`.

### Error 3 — `jwt_secret` deprecated conflict
**Causa:** Clave `jwt_secret` a nivel raíz coexistiendo con `identity_validation.reset_password`.  
**Solución:** Eliminar `jwt_secret` del YAML y pasar el secret exclusivamente via variable de entorno `AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET`.

### Error 4 — `default_redirection_url effectively equal to authelia_url`
**Causa:** La URL de redirección post-login no puede ser igual a la URL de Authelia.  
**Solución (en esta fase):** `default_redirection_url` apunta a `https://portainer.oob.local` en lugar de `https://auth.oob.local`.

> [!NOTE]
> **Corrección.** El valor final desplegado es `https://chat.oob.local`, no `https://portainer.oob.local`: Portainer nunca quedó detrás de Authelia (ver `fase1-infraestructura/README.md`), así que no tenía sentido como destino tras un login que solo protege Rocket.Chat.

### Error 5 — WebAuthn no disponible en `https://auth.oob.local`
**Causa:** WebAuthn requiere contexto seguro: HTTPS con certificado válido o `localhost` exacto. Los certificados self-signed no son aceptados por los navegadores para WebAuthn.  
**Solución:** Para registro WebAuthn en laboratorio, acceder via `http://localhost:9091` (excepción explícita del estándar WebAuthn W3C).

---

## Procedimiento de despliegue

### Prerrequisitos
- Docker y Docker Compose instalados
- Red `oob-network` creada (`docker network create oob-network`)
- Traefik y Portainer operativos (Fase 1a completada)
- Entradas `/etc/hosts` añadidas

### Paso 1 — Generar secrets
```bash
echo "AUTHELIA_JWT_SECRET=$(openssl rand -hex 32)"
echo "AUTHELIA_SESSION_SECRET=$(openssl rand -hex 32)"
echo "AUTHELIA_STORAGE_ENCRYPTION_KEY=$(openssl rand -hex 32)"
```

### Paso 2 — Crear estructura de directorios
```bash
mkdir -p ~/tfm-alerta-temprana-oob/fase1-infraestructura/authelia
```

### Paso 3 — Crear ficheros de configuración
Copiar `configuration.yml` y `users_database.yml` con los valores del apartado anterior.

### Paso 4 — Generar hash de contraseña de usuario
```bash
docker run --rm authelia/authelia:latest \
  authelia crypto hash generate argon2 --password TU_PASSWORD_SEGURA
```

### Paso 5 — Arrancar el servicio
```bash
cd ~/tfm-alerta-temprana-oob/fase1-infraestructura
docker compose up -d authelia
docker compose logs -f authelia
```

Resultado esperado:
```
level=info  msg="Startup complete"
level=info  msg="Listening for non-TLS connections on '[::]:9091' path '/'"
```

### Paso 6 — Registrar TOTP
```bash
# Leer enlace de registro del fichero de notificación
cat ~/tfm-alerta-temprana-oob/fase1-infraestructura/authelia/notification.txt
```
Abrir el enlace en el navegador y escanear el código QR con Google Authenticator, Authy o Microsoft Authenticator.

---

## Verificación

```bash
# Estado del contenedor
docker compose ps authelia

# Logs sin errores
docker compose logs --tail=20 authelia

# Acceso al portal
curl -k -o /dev/null -w "%{http_code}" https://auth.oob.local
# Esperado: 200 o 302

# Puerto escuchando
ss -tulpn | grep 9091
```

---

## Estado de métodos 2FA

| Método | Estado | Notas |
|--------|--------|-------|
| TOTP (OTP 6 dígitos) | ✅ Registrado y funcional | Compatible con Google Authenticator, Authy, Microsoft Authenticator |
| WebAuthn (passkey/FIDO2) | ⚠️ Sin configurar (corregido) | La `configuration.yml` real no declara ningún bloque `webauthn`. El registro descrito vía `http://localhost:9091` corresponde al plan inicial, no al estado final. |
| Email OTP | ⚪ No configurado | Notifier filesystem usado para lab — Mailhog opcional en fases posteriores |

---

## Decisiones de diseño

- **`notifier.filesystem`** en lugar de SMTP: en entorno de laboratorio local no existe servidor de correo. Los enlaces de registro se escriben en `notification.txt` y se leen directamente. Para producción se sustituiría por un bloque `notifier.smtp` apuntando a un servidor interno.
- **SQLite** en lugar de PostgreSQL/MySQL: suficiente para laboratorio. En producción con alta disponibilidad se migraría a PostgreSQL.
- **Secrets hexadecimales** (`openssl rand -hex 32`): evita caracteres especiales (`+`, `/`, `=`) que Docker Compose interpola incorrectamente.
- **Sin puerto expuesto al host**: Authelia solo es accesible a través de Traefik, manteniendo el principio out-of-band. El puerto 9091 se expone temporalmente solo para tareas de administración.

---

## Próxima fase

**Fase 1c — MongoDB + Rocket.Chat**

Canal de comunicación out-of-band del War Room. Requiere:
1. MongoDB 6.0 con replica set inicializado
2. Rocket.Chat con `ROOT_URL` apuntando a `https://chat.oob.local`
3. Creación de canales `#alerts` y `#war-room`
4. Usuario `orchestrator-bot` con token API para integración con el Orquestador (Fase 2)
