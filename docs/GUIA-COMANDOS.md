# Guía de comandos del enclave OOB

- **Commit analizado:** `c233bbe` (2026-09-27).
- **Universo de fuentes:** 99 ficheros con comandos, de 123 examinados (Paso 0), más `docs/LECCIONES-OPERATIVAS-conversaciones.md`. Este último procede de conversaciones de trabajo transcritas, no de mediciones repetidas: sus entradas dicen qué observó la conversación y qué no quedó registrado. Excluidos: MISP, el código de DFIR-IRIS (`fase6-iris/{source,docker,tests}`, `linguist-vendored`) y los árboles upstream sin cambios del proyecto (Wazuh-docker, glkvm-cloud, documentación de IRIS).
- **Registro trazable:** [`GUIA-COMANDOS-inventario.tsv`](GUIA-COMANDOS-inventario.tsv). Cada entrada de esta guía corresponde a una fila del inventario con el mismo identificador; si hay discrepancia, manda el inventario.
- **Entradas:** 452. Los comandos se copian literalmente de la fuente; los multilínea se reconstruyen a partir de la columna `comando` (unida con ` ⏎ `).

## Leyenda de estados

| Estado | Cuándo se usa |
|---|---|
| `VALIDADO` | La fuente registra la salida o el efecto observado (código HTTP, `exit 0`, `healthy`, `Verify return code: 0`, `True`, hash coincidente…). |
| `PROCEDIMIENTO` | Aparece como instrucción, pero la fuente no registra ningún resultado observado. |
| `FALLÓ` | La fuente registra que falló o que su resultado engañó. `→ C-0MM` remite a la corrección cuando existe. |
| `CONTROL-NEGATIVO` | Ejecutado para comprobar que algo se deniega o falla (403, 401, `False`…). |
| `DIAGNÓSTICO` | Inspección sin efecto sobre el sistema. |

Criterios de aplicación: «resultado esperado» y los comentarios `# →` de las guías se tratan como expectativa, no como observación. Una inspección de solo lectura es `DIAGNÓSTICO` cuando su papel fue investigar, aunque la fuente registre su salida; es `VALIDADO` cuando verificó un despliegue o un control. Los documentos de planificación («solo de planificación», «sin ejecutar», «pruebas que debe ejecutar el usuario») quedan como `PROCEDIMIENTO`.

**(genérico)** marca la explicación de la herramienta, contrastada con `--help` cuando está disponible en el entorno de redacción; **(en este proyecto)** marca lo que cuenta la fuente. Los valores con aspecto de credencial, incluidos los marcadores de la fuente, aparecen como `[REDACTADO]` (en las cabeceras HTTP `Authorization` y `X-Auth-Token`, como `<REDACTADO>`, el formato de marcador que admite `scripts/verify-no-secrets.sh`): el valor real se introduce con `read -s` en su propia línea, que es el patrón del proyecto (C-085). Las referencias a variables (`${AGENT_TOKEN}`, `${OS_PASS:?…}`) se conservan.

---

## Parte I — Por herramienta

Las entradas de PowerShell y las ejecutadas en DC01-TFM o analyst-w11 están en la Parte IV.

## I.1 Docker Compose

**(en este proyecto)** Cada fase se despliega como un proyecto Compose propio (`fase1-infraestructura/`, `wazuh/single-node/`, `fase2-orquestador/n8n/`, `fase3-agentic/`, `fase4-breakglass-dc/headscale/config/`, `fase4-breakglass-dc/` para RustDesk y Headscale UI, `fase5-velociraptor/`, `fase6-iris/`, `fase8-kvm/glkvm-cloud/docker-compose/`). Las fuentes registran dos lecciones repetidas: el directorio de trabajo y `-f` deciden qué ficheros se cargan (override incluido), y un cambio en el compose no actúa hasta recrear el contenedor. Esta familia incluye las claves `command`, `entrypoint` y `test` de los compose versionados.

### C-018 · Levantar Traefik y Portainer

```bash
docker compose up -d traefik portainer
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano.
- **En este proyecto:** Fase 1 · Traefik · directorio: `/home/jose/tfm-alerta-temprana-oob/fase1-infraestructura`. Levantar Traefik y Portainer.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:293`

### C-019 · Estado de los contenedores del proyecto Compose (la fuente da el resultado…

```bash
docker compose ps
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `ps`: lista los contenedores del proyecto y su estado.
- **En este proyecto:** Fase 1 · Traefik · directorio: `varios: fase1-infraestructura, wazuh/single-node, fase2-orquestador/n8n`. Estado de los contenedores del proyecto Compose (la fuente da el resultado esperado, no el observado).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:302`, `docs/README-fase1d-wazuh.md:204`, `docs/README-fase1d-wazuh.md:213`, `fase2-orquestador/n8n/README.md:39`

### C-021 · Revisar el log de Traefik

```bash
docker compose logs traefik | tail -10
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `logs`: muestra la salida de los contenedores del servicio. `tail [-N]`: últimas líneas.
- **En este proyecto:** Fase 1 · Traefik · directorio: `/home/jose/tfm-alerta-temprana-oob/fase1-infraestructura`. Revisar el log de Traefik (esperado: solo INF).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:311`

### C-027 · Arrancar Authelia

```bash
docker compose up -d authelia
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano.
- **En este proyecto:** Fase 1 · Authelia · directorio: `~/tfm-alerta-temprana-oob/fase1-infraestructura`. Arrancar Authelia.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1b-authelia.md:229`

### C-028 · Seguir el log de arranque (esperado «Startup complete»)

```bash
docker compose logs -f authelia
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `logs`: muestra la salida de los contenedores del servicio. `logs -f`: sigue el log en tiempo real.
- **En este proyecto:** Fase 1 · Authelia · directorio: `~/tfm-alerta-temprana-oob/fase1-infraestructura`. Seguir el log de arranque (esperado «Startup complete»).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1b-authelia.md:230`

### C-030 · Estado del contenedor de Authelia

```bash
docker compose ps authelia
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `ps`: lista los contenedores del proyecto y su estado.
- **En este proyecto:** Fase 1 · Authelia · directorio: no consta. Estado del contenedor de Authelia.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1b-authelia.md:252`

### C-031 · Últimas 20 líneas del log de Authelia

```bash
docker compose logs --tail=20 authelia
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `logs`: muestra la salida de los contenedores del servicio. `--tail N`: solo las últimas N líneas.
- **En este proyecto:** Fase 1 · Authelia · directorio: no consta. Últimas 20 líneas del log de Authelia.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1b-authelia.md:255`

### C-037 · Primer arranque de MongoDB sin keyFile

```bash
docker compose up -d mongodb
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano.
- **En este proyecto:** Fase 1 · MongoDB · directorio: no consta. Primer arranque de MongoDB sin keyFile.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1c-mongodb-rocketchat.md:177`

### C-041 · Recrear MongoDB con el keyFile activado

```bash
docker compose up -d --force-recreate mongodb
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano. `--force-recreate`: recrea los contenedores aunque su configuración y su imagen no hayan cambiado.
- **En este proyecto:** Fase 1 · MongoDB · directorio: no consta. Recrear MongoDB con el keyFile activado.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1c-mongodb-rocketchat.md:235`

### C-042 · Vigilar hasta «healthy»

```bash
watch docker compose ps mongodb
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `ps`: lista los contenedores del proyecto y su estado. `watch CMD`: repite el comando cada 2 s.
- **En este proyecto:** Fase 1 · MongoDB · directorio: no consta. Vigilar hasta «healthy».
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1c-mongodb-rocketchat.md:236`

### C-043 · Arrancar Rocket.Chat y seguir su log (esperado «SERVER RUNNING»)

```bash
docker compose up -d rocketchat
docker compose logs -f rocketchat
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano. `logs`: muestra la salida de los contenedores del servicio. `logs -f`: sigue el log en tiempo real.
- **En este proyecto:** Fase 1 · Rocket.Chat · directorio: no consta. Arrancar Rocket.Chat y seguir su log (esperado «SERVER RUNNING»).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1c-mongodb-rocketchat.md:270`

### C-044 · Estado de mongodb y rocketchat

```bash
docker compose ps mongodb rocketchat
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `ps`: lista los contenedores del proyecto y su estado.
- **En este proyecto:** Fase 1 · Rocket.Chat · directorio: no consta. Estado de mongodb y rocketchat.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1c-mongodb-rocketchat.md:329`

### C-053 · Generar los certificados TLS del indexer

```bash
docker compose -f generate-indexer-certs.yml run --rm generator
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `-f FICHERO`: fichero de configuración de Compose que se usa en lugar de los descubiertos automáticamente. `run --rm SERVICIO`: ejecuta un contenedor puntual del servicio y lo elimina al terminar.
- **En este proyecto:** Fase 1 · Wazuh · directorio: `single-node`. Generar los certificados TLS del indexer.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1d-wazuh.md:134`

### C-057 · Arrancar indexer, manager y dashboard en orden estricto

```bash
docker compose up -d wazuh.indexer
sleep 30
docker compose up -d wazuh.manager
sleep 15
docker compose up -d wazuh.dashboard
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano. `sleep N`: espera N segundos.
- **En este proyecto:** Fase 1 · Wazuh · directorio: `~/tfm-alerta-temprana-oob/fase1-infraestructura/wazuh/single-node`. Arrancar indexer, manager y dashboard en orden estricto.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1d-wazuh.md:193`

### C-076 · Estado de los servicios

```bash
docker compose ps --format "table {{.Name}}\t{{.Status}}"
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `ps`: lista los contenedores del proyecto y su estado.
- **En este proyecto:** Fase 1 · host · directorio: `fase1-infraestructura`. Estado de los servicios (salida esperada: Up; authelia y mongodb healthy).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase1-infraestructura/README.md:227`

### C-078 · Rs.status().ok con credenciales por variable (esperado 1)

```bash
docker compose exec mongodb mongosh --quiet \
  -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin --eval "rs.status().ok"
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `docker compose exec SERVICIO CMD`: ejecuta un comando en el contenedor de un servicio en marcha. `mongosh`: shell de MongoDB. `--quiet`: sin banner; `--eval JS`: ejecuta y sale; `-u/-p/--authenticationDatabase`: credenciales y base de autenticación.
- **En este proyecto:** Fase 1 · MongoDB · directorio: no consta. rs.status().ok con credenciales por variable (esperado 1).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase1-infraestructura/README.md:244`

### C-079 · Alcance de Authelia desde Traefik

```bash
docker compose exec traefik wget -qO- http://authelia:9091/api/health
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `docker compose exec SERVICIO CMD`: ejecuta un comando en el contenedor de un servicio en marcha. `wget URL`: cliente HTTP. `-q`: sin mensajes; `-O-`: escribe el cuerpo en la salida estándar.
- **En este proyecto:** Fase 1 · Authelia · directorio: no consta. Alcance de Authelia desde Traefik.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase1-infraestructura/README.md:254`

### C-098 · Configurar .env y construir/levantar el motor de triage

```bash
cd fase3-agentic
cp .env.example .env && nano .env
docker compose up -d --build
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano. `--build`: construye las imágenes antes de arrancar. `nano`: editor de texto en terminal. `cp ORIGEN DESTINO`: copia ficheros. `cd DIR`: cambia el directorio de trabajo.
- **En este proyecto:** Fase 3 · orchestrator · directorio: `fase3-agentic`. Configurar .env y construir/levantar el motor de triage.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase2-orquestador/README.md:429`

### C-099 · Crear .env de n8n desde .env.example y levantar

```bash
cd fase2-orquestador/n8n
cp .env.example .env && nano .env
docker compose up -d
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano. `nano`: editor de texto en terminal. `cp ORIGEN DESTINO`: copia ficheros. `cd DIR`: cambia el directorio de trabajo.
- **En este proyecto:** Fase 2 · n8n · directorio: `fase2-orquestador/n8n`. Crear .env de n8n desde .env.example y levantar. La corrección de 2026-09-24 registra que n8n/.env.example no existe: el .env se crea a mano.
- **Resultado:** **FALLÓ**
- **Fuente:** `fase2-orquestador/README.md:434`

### C-109 · Levantar n8n

```bash
docker compose up -d
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano.
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. Levantar n8n.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase2-orquestador/n8n/README.md:36`, `fase2-orquestador/n8n/README.md:113`

### C-131 · Primer intento de reinicio

```bash
cd fase4-breakglass-dc && docker compose restart headscale
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `restart`: reinicia los contenedores del servicio sin recrearlos. `cd DIR`: cambia el directorio de trabajo.
- **En este proyecto:** Fase 4 · Headscale · directorio: `fase4-breakglass-dc`. Primer intento de reinicio: «no configuration file provided: not found»; sin echo $? era indistinguible de «reiniciado y sin efecto».
- **Resultado:** **FALLÓ** (→ C-132)
- **Fuente:** `docs/HALLAZGO-headscale-politica-modo-file.md:93`, `docs/README-fase4a-headscale.md:61`

### C-132 · Reiniciar Headscale para recargar la ACL en modo file

```bash
docker compose -f docker-compose.headscale.yml restart headscale
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `-f FICHERO`: fichero de configuración de Compose que se usa en lugar de los descubiertos automáticamente. `restart`: reinicia los contenedores del servicio sin recrearlos.
- **En este proyecto:** Fase 4 · Headscale · directorio: `~/tfm-alerta-temprana-oob/fase4-breakglass-dc/headscale/config`. Reiniciar Headscale para recargar la ACL en modo file. Después del reinicio el netmap mostró la regla y el W11 alcanzó 100.64.0.1:443 (True).
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/HALLAZGO-headscale-politica-modo-file.md:109`, `docs/README-fase4a-headscale.md:65`

### C-136 · Levantar Headscale UI y comprobar que el contenedor corre

```bash
cd ~/tfm-alerta-temprana-oob/fase4-breakglass-dc
docker compose -f docker-compose.headscale-ui.yml up -d
docker ps | grep headscale-ui
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `-f FICHERO`: fichero de configuración de Compose que se usa en lugar de los descubiertos automáticamente. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano. `docker ps`: lista los contenedores en ejecución. `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto). `cd DIR`: cambia el directorio de trabajo.
- **En este proyecto:** Fase 4 · Headscale · directorio: `~/tfm-alerta-temprana-oob/fase4-breakglass-dc`. Levantar Headscale UI y comprobar que el contenedor corre.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4a-headscale-ui.md:114`

### C-137 · Arrancar Headscale

```bash
cd /home/jose/tfm-alerta-temprana-oob/fase4-breakglass-dc/headscale/config
docker compose -f /home/jose/tfm-alerta-temprana-oob/fase4-breakglass-dc/headscale/config/docker-compose.headscale.yml up -d
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `-f FICHERO`: fichero de configuración de Compose que se usa en lugar de los descubiertos automáticamente. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano. `cd DIR`: cambia el directorio de trabajo.
- **En este proyecto:** Fase 4 · Headscale · directorio: `/home/jose/tfm-alerta-temprana-oob/fase4-breakglass-dc/headscale/config`. Arrancar Headscale (ruta validada: cd al directorio del compose antes de -f).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4a-headscale.md:304`

### C-138 · Invocar -f con ruta absoluta desde otro directorio

```bash
docker compose -f <ruta_absoluta>/docker-compose.headscale.yml
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `-f FICHERO`: fichero de configuración de Compose que se usa en lugar de los descubiertos automáticamente.
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Invocar -f con ruta absoluta desde otro directorio: el contenedor montó otra carpeta («No config file found, using defaults»).
- **Resultado:** **FALLÓ** (→ C-137)
- **Fuente:** `docs/README-fase4a-headscale.md:291`

### C-158 · Reparación manual

```bash
docker compose -f docker-compose.rustdesk.yml up -d
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `-f FICHERO`: fichero de configuración de Compose que se usa en lugar de los descubiertos automáticamente. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano.
- **En este proyecto:** Fase 4 · RustDesk · directorio: `fase4-breakglass-dc/`. Reparación manual: tras ella, cinco puertos publicados en 100.64.0.1, verificado con ss, y Test-NetConnection a 21116 True.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:64`

### C-169 · Arrancar hbbs/hbbr y comprobar que están activos (hoy los levanta la unidad…

```bash
docker compose -f ~/tfm-alerta-temprana-oob/fase4-breakglass-dc/docker-compose.rustdesk.yml up -d
docker ps | grep rustdesk
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `-f FICHERO`: fichero de configuración de Compose que se usa en lugar de los descubiertos automáticamente. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano. `docker ps`: lista los contenedores en ejecución. `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto).
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. Arrancar hbbs/hbbr y comprobar que están activos (hoy los levanta la unidad tfm-fase4-rustdesk.service).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4e-rustdesk-breakglass.md:84`

### C-235 · Desde la raíz, -f descarta docker-compose.override.yml

```bash
docker compose -f fase6-iris/docker-compose.yml up -d --force-recreate
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `-f FICHERO`: fichero de configuración de Compose que se usa en lugar de los descubiertos automáticamente. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano. `--force-recreate`: recrea los contenedores aunque su configuración y su imagen no hayan cambiado.
- **En este proyecto:** Fase 6 · IRIS · directorio: `raíz del repositorio`. Desde la raíz, -f descarta docker-compose.override.yml: el servicio volvió a 0.0.0.0:4833 sin aviso.
- **Resultado:** **FALLÓ** (→ C-260)
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:308`, `docs/CATALOGO-fallos-silenciosos.md:117`

### C-236 · Verificación previa a cualquier recreación

```bash
docker compose config | grep -E 'CA_BUNDLE|100\.64\.0\.1|service_healthy'
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `config`: valida los ficheros y muestra la configuración efectiva tras fusionarlos. `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto).
- **En este proyecto:** Fase 6 · IRIS · directorio: `fase6-iris`. Verificación previa a cualquier recreación: renderizar la fusión efectiva del compose (CA_BUNDLE, 100.64.0.1, service_healthy).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:994`, `fase6-iris/README.md:164`

### C-239 · Restaurar el ancla con la CA del enclave y recrear app, worker y nginx

```bash
mkdir -p fase6-iris/certificates/rootCA fase6-iris/certificates/ldap
cp fase1-infraestructura/traefik/certs/oob-rootCA.crt \
   fase6-iris/certificates/rootCA/irisRootCACert.pem
docker compose up -d --force-recreate app worker nginx
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano. `--force-recreate`: recrea los contenedores aunque su configuración y su imagen no hayan cambiado. `mkdir -p`: crea el directorio y los padres que falten. `cp ORIGEN DESTINO`: copia ficheros.
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. Restaurar el ancla con la CA del enclave y recrear app, worker y nginx.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:237`

### C-246 · Primera corrección (healthcheck + depends_on) validada con up

```bash
docker compose up
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `up`: crea (si hace falta) y arranca los contenedores de los servicios.
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. Primera corrección (healthcheck + depends_on) validada con up: funcionaba en ese escenario y no en el arranque en frío (el demonio ignora depends_on).
- **Resultado:** **FALLÓ** (→ C-415)
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:399`, `docs/INFORME-AUDITORIA-FASE6.md:41`

### C-247 · up -d sobre un contenedor exited lo arranca sin recrear («Started») y…

```bash
docker compose up -d
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano.
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. up -d sobre un contenedor exited lo arranca sin recrear («Started») y conserva el endpoint de red obsoleto.
- **Resultado:** **FALLÓ** (→ C-260)
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:430`, `docs/INFORME-AUDITORIA-FASE6.md:886`, `docs/CATALOGO-fallos-silenciosos.md:128`

### C-260 · Nginx en bucle de reinicio con endpoint obsoleto

```bash
docker compose up -d --force-recreate nginx
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano. `--force-recreate`: recrea los contenedores aunque su configuración y su imagen no hayan cambiado.
- **En este proyecto:** Fase 6 · IRIS · directorio: `~/tfm-alerta-temprana-oob/fase6-iris`. nginx en bucle de reinicio con endpoint obsoleto: recrear, no arrancar.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:1031`, `fase6-iris/README.md:328`

### C-268 · Arranque manual de la pila esperando a los healthchecks (normalmente lo hace…

```bash
cd fase6-iris
docker compose up -d --wait
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano. `--wait`: espera a que los servicios estén en ejecución o `healthy` antes de devolver el control. `cd DIR`: cambia el directorio de trabajo.
- **En este proyecto:** Fase 6 · IRIS · directorio: `fase6-iris`. Arranque manual de la pila esperando a los healthchecks (normalmente lo hace la unidad systemd).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase6-iris/README.md:173`

### C-269 · Tras cambiar .env o montajes

```bash
docker compose up -d --force-recreate app worker nginx
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano. `--force-recreate`: recrea los contenedores aunque su configuración y su imagen no hayan cambiado.
- **En este proyecto:** Fase 6 · IRIS · directorio: `fase6-iris`. Tras cambiar .env o montajes: recreación, no reinicio.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase6-iris/README.md:180`, `docs/INFORME-AUDITORIA-FASE6.md:240`

### C-310 · Respondió «sintaxis OK» mientras Compose fusionaba las listas de ports y el…

```bash
docker compose config --quiet
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `config`: valida los ficheros y muestra la configuración efectiva tras fusionarlos. `--quiet`: solo valida, sin imprimir la configuración.
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. Respondió «sintaxis OK» mientras Compose fusionaba las listas de ports y el contenedor colisionaba consigo mismo; resuelto con !override.
- **Resultado:** **FALLÓ**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE8.md:223`, `fase8-kvm/README.md:227`, `docs/CATALOGO-fallos-silenciosos.md:83`

### C-321 · V6

```bash
docker compose up --force-recreate
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `--force-recreate`: recrea los contenedores aunque su configuración y su imagen no hayan cambiado.
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. V6: tras recrear, user-hook-url sigue en /home/rttys.conf; «Aprobada» en cierre-mejora1-hook.md:34 (línea 59 de rttys.conf).
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/diseno-hook-autorizacion.md:241`, `docs/riesgos-aceptados-hook-nivel1.md:157`

### C-401 · Comando de MongoDB

```bash
command: ["mongod", "--replSet", "rs0", "--bind_ip_all", "--keyFile", "/etc/mongodb/mongo-keyfile"]
```

- **Qué hace (genérico):** Clave de Compose: `command` sustituye al comando por defecto de la imagen, `entrypoint` al punto de entrada y `test` define el healthcheck (`CMD` ejecuta sin shell, `CMD-SHELL` con `/bin/sh -c`).
- **En este proyecto:** Fase 1 · MongoDB · directorio: no consta. Comando de MongoDB: replica set rs0 con keyFile.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase1-infraestructura/docker-compose.yml:81`

### C-402 · Healthcheck de MongoDB con la contraseña por variable (el literal versionado…

```bash
test: ["CMD", "mongosh", "--quiet",
       "-u", "rcuser", "-p", "${MONGO_INITDB_ROOT_PASSWORD}",
       "--authenticationDatabase", "admin",
       "--eval", "rs.status().ok"]
```

- **Qué hace (genérico):** Clave de Compose: `command` sustituye al comando por defecto de la imagen, `entrypoint` al punto de entrada y `test` define el healthcheck (`CMD` ejecuta sin shell, `CMD-SHELL` con `/bin/sh -c`). `mongosh`: shell de MongoDB. `--quiet`: sin banner; `--eval JS`: ejecuta y sale; `-u/-p/--authenticationDatabase`: credenciales y base de autenticación.
- **En este proyecto:** Fase 1 · MongoDB · directorio: no consta. Healthcheck de MongoDB con la contraseña por variable (el literal versionado fue el hallazgo A-21).
- **Resultado:** **VALIDADO**
- **Fuente:** `fase1-infraestructura/docker-compose.yml:90`

### C-403 · Healthcheck del agente LangGraph

```bash
test: ["CMD-SHELL", "python3 -c \"import urllib.request;urllib.request.urlopen('http://127.0.0.1:8000/health')\" || exit 1"]
```

- **Qué hace (genérico):** Clave de Compose: `command` sustituye al comando por defecto de la imagen, `entrypoint` al punto de entrada y `test` define el healthcheck (`CMD` ejecuta sin shell, `CMD-SHELL` con `/bin/sh -c`). `python3 -c` / `node -e`: ejecuta un fragmento de código en línea.
- **En este proyecto:** Fase 3 · orchestrator · directorio: no consta. Healthcheck del agente LangGraph.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase3-agentic/docker-compose.yml:35`

### C-404 · Hbbs con relay rustdesk-hbbr:21117 y -k _ (exige clave)

```bash
command: hbbs -r rustdesk-hbbr:21117 -k _
```

- **Qué hace (genérico):** Clave de Compose: `command` sustituye al comando por defecto de la imagen, `entrypoint` al punto de entrada y `test` define el healthcheck (`CMD` ejecuta sin shell, `CMD-SHELL` con `/bin/sh -c`).
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. hbbs con relay rustdesk-hbbr:21117 y -k _ (exige clave). Sin red, hbbs no resuelve el relay y registra relay-servers=[].
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase4-breakglass-dc/docker-compose.rustdesk.yml:5`

### C-405 · Hbbr con -k _

```bash
command: hbbr -k _
```

- **Qué hace (genérico):** Clave de Compose: `command` sustituye al comando por defecto de la imagen, `entrypoint` al punto de entrada y `test` define el healthcheck (`CMD` ejecuta sin shell, `CMD-SHELL` con `/bin/sh -c`).
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. hbbr con -k _.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase4-breakglass-dc/docker-compose.rustdesk.yml:20`

### C-406 · Comando de Headscale

```bash
command: serve
```

- **Qué hace (genérico):** Clave de Compose: `command` sustituye al comando por defecto de la imagen, `entrypoint` al punto de entrada y `test` define el healthcheck (`CMD` ejecuta sin shell, `CMD-SHELL` con `/bin/sh -c`).
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Comando de Headscale.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase4-breakglass-dc/headscale/config/docker-compose.headscale.yml:6`

### C-407 · MinIO con consola en :9001 interna

```bash
command: server /data --console-address ":9001"
```

- **Qué hace (genérico):** Clave de Compose: `command` sustituye al comando por defecto de la imagen, `entrypoint` al punto de entrada y `test` define el healthcheck (`CMD` ejecuta sin shell, `CMD-SHELL` con `/bin/sh -c`).
- **En este proyecto:** Fase 5 · MinIO · directorio: no consta. MinIO con consola en :9001 interna (publicación retirada; se sirve por Traefik).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase5-velociraptor/docker-compose.yml:38`

### C-408 · Healthcheck de MinIO

```bash
test: ["CMD-SHELL", "curl -f http://localhost:9000/minio/health/live || exit 1"]
```

- **Qué hace (genérico):** Clave de Compose: `command` sustituye al comando por defecto de la imagen, `entrypoint` al punto de entrada y `test` define el healthcheck (`CMD` ejecuta sin shell, `CMD-SHELL` con `/bin/sh -c`). `-f`: falla sin cuerpo de salida ante errores HTTP.
- **En este proyecto:** Fase 5 · MinIO · directorio: no consta. Healthcheck de MinIO.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase5-velociraptor/docker-compose.yml:52`

### C-409 · Healthcheck de app (/login 200)

```bash
test: ["CMD", "python3", "-c",
       "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/login', timeout=5).status==200 else 1)"]
```

- **Qué hace (genérico):** Clave de Compose: `command` sustituye al comando por defecto de la imagen, `entrypoint` al punto de entrada y `test` define el healthcheck (`CMD` ejecuta sin shell, `CMD-SHELL` con `/bin/sh -c`).
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. Healthcheck de app (/login 200). Validado con docker compose up; no basta en arranque en frío.
- **Resultado:** **FALLÓ** (→ C-415)
- **Fuente:** `fase6-iris/docker-compose.override.yml:10`

### C-410 · Entrypoint que genera rttys.conf desde la plantilla

```bash
entrypoint: ["/bin/sh", "/docker-entrypoint.sh"]
command: ["rttys"]
```

- **Qué hace (genérico):** Clave de Compose: `command` sustituye al comando por defecto de la imagen, `entrypoint` al punto de entrada y `test` define el healthcheck (`CMD` ejecuta sin shell, `CMD-SHELL` con `/bin/sh -c`).
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. Entrypoint que genera rttys.conf desde la plantilla (el sed solo escapa / y &: secretos sin símbolos).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase8-kvm/glkvm-cloud/docker-compose/docker-compose.yml:62`

### C-427 · Renderiza y valida el compose (fusión de ficheros)

```bash
docker compose config
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `config`: valida los ficheros y muestra la configuración efectiva tras fusionarlos.
- **En este proyecto:** Fase transversal · host · directorio: no consta. Renderiza y valida el compose (fusión de ficheros). No valida el contenido de ficheros montados (traefik.yml) ni detecta merges semánticamente erróneos; en IRIS confirmó que la configuración era correcta y el defecto estaba en la reincorporación a la red. L-1: validar con docker compose config antes de cualquier --force-recreate.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/DECISION-dashboard-traefik.md:44`, `docs/INFORME-AUDITORIA-FASE6.md:320`, `docs/INFORME-AUDITORIA-FASE6.md:391`, `docs/LECCIONES-OPERATIVAS-conversaciones.md:16`

### C-440 · La clave queda solo con comentarios y YAML la lee como nula

_Sin comando literal en la fuente._ Recrear un servicio tras retirar la única entrada de `ports:` del compose

- **Qué hace (genérico):** Sin explicación genérica aplicable: sintaxis propia del producto o del proyecto; ver la fuente.
- **En este proyecto:** Fase transversal · host · directorio: no consta. L-1: la clave queda solo con comentarios y YAML la lee como nula; el comando aborta y el contenedor no se recrea. Servicio afectado no registrado.
- **Resultado:** **FALLÓ** (→ C-427)
- **Fuente:** `docs/LECCIONES-OPERATIVAS-conversaciones.md:15`

## I.2 Docker (contenedores, redes, imágenes)

**(en este proyecto)** Operación e inspección de contenedores: `docker exec` para ejecutar herramientas dentro (mongosh, wazuh-control, CLI de Headscale, openssl, psql), `docker inspect` y `docker network inspect` como discriminadores del estado real, `docker cp` para mover ficheros. Varias fuentes documentan que `docker ps` o `docker inspect` de bindings informan de un estado que no corresponde al comportamiento.

### C-004 · Comprobar que Docker es el .deb oficial y no el snap

```bash
docker --version
which docker
snap list | grep docker # debe estar vacío
```

- **Qué hace (genérico):** `docker --version`: versión del cliente Docker. `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto). `which`: ruta del ejecutable; `snap list`: paquetes snap instalados.
- **En este proyecto:** Fase 1 · host · directorio: no consta. Comprobar que Docker es el .deb oficial y no el snap.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:82`

### C-014 · Crear la red externa oob-network

```bash
docker network create oob-network
```

- **Qué hace (genérico):** `docker network create RED`: crea una red de Docker.
- **En este proyecto:** Fase 1 · host · directorio: no consta. Crear la red externa oob-network.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:257`, `docs/README-fase1b-authelia.md:201`, `fase1-infraestructura/README.md:160`

### C-026 · Generar el hash argon2 de la contraseña de usuario (marcador…

```bash
docker run --rm authelia/authelia:latest \
  authelia crypto hash generate argon2 --password [REDACTADO]
```

- **Qué hace (genérico):** `docker run IMAGEN`: crea y ejecuta un contenedor nuevo. `--rm`: elimina el contenedor al terminar. `authelia crypto hash generate argon2 --password`: genera el hash Argon2 de una contraseña para `users_database.yml`.
- **En este proyecto:** Fase 1 · Authelia · directorio: no consta. Generar el hash argon2 de la contraseña de usuario (marcador TU_PASSWORD_SEGURA en la fuente). Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1b-authelia.md:222`

### C-034 · Desactivar la verificación de email de Rocket.Chat 8.x en MongoDB…

```bash
docker exec -it mongodb mongosh admin \
  -u rcuser -p [REDACTADO] \
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

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `-i`: mantiene abierta la entrada estándar; `-t`: asigna una pseudo-TTY. `mongosh`: shell de MongoDB. `--quiet`: sin banner; `--eval JS`: ejecuta y sale; `-u/-p/--authenticationDatabase`: credenciales y base de autenticación.
- **En este proyecto:** Fase 1 · MongoDB · directorio: no consta. Desactivar la verificación de email de Rocket.Chat 8.x en MongoDB (laboratorio sin SMTP). Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1c-mongodb-rocketchat.md:103`

### C-038 · Inicializar el replica set rs0

```bash
docker exec -it mongodb mongosh --quiet --eval \
  'rs.initiate({_id:"rs0", members:[{_id:0, host:"mongodb:27017"}]})'
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `-i`: mantiene abierta la entrada estándar; `-t`: asigna una pseudo-TTY. `mongosh`: shell de MongoDB. `--quiet`: sin banner; `--eval JS`: ejecuta y sale; `-u/-p/--authenticationDatabase`: credenciales y base de autenticación. `rs.initiate({...})`: inicializa el replica set; `rs.status()` informa del estado de los miembros.
- **En este proyecto:** Fase 1 · MongoDB · directorio: no consta. Inicializar el replica set rs0.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1c-mongodb-rocketchat.md:184`

### C-039 · Comprobar que el miembro es PRIMARY (esperado)

```bash
docker exec -it mongodb mongosh --quiet --eval \
  'rs.status().members[0].stateStr'
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `-i`: mantiene abierta la entrada estándar; `-t`: asigna una pseudo-TTY. `mongosh`: shell de MongoDB. `--quiet`: sin banner; `--eval JS`: ejecuta y sale; `-u/-p/--authenticationDatabase`: credenciales y base de autenticación.
- **En este proyecto:** Fase 1 · MongoDB · directorio: no consta. Comprobar que el miembro es PRIMARY (esperado).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1c-mongodb-rocketchat.md:190`

### C-040 · Crear el usuario rcuser con roles root y clusterAdmin (contraseña como…

```bash
docker exec -it mongodb mongosh admin --quiet --eval '
db.createUser({
  user: "rcuser",
  pwd: "[REDACTADO]",
  roles: [
    {role: "root", db: "admin"},
    {role: "clusterAdmin", db: "admin"}
  ]
});'
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `-i`: mantiene abierta la entrada estándar; `-t`: asigna una pseudo-TTY. `mongosh`: shell de MongoDB. `--quiet`: sin banner; `--eval JS`: ejecuta y sale; `-u/-p/--authenticationDatabase`: credenciales y base de autenticación.
- **En este proyecto:** Fase 1 · MongoDB · directorio: no consta. Crear el usuario rcuser con roles root y clusterAdmin (contraseña como marcador en la fuente). Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1c-mongodb-rocketchat.md:195`

### C-051 · Instalar sudo en el indexer y cambiar la contraseña con…

```bash
docker exec -u root -it single-node-wazuh.indexer-1 bash
yum install -y sudo
bash /usr/share/wazuh-indexer/plugins/opensearch-security/tools/wazuh-passwords-tool.sh \
  -u admin -p '[REDACTADO]'
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `-u USUARIO`: ejecuta el comando con ese usuario o UID. `yum install -y`: instala paquetes (imágenes basadas en RHEL). `wazuh-passwords-tool.sh -u USUARIO -p CLAVE`: cambia la contraseña de un usuario interno del indexador.
- **En este proyecto:** Fase 1 · Wazuh · directorio: no consta. Instalar sudo en el indexer y cambiar la contraseña con wazuh-passwords-tool.sh (solución alternativa; contraseña como marcador). Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1d-wazuh.md:88`

### C-065 · Comprobar la vigencia de la credencial versionada

```bash
docker inspect --format '{{.State.Health.Status}}' mongodb
```

- **Qué hace (genérico):** `docker inspect`: devuelve la configuración y el estado de bajo nivel del objeto. `-f/--format PLANTILLA`: filtra la salida con una plantilla Go.
- **En este proyecto:** Fase 1 · MongoDB · directorio: no consta. Comprobar la vigencia de la credencial versionada: healthy, luego el literal era la credencial en uso.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/HALLAZGO-credencial-mongodb-2026-09-23.md:29`

### C-068 · Validación integral de la Fase 1

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

- **Qué hace (genérico):** `docker ps`: lista los contenedores en ejecución. `--format`: plantilla de columnas de salida.
- **En este proyecto:** Fase 1 · host · directorio: no consta. Validación integral de la Fase 1: estado de todos los contenedores (tabla «Servicios validados»: Up).
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/README-fase1e-validacion.md:99`

### C-069 · Contenedores conectados a oob-network

```bash
docker network inspect oob-network | python3 -m json.tool | grep -E "Name|IPv4"
```

- **Qué hace (genérico):** `docker network inspect RED`: muestra la red y los contenedores conectados. `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto). `python3 -m json.tool`: formatea JSON.
- **En este proyecto:** Fase 1 · host · directorio: no consta. Contenedores conectados a oob-network.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1e-validacion.md:102`

### C-072 · MongoDB PRIMARY

```bash
docker exec -it mongodb mongosh admin \
  -u rcuser -p [REDACTADO] \
  --authenticationDatabase admin \
  --quiet --eval 'rs.status().members[0].stateStr'
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `-i`: mantiene abierta la entrada estándar; `-t`: asigna una pseudo-TTY. `mongosh`: shell de MongoDB. `--quiet`: sin banner; `--eval JS`: ejecuta y sale; `-u/-p/--authenticationDatabase`: credenciales y base de autenticación.
- **En este proyecto:** Fase 1 · MongoDB · directorio: no consta. MongoDB PRIMARY (registrado «PRIMARY ✅»; contraseña como marcador). Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/README-fase1e-validacion.md:116`, `docs/README-fase1c-mongodb-rocketchat.md:332`

### C-077 · Segmentación

```bash
docker network inspect oob-network --format '{{range .Containers}}{{println .Name}}{{end}}'
docker network inspect fase1-internal --format '{{range .Containers}}{{println .Name}}{{end}}'
```

- **Qué hace (genérico):** `-f/--format PLANTILLA`: filtra la salida con una plantilla Go. `docker network inspect RED`: muestra la red y los contenedores conectados.
- **En este proyecto:** Fase 1 · MongoDB · directorio: no consta. Segmentación: mongodb debe aparecer solo en fase1-internal.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase1-infraestructura/README.md:235`

### C-089 · Diagnóstico de firma rechazada

```bash
docker cp /tmp/alerta-prueba.json n8n:/tmp/a.json
docker exec n8n node -e "
const c=require('crypto'),f=require('fs');
const b=f.readFileSync('/tmp/a.json');
console.log('len secreto:', (process.env.OOB_WEBHOOK_SECRET||'').length);
console.log('bytes cuerpo:', b.length);
console.log('sha256='+c.createHmac('sha256',process.env.OOB_WEBHOOK_SECRET).update(b).digest('hex'));
"
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `docker cp ORIGEN DESTINO`: copia ficheros entre el host y un contenedor (`contenedor:ruta`). `python3 -c` / `node -e`: ejecuta un fragmento de código en línea.
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. Diagnóstico de firma rechazada: calcular el HMAC dentro del contenedor con el secreto que ve n8n.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/PROCEDIMIENTO-prueba-manual-webhook.md:92`

### C-094 · Verificar desde n8n que mistral:7b está cargado

```bash
docker exec n8n wget -qO- http://ollama:11434/api/tags
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `wget URL`: cliente HTTP. `-q`: sin mensajes; `-O-`: escribe el cuerpo en la salida estándar.
- **En este proyecto:** Fase 2 · Ollama · directorio: no consta. Verificar desde n8n que mistral:7b está cargado (wget confirmó conectividad; curl no estaba en la imagen).
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/README-fase2e-ollama-ai-agent.md:84`

### C-100 · Copiar la CA del enclave al manager de Wazuh

```bash
CA=fase1-infraestructura/traefik/certs/oob-rootCA.crt
docker cp "$CA" single-node-wazuh.manager-1:/var/ossec/etc/oob-rootCA.crt
```

- **Qué hace (genérico):** `docker cp ORIGEN DESTINO`: copia ficheros entre el host y un contenedor (`contenedor:ruta`).
- **En este proyecto:** Fase 2 · Wazuh · directorio: no consta. Copiar la CA del enclave al manager de Wazuh.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase2-orquestador/README.md:439`

### C-101 · Reiniciar el manager tras configurar la integración

```bash
docker exec single-node-wazuh.manager-1 /var/ossec/bin/wazuh-control restart
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `wazuh-control status/restart`: estado o reinicio de los demonios del manager de Wazuh.
- **En este proyecto:** Fase 2 · Wazuh · directorio: no consta. Reiniciar el manager tras configurar la integración.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase2-orquestador/README.md:443`

### C-105 · Integratord activo

```bash
docker exec single-node-wazuh.manager-1 /var/ossec/bin/wazuh-control status | grep integrator
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto). `wazuh-control status/restart`: estado o reinicio de los demonios del manager de Wazuh.
- **En este proyecto:** Fase 2 · Wazuh · directorio: no consta. Integratord activo. Comprobar siempre tras un --force-recreate: sin bloque <integration> válido termina con «Clean exit» y sin error visible.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase2-orquestador/README.md:468`, `fase2-orquestador/README.md:119`, `docs/README-fase2bcd-workflow-n8n.md:120`

### C-106 · Salud del motor de triage desde n8n

```bash
docker exec n8n wget -qO- http://langgraph-agent:8000/health
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `wget URL`: cliente HTTP. `-q`: sin mensajes; `-O-`: escribe el cuerpo en la salida estándar.
- **En este proyecto:** Fase 3 · orchestrator · directorio: no consta. Salud del motor de triage desde n8n.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase2-orquestador/README.md:471`

### C-110 · Verificar el volumen n8n_data si los workflows no persisten

```bash
docker volume ls
```

- **Qué hace (genérico):** `docker volume ls`: lista los volúmenes.
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. Verificar el volumen n8n_data si los workflows no persisten.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase2-orquestador/n8n/README.md:115`

### C-111 · Copiar el banco de pruebas al contenedor langgraph-agent

```bash
docker cp bench langgraph-agent:/app/bench
```

- **Qué hace (genérico):** `docker cp ORIGEN DESTINO`: copia ficheros entre el host y un contenedor (`contenedor:ruta`).
- **En este proyecto:** Fase 3 · orchestrator · directorio: no consta. Copiar el banco de pruebas al contenedor langgraph-agent.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase3-agentic/README.md:205`

### C-112 · Suite de rendimiento en tres modos

```bash
docker exec -it langgraph-agent python3 /app/bench/replay_alerts.py \
    --suite rendimiento --modes deterministic hybrid llm -n 3
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `-i`: mantiene abierta la entrada estándar; `-t`: asigna una pseudo-TTY. Script del proyecto `fase3-agentic/bench/replay_alerts.py` (`--suite`, `--modes`, `-n` repeticiones).
- **En este proyecto:** Fase 3 · orchestrator · directorio: no consta. Suite de rendimiento en tres modos; resultados versionados en bench/resultados (ejecución del 26-08-2026).
- **Resultado:** **VALIDADO**
- **Fuente:** `fase3-agentic/README.md:208`

### C-113 · Batería de inyección indirecta

```bash
docker exec -it langgraph-agent python3 /app/bench/replay_alerts.py \
    --suite inyeccion --modes llm hybrid -n 3
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `-i`: mantiene abierta la entrada estándar; `-t`: asigna una pseudo-TTY. Script del proyecto `fase3-agentic/bench/replay_alerts.py` (`--suite`, `--modes`, `-n` repeticiones).
- **En este proyecto:** Fase 3 · orchestrator · directorio: no consta. Batería de inyección indirecta; resultados versionados en bench/resultados.
- **Resultado:** **VALIDADO**
- **Fuente:** `fase3-agentic/README.md:212`

### C-114 · Recuperar los resultados del contenedor

```bash
docker cp langgraph-agent:/app/bench/resultados ./bench/resultados
```

- **Qué hace (genérico):** `docker cp ORIGEN DESTINO`: copia ficheros entre el host y un contenedor (`contenedor:ruta`).
- **En este proyecto:** Fase 3 · orchestrator · directorio: no consta. Recuperar los resultados del contenedor.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase3-agentic/README.md:215`

### C-115 · Consumo de CPU de ollama y langgraph-agent durante la inferencia

```bash
docker stats --no-stream ollama langgraph-agent
```

- **Qué hace (genérico):** `docker stats`: consumo de CPU y memoria de los contenedores. `--no-stream`: una sola lectura en lugar de flujo continuo.
- **En este proyecto:** Fase 3 · orchestrator · directorio: no consta. Consumo de CPU de ollama y langgraph-agent durante la inferencia.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase3-agentic/README.md:221`

### C-116 · Salud y modo efectivo del agente

```bash
docker exec -it langgraph-agent \
  python3 -c "import urllib.request;print(urllib.request.urlopen('http://127.0.0.1:8000/health').read())"
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `-i`: mantiene abierta la entrada estándar; `-t`: asigna una pseudo-TTY. `python3 -c` / `node -e`: ejecuta un fragmento de código en línea.
- **En este proyecto:** Fase 3 · orchestrator · directorio: no consta. Salud y modo efectivo del agente.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase3-agentic/README.md:572`

### C-117 · Triage de una alerta desde la red de n8n

```bash
docker exec -it n8n sh -c 'wget -qO- --post-file=/dev/stdin \
  --header="Content-Type: application/json" http://langgraph-agent:8000/triage' \
  < bench/una_alerta.json
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `-i`: mantiene abierta la entrada estándar; `-t`: asigna una pseudo-TTY. `wget URL`: cliente HTTP. `-q`: sin mensajes; `-O-`: escribe el cuerpo en la salida estándar. `--post-file FICHERO`: envía el fichero como cuerpo de un POST.
- **En este proyecto:** Fase 3 · orchestrator · directorio: no consta. Triage de una alerta desde la red de n8n. bench/una_alerta.json no está versionado (lo excluye .gitignore).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase3-agentic/README.md:576`

### C-119 · Plan (no ejecutado, según la cabecera del documento)

```bash
docker exec -it <CONTENEDOR_INDEXADOR> \
  /usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh -p '[REDACTADO]'
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `-i`: mantiene abierta la entrada estándar; `-t`: asigna una pseudo-TTY. `hash.sh -p CLAVE`: genera el hash bcrypt para `internal_users.yml` del plugin de seguridad de OpenSearch.
- **En este proyecto:** Fase 3 · OpenSearch · directorio: no consta. Plan (no ejecutado, según la cabecera del documento): generar el hash de la contraseña de tfm_metrics_svc con hash.sh del indexador. Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase3-agentic/docs/rotacion-credenciales-metricas.md:75`

### C-120 · Plan (no ejecutado)

```bash
docker exec -it <CONTENEDOR_INDEXADOR> \
  /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
  -cd /usr/share/wazuh-indexer/opensearch-security/ \
  -icl -key /usr/share/wazuh-indexer/certs/admin-key.pem \
  -cert /usr/share/wazuh-indexer/certs/admin.pem \
  -cacert /usr/share/wazuh-indexer/certs/root-ca.pem \
  -nhnv
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `-i`: mantiene abierta la entrada estándar; `-t`: asigna una pseudo-TTY. `securityadmin.sh`: carga la configuración de seguridad en el clúster. `-cd`: directorio de configuración; `-icl`: ignora el nombre del clúster; `-key/-cert/-cacert`: certificado de administrador; `-nhnv`: no verifica el nombre de host.
- **En este proyecto:** Fase 3 · OpenSearch · directorio: no consta. Plan (no ejecutado): aplicar la configuración de seguridad con securityadmin.sh.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase3-agentic/docs/rotacion-credenciales-metricas.md:90`

### C-130 · Localizar el directorio del proyecto Compose por la etiqueta que guarda Docker

```bash
docker inspect headscale -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'
```

- **Qué hace (genérico):** `docker inspect`: devuelve la configuración y el estado de bajo nivel del objeto. `-f/--format PLANTILLA`: filtra la salida con una plantilla Go.
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Localizar el directorio del proyecto Compose por la etiqueta que guarda Docker.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/HALLAZGO-headscale-politica-modo-file.md:102`

### C-139 · Log de arranque

```bash
docker logs --tail 50 headscale
```

- **Qué hace (genérico):** `--tail N`: solo las últimas N líneas. `docker logs CONTENEDOR`: muestra la salida estándar y de error del contenedor.
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Log de arranque: se registra la salida observada (clave Noise creada, SQLite abierta).
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/README-fase4a-headscale.md:312`

### C-154 · Mostraba hbbs y hbbr como running con la columna de puertos vacía

```bash
docker ps
```

- **Qué hace (genérico):** `docker ps`: lista los contenedores en ejecución.
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. Mostraba hbbs y hbbr como running con la columna de puertos vacía: estado engañoso.
- **Resultado:** **FALLÓ** (→ C-156)
- **Fuente:** `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:22`, `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:79`

### C-155 · Devolvía los bindings correctos (100.64.0.1:21115-21118), sin efecto real

```bash
docker inspect ... .HostConfig.PortBindings
```

- **Qué hace (genérico):** `docker inspect`: devuelve la configuración y el estado de bajo nivel del objeto.
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. Devolvía los bindings correctos (100.64.0.1:21115-21118), sin efecto real.
- **Resultado:** **FALLÓ** (→ C-156)
- **Fuente:** `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:24`

### C-156 · Discriminador

```bash
docker inspect ... .NetworkSettings.Networks
```

- **Qué hace (genérico):** `docker inspect`: devuelve la configuración y el estado de bajo nivel del objeto.
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. Discriminador: .NetworkSettings.Networks devolvía {}.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:26`

### C-219 · Regenerar server.config.yaml (no se versiona)

```bash
docker run --rm velociraptor-oob:0.76.6 --nobanner config generate \
  > velociraptor-config/server.config.yaml
```

- **Qué hace (genérico):** `docker run IMAGEN`: crea y ejecuta un contenedor nuevo. `--rm`: elimina el contenedor al terminar. `velociraptor config generate`: genera una configuración de servidor nueva (con su PKI). `--nobanner`: sin banner de inicio.
- **En este proyecto:** Fase 5 · Velociraptor · directorio: no consta. Regenerar server.config.yaml (no se versiona).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase5-velociraptor/README.md:275`

### C-220 · Regenerar client.config.yaml desde la configuración de servidor

```bash
docker run --rm -v "$PWD/velociraptor-config:/velociraptor" \
  velociraptor-oob:0.76.6 --config /velociraptor/server.config.yaml \
  --nobanner config client > client.config.yaml
```

- **Qué hace (genérico):** `docker run IMAGEN`: crea y ejecuta un contenedor nuevo. `--rm`: elimina el contenedor al terminar. `-v ORIGEN:DESTINO`: monta un volumen o directorio del host en el contenedor. `config client`: deriva la configuración de cliente de la de servidor. `--nobanner`: sin banner de inicio.
- **En este proyecto:** Fase 5 · Velociraptor · directorio: no consta. Regenerar client.config.yaml desde la configuración de servidor.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase5-velociraptor/README.md:286`

### C-221 · Reempaquetar el MSI de cliente con config repack --msi (la fuente pide…

```bash
docker run --rm -v "$PWD:/work" -w /work \
  velociraptor-oob:0.76.6 --config velociraptor-config/server.config.yaml \
  --nobanner config repack --msi <velociraptor-oficial-windows-amd64.msi> \
  client.config.yaml installer-windows/velociraptor-client.msi
```

- **Qué hace (genérico):** `docker run IMAGEN`: crea y ejecuta un contenedor nuevo. `--rm`: elimina el contenedor al terminar. `-v ORIGEN:DESTINO`: monta un volumen o directorio del host en el contenedor. `-w DIR`: directorio de trabajo dentro del contenedor. `config repack --msi`: reempaqueta el MSI oficial con la configuración de cliente embebida. `--nobanner`: sin banner de inicio.
- **En este proyecto:** Fase 5 · Velociraptor · directorio: no consta. Reempaquetar el MSI de cliente con config repack --msi (la fuente pide comprobar la sintaxis con --help).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase5-velociraptor/README.md:300`

### C-222 · Generar el cliente API orchestrator con rol investigator

```bash
docker exec velociraptor /usr/local/bin/velociraptor \
  --config /velociraptor/server.config.yaml \
  config api_client \
  --name orchestrator \
  --role investigator \
  /velociraptor/api_client.yaml
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `config api_client --name --role`: emite un certificado de cliente de la API gRPC con ese rol.
- **En este proyecto:** Fase 5 · Velociraptor · directorio: no consta. Generar el cliente API orchestrator con rol investigator.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase5-velociraptor/README.md:344`

### C-223 · Control negativo→positivo del gRPC desde el orchestrator

```bash
docker exec orchestrator python3 -c "
import grpc, yaml, json
from pyvelociraptor import api_pb2, api_pb2_grpc
cfg=yaml.safe_load(open('/app/api_client.yaml'))
creds=grpc.ssl_channel_credentials(cfg['ca_certificate'].encode(),
      cfg['client_private_key'].encode(), cfg['client_cert'].encode())
ch=grpc.secure_channel(cfg['api_connection_string'], creds,
      (('grpc.ssl_target_name_override','VelociraptorServer'),))
stub=api_pb2_grpc.APIStub(ch)
req=api_pb2.VQLCollectorArgs(Query=[api_pb2.VQLRequest(Name='c',
      VQL='SELECT client_id, os_info.hostname AS host FROM clients()')])
for r in stub.Query(req):
    if r.Response: print(json.loads(r.Response))
"
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `python3 -c` / `node -e`: ejecuta un fragmento de código en línea.
- **En este proyecto:** Fase 5 · Velociraptor · directorio: no consta. Control negativo→positivo del gRPC desde el orchestrator: antes falla, después debe autenticar y devolver filas.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase5-velociraptor/README.md:384`

### C-233 · Discriminar el camino n8n→IRIS por el 4833

```bash
docker exec n8n node -e "
const https=require('https');
https.get({host:'iris.oob.local',port:4833,path:'/manage/customers/list'},
  r=>console.log('HTTP',r.statusCode))
 .on('error',e=>console.log('FAIL',e.code));"
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `python3 -c` / `node -e`: ejecuta un fragmento de código en línea.
- **En este proyecto:** Fase 6 · n8n · directorio: no consta. Discriminar el camino n8n→IRIS por el 4833: HTTP 401 = camino sano; cualquier FAIL = roto.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/DECISION-n8n-iris-ruta-directa.md:135`

### C-238 · P0-C

```bash
docker exec iriswebapp_app ls -li /etc/irisRootCACert.pem
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `ls -l` (`-a` ocultos, `-i` número de inodo).
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. P0-C: nlink = 0, el fichero solo sobrevivía en el espacio de montaje del contenedor; tras la remediación, inodo nuevo con nlink = 1.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:200`, `docs/INFORME-AUDITORIA-FASE6.md:249`

### C-243 · Tras el reinicio del anfitrión

```bash
docker ps -a --filter name=iriswebapp
```

- **Qué hace (genérico):** `docker ps`: lista los contenedores en ejecución. `-a`: incluye también los contenedores parados. `--filter CONDICIÓN`: filtra la lista (p. ej. por nombre).
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. Tras el reinicio del anfitrión: iriswebapp_nginx en Restarting.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:373`

### C-244 · Log de nginx

```bash
docker logs --tail=2 iriswebapp_nginx
```

- **Qué hace (genérico):** `--tail N`: solo las últimas N líneas. `docker logs CONTENEDOR`: muestra la salida estándar y de error del contenedor.
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. Log de nginx: «host not found in upstream "app"».
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:378`

### C-245 · Diagnóstico decisivo

```bash
docker network inspect iris_frontend --format '{{range .Containers}}{{.Name}} {{end}}'
```

- **Qué hace (genérico):** `-f/--format PLANTILLA`: filtra la salida con una plantilla Go. `docker network inspect RED`: muestra la red y los contenedores conectados.
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. Diagnóstico decisivo: nginx ausente de iris_frontend. Si no aparece, recrear, no arrancar.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:386`, `docs/INFORME-AUDITORIA-FASE6.md:1028`, `fase6-iris/README.md:320`

### C-250 · P1-6

```bash
docker exec iriswebapp_app python3 -c "
import ssl; print('CAs cargadas:', len(ssl.create_default_context().get_ca_certs()))"
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `python3 -c` / `node -e`: ejecuta un fragmento de código en línea.
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. P1-6: CAs cargadas en el contexto TLS de la aplicación → 151.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:570`

### C-251 · P1-7

```bash
docker exec iriswebapp_app ps -eo user,uid,comm
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `ps`: lista procesos (`-eo` elige las columnas de salida).
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. P1-7: la aplicación corre como root (riesgo aceptado).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:603`

### C-254 · Prueba negativa del verificador

```bash
docker network disconnect iris_frontend iriswebapp_nginx
```

- **Qué hace (genérico):** `docker network disconnect RED CONTENEDOR`: desconecta un contenedor de la red.
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. Prueba negativa del verificador: sacar nginx de la red → verify-fase6.sh «FALLO … NO esta en iris_frontend», exit 1; revertido, exit 0.
- **Resultado:** **CONTROL-NEGATIVO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:751`

### C-259 · Recuperación si ninguna cuenta tiene MFA

```bash
docker exec iriswebapp_db psql -U postgres -d iris_db -c \
  'UPDATE server_settings SET enforce_mfa = false;'
docker compose up -d --force-recreate app worker
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano. `--force-recreate`: recrea los contenedores aunque su configuración y su imagen no hayan cambiado. `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha.
- **En este proyecto:** Fase 6 · IRIS · directorio: `~/tfm-alerta-temprana-oob/fase6-iris`. Recuperación si ninguna cuenta tiene MFA: desactivar enforce_mfa en BD y recrear (un cambio en BD no refresca app.config).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:1017`, `fase6-iris/README.md:304`

### C-279 · Iris.oob.local dentro de n8n → OK 100.64.0.1

```bash
docker exec n8n node -e "require('dns').lookup('iris.oob.local',(e,a)=>...)"
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `python3 -c` / `node -e`: ejecuta un fragmento de código en línea.
- **En este proyecto:** Fase 6 · n8n · directorio: no consta. iris.oob.local dentro de n8n → OK 100.64.0.1.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:42`

### C-284 · Censo de oob-network

```bash
docker network inspect oob-network
```

- **Qué hace (genérico):** `docker network inspect RED`: muestra la red y los contenedores conectados.
- **En este proyecto:** Fase transversal · host · directorio: no consta. Censo de oob-network: 24 contenedores.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:91`

### C-285 · Cadena de resolución dentro de n8n

```bash
docker exec n8n cat /etc/resolv.conf
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `cat`: muestra el contenido.
- **En este proyecto:** Fase 6 · n8n · directorio: no consta. Cadena de resolución dentro de n8n: nameserver 127.0.0.11.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:96`

### C-286 · Nombres .oob.local de servicio dentro de n8n

```bash
docker exec n8n node -e "['chat.oob.local','minio.oob.local',
  'velociraptor.oob.local','wazuh.oob.local'].forEach(...)"
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `python3 -c` / `node -e`: ejecuta un fragmento de código en línea.
- **En este proyecto:** Fase 6 · n8n · directorio: no consta. Nombres .oob.local de servicio dentro de n8n: los cuatro resuelven a 127.0.0.1.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:105`

### C-288 · Comprobar que la indirección por $env y el literal son funcionalmente…

```bash
docker exec n8n printenv RC_BOT_USER_ID
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha.
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. Comprobar que la indirección por $env y el literal son funcionalmente idénticos.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:191`

### C-296 · Prueba antes/después propuesta para un alias de red

```bash
docker exec n8n getent hosts iris.oob.local
docker exec n8n curl -sSv --cacert <bundle> https://iris.oob.local:4833/manage/cases/add
docker exec n8n getent hosts iris.oob.local
docker exec n8n curl -sSv --cacert <bundle-corregido> https://iris.oob.local:4833/manage/cases/add
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `curl URL`: cliente HTTP(S). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-S`: muestra el error aunque se use `-s`. `--cacert FICHERO`: verifica el certificado del servidor contra esa CA.
- **En este proyecto:** Fase 6 · n8n · directorio: no consta. Prueba antes/después propuesta para un alias de red (no ejecutada; documento parcialmente refutado).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/revision-workflow1-caso-iris-warroom.md:226`

### C-302 · Prueba unitaria de emisión de métricas del triage

```bash
docker exec -it langgraph-agent python3 -c "
from app.main import triage
from app.models import TriageRequest
print(triage(TriageRequest(wazuh={'incident_id':'TEST-TRIAGE-01','host':'HOST-01'}, cti={})))
"
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `-i`: mantiene abierta la entrada estándar; `-t`: asigna una pseudo-TTY. `python3 -c` / `node -e`: ejecuta un fragmento de código en línea.
- **En este proyecto:** Fase 7 · orchestrator · directorio: no consta. Prueba unitaria de emisión de métricas del triage.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase7-observabilidad/README.md:210`

### C-303 · Prueba unitaria de emisión de la colección

```bash
docker exec -it orchestrator python3 -c "
from main import collect, CollectRequest
import asyncio
print(asyncio.run(collect(CollectRequest(incidentid='TEST-COLLECT-01', host='HOST-02', profile='generic_high_signal_collection'))))
"
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `-i`: mantiene abierta la entrada estándar; `-t`: asigna una pseudo-TTY. `python3 -c` / `node -e`: ejecuta un fragmento de código en línea.
- **En este proyecto:** Fase 7 · orchestrator · directorio: no consta. Prueba unitaria de emisión de la colección. La nota de 2026-09-24 registra que ya falla: desde P0-4 collect(request) exige firma HMAC.
- **Resultado:** **FALLÓ**
- **Fuente:** `fase7-observabilidad/README.md:220`

### C-308 · P1-2

```bash
docker exec
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha.
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. P1-2: la plataforma consultaba api.ipify.org en el arranque (devolvía la IP pública); corregido con GLKVM_ACCESS_IP.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE8.md:153`

### C-309 · Copia local de la imagen fijada por digest (namespace personal de Docker Hub)

```bash
docker save
```

- **Qué hace (genérico):** `docker save`: exporta una imagen a un fichero tar.
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. Copia local de la imagen fijada por digest (namespace personal de Docker Hub).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE8.md:187`, `fase8-kvm/README.md:622`, `docs/AUDITORIA-CIERRE-2026-09-23.md:402`

### C-312 · Criterio de la sonda

```bash
docker exec glkvm_cloud sh -c 'netstat -tn | grep -c ":5912.*ESTABLISHED"'
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `netstat -tn`: conexiones TCP numéricas (`-p` añade el PID). `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto).
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. Criterio de la sonda: conexión ESTABLISHED al 5912 dentro del namespace del contenedor; al matar rtty baja a 0.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE8.md:275`, `fase8-kvm/README.md:302`

### C-318 · Instrumento de referencia del hook

```bash
docker exec -i n8n node -e '
const http=require("http");
http.request({host:"localhost",port:5678,path:"/webhook/kvm-hook",method:"GET",
 headers:{"x-rttys-hook":"true","x-original-url":"/connect/zsb25f8","x-original-method":"GET"}},
 r=>{let b="";r.on("data",d=>b+=d);r.on("end",()=>console.log("status HTTP:",r.statusCode))}).end()'
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `-i`: mantiene abierta la entrada estándar; `-t`: asigna una pseudo-TTY. `python3 -c` / `node -e`: ejecuta un fragmento de código en línea.
- **En este proyecto:** Fase 8 · n8n · directorio: no consta. Instrumento de referencia del hook: el código HTTP que ve rttys, sin cookie ni efecto sobre el dispositivo.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/cierre-mejora1-hook.md:136`

### C-319 · Conectividad glkvm_cloud → n8n verificada → 200

```bash
docker exec glkvm_cloud  wget http://n8n:5678/
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `wget URL`: cliente HTTP.
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. Conectividad glkvm_cloud → n8n verificada → 200.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/diseno-hook-autorizacion.md:83`

### C-320 · N8n → /auth-config de rttys con cabecera Host obligatoria → 200 (sin Host,…

```bash
docker exec n8n  wget --header="Host: kvm.oob.local" \
                      http://glkvm_cloud:8180/auth-config
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `wget URL`: cliente HTTP. `--header`: añade una cabecera HTTP.
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. n8n → /auth-config de rttys con cabecera Host obligatoria → 200 (sin Host, 400).
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/diseno-hook-autorizacion.md:84`

### C-326 · M2

```bash
docker stop headscale
sleep 20
ping -c 3 100.64.0.2
curl -sk -o /dev/null -w '%{http_code}\n' https://100.64.0.1:4833
```

- **Qué hace (genérico):** `docker stop` / `docker start`: para o arranca un contenedor existente (sin recrearlo). `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-o FICHERO`: escribe el cuerpo en un fichero (`/dev/null` lo descarta). `-w FORMATO`: imprime datos de la transferencia al terminar, p. ej. `%{http_code}`. `ping` (`-c N` en Linux): eco ICMP. `sleep N`: espera N segundos.
- **En este proyecto:** Fase 8 · Headscale · directorio: no consta. M2: con Headscale parado el plano de datos sobrevive. Primera ejecución medida: ping responde, IRIS 302. Usa -k (-sk).
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/mejora5-prueba-mensual-resiliencia.md:97`

### C-328 · M3

```bash
docker start headscale
sleep 60
ping -c 3 100.64.0.2
```

- **Qué hace (genérico):** `docker stop` / `docker start`: para o arranca un contenedor existente (sin recrearlo). `ping` (`-c N` en Linux): eco ICMP. `sleep N`: espera N segundos.
- **En este proyecto:** Fase 8 · Headscale · directorio: no consta. M3: restablecer Headscale; reconecta con más de 30 s de retraso (primera ejecución).
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/mejora5-prueba-mensual-resiliencia.md:124`

### C-329 · M4

```bash
docker stop n8n
```

- **Qué hace (genérico):** `docker stop` / `docker start`: para o arranca un contenedor existente (sin recrearlo).
- **En este proyecto:** Fase 8 · n8n · directorio: no consta. M4: con n8n caído el hook debe denegar (403).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/mejora5-prueba-mensual-resiliencia.md:137`

### C-330 · Restablecer n8n para M5

```bash
docker start n8n
```

- **Qué hace (genérico):** `docker stop` / `docker start`: para o arranca un contenedor existente (sin recrearlo).
- **En este proyecto:** Fase 8 · n8n · directorio: no consta. Restablecer n8n para M5.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/mejora5-prueba-mensual-resiliencia.md:153`

### C-333 · M7

```bash
docker exec glkvm_cloud grep -c 'user-hook-url' /home/rttys.conf
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto).
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. M7: user-hook-url sigue en rttys.conf tras recrear (debe devolver 1).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/mejora5-prueba-mensual-resiliencia.md:191`

### C-338 · ¿Hay conexión real del dispositivo?

```bash
docker exec glkvm_cloud sh -c 'netstat -tn | grep 5912'
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `netstat -tn`: conexiones TCP numéricas (`-p` añade el PID). `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto).
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. ¿Hay conexión real del dispositivo?.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase8-kvm/README.md:272`

### C-345 · A21

```bash
head -20
```

- **Qué hace (genérico):** `head -N`: primeras N líneas.
- **En este proyecto:** Fase transversal · host · directorio: no consta. A21: head -20 sobre docker ps cortó ocho servicios vivos del inventario.
- **Resultado:** **FALLÓ**
- **Fuente:** `docs/CATALOGO-fallos-silenciosos.md:78`, `docs/revision-credenciales-fases1-8.md:201`

### C-349 · D-10 (propuesta)

```bash
docker port langgraph-agent
```

- **Qué hace (genérico):** `docker port CONTENEDOR`: muestra los puertos publicados.
- **En este proyecto:** Fase 3 · orchestrator · directorio: no consta. D-10 (propuesta): langgraph-agent no publica puerto.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/AUDITORIA-CIERRE-2026-09-23.md:452`

### C-350 · D-11 (propuesta)

```bash
docker exec langgraph-agent env
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha.
- **En este proyecto:** Fase 3 · orchestrator · directorio: no consta. D-11 (propuesta): tiempo de espera efectivo de Ollama (solo esa variable).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/AUDITORIA-CIERRE-2026-09-23.md:453`

### C-376 · Init-mongo.sh

```bash
mongosh admin << JSEOF
rs.initiate({_id:"rs0", members:[{_id:0, host:"mongodb:27017"}]});
sleep(2000);
db.createUser({
  user: "${MONGO_INITDB_ROOT_USERNAME}",
  pwd: "${MONGO_INITDB_ROOT_PASSWORD}",
  roles: [
    {role:"root", db:"admin"},
    {role:"clusterAdmin", db:"admin"}
  ]
});
JSEOF
```

- **Qué hace (genérico):** `mongosh`: shell de MongoDB. `--quiet`: sin banner; `--eval JS`: ejecuta y sale; `-u/-p/--authenticationDatabase`: credenciales y base de autenticación. `rs.initiate({...})`: inicializa el replica set; `rs.status()` informa del estado de los miembros.
- **En este proyecto:** Fase 1 · MongoDB · directorio: no consta. init-mongo.sh: inicializar el replica set y crear el usuario con credenciales por variable.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase1-infraestructura/mongodb/init-mongo.sh:10`

### C-382 · Núcleo de la sonda de capacidad

```bash
N=$(docker exec "$CONTENEDOR" sh -c \
      "netstat -tn 2>/dev/null | grep -c ':${PUERTO}.*ESTABLISHED'" 2>/dev/null)
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `netstat -tn`: conexiones TCP numéricas (`-p` añade el PID). `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto).
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. Núcleo de la sonda de capacidad: conexiones ESTABLISHED al 5912 dentro del contenedor (exit 0/1/2).
- **Resultado:** **VALIDADO**
- **Fuente:** `fase8-kvm/scripts/check-kvm-lastseen.sh:36`

### C-400 · Dentro de verify-fase6.sh

```bash
mfa=$(docker exec iriswebapp_db psql -U postgres -d iris_db -tAc \
       'SELECT enforce_mfa FROM server_settings;' 2>/dev/null | tr -d ' ')
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha.
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. Dentro de verify-fase6.sh: enforce_mfa en la base de datos; prueba negativa con enforce_mfa = false → FALLO, exit 1.
- **Resultado:** **CONTROL-NEGATIVO**
- **Fuente:** `scripts/verify-fase6.sh:60`

### C-428 · Las copias con docker cp no sobreviven a docker compose up --force-recreate

```bash
docker cp
```

- **Qué hace (genérico):** `docker cp ORIGEN DESTINO`: copia ficheros entre el host y un contenedor (`contenedor:ruta`).
- **En este proyecto:** Fase 2 · Wazuh · directorio: no consta. Las copias con docker cp no sobreviven a docker compose up --force-recreate: el script de integración se monta como bind mount desde el repositorio.
- **Resultado:** **FALLÓ**
- **Fuente:** `fase2-orquestador/README.md:124`

### C-434 · P2-6

```bash
docker logs
```

- **Qué hace (genérico):** `docker logs CONTENEDOR`: muestra la salida estándar y de error del contenedor.
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. P2-6: el volcado de configuración de rttys imprime Token y Password en claro en docker logs.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE8.md:197`, `docs/api-reconocimiento-fase8.md:240`, `docs/mejora6-endurecimiento-dispositivo.md:243`

### C-442 · Reparación propuesta

```bash
docker restart single-node-wazuh.manager-1
sleep 20
docker exec single-node-wazuh.manager-1 sha256sum /var/ossec/integrations/custom-n8n | cut -c1-16
sha256sum ~/tfm-alerta-temprana-oob/fase2-orquestador/wazuh-integration/custom-n8n | cut -c1-16
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `docker restart`: reinicia un contenedor sin recrearlo. `cut -d SEP -f N`: extrae campos. `sleep N`: espera N segundos. `sha256sum [-c FICHERO]`: calcula o comprueba (con `-c`) resúmenes SHA-256.
- **En este proyecto:** Fase 2 · Wazuh · directorio: no consta. L-2: reparación propuesta: reiniciar el manager y comparar el hash del fichero dentro y fuera (criterio: iguales y distintos de 41890ce63ebb). El resultado no consta transcrito.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/LECCIONES-OPERATIVAS-conversaciones.md:28`

### C-448 · Identificar el modo de respuesta del webhook kvm-hook

```bash
docker exec glkvm_cloud sh -c 'wget -q -O - http://n8n:5678/webhook/kvm-hook; echo'
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `wget URL`: cliente HTTP. `wget -q -O -`: sin mensajes y con el cuerpo a la salida estándar.
- **En este proyecto:** Fase 8 · n8n · directorio: no consta. L-5: identificar el modo de respuesta del webhook kvm-hook: salida registrada {"message":"Workflow was started"} (34 bytes, Respond: Immediately). Corregido a «Using 'Respond to Webhook' node».
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/LECCIONES-OPERATIVAS-conversaciones.md:68`

### C-451 · En glkvm_cloud y en n8n, date +%s%N devolvió 1789040529 (diez dígitos)

```bash
docker exec glkvm_cloud sh -c 'command -v curl; command -v wget; date +%s%N'
docker exec n8n sh -c 'command -v curl; command -v wget; command -v node; date +%s%N'
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `curl URL`: cliente HTTP(S). `-v`: modo detallado (handshake y cabeceras). `wget URL`: cliente HTTP. `command -v PROGRAMA`: indica si existe en el PATH. `date +%s%N`: segundos desde la época seguidos de nanosegundos (`%N` es una extensión de GNU date).
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. L-7: en glkvm_cloud y en n8n, date +%s%N devolvió 1789040529 (diez dígitos): el date de busybox descarta %N sin avisar.
- **Resultado:** **FALLÓ** (→ C-452)
- **Fuente:** `docs/LECCIONES-OPERATIVAS-conversaciones.md:96`

## I.3 Clientes HTTP y APIs

**(en este proyecto)** Verificación por comportamiento de los servicios tras Traefik y de las APIs internas: Wazuh, Rocket.Chat, n8n, agente del DC, orchestrator, OpenSearch, IRIS, MISP y la plataforma KVM. Las guías de la Fase 1 usan `-k`; las fases posteriores verifican con `--cacert` contra la CA del enclave y firman con HMAC las peticiones al orchestrator y al agente.

### C-032 · Código HTTP del portal (esperado 200 o 302)

```bash
curl -k -o /dev/null -w "%{http_code}" https://auth.oob.local
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-o FICHERO`: escribe el cuerpo en un fichero (`/dev/null` lo descarta). `-w FORMATO`: imprime datos de la transferencia al terminar, p. ej. `%{http_code}`.
- **En este proyecto:** Fase 1 · Authelia · directorio: no consta. Código HTTP del portal (esperado 200 o 302). Usa -k.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1b-authelia.md:258`

### C-045 · Rocket.Chat responde (esperado 200)

```bash
curl -k -o /dev/null -w "%{http_code}" https://chat.oob.local
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-o FICHERO`: escribe el cuerpo en un fichero (`/dev/null` lo descarta). `-w FORMATO`: imprime datos de la transferencia al terminar, p. ej. `%{http_code}`.
- **En este proyecto:** Fase 1 · Rocket.Chat · directorio: no consta. Rocket.Chat responde (esperado 200). Usa -k.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1c-mongodb-rocketchat.md:339`

### C-046 · Listar canales por la API REST (token e id como marcadores)

```bash
curl -k -H "X-Auth-Token: <REDACTADO>" \
     -H "X-User-Id: <USER_ID>" \
     https://chat.oob.local/api/v1/channels.list | python3 -m json.tool | grep name
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-H "Cabecera: valor"`: añade una cabecera a la petición. `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto). `python3 -m json.tool`: formatea JSON.
- **En este proyecto:** Fase 1 · Rocket.Chat · directorio: no consta. Listar canales por la API REST (token e id como marcadores). Usa -k. Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1c-mongodb-rocketchat.md:343`

### C-058 · Consultar la API del manager (credencial vía variable API_PASSWORD, nunca en…

```bash
curl -k -u "admin:${API_PASSWORD:?exporta API_PASSWORD antes de ejecutar}" \
  "https://localhost:55000/" | python3 -m json.tool
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-u usuario:contraseña`: autenticación básica. `python3 -m json.tool`: formatea JSON.
- **En este proyecto:** Fase 1 · Wazuh · directorio: no consta. Consultar la API del manager (credencial vía variable API_PASSWORD, nunca en el comando). Usa -k.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1d-wazuh.md:218`

### C-059 · Dashboard accesible (esperado 200)

```bash
curl -k -o /dev/null -w "%{http_code}" https://localhost:4443
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-o FICHERO`: escribe el cuerpo en un fichero (`/dev/null` lo descarta). `-w FORMATO`: imprime datos de la transferencia al terminar, p. ej. `%{http_code}`.
- **En este proyecto:** Fase 1 · Wazuh · directorio: no consta. Dashboard accesible (esperado 200). Usa -k.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1d-wazuh.md:222`

### C-060 · Medir desde n8n si la API de Traefik es alcanzable sin autenticar

```bash
wget http://172.18.0.1:8080/api/http/routers
wget http://traefik:8080/api/http/routers
```

- **Qué hace (genérico):** `wget URL`: cliente HTTP.
- **En este proyecto:** Fase 1 · Traefik · directorio: no consta. Medir desde n8n si la API de Traefik es alcanzable sin autenticar: HTTP/1.1 200 OK por ambas rutas.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/DECISION-dashboard-traefik.md:67`

### C-062 · V2

```bash
curl http://localhost:8080/api/http/routers
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S).
- **En este proyecto:** Fase 1 · Traefik · directorio: no consta. V2: diagnóstico local conservado → 200.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/DECISION-dashboard-traefik.md:121`

### C-063 · V3/V4

```bash
curl http://192.168.127.138:8080/...
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S).
- **En este proyecto:** Fase 1 · Traefik · directorio: no consta. V3/V4: la API no responde por LAN ni por tailnet → 000 (timeout).
- **Resultado:** **CONTROL-NEGATIVO**
- **Fuente:** `docs/DECISION-dashboard-traefik.md:122`, `docs/DECISION-dashboard-traefik.md:123`

### C-067 · Dashboard vía Traefik (esperado 200)

```bash
curl -k -o /dev/null -w "%{http_code}" https://wazuh.oob.local
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-o FICHERO`: escribe el cuerpo en un fichero (`/dev/null` lo descarta). `-w FORMATO`: imprime datos de la transferencia al terminar, p. ej. `%{http_code}`.
- **En este proyecto:** Fase 1 · Wazuh · directorio: no consta. Dashboard vía Traefik (esperado 200). Usa -k.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1d-wazuh.md:226`

### C-071 · Test de URLs de la Fase 1

```bash
curl -o /dev/null -w "Traefik:    %{http_code}\n" http://localhost:8080
curl -k -o /dev/null -w "Portainer: %{http_code}\n" https://localhost:9443
curl -k -o /dev/null -w "Authelia:  %{http_code}\n" https://auth.oob.local
curl -k -o /dev/null -w "RocketChat:%{http_code}\n" https://chat.oob.local
curl -k -o /dev/null -w "Wazuh dir: %{http_code}\n" https://localhost:4443
curl -k -o /dev/null -w "Wazuh TFK: %{http_code}\n" https://wazuh.oob.local
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-o FICHERO`: escribe el cuerpo en un fichero (`/dev/null` lo descarta). `-w FORMATO`: imprime datos de la transferencia al terminar, p. ej. `%{http_code}`.
- **En este proyecto:** Fase 1 · host · directorio: no consta. Test de URLs de la Fase 1. Registrado: Traefik 301, Portainer 200, Authelia 200, Rocket.Chat 200, Wazuh 302. Usa -k.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/README-fase1e-validacion.md:108`

### C-073 · Login del bot orchestrator-bot por la API

```bash
curl -k -X POST https://chat.oob.local/api/v1/login \
  -H "Content-Type: application/json" \
  -d '{"user":"orchestrator-bot","password":"[REDACTADO]"}' \
  | python3 -m json.tool | grep status
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-X MÉTODO`: método HTTP de la petición. `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto). `python3 -m json.tool`: formatea JSON.
- **En este proyecto:** Fase 1 · Rocket.Chat · directorio: no consta. Login del bot orchestrator-bot por la API (registrado «success ✅»; contraseña como marcador). Usa -k. Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/README-fase1e-validacion.md:122`

### C-088 · Enviar la alerta firmada al webhook de test con --data-binary y cabecera…

```bash
curl -sS -w '\nHTTP %{http_code}\n' -X POST \
  https://n8n.oob.local/webhook-test/wazuh-alerts \
  -H "Content-Type: application/json" \
  -H "x-oob-signature: $SIG" \
  --data-binary @/tmp/alerta-prueba.json
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-S`: muestra el error aunque se use `-s`. `-w FORMATO`: imprime datos de la transferencia al terminar, p. ej. `%{http_code}`. `-X MÉTODO`: método HTTP de la petición. `--data-binary @FICHERO`: envía el cuerpo byte a byte, sin ninguna transformación.
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. Enviar la alerta firmada al webhook de test con --data-binary y cabecera x-oob-signature.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/PROCEDIMIENTO-prueba-manual-webhook.md:76`

### C-090 · Validación de n8n tras Traefik

```bash
curl -k -o /dev/null -w "n8n: %{http_code}\n" https://n8n.oob.local
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-o FICHERO`: escribe el cuerpo en un fichero (`/dev/null` lo descarta). `-w FORMATO`: imprime datos de la transferencia al terminar, p. ej. `%{http_code}`.
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. Validación de n8n tras Traefik (esperado 200; checklist ✅ «Acceso vía Traefik»). Usa -k.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/README-fase2a-n8n.md:80`, `fase2-orquestador/n8n/README.md:40`

### C-093 · Test del flujo con payload a mano desde el host, sin firma

```bash
curl -k -X POST https://n8n.oob.local/webhook/wazuh-alerts \
  -H "Content-Type: application/json" \
  -d '{
    "rule": {"id": "5710", "level": 7, "description": "Test alert OOB"},
    "agent": {"id": "000", "name": "wazuh-manager"},
    "oob_timestamp": "2026-05-17T21:00:00Z"
  }'
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-X MÉTODO`: método HTTP de la petición.
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. Test del flujo con payload a mano desde el host, sin firma. La validación posterior registra que el camino real nunca funcionó en 2c–2f.
- **Resultado:** **FALLÓ** (→ C-088)
- **Fuente:** `docs/README-fase2bcd-workflow-n8n.md:223`

### C-095 · Prueba manual del webhook en modo test

```bash
curl -k -X POST https://n8n.oob.local/webhook-test/wazuh-alerts \
  -H "Content-Type: application/json" \
  -d '{
    "rule": {"id": "5710", "level": 7, "description": "SSH brute force attack detected"},
    "agent": {"id": "001", "name": "web-server-01"},
    "oob_timestamp": "2026-05-21T20:00:00Z"
  }'
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-X MÉTODO`: método HTTP de la petición.
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. Prueba manual del webhook en modo test; se observó el mensaje en Rocket.Chat, pero era un payload a mano sin firma por un camino que el tráfico real no recorría.
- **Resultado:** **FALLÓ** (→ C-088)
- **Fuente:** `docs/README-fase2e-ollama-ai-agent.md:185`

### C-104 · TLS del enclave verificado contra la CA (--cacert, sin -k)

```bash
curl --cacert "$CA" -o /dev/null -w "%{http_code}\n" https://n8n.oob.local/
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-o FICHERO`: escribe el cuerpo en un fichero (`/dev/null` lo descarta). `-w FORMATO`: imprime datos de la transferencia al terminar, p. ej. `%{http_code}`. `--cacert FICHERO`: verifica el certificado del servidor contra esa CA.
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. TLS del enclave verificado contra la CA (--cacert, sin -k).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase2-orquestador/README.md:465`

### C-121 · Plan (no ejecutado)

```bash
curl -sk -u '<USUARIO_ADMIN>:[REDACTADO]' \
  -X PUT "https://<HOST_INDEXADOR>:9200/_plugins/_security/api/roles/tfm_metrics_writer" \
  -H "Content-Type: application/json" -d '{
    "cluster_permissions": ["cluster:admin/opensearch/indices/create"],
    "index_permissions": [{
      "index_patterns": ["tfm-metrics-events*"],
      "allowed_actions": ["write", "create_index"]
    }]
  }'
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-u usuario:contraseña`: autenticación básica. API REST del plugin de seguridad de OpenSearch (`roles`, `internalusers`, `rolesmapping`).
- **En este proyecto:** Fase 3 · OpenSearch · directorio: no consta. Plan (no ejecutado): crear el rol tfm_metrics_writer por la API REST de seguridad. Usa -k (-sk). Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase3-agentic/docs/rotacion-credenciales-metricas.md:104`

### C-122 · Plan (no ejecutado)

```bash
curl -sk -u '<USUARIO_ADMIN>:[REDACTADO]' \
  -X PUT "https://<HOST_INDEXADOR>:9200/_plugins/_security/api/internalusers/tfm_metrics_svc" \
  -H "Content-Type: application/json" -d '{
    "password": "[REDACTADO]",
    "backend_roles": [],
    "description": "Cuenta de servicio de langgraph-agent (Fase 3) para tfm-metrics-events*"
  }'
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-u usuario:contraseña`: autenticación básica. API REST del plugin de seguridad de OpenSearch (`roles`, `internalusers`, `rolesmapping`).
- **En este proyecto:** Fase 3 · OpenSearch · directorio: no consta. Plan (no ejecutado): crear el usuario interno tfm_metrics_svc. Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase3-agentic/docs/rotacion-credenciales-metricas.md:121`

### C-123 · Plan (no ejecutado)

```bash
curl -sk -u '<USUARIO_ADMIN>:[REDACTADO]' \
  -X PUT "https://<HOST_INDEXADOR>:9200/_plugins/_security/api/rolesmapping/tfm_metrics_writer" \
  -H "Content-Type: application/json" -d '{
    "users": ["tfm_metrics_svc"]
  }'
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-u usuario:contraseña`: autenticación básica. API REST del plugin de seguridad de OpenSearch (`roles`, `internalusers`, `rolesmapping`).
- **En este proyecto:** Fase 3 · OpenSearch · directorio: no consta. Plan (no ejecutado): mapear el usuario al rol. Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase3-agentic/docs/rotacion-credenciales-metricas.md:133`

### C-124 · Plan (no ejecutado)

```bash
curl -sk -u 'tfm_metrics_svc:[REDACTADO]' \
  -X POST "https://<HOST_INDEXADOR>:9200/tfm-metrics-events/_doc" \
  -H "Content-Type: application/json" \
  -d '{"@timestamp":"<ISO8601>","event_type":"rotation_smoke_test","source":"manual-check"}'
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-u usuario:contraseña`: autenticación básica.
- **En este proyecto:** Fase 3 · OpenSearch · directorio: no consta. Plan (no ejecutado): el usuario nuevo puede escribir en su índice (esperado 201 «created»). Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase3-agentic/docs/rotacion-credenciales-metricas.md:145`

### C-125 · Plan (no ejecutado)

```bash
curl -sk -o /dev/null -w '%{http_code}\n' -u 'tfm_metrics_svc:[REDACTADO]' \
  "https://<HOST_INDEXADOR>:9200/wazuh-alerts-*/_search"
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-o FICHERO`: escribe el cuerpo en un fichero (`/dev/null` lo descarta). `-w FORMATO`: imprime datos de la transferencia al terminar, p. ej. `%{http_code}`. `-u usuario:contraseña`: autenticación básica.
- **En este proyecto:** Fase 3 · OpenSearch · directorio: no consta. Plan (no ejecutado): control negativo previsto, el usuario no lee wazuh-alerts-* (esperado 403) ni administra el cluster (esperado 403). Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase3-agentic/docs/rotacion-credenciales-metricas.md:156`, `fase3-agentic/docs/rotacion-credenciales-metricas.md:166`

### C-140 · Healthcheck de Headscale

```bash
curl http://localhost:8090/health
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S).
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Healthcheck de Headscale: respuesta validada {"status":"pass"}.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/README-fase4a-headscale.md:330`

### C-141 · Comprobar que la UI pasa por Authelia

```bash
curl -H "Host: hs.oob.local" https://localhost/web
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-H "Cabecera: valor"`: añade una cabecera a la petición.
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Comprobar que la UI pasa por Authelia: 302 hacia Authelia (registrado como evidencia).
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/README-fase4-pendientes.md:36`

### C-151 · Estado del agente del DC por la tailnet

```bash
curl -s http://100.64.0.2:8000/health
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`).
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. Estado del agente del DC por la tailnet. Confirmado el 2026-09-27: «hmac_required»:true (HITO §5.6).
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/README-fase4-validacion.md:45`, `docs/HITO-dominio-tfm-local-2026-09-26.md:478`, `docs/HITO-dominio-tfm-local-2026-09-26.md:570`, `docs/HITO-dominio-tfm-local-2026-09-26.md:294`

### C-164 · Petición directa al agente equivalente al nodo Call DC Agent

```bash
curl -X POST http://100.64.0.2:8000/run \
  -H "Authorization: Bearer ${AGENT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"script":"disable_account.ps1","target":"usuario.prueba"}'
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-X MÉTODO`: método HTTP de la petición.
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. Petición directa al agente equivalente al nodo Call DC Agent; respuesta real registrada (returncode 0). Previa al Paso 9: hoy el agente exige además firma HMAC.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/README-fase4d-n8n.md:100`

### C-165 · Disparar el webhook de test dc-action

```bash
curl -k -X POST "https://n8n.oob.local/webhook-test/dc-action" \
  -H "Content-Type: application/json" \
  -d '{
    "decision": "approved",
    "script": "disable_account.ps1",
    "target": "usuario.prueba",
    "requested_by": "jgarcia",
    "incident_id": "INC-2026-001"
  }'
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-X MÉTODO`: método HTTP de la petición.
- **En este proyecto:** Fase 4 · n8n · directorio: no consta. Disparar el webhook de test dc-action: el nodo Call DC Agent recibió returncode 0 y Rocket.Chat publicó el mensaje. Usa -k.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/README-fase4d-n8n.md:161`

### C-166 · Control negativo

```bash
curl -s -X POST http://dc01-tfm:8000/run \
  -H "Authorization: Bearer <REDACTADO>" \
  -H "Content-Type: application/json" \
  -d '{"script":"disable_account.ps1","target":"test"}'
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-X MÉTODO`: método HTTP de la petición.
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. Control negativo: token incorrecto → {"detail":"Forbidden"}. Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **CONTROL-NEGATIVO**
- **Fuente:** `docs/README-fase4d-n8n.md:190`

### C-167 · Control negativo

```bash
curl -s -X POST http://dc01-tfm:8000/run \
  -H "Authorization: Bearer ${AGENT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"script":"malicioso.ps1","target":"x"}'
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-X MÉTODO`: método HTTP de la petición.
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. Control negativo: script fuera de la allowlist → «Script no permitido: malicioso.ps1».
- **Resultado:** **CONTROL-NEGATIVO**
- **Fuente:** `docs/README-fase4d-n8n.md:209`

### C-170 · Validación de activación del break-glass

```bash
curl -s -X POST http://dc01-tfm:8000/run \
  -H "Authorization: Bearer ${AGENT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"script":"rustdesk_enable.ps1","target":"DC01"}'
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-X MÉTODO`: método HTTP de la petición.
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. Validación de activación del break-glass: respuesta con service Running, ttl_task Ready, returncode 0.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/README-fase4e-rustdesk-breakglass.md:259`

### C-171 · Validación de desactivación

```bash
curl -s -X POST http://dc01-tfm:8000/run \
  -H "Authorization: Bearer ${AGENT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"script":"rustdesk_disable.ps1","target":"DC01"}'
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-X MÉTODO`: método HTTP de la petición.
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. Validación de desactivación: «RustDesk deshabilitado y TTL cancelado», returncode 0.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/README-fase4e-rustdesk-breakglass.md:291`

### C-214 · Lanzar una colección sin firma HMAC

```bash
curl -X POST http://localhost:8020/velociraptor/collect \
  -H "Content-Type: application/json" \
  -d '{
    "incidentid": "INC-2026-042",
    "host": "HOST-DC01",
    "profile": "credential_dump_collection",
    "source": "n8n-fase5"
  }'
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-X MÉTODO`: método HTTP de la petición.
- **En este proyecto:** Fase 5 · orchestrator · directorio: no consta. Lanzar una colección sin firma HMAC. La corrección de 2026-09-24 registra que devuelve 400 Missing signature headers (ORCH_REQUIRE_HMAC=true).
- **Resultado:** **FALLÓ** (→ C-384)
- **Fuente:** `fase5-orchestrator-api/README.md:316`

### C-215 · Caso 1 de las pruebas previstas para el usuario

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8020/velociraptor/collect -H 'Content-Type: application/json' -d '{"incidentid":"INC-2026-042","host":"HOST-DC01","profile":"credential_dump_collection"}'
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-o FICHERO`: escribe el cuerpo en un fichero (`/dev/null` lo descarta). `-w FORMATO`: imprime datos de la transferencia al terminar, p. ej. `%{http_code}`. `-X MÉTODO`: método HTTP de la petición. `-H "Cabecera: valor"`: añade una cabecera a la petición. `-d DATOS`: cuerpo de la petición (POST) tal como se escribe.
- **En este proyecto:** Fase 5 · orchestrator · directorio: no consta. Caso 1 de las pruebas previstas para el usuario: petición sin firma, HTTP esperado 400 (Missing signature headers).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/INFORME-P0-4-implementacion.md:190`

### C-272 · Medir la redirección de MISP

```bash
curl -H 'Host: misp.oob.local' https://127.0.0.1:12443/
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-H "Cabecera: valor"`: añade una cabecera a la petición.
- **En este proyecto:** Fase 6 · MISP · directorio: no consta. Medir la redirección de MISP: location al puerto directo 12443, por fuera del proxy (BASE_URL sin corregir). Usa Host: sin --resolve.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:105`

### C-281 · Authelia ante un Bearer por el 443

```bash
curl -sS -D- -o /dev/null -H "Authorization: Bearer <REDACTADO>" \
  https://iris.oob.local/manage/cases/add
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-S`: muestra el error aunque se use `-s`. `-o FICHERO`: escribe el cuerpo en un fichero (`/dev/null` lo descarta). `-H "Cabecera: valor"`: añade una cabecera a la petición. `-D-`: vuelca las cabeceras recibidas a la salida estándar.
- **En este proyecto:** Fase 6 · Authelia · directorio: no consta. Authelia ante un Bearer por el 443: HTTP/2 302 al login; el Bearer no llega a IRIS (por eso n8n va por el 4833). Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:57`

### C-283 · Llamada real a la API de IRIS por la tailnet con --cacert ca-bundle-oob.crt

```bash
curl -sS --cacert fase6-iris/certificates/rootCA/ca-bundle-oob.crt \
  -H "Authorization: Bearer <REDACTADO>" https://iris.oob.local:4833/manage/customers/list
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-S`: muestra el error aunque se use `-s`. `--cacert FICHERO`: verifica el certificado del servidor contra esa CA.
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. Llamada real a la API de IRIS por la tailnet con --cacert ca-bundle-oob.crt: HTTP/1.1 200 OK. Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:80`

### C-294 · Propuesto, sin ejecutar en este documento ([PENDIENTE DE MEDICIÓN])

```bash
curl -sS -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: Bearer <REDACTADO>" \
  https://iris.oob.local/manage/cases/add
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-S`: muestra el error aunque se use `-s`. `-o FICHERO`: escribe el cuerpo en un fichero (`/dev/null` lo descarta). `-w FORMATO`: imprime datos de la transferencia al terminar, p. ej. `%{http_code}`.
- **En este proyecto:** Fase 6 · Authelia · directorio: no consta. Propuesto, sin ejecutar en este documento ([PENDIENTE DE MEDICIÓN]); la medición equivalente está en el registro del 13-09. Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/revision-workflow1-caso-iris-warroom.md:145`

### C-304 · Contar eventos en tfm-metrics-events (credencial por variable OS_PASS)

```bash
curl -sk -u "admin:${OS_PASS:?exporta OS_PASS antes de ejecutar}" \
  "https://localhost:9200/tfm-metrics-events/_count?pretty"
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-u usuario:contraseña`: autenticación básica.
- **En este proyecto:** Fase 7 · OpenSearch · directorio: no consta. Contar eventos en tfm-metrics-events (credencial por variable OS_PASS): resultado validado count 404. Usa -k (-sk).
- **Resultado:** **VALIDADO**
- **Fuente:** `fase7-observabilidad/README.md:240`

### C-305 · Reimportar el dashboard en otro despliegue («procedimiento no ejecutado»)

```bash
curl -sk -u "admin:${OS_PASS:?exporta OS_PASS antes de ejecutar}" -H 'osd-xsrf: true' \
  -X POST "https://<dashboards>:5601/api/saved_objects/_import?overwrite=true" \
  --form file=@dashboards/tfm-fase7-observabilidad.ndjson
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-H "Cabecera: valor"`: añade una cabecera a la petición. `-u usuario:contraseña`: autenticación básica. `--form campo=@fichero`: envía datos multipart (subida de fichero).
- **En este proyecto:** Fase 7 · OpenSearch · directorio: no consta. Reimportar el dashboard en otro despliegue («procedimiento no ejecutado»). Usa -k.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase7-observabilidad/README.md:311`

### C-306 · Consulta propuesta

```bash
curl -sk -u "admin:${OS_PASS:?exporta OS_PASS antes de ejecutar}" \
  -H 'Content-Type: application/json' \
  "https://localhost:9200/tfm-metrics-events/_search?pretty" \
  -d '{
    "size": 0,
    "query": { "term": { "event_type.keyword": "collection_completed" } },
    "aggs": {
      "duracion": { "stats": { "field": "duration_ms" } }
    }
  }'
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-u usuario:contraseña`: autenticación básica.
- **En este proyecto:** Fase 7 · OpenSearch · directorio: no consta. Consulta propuesta: estadísticas de duration_ms de las colecciones. Usa -k.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/tfm/metricas-calculadas.md:139`

### C-307 · Consulta propuesta

```bash
curl -sk -u "admin:${OS_PASS:?exporta OS_PASS antes de ejecutar}" \
  -H 'Content-Type: application/json' \
  "https://localhost:9200/tfm-metrics-events/_search?pretty" \
  -d '{
    "size": 0,
    "aggs": {
      "por_tipo": { "terms": { "field": "event_type.keyword" } }
    }
  }'
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-u usuario:contraseña`: autenticación básica.
- **En este proyecto:** Fase 7 · OpenSearch · directorio: no consta. Consulta propuesta: recuento de eventos por tipo. Usa -k.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/tfm/metricas-calculadas.md:156`

### C-311 · El certificado del GL-RM1 valida contra la CA del enclave sin -k

```bash
curl --cacert fase1-infraestructura/traefik/certs/oob-rootCA.crt \
     -o /dev/null -w 'HTTP %{http_code}\n' https://192.168.0.36/
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `--cacert FICHERO`: verifica el certificado del servidor contra esa CA.
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. El certificado del GL-RM1 valida contra la CA del enclave sin -k (registrado: HTTP 200). Misma comprobación con --cacert oob-rootCA.crt en INFORME-AUDITORIA-FASE8:255 → HTTP 200.
- **Resultado:** **VALIDADO**
- **Fuente:** `fase8-kvm/README.md:165`, `fase8-kvm/README.md:275`

### C-315 · Instrumento invalidado

```bash
curl -s
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`).
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. Instrumento invalidado: con --cacert a una ruta inexistente curl falla y no imprime nada, indistinguible de «cuerpo vacío».
- **Resultado:** **FALLÓ**
- **Fuente:** `docs/api-reconocimiento-fase8.md:40`, `docs/CATALOGO-fallos-silenciosos.md:64`

### C-348 · D-5 (verificación propuesta)

```bash
curl -I https://n8n.oob.local/
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-I`: solo cabeceras (petición HEAD).
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. D-5 (verificación propuesta): ¿la interfaz de n8n responde 302 a Authelia o 200 sin sesión?.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/AUDITORIA-CIERRE-2026-09-23.md:447`

### C-353 · D-19 (propuesta)

```bash
curl -I -H 'Host: misp.oob.local' https://127.0.0.1:12443/
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-H "Cabecera: valor"`: añade una cabecera a la petición. `-I`: solo cabeceras (petición HEAD).
- **En este proyecto:** Fase 6 · MISP · directorio: no consta. D-19 (propuesta): ¿location de MISP con :12443?.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/AUDITORIA-CIERRE-2026-09-23.md:461`

### C-384 · Petición firmada al orchestrator

```bash
scripts/collect-signed.sh INC-2026-042 HOST-DC01 credential_dump_collection
```

- **Qué hace (genérico):** Script del proyecto `scripts/collect-signed.sh <incidentid> <host> <profile> [source]`; `SIGN_TS`, `SIGN_NONCE` y `SIGN_CORRUPT` fuerzan los casos de prueba.
- **En este proyecto:** Fase 5 · orchestrator · directorio: `~/tfm-alerta-temprana-oob`. Petición firmada al orchestrator. Coherencia de firma verificada con un arnés local y secreto ficticio («TODAS LAS COMPROBACIONES OK»); la prueba contra el servicio queda para el usuario.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/INFORME-P0-4-implementacion.md:191`

### C-385 · Pruebas negativas de la firma

```bash
SIGN_CORRUPT=1 scripts/collect-signed.sh INC-2026-042 HOST-DC01 credential_dump_collection
```

- **Qué hace (genérico):** Script del proyecto `scripts/collect-signed.sh <incidentid> <host> <profile> [source]`; `SIGN_TS`, `SIGN_NONCE` y `SIGN_CORRUPT` fuerzan los casos de prueba.
- **En este proyecto:** Fase 5 · orchestrator · directorio: `~/tfm-alerta-temprana-oob`. Pruebas negativas de la firma: alterada (403), replay con nonce fijo (409), timestamp fuera de ventana (400). Ejecutadas contra el arnés local.
- **Resultado:** **CONTROL-NEGATIVO**
- **Fuente:** `docs/INFORME-P0-4-implementacion.md:194`, `docs/INFORME-P0-4-implementacion.md:192`, `docs/INFORME-P0-4-implementacion.md:193`

### C-386 · Casos de validación del modelo y de la lista de perfiles (422/400) previstos…

```bash
scripts/collect-signed.sh 'INC/2026' HOST-DC01 credential_dump_collection
```

- **Qué hace (genérico):** Script del proyecto `scripts/collect-signed.sh <incidentid> <host> <profile> [source]`; `SIGN_TS`, `SIGN_NONCE` y `SIGN_CORRUPT` fuerzan los casos de prueba.
- **En este proyecto:** Fase 5 · orchestrator · directorio: `~/tfm-alerta-temprana-oob`. Casos de validación del modelo y de la lista de perfiles (422/400) previstos para el usuario.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/INFORME-P0-4-implementacion.md:195`, `docs/INFORME-P0-4-implementacion.md:196`, `docs/INFORME-P0-4-implementacion.md:202`, `docs/INFORME-P0-4-implementacion.md:203`

### C-387 · Dentro de collect-signed.sh

```bash
code="$(curl -sS -X POST "${ORCH_URL}/velociraptor/collect" \
  -H 'Content-Type: application/json' \
  -H "x-timestamp: ${ts}" \
  -H "x-nonce: ${nonce}" \
  -H "x-signature: ${sig}" \
  --data-binary "@${body_file}" \
  -w '%{http_code}' -o "${resp_file}")"
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-S`: muestra el error aunque se use `-s`. `-X MÉTODO`: método HTTP de la petición. `--data-binary @FICHERO`: envía el cuerpo byte a byte, sin ninguna transformación.
- **En este proyecto:** Fase 5 · orchestrator · directorio: no consta. Dentro de collect-signed.sh: se envía con --data-binary el mismo fichero que se firmó, con x-timestamp, x-nonce y x-signature.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `scripts/collect-signed.sh:114`

### C-388 · Dentro de dc-signed.sh

```bash
RESP_CODE="$(curl -sS -X POST "${AGENT_URL%/}/run" \
  "${headers[@]}" \
  --data-binary "@${body_file}" \
  -w '%{http_code}' -o "${resp_file}")"
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-S`: muestra el error aunque se use `-s`. `-X MÉTODO`: método HTTP de la petición. `--data-binary @FICHERO`: envía el cuerpo byte a byte, sin ninguna transformación.
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. Dentro de dc-signed.sh: petición firmada a /run con --data-binary (credenciales por variable con ${VAR:?}).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `scripts/dc-signed.sh:198`

### C-390 · Dentro de verify-dcagent-health.sh

```bash
if ! body="$(curl -sS --max-time 10 "$origen")"; then
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-S`: muestra el error aunque se use `-s`. `--max-time N`: tiempo máximo total de la transferencia.
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. Dentro de verify-dcagent-health.sh: GET a /health sin token.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `scripts/verify-dcagent-health.sh:67`

### C-439 · M-29

```bash
GET /case/evidences/list?cid=<caso borrado>
```

- **Qué hace (genérico):** Petición HTTP GET a la API de IRIS.
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. M-29: un case_id inexistente devuelve 500, no 404; se atribuyó a falta de acceso del usuario de API y lo refutó un 200 sobre un caso vivo.
- **Resultado:** **FALLÓ**
- **Fuente:** `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:1013`

### C-447 · El 2026-08-30 la respuesta del historial de la integración saliente de…

_Sin comando literal en la fuente._ Leer el HTTP 200 o `{"message":"Workflow was started"}` del webhook de n8n como prueba de ejecución

- **Qué hace (genérico):** Sin explicación genérica aplicable: sintaxis propia del producto o del proyecto; ver la fuente.
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. L-5: el 2026-08-30 la respuesta del historial de la integración saliente de Rocket.Chat se interpretó como prueba de que funcionaba, sin que apareciera la ejecución. Es acuse de recepción (modo Respond: Immediately); el único testigo fiable de ejecución es una fila en execution_entity (L-5, regla formalizada 2026-09-23 a 2026-09-25).
- **Resultado:** **FALLÓ** (→ C-446)
- **Fuente:** `docs/LECCIONES-OPERATIVAS-conversaciones.md:64`

### C-449 · Devolvió 404

_Sin comando literal en la fuente._ `curl -H 'Host: …'` contra Portainer sin `--resolve` (el literal no está registrado)

- **Qué hace (genérico):** Sin explicación genérica aplicable: sintaxis propia del producto o del proyecto; ver la fuente.
- **En este proyecto:** Fase 1 · Traefik · directorio: no consta. L-6: devolvió 404: Traefik enruta TLS por SNI antes de mirar la cabecera, y con -H el SNI va vacío.
- **Resultado:** **FALLÓ** (→ C-450)
- **Fuente:** `docs/LECCIONES-OPERATIVAS-conversaciones.md:75`

### C-450 · Misma prueba con --resolve, que envía el SNI correcto

```bash
curl -sk -o /dev/null -w 'con SNI: %{http_code}\n' --resolve portainer.oob.local:443:192.168.0.70 https://portainer.oob.local/
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-k`: permite conexiones TLS inseguras (no verifica el certificado del servidor). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-o FICHERO`: escribe el cuerpo en un fichero (`/dev/null` lo descarta). `-w FORMATO`: imprime datos de la transferencia al terminar, p. ej. `%{http_code}`. `--resolve HOST:PUERTO:IP`: resuelve ese nombre a esa IP sin DNS; la conexión TLS lleva el nombre como SNI.
- **En este proyecto:** Fase 1 · Traefik · directorio: no consta. L-6: misma prueba con --resolve, que envía el SNI correcto: salida registrada «con SNI: 403» (Authelia deniega sin sesión); router enabled y servicio UP en la API de Traefik. Con el mismo método, MISP: «misp con SNI: 404». Usa -k.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/LECCIONES-OPERATIVAS-conversaciones.md:83`

## I.4 OpenSSL y PKI

**(en este proyecto)** Generación de secretos (`openssl rand`), firma HMAC del canal Wazuh→n8n (`openssl dgst -hmac`), emisión de la CA del enclave (`generate-oob-ca.sh`) y verificación de cadenas y canales TLS (`x509`, `verify`, `s_client`). Regla del proyecto sobre TLS (`docs/LECCIONES-OPERATIVAS-conversaciones.md:104-109`, L-8): lo que no se admite es desactivar la verificación en la configuración de servicios y nodos («Ignore SSL Issues» en el nodo HTTP de n8n, `insecureSkipVerify`, `ssl.CERT_NONE`); si llegara a hacerse, debe constar como hallazgo. La salida correcta es la CA del enclave (`NODE_EXTRA_CA_CERTS`, `ca-bundle-oob.crt`). `curl -k` sí se usó en sondas de diagnóstico desde el host y no consta ninguna prohibición sobre ese uso.

### C-024 · Generar los secretos hexadecimales de Authelia (Base64 rompía la…

```bash
echo "AUTHELIA_JWT_SECRET=$(openssl rand -hex 32)"
echo "AUTHELIA_SESSION_SECRET=$(openssl rand -hex 32)"
echo "AUTHELIA_STORAGE_ENCRYPTION_KEY=$(openssl rand -hex 32)"
```

- **Qué hace (genérico):** `openssl rand N`: genera N bytes aleatorios. `-hex`: salida en hexadecimal (2·N caracteres).
- **En este proyecto:** Fase 1 · Authelia · directorio: no consta. Generar los secretos hexadecimales de Authelia (Base64 rompía la interpolación de Compose).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1b-authelia.md:207`

### C-035 · Generar el keyFile del replica set

```bash
openssl rand -base64 756 > mongo-keyfile
chmod 644 mongo-keyfile
```

- **Qué hace (genérico):** `openssl rand N`: genera N bytes aleatorios. `-base64`: salida en Base64. `chmod MODO`: permisos (p. ej. `600` solo el propietario lee y escribe; `755` todos leen y ejecutan; `400` solo lectura del propietario; `+x` ejecutable).
- **En este proyecto:** Fase 1 · MongoDB · directorio: `~/tfm-alerta-temprana-oob/fase1-infraestructura/mongodb`. Generar el keyFile del replica set.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1c-mongodb-rocketchat.md:138`, `docs/README-fase1c-mongodb-rocketchat.md:89`

### C-066 · Segunda rotación a 48 hex

```bash
openssl rand -hex 24
```

- **Qué hace (genérico):** `openssl rand N`: genera N bytes aleatorios. `-hex`: salida en hexadecimal (2·N caracteres).
- **En este proyecto:** Fase 1 · MongoDB · directorio: no consta. Segunda rotación a 48 hex (regla: alfanumérica y longitud comprobada antes de recrear).
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/HALLAZGO-credencial-mongodb-2026-09-23.md:103`

### C-075 · Generar el keyfile del replica set con permisos 400 (versión del README de…

```bash
openssl rand -base64 756 > mongodb/mongo-keyfile
chmod 400 mongodb/mongo-keyfile
```

- **Qué hace (genérico):** `openssl rand N`: genera N bytes aleatorios. `-base64`: salida en Base64. `chmod MODO`: permisos (p. ej. `600` solo el propietario lee y escribe; `755` todos leen y ejecutan; `400` solo lectura del propietario; `+x` ejecutable).
- **En este proyecto:** Fase 1 · MongoDB · directorio: no consta. Generar el keyfile del replica set con permisos 400 (versión del README de fase).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase1-infraestructura/README.md:151`

### C-087 · Calcular la firma HMAC-SHA256 del fichero con openssl dgst -r

```bash
SIG="sha256=$(openssl dgst -sha256 -hmac "$OOB_SECRET" -r /tmp/alerta-prueba.json | cut -d' ' -f1)"
```

- **Qué hace (genérico):** `openssl dgst -sha256`: calcula un resumen SHA-256. `-hmac CLAVE`: calcula un HMAC con esa clave en lugar de un resumen simple. `-r`: imprime el resultado en formato coreutils (`hash *fichero`). `cut -d SEP -f N`: extrae campos.
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. Calcular la firma HMAC-SHA256 del fichero con openssl dgst -r.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/PROCEDIMIENTO-prueba-manual-webhook.md:73`

### C-097 · Generar la CA del enclave y recrear Traefik

```bash
cd fase1-infraestructura/traefik
bash generate-oob-ca.sh
docker compose up -d --force-recreate traefik
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano. `--force-recreate`: recrea los contenedores aunque su configuración y su imagen no hayan cambiado. `cd DIR`: cambia el directorio de trabajo. Script del proyecto `fase1-infraestructura/traefik/generate-oob-ca.sh`.
- **En este proyecto:** Fase 1 · Traefik · directorio: `fase1-infraestructura/traefik`. Generar la CA del enclave y recrear Traefik.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase2-orquestador/README.md:424`

### C-108 · Generar N8N_ENCRYPTION_KEY (va en fase2-orquestador/n8n/.env, no en el…

```bash
openssl rand -hex 32
```

- **Qué hace (genérico):** `openssl rand N`: genera N bytes aleatorios. `-hex`: salida en hexadecimal (2·N caracteres).
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. Generar N8N_ENCRYPTION_KEY (va en fase2-orquestador/n8n/.env, no en el compose).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase2-orquestador/n8n/README.md:27`

### C-240 · Comprobar sujeto y huella del ancla

```bash
docker exec iriswebapp_app openssl x509 -in /etc/irisRootCACert.pem \
    -noout -subject -fingerprint -sha256
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `openssl x509`: muestra o firma certificados X.509.
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. Comprobar sujeto y huella del ancla: CN=OOB Enclave Root CA.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:244`

### C-241 · El ancla valida el certificado del enclave → OK (se usa con éxito, no solo…

```bash
docker exec iriswebapp_app openssl verify -CAfile /etc/irisRootCACert.pem \
    /home/iris/certificates/web_certificates/iris_oob_cert.pem
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `openssl verify -CAfile CA CERT`: comprueba que el certificado encadena hasta esa CA.
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. El ancla valida el certificado del enclave → OK (se usa con éxito, no solo está presente).
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:252`

### C-262 · P0-E

```bash
openssl rand -base64 48
```

- **Qué hace (genérico):** `openssl rand N`: genera N bytes aleatorios. `-base64`: salida en Base64.
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. P0-E: rotar IRIS_SECRET_KEY (len=64); verificado porque la firma de la cookie cambia.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:150`, `fase6-iris/README.md:232`

### C-267 · Verificación TLS contra la CA del enclave

```bash
openssl s_client
```

- **Qué hace (genérico):** `openssl s_client -connect HOST:PUERTO`: abre una conexión TLS y muestra el certificado y el resultado de la verificación.
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. Verificación TLS contra la CA del enclave: «Verify return code: 0 (ok)»; curl sin -k → 302.
- **Resultado:** **VALIDADO**
- **Fuente:** `fase6-iris/SECURITY-NOTICE.md:108`, `docs/INFORME-AUDITORIA-FASE6.md:917`, `docs/CATALOGO-fallos-silenciosos.md:127`

### C-323 · El certificado del 5912 valida → Verify return code

```bash
openssl s_client -connect 192.168.0.70:5912 \
  -CAfile /etc/kvmd/user/oob-rootCA.crt -verify_return_error < /dev/null
```

- **Qué hace (genérico):** `openssl s_client -connect HOST:PUERTO`: abre una conexión TLS y muestra el certificado y el resultado de la verificación. `-verify_return_error`: cierra la conexión si la verificación falla.
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. En el GL-RM1, antes de tocar el script: el certificado del 5912 valida → Verify return code: 0 (ok); también con -verify_ip.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/mejora2-tls-canal-rtty.md:61`, `docs/mejora2-tls-canal-rtty.md:66`

### C-331 · M6

```bash
echo | openssl s_client -connect 192.168.0.70:5912 2>/dev/null | \
  openssl x509 -noout -subject -issuer -dates
```

- **Qué hace (genérico):** `openssl x509`: muestra o firma certificados X.509. `-noout`: no imprime el certificado codificado; `-subject`/`-issuer`/`-dates`/`-fingerprint`/`-ext`: imprimen esos campos. `openssl s_client -connect HOST:PUERTO`: abre una conexión TLS y muestra el certificado y el resultado de la verificación.
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. M6: certificado del canal rtty emitido por la CA del enclave y no próximo a caducar.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/mejora5-prueba-mensual-resiliencia.md:167`

### C-370 · Generar la CA del enclave y el certificado *.oob.local (aborta si ya existe…

```bash
bash generate-oob-ca.sh
```

- **Qué hace (genérico):** Script del proyecto `fase1-infraestructura/traefik/generate-oob-ca.sh`.
- **En este proyecto:** Fase 1 · Traefik · directorio: `fase1-infraestructura/traefik`. Generar la CA del enclave y el certificado *.oob.local (aborta si ya existe una CA).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase2-orquestador/README.md:425`

### C-371 · Dentro de generate-oob-ca.sh

```bash
openssl genrsa -out oob-rootCA.key 4096
openssl req -x509 -new -nodes -key oob-rootCA.key -sha256 -days "$DAYS_CA" \
  -out oob-rootCA.crt \
  -subj "/C=ES/O=TFM Enclave OOB/OU=Seguridad/CN=OOB Enclave Root CA"
```

- **Qué hace (genérico):** `openssl genrsa -out FICHERO BITS`: genera una clave privada RSA. `openssl req`: crea una petición de certificado (CSR) o, con `-x509`, un certificado autofirmado. `-x509`: emite un certificado en lugar de una petición; `-new`: petición nueva; `-nodes`: no cifra la clave; `-key`: clave de firma; `-subj`: sujeto; `-days`: validez.
- **En este proyecto:** Fase 1 · Traefik · directorio: `fase1-infraestructura/traefik/certs`. Dentro de generate-oob-ca.sh: clave RSA 4096 y certificado raíz autofirmado de 10 años.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase1-infraestructura/traefik/generate-oob-ca.sh:44`

### C-372 · Petición del certificado de servidor con la lista de SAN de san.cnf

```bash
openssl req -new -key oob-wildcard.key -out oob-wildcard.csr -config san.cnf
```

- **Qué hace (genérico):** `openssl req`: crea una petición de certificado (CSR) o, con `-x509`, un certificado autofirmado. `-config FICHERO`: plantilla de la petición (aquí, con las SAN).
- **En este proyecto:** Fase 1 · Traefik · directorio: `fase1-infraestructura/traefik/certs`. Petición del certificado de servidor con la lista de SAN de san.cnf.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase1-infraestructura/traefik/generate-oob-ca.sh:84`

### C-373 · Firmar el certificado de servidor con la CA del enclave (825 días)

```bash
openssl x509 -req -in oob-wildcard.csr \
  -CA oob-rootCA.crt -CAkey oob-rootCA.key -CAcreateserial \
  -out oob-wildcard.crt -days "$DAYS_LEAF" -sha256 \
  -extfile san.cnf -extensions ext
```

- **Qué hace (genérico):** `openssl x509`: muestra o firma certificados X.509. `-req`: la entrada es una CSR; `-CA`/`-CAkey`: certificado y clave de la CA que firma; `-CAcreateserial`: crea el fichero de número de serie; `-days`: validez; `-extfile`/`-extensions`: extensiones X.509v3 a añadir.
- **En este proyecto:** Fase 1 · Traefik · directorio: `fase1-infraestructura/traefik/certs`. Firmar el certificado de servidor con la CA del enclave (825 días).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase1-infraestructura/traefik/generate-oob-ca.sh:87`

### C-374 · Verificación final del script

```bash
openssl verify -CAfile oob-rootCA.crt oob-wildcard.crt
openssl x509 -in oob-wildcard.crt -noout -subject -dates
openssl x509 -in oob-wildcard.crt -noout -ext subjectAltName
```

- **Qué hace (genérico):** `openssl x509`: muestra o firma certificados X.509. `-noout`: no imprime el certificado codificado; `-subject`/`-issuer`/`-dates`/`-fingerprint`/`-ext`: imprimen esos campos. `openssl verify -CAfile CA CERT`: comprueba que el certificado encadena hasta esa CA.
- **En este proyecto:** Fase 1 · Traefik · directorio: `fase1-infraestructura/traefik/certs`. Verificación final del script: cadena, fechas y SAN.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase1-infraestructura/traefik/generate-oob-ca.sh:100`

### C-436 · Formato hexadecimal obligatorio para los secretos

```bash
openssl rand -hex 32
```

- **Qué hace (genérico):** `openssl rand N`: genera N bytes aleatorios. `-hex`: salida en hexadecimal (2·N caracteres).
- **En este proyecto:** Fase 1 · Authelia · directorio: no consta. Formato hexadecimal obligatorio para los secretos: Base64 causaba errores de interpolación en Compose (+, /, =).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1b-authelia.md:127`, `docs/README-fase1b-authelia.md:169`, `docs/README-fase1b-authelia.md:281`

## I.5 systemd y journal

**(en este proyecto)** Unidades que garantizan el arranque correcto (red `oob-network`, RustDesk e IRIS esperando a la IP de la tailnet) y lectura del journal para diagnóstico de arranques.

### C-003 · Reiniciar el demonio Docker tras limpiar el snap o editar…

```bash
sudo systemctl restart docker
```

- **Qué hace (genérico):** `systemctl start/restart UNIDAD`: arranca o reinicia la unidad. `systemctl restart docker`: reinicia el demonio Docker.
- **En este proyecto:** Fase 1 · host · directorio: no consta. Reiniciar el demonio Docker tras limpiar el snap o editar /etc/docker/daemon.json.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:40`, `docs/README-fase1a-traefik-portainer.md:248`

### C-016 · Recargar systemd y habilitar/arrancar docker-oob-network

```bash
sudo systemctl daemon-reload
sudo systemctl enable docker-oob-network
sudo systemctl start docker-oob-network
```

- **Qué hace (genérico):** `systemctl daemon-reload`: relee las unidades tras crearlas o editarlas. `systemctl enable`: habilita la unidad en el arranque. `systemctl start/restart UNIDAD`: arranca o reinicia la unidad.
- **En este proyecto:** Fase 1 · host · directorio: no consta. Recargar systemd y habilitar/arrancar docker-oob-network.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:275`

### C-159 · Log del demonio Docker en el arranque

```bash
journalctl -u docker -b
```

- **Qué hace (genérico):** `journalctl`: consulta el journal de systemd. `-u UNIDAD`: solo esa unidad. `-b`: solo el arranque actual.
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. Log del demonio Docker en el arranque: sbJoin correcto y «failed to bind host port 100.64.0.1:…: cannot assign requested address» (causa raíz).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:148`

### C-160 · Regla de operación si el canal está caído

```bash
sudo systemctl restart tfm-fase4-rustdesk.service
```

- **Qué hace (genérico):** `systemctl start/restart UNIDAD`: arranca o reinicia la unidad.
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. Regla de operación si el canal está caído: no Portainer ni docker start.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:241`

### C-161 · Prueba en arranque en frío

```bash
sudo reboot
```

- **Qué hace (genérico):** `reboot`: reinicia el equipo.
- **En este proyecto:** Fase 4 · host · directorio: no consta. Prueba en arranque en frío: tfm-fase4-rustdesk y tfm-fase6-iris en active, 29 contenedores con red, seis puertos en 100.64.0.1.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:252`, `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:304`

### C-162 · Confirmar que hubo arranque nuevo tras el apagado no limpio

```bash
journalctl --list-boots
```

- **Qué hace (genérico):** `journalctl`: consulta el journal de systemd. `--list-boots`: lista los arranques registrados.
- **En este proyecto:** Fase 4 · host · directorio: no consta. Confirmar que hubo arranque nuevo tras el apagado no limpio. Un primer intento sin reinicio real se delató con estas comprobaciones.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:286`, `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:286`

### C-248 · Prueba de reinicio

```bash
systemctl is-active tfm-fase6-iris.service
```

- **Qué hace (genérico):** `systemctl is-active UNIDAD`: imprime `active` o el estado real; código 0 solo si está activa.
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. Prueba de reinicio: unidad tfm-fase6-iris active, ExecMainStatus=0. ExecMainStatus=0 con systemctl show (INFORME-AUDITORIA-FASE6:470).
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:468`, `docs/INFORME-AUDITORIA-FASE6.md:1003`

### C-261 · La pila no levanta tras reiniciar

```bash
systemctl status tfm-fase6-iris.service
journalctl -u tfm-fase6-iris.service -b --no-pager
sudo systemctl restart tfm-fase6-iris.service
```

- **Qué hace (genérico):** `systemctl start/restart UNIDAD`: arranca o reinicia la unidad. `systemctl status UNIDAD`: estado y últimas líneas del journal. `journalctl`: consulta el journal de systemd. `-u UNIDAD`: solo esa unidad. `-b`: solo el arranque actual. `--no-pager`: sin paginador.
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. La pila no levanta tras reiniciar: estado y journal de la unidad, y reinicio.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:1037`, `fase6-iris/README.md:335`

### C-263 · Prueba de arranque en frío, criterio de aceptación de la fase

```bash
sudo reboot
sleep 90
systemctl is-active tfm-fase6-iris.service
./scripts/verify-fase6.sh
```

- **Qué hace (genérico):** `systemctl is-active UNIDAD`: imprime `active` o el estado real; código 0 solo si está activa. `sleep N`: espera N segundos. `reboot`: reinicia el equipo. Script del proyecto `scripts/verify-fase6.sh` (16 comprobaciones; 0 = OK, 1 = fallo).
- **En este proyecto:** Fase 6 · IRIS · directorio: `~/tfm-alerta-temprana-oob`. Prueba de arranque en frío, criterio de aceptación de la fase: reboot, esperar, unidad active y verify-fase6.sh exit 0.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:1000`, `fase6-iris/README.md:379`

### C-271 · Instalar y habilitar la unidad tfm-fase6-iris.service

```bash
sudo cp systemd/tfm-fase6-iris.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now tfm-fase6-iris.service
```

- **Qué hace (genérico):** `systemctl daemon-reload`: relee las unidades tras crearlas o editarlas. `systemctl enable --now`: habilita la unidad en el arranque y la arranca ya. `systemctl enable`: habilita la unidad en el arranque. `cp ORIGEN DESTINO`: copia ficheros.
- **En este proyecto:** Fase 6 · IRIS · directorio: `fase6-iris`. Instalar y habilitar la unidad tfm-fase6-iris.service.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase6-iris/README.md:353`

### C-411 · Esperar hasta 300 s a que exista TAILNET_IP antes de levantar hbbs/hbbr

```bash
ExecStartPre=/bin/sh -c '. ./.env; i=0; while [ $$i -lt 150 ]; do ip -4 -o addr show | grep -q " $$TAILNET_IP/" && exit 0; i=$$((i+1)); sleep 2; done; echo "TAILNET_IP $$TAILNET_IP no disponible tras 300 s" >&2; exit 1'
```

- **Qué hace (genérico):** Directivas de unidad systemd: `ExecStartPre` se ejecuta antes del arranque, `ExecStart` arranca (varias líneas se ejecutan en orden con `Type=oneshot`) y `ExecStop` al parar. En `Exec*` systemd sustituye `$VAR`; `$$` produce un `$` literal para el shell. `ip addr show`: direcciones de las interfaces (`-4` solo IPv4, `-o` una línea por dirección). `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto). `sleep N`: espera N segundos.
- **En este proyecto:** Fase 4 · RustDesk · directorio: `/home/jose/tfm-alerta-temprana-oob/fase4-breakglass-dc`. Esperar hasta 300 s a que exista TAILNET_IP antes de levantar hbbs/hbbr. Los $ van duplicados ($$): sin duplicar, la espera sale al instante sin error.
- **Resultado:** **VALIDADO**
- **Fuente:** `fase4-breakglass-dc/systemd/tfm-fase4-rustdesk.service:18`

### C-412 · Down + up --wait sin --remove-orphans (borraría headscale-ui, que comparte…

```bash
ExecStart=/usr/bin/docker compose -f docker-compose.rustdesk.yml down
ExecStart=/usr/bin/docker compose -f docker-compose.rustdesk.yml up -d --wait --wait-timeout 120
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `-f FICHERO`: fichero de configuración de Compose que se usa en lugar de los descubiertos automáticamente. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano. `--wait-timeout N`: tiempo máximo, en segundos, de esa espera. `--wait`: espera a que los servicios estén en ejecución o `healthy` antes de devolver el control. `down`: para y elimina los contenedores y las redes del proyecto (los volúmenes con nombre se conservan). Directivas de unidad systemd: `ExecStartPre` se ejecuta antes del arranque, `ExecStart` arranca (varias líneas se ejecutan en orden con `Type=oneshot`) y `ExecStop` al parar. En `Exec*` systemd sustituye `$VAR`; `$$` produce un `$` literal para el shell.
- **En este proyecto:** Fase 4 · RustDesk · directorio: `/home/jose/tfm-alerta-temprana-oob/fase4-breakglass-dc`. down + up --wait sin --remove-orphans (borraría headscale-ui, que comparte proyecto). Verificado: active (exited), status=0/SUCCESS, cinco puertos, headscale-ui intacto.
- **Resultado:** **VALIDADO**
- **Fuente:** `fase4-breakglass-dc/systemd/tfm-fase4-rustdesk.service:20`

### C-413 · ExecStop down

```bash
ExecStop=/usr/bin/docker compose -f docker-compose.rustdesk.yml down
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `-f FICHERO`: fichero de configuración de Compose que se usa en lugar de los descubiertos automáticamente. `down`: para y elimina los contenedores y las redes del proyecto (los volúmenes con nombre se conservan). Directivas de unidad systemd: `ExecStartPre` se ejecuta antes del arranque, `ExecStart` arranca (varias líneas se ejecutan en orden con `Type=oneshot`) y `ExecStop` al parar. En `Exec*` systemd sustituye `$VAR`; `$$` produce un `$` literal para el shell.
- **En este proyecto:** Fase 4 · RustDesk · directorio: `/home/jose/tfm-alerta-temprana-oob/fase4-breakglass-dc`. ExecStop down: en apagado limpio elimina los contenedores (por eso el reboot limpio no reproduce el fallo de bind).
- **Resultado:** **VALIDADO**
- **Fuente:** `fase4-breakglass-dc/systemd/tfm-fase4-rustdesk.service:22`

### C-414 · Esperar a 100.64.0.1

```bash
ExecStartPre=/bin/sh -c 'i=0; while [ $$i -lt 150 ]; do ip -4 -o addr show | grep -q " 100.64.0.1/" && exit 0; i=$$((i+1)); sleep 2; done; echo "100.64.0.1 no disponible tras 300 s" >&2; exit 1'
```

- **Qué hace (genérico):** Directivas de unidad systemd: `ExecStartPre` se ejecuta antes del arranque, `ExecStart` arranca (varias líneas se ejecutan en orden con `Type=oneshot`) y `ExecStop` al parar. En `Exec*` systemd sustituye `$VAR`; `$$` produce un `$` literal para el shell. `ip addr show`: direcciones de las interfaces (`-4` solo IPv4, `-o` una línea por dirección). `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto). `sleep N`: espera N segundos.
- **En este proyecto:** Fase 6 · IRIS · directorio: `/home/jose/tfm-alerta-temprana-oob/fase6-iris`. Esperar a 100.64.0.1 (máx. 300 s) antes de levantar IRIS, con $$ duplicados.
- **Resultado:** **VALIDADO**
- **Fuente:** `fase6-iris/systemd/tfm-fase6-iris.service:22`

### C-415 · down --remove-orphans + up --wait

```bash
ExecStart=/usr/bin/docker compose down --remove-orphans
ExecStart=/usr/bin/docker compose up -d --wait --wait-timeout 180
```

- **Qué hace (genérico):** `docker compose`: CLI de Compose v2; actúa sobre el proyecto Compose del directorio de trabajo o de los ficheros indicados. `up`: crea (si hace falta) y arranca los contenedores de los servicios. `-d`: modo desacoplado; los contenedores quedan en segundo plano. `--wait-timeout N`: tiempo máximo, en segundos, de esa espera. `--wait`: espera a que los servicios estén en ejecución o `healthy` antes de devolver el control. `--remove-orphans`: elimina contenedores de servicios que no están definidos en los ficheros del proyecto. `down`: para y elimina los contenedores y las redes del proyecto (los volúmenes con nombre se conservan). Directivas de unidad systemd: `ExecStartPre` se ejecuta antes del arranque, `ExecStart` arranca (varias líneas se ejecutan en orden con `Type=oneshot`) y `ExecStop` al parar. En `Exec*` systemd sustituye `$VAR`; `$$` produce un `$` literal para el shell.
- **En este proyecto:** Fase 6 · IRIS · directorio: `/home/jose/tfm-alerta-temprana-oob/fase6-iris`. down --remove-orphans + up --wait: elimina endpoints obsoletos y espera a los healthchecks. Prueba de reinicio: active, ExecMainStatus=0, verify-fase6 exit 0.
- **Resultado:** **VALIDADO**
- **Fuente:** `fase6-iris/systemd/tfm-fase6-iris.service:23`, `docs/INFORME-AUDITORIA-FASE6.md:454`

## I.6 Red: Tailscale, Headscale, sockets y conectividad

**(en este proyecto)** Tailnet de contingencia (Tailscale con Headscale como plano de control), exposición de puertos (`ss`) y conectividad. Las fuentes establecen que la política ACL vigente solo se ve en el netmap del nodo destino y que `ss` en el host es el control de exposición.

### C-020 · Puertos 80/443/9443 en escucha

```bash
ss -tulpn | grep -E ':80|:443|:9443'
```

- **Qué hace (genérico):** `ss`: sockets del sistema. `-t` TCP, `-u` UDP, `-l` solo en escucha, `-n` sin resolver nombres, `-p` proceso propietario. `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto).
- **En este proyecto:** Fase 1 · Traefik · directorio: no consta. Puertos 80/443/9443 en escucha.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:308`

### C-033 · Puerto 9091 en escucha

```bash
ss -tulpn | grep 9091
```

- **Qué hace (genérico):** `ss`: sockets del sistema. `-t` TCP, `-u` UDP, `-l` solo en escucha, `-n` sin resolver nombres, `-p` proceso propietario. `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto).
- **En este proyecto:** Fase 1 · Authelia · directorio: no consta. Puerto 9091 en escucha.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1b-authelia.md:262`

### C-061 · V1

```bash
ss -tlnp | grep :8080
```

- **Qué hace (genérico):** `ss`: sockets del sistema. `-t` TCP, `-u` UDP, `-l` solo en escucha, `-n` sin resolver nombres, `-p` proceso propietario. `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto).
- **En este proyecto:** Fase 1 · Traefik · directorio: no consta. V1: la API 8080 solo escucha en loopback → «LISTEN 127.0.0.1:8080 únicamente».
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/DECISION-dashboard-traefik.md:120`

### C-070 · Puertos activos del host de la Fase 1

```bash
sudo ss -tulpn | grep -E "80|443|4443|9443|9200|55000|1514" | sort
```

- **Qué hace (genérico):** `ss`: sockets del sistema. `-t` TCP, `-u` UDP, `-l` solo en escucha, `-n` sin resolver nombres, `-p` proceso propietario. `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto). `sort`: ordena líneas.
- **En este proyecto:** Fase 1 · host · directorio: no consta. Puertos activos del host de la Fase 1.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1e-validacion.md:105`

### C-126 · Valida la sintaxis del fichero

```bash
headscale policy check --file ...
```

- **Qué hace (genérico):** `headscale policy check --file`: valida la sintaxis de un fichero de política.
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Valida la sintaxis del fichero: devolvió «Policy is valid», rc=0, con la política nueva sin aplicar. No prueba la política vigente.
- **Resultado:** **FALLÓ** (→ C-129)
- **Fuente:** `docs/HALLAZGO-headscale-politica-modo-file.md:19`, `docs/CATALOGO-fallos-silenciosos.md:75`

### C-127 · Imprime el fichero configurado, no la política aplicada

```bash
headscale policy get
```

- **Qué hace (genérico):** `headscale policy get`: imprime la política configurada.
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Imprime el fichero configurado, no la política aplicada: mostró la regla nueva aún no vigente.
- **Resultado:** **FALLÓ** (→ C-129)
- **Fuente:** `docs/HALLAZGO-headscale-politica-modo-file.md:20`

### C-128 · Actualizar la política

```bash
headscale policy set --file ...
```

- **Qué hace (genérico):** `headscale policy set --file`: carga una política (solo en modo `database`).
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Actualizar la política: «update is disabled for modes other than 'database'» en modo file.
- **Resultado:** **FALLÓ** (→ C-132)
- **Fuente:** `docs/HALLAZGO-headscale-politica-modo-file.md:21`

### C-129 · Única forma de ver la política vigente

```bash
sudo tailscale debug netmap | python3 -c 'import sys,json
d=json.load(sys.stdin)
for r in (d.get("PacketFilterRules") or []):
    print(r["SrcIPs"][0], sorted(set((p["Ports"]["First"], p["Ports"]["Last"])
          for p in r["DstPorts"] if ":" not in p["IP"])))'
```

- **Qué hace (genérico):** `tailscale debug netmap`: vuelca en JSON el mapa de red que el nodo ha recibido, incluidos los filtros de paquetes aplicados (`PacketFilterRules`). `python3 -c` / `node -e`: ejecuta un fragmento de código en línea.
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Única forma de ver la política vigente: PacketFilterRules del netmap en el nodo destino. Antes del reinicio faltaba el 443; después aparece 100.64.0.4/32 [(443, 443)].
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/HALLAZGO-headscale-politica-modo-file.md:30`, `docs/README-fase4a-headscale.md:53`

### C-133 · Comprobar el túnel desde el W11

```bash
tailscale ping
```

- **Qué hace (genérico):** `tailscale ping`: prueba de conectividad por la tailnet (indica si es directa o por DERP).
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Comprobar el túnel desde el W11: respuesta en 1 ms, sesión directa.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/HALLAZGO-headscale-politica-modo-file.md:58`

### C-135 · Generar la API key de Headscale para la UI (90 días)

```bash
docker exec -it headscale headscale apikeys create --expiration 90d
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `-i`: mantiene abierta la entrada estándar; `-t`: asigna una pseudo-TTY. `headscale apikeys create --expiration`: crea una clave de API con caducidad.
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Generar la API key de Headscale para la UI (90 días).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4a-headscale-ui.md:103`

### C-142 · Crear y listar el usuario tfm-oob en Headscale

```bash
docker exec headscale headscale users create tfm-oob
docker exec headscale headscale users list
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `headscale users create/list`: gestiona los usuarios (espacios de nodos) de Headscale.
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Crear y listar el usuario tfm-oob en Headscale.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4b-tailnet.md:33`

### C-144 · Pre-auth key de un solo uso para el orquestador (1 h, tag:orchestrator)

```bash
docker exec headscale headscale preauthkeys create \
  --user tfm-oob --expiration 1h --tags tag:orchestrator
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `headscale preauthkeys create`: genera una clave de pre-autorización. `--user`: usuario; `--expiration`: caducidad; `--tags`: etiquetas asignadas a los nodos que se registren con ella.
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Pre-auth key de un solo uso para el orquestador (1 h, tag:orchestrator); igual para el DC con tag:dc.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4b-tailnet.md:60`, `docs/README-fase4b-tailnet.md:89`

### C-145 · Unir el orquestador a la tailnet vía https://hs.oob.local con…

```bash
sudo tailscale up \
  --login-server https://hs.oob.local \
  --authkey [REDACTADO] --hostname orchestrator-tfm \
  --advertise-tags=tag:orchestrator --accept-dns=false
```

- **Qué hace (genérico):** `tailscale up`: conecta el nodo a la tailnet. `--login-server URL`: servidor de control (aquí Headscale); `--authkey`: clave de pre-autorización; `--hostname`: nombre del nodo; `--advertise-tags`: etiquetas que solicita; `--accept-dns=false`: no aplica la configuración DNS de la tailnet.
- **En este proyecto:** Fase 4 · host · directorio: no consta. Unir el orquestador a la tailnet vía https://hs.oob.local con --accept-dns=false. Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4b-tailnet.md:67`

### C-146 · Listar nodos (debe mostrar orchestrator-tfm y dc01-tfm)

```bash
docker exec headscale headscale nodes list
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `headscale nodes list`: nodos registrados, IP, etiquetas y estado de conexión.
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Listar nodos (debe mostrar orchestrator-tfm y dc01-tfm).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase4b-tailnet.md:110`

### C-147 · Conectividad de la tailnet desde el orquestador

```bash
tailscale status
ping <IP_TAILSCALE_DC01>
```

- **Qué hace (genérico):** `tailscale status`: pares visibles y estado de la conexión. `ping` (`-c N` en Linux): eco ICMP.
- **En este proyecto:** Fase 4 · host · directorio: no consta. Conectividad de la tailnet desde el orquestador.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase4b-tailnet.md:120`, `docs/README-fase4-validacion.md:570`

### C-148 · Etiquetar un nodo desde el plano de control

```bash
headscale nodes tag --identifier <id> -t tag:x
```

- **Qué hace (genérico):** `headscale nodes tag --identifier ID -t ETIQUETA`: asigna etiquetas a un nodo desde el plano de control.
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Etiquetar un nodo desde el plano de control.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4b-tailnet.md:163`

### C-149 · Confirmar que RustDesk fluye por la tailnet tras la ACL

```bash
tcpdump -ni tailscale0 port 21116
```

- **Qué hace (genérico):** `tcpdump -n -i INTERFAZ FILTRO`: captura de paquetes sin resolver nombres.
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. Confirmar que RustDesk fluye por la tailnet tras la ACL: captura tráfico 100.64.0.2 → 100.64.0.1.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/README-fase4-pendientes.md:35`

### C-157 · Ningún docker-proxy en 21115-21119

```bash
sudo ss -tlnp
```

- **Qué hace (genérico):** `ss`: sockets del sistema. `-t` TCP, `-u` UDP, `-l` solo en escucha, `-n` sin resolver nombres, `-p` proceso propietario.
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. Ningún docker-proxy en 21115-21119. Ojo: el rustdesk --server del host es el cliente de escritorio, no el servidor.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:27`, `docs/MEDICION-postura-red-2026-09-23.md:5`

### C-163 · Confirmar MagicDNS con sufijo tailnet.internal tras cambiar base_domain…

```bash
tailscale dns status
```

- **Qué hace (genérico):** `tailscale dns status`: estado de MagicDNS y sufijos de búsqueda.
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Confirmar MagicDNS con sufijo tailnet.internal tras cambiar base_domain (registrado como confirmado).
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/README-fase4c-dcagent.md:585`

### C-230 · Medir que la consola 9001 de MinIO ya no está publicada

```bash
ss -tlnp
```

- **Qué hace (genérico):** `ss`: sockets del sistema. `-t` TCP, `-u` UDP, `-l` solo en escucha, `-n` sin resolver nombres, `-p` proceso propietario.
- **En este proyecto:** Fase 5 · MinIO · directorio: no consta. Medir que la consola 9001 de MinIO ya no está publicada: ningún proceso en el 9001, un único mapeo en docker ps.
- **Resultado:** **VALIDADO**
- **Fuente:** `fase5-velociraptor/SECURITY-NOTICE.md:156`, `fase5-velociraptor/SECURITY-NOTICE.md:298`, `docs/AUDITORIA-CIERRE-2026-09-23.md:449`, `docs/AUDITORIA-CIERRE-2026-09-23.md:450`

### C-234 · IRIS solo escucha en la IP de la tailnet → «LISTEN 0 4096 100.64.0.1:4833»

```bash
ss -tlnp | grep 4833
```

- **Qué hace (genérico):** `ss`: sockets del sistema. `-t` TCP, `-u` UDP, `-l` solo en escucha, `-n` sin resolver nombres, `-p` proceso propietario. `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto).
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. IRIS solo escucha en la IP de la tailnet → «LISTEN 0 4096 100.64.0.1:4833». Detectó la reversión silenciosa del override.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:298`, `docs/INFORME-AUDITORIA-FASE6.md:316`

### C-264 · En arranque manual, comprobar antes que tailscale0 tiene 100.64.0.1

```bash
ip a show tailscale0 | grep 100.64.0.1
```

- **Qué hace (genérico):** `ip addr show`: direcciones de las interfaces (`-4` solo IPv4, `-o` una línea por dirección). `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto).
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. En arranque manual, comprobar antes que tailscale0 tiene 100.64.0.1.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase6-iris/README.md:188`

### C-280 · Alcance de n8n a la tailnet

```bash
docker exec n8n sh -c 'nc -zv -w 5 100.64.0.1 443'
  → 100.64.0.1 (100.64.0.1:443) open
docker exec n8n sh -c 'nc -zv -w 5 100.64.0.1 4833'
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `nc -z`: comprueba si el puerto acepta conexiones sin enviar datos; `-v`: detallado; `-w N`: tiempo de espera.
- **En este proyecto:** Fase 6 · n8n · directorio: no consta. Alcance de n8n a la tailnet: 443 y 4833 open.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:48`

### C-282 · Puerto real del nginx de IRIS en la tailnet

```bash
sudo ss -ltnp | grep 4833
```

- **Qué hace (genérico):** `ss`: sockets del sistema. `-t` TCP, `-u` UDP, `-l` solo en escucha, `-n` sin resolver nombres, `-p` proceso propietario. `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto).
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. Puerto real del nginx de IRIS en la tailnet: 100.64.0.1:4833.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:66`

### C-322 · El cliente rtty verifica el canal con -C oob-rootCA.crt (antes -sx sin…

```bash
rtty -s -C /etc/kvmd/user/oob-rootCA.crt -T 2 -I "$device_id" \
     -h $HOSTNAME$PORT -t "$TOKEN" -d "$device_mac" &
```

- **Qué hace (genérico):** `rtty`: cliente del terminal remoto rttys. `-s`: conexión TLS; `-C, --cacert`: «CA certificate to verify peer against» (ayuda del binario, citada en la fuente); el resto de opciones son los parámetros de conexión del dispositivo.
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. En el GL-RM1: el cliente rtty verifica el canal con -C oob-rootCA.crt (antes -sx sin verificación).
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/mejora2-tls-canal-rtty.md:42`

### C-325 · Prueba mensual M1

```bash
docker exec headscale headscale nodes list
docker exec headscale headscale preauthkeys list
ping -c 5 100.64.0.2
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `headscale preauthkeys list`: lista las claves (reutilizable, usada, caducidad). `headscale nodes list`: nodos registrados, IP, etiquetas y estado de conexión. `ping` (`-c N` en Linux): eco ICMP.
- **En este proyecto:** Fase 8 · Headscale · directorio: no consta. Prueba mensual M1: nodos online, ninguna preauthkey reutilizable vigente, latencia.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/mejora5-prueba-mensual-resiliencia.md:82`

### C-327 · M3

```bash
ping -c 3 100.64.0.2
```

- **Qué hace (genérico):** `ping` (`-c N` en Linux): eco ICMP.
- **En este proyecto:** Fase 8 · Headscale · directorio: no consta. M3: con Headscale parado y DC01 reiniciado → 100 % de pérdida (medido en la primera ejecución).
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/mejora5-prueba-mensual-resiliencia.md:114`

### C-332 · M6, en el dispositivo

```bash
grep -c 'oob-rootCA' /etc/kvmd/user/scripts/S01selfCloud
netstat -tnp | grep 5912
```

- **Qué hace (genérico):** `netstat -tn`: conexiones TCP numéricas (`-p` añade el PID). `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto). `S01selfCloud start|restart`: script de arranque del cliente rtty en el GL-RM1 (firmware del fabricante, adaptado).
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. M6, en el dispositivo: el script conserva -C y hay conexión ESTABLISHED.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/mejora5-prueba-mensual-resiliencia.md:178`

### C-335 · Identificar el watchdog por conexión y PID en lugar de por nombre

```bash
netstat -tnp
```

- **Qué hace (genérico):** `netstat -tn`: conexiones TCP numéricas (`-p` añade el PID).
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. Identificar el watchdog por conexión y PID en lugar de por nombre.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/mejora6-endurecimiento-dispositivo.md:357`

### C-337 · Altas futuras con preauthkey creada en el momento

```bash
headscale preauthkeys create
```

- **Qué hace (genérico):** `headscale preauthkeys create`: genera una clave de pre-autorización. `--user`: usuario; `--expiration`: caducidad; `--tags`: etiquetas asignadas a los nodos que se registren con ella.
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Altas futuras con preauthkey creada en el momento.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/mejora6-endurecimiento-dispositivo.md:197`

### C-347 · Nearest DERP

```bash
tailscale netcheck
```

- **Qué hace (genérico):** `tailscale netcheck`: diagnóstico de conectividad UDP y latencia a los DERP.
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Nearest DERP: unknown con el servicio sano: el estado real lo dan los logs de tailscaled y tailscale status.
- **Resultado:** **FALLÓ** (→ C-147)
- **Fuente:** `docs/CATALOGO-fallos-silenciosos.md:200`

### C-351 · D-27 (propuesta)

```bash
ss -tlnup | grep 2111
```

- **Qué hace (genérico):** `ss`: sockets del sistema. `-t` TCP, `-u` UDP, `-l` solo en escucha, `-n` sin resolver nombres, `-p` proceso propietario. `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto).
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. D-27 (propuesta): hbbs/hbbr solo en 100.64.0.1:21115-21119.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/AUDITORIA-CIERRE-2026-09-23.md:469`

### C-358 · Listar nodos

```bash
headscale nodes list
```

- **Qué hace (genérico):** `headscale nodes list`: nodos registrados, IP, etiquetas y estado de conexión.
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Listar nodos: 4 nodos; glkvm offline desde 2026-07-13 y sin tag.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/INFORME-P1-0-correcciones.md:18`, `docs/INFORME-P1-0-correcciones.md:151`, `docs/AUDITORIA-CIERRE-2026-09-23.md:459`

### C-362 · Diez claves

```bash
headscale preauthkeys list
```

- **Qué hace (genérico):** `headscale preauthkeys list`: lista las claves (reutilizable, usada, caducidad).
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Diez claves; la ID 1 reutilizable y válida un año.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/credenciales-de-arranque.md:21`

### C-363 · Expirar la clave reutilizable

```bash
headscale preauthkeys expire -i 1
```

- **Qué hace (genérico):** `headscale preauthkeys expire -i ID`: invalida una clave.
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Expirar la clave reutilizable; verificado: figura expirada y los nodos siguen online.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/credenciales-de-arranque.md:40`

### C-399 · Dentro de verify-fase6.sh

```bash
if ss -tln | grep -q '100\.64\.0\.1:4833'; then ok "escucha en 100.64.0.1:4833"
```

- **Qué hace (genérico):** `ss`: sockets del sistema. `-t` TCP, `-u` UDP, `-l` solo en escucha, `-n` sin resolver nombres, `-p` proceso propietario. `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto).
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. Dentro de verify-fase6.sh: escucha en 100.64.0.1:4833 (y ausencia de 0.0.0.0 e IPv6 en la línea 32).
- **Resultado:** **VALIDADO**
- **Fuente:** `scripts/verify-fase6.sh:30`

### C-416 · Acceso remoto a Portainer por túnel SSH tras restringir 9443 a loopback

```bash
ssh -N -L 9443:127.0.0.1:9443 jose@192.168.0.70
```

- **Qué hace (genérico):** `ssh -N -L LOCAL:DESTINO:PUERTO`: túnel de reenvío local sin abrir shell.
- **En este proyecto:** Fase 1 · Traefik · directorio: no consta. Acceso remoto a Portainer por túnel SSH tras restringir 9443 a loopback (verificado: desde la LAN no conecta, desde el host 200).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/revision-credenciales-fases1-8.md:71`

### C-417 · Medición desde n8n

```bash
nc -zv 100.64.0.1 443
```

- **Qué hace (genérico):** `nc -z`: comprueba si el puerto acepta conexiones sin enviar datos; `-v`: detallado; `-w N`: tiempo de espera.
- **En este proyecto:** Fase 6 · n8n · directorio: no consta. Medición desde n8n: 443 y 4833 abiertos, refuta la inferencia «n8n no tiene vía de red hacia 100.64.0.1».
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:302`

### C-420 · Verificación propuesta en la auditoría

```bash
ip -4 addr
```

- **Qué hace (genérico):** `ip addr show`: direcciones de las interfaces (`-4` solo IPv4, `-o` una línea por dirección).
- **En este proyecto:** Fase transversal · host · directorio: no consta. Verificación propuesta en la auditoría: interfaces del host.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/AUDITORIA-CIERRE-2026-09-23.md:446`

### C-431 · Lectura del netmap cortada en la primera regla

```bash
grep -A 40
```

- **Qué hace (genérico):** `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto).
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Lectura del netmap cortada en la primera regla: llevó a concluir que la ACL no concedía acceso a DC01; la tercera regla lo concedía.
- **Resultado:** **FALLÓ** (→ C-129)
- **Fuente:** `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:123`, `docs/CATALOGO-fallos-silenciosos.md:90`

### C-432 · Validar la sintaxis de la ACL antes de reiniciar (paso no opcional)

```bash
docker exec headscale headscale policy check --file /etc/headscale/acl.hujson
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `headscale policy check --file`: valida la sintaxis de un fichero de política.
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Validar la sintaxis de la ACL antes de reiniciar (paso no opcional): detectó unknown field "tests" mientras el servidor arrancaba sin política, en allow-all. Valida el fichero, no la política vigente.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/README-fase4a-headscale.md:241`

## I.7 n8n CLI y SQLite

**(en este proyecto)** Importación y exportación de workflows de n8n y lectura de bases SQLite (inventario de peers de RustDesk).

### C-102 · Importar el workflow y reiniciar n8n (hay que reasignar credenciales a mano)

```bash
docker cp workflows/wazuh-alert-handler.json n8n:/tmp/w.json
docker exec n8n n8n import:workflow --input=/tmp/w.json
docker restart n8n
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `docker cp ORIGEN DESTINO`: copia ficheros entre el host y un contenedor (`contenedor:ruta`). `docker restart`: reinicia un contenedor sin recrearlo. `n8n import:workflow --input=FICHERO`: importa un workflow desde JSON en la base de n8n.
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. Importar el workflow y reiniciar n8n (hay que reasignar credenciales a mano).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase2-orquestador/README.md:446`

### C-150 · Resolver la identidad del par desde la base del servidor de rendezvous

```bash
sqlite3 rustdesk/data/db_v2.sqlite3 "SELECT id, note FROM peer;"
```

- **Qué hace (genérico):** `sqlite3 BASE "SQL"`: consulta una base SQLite. `-readonly`: sin escritura; `-json`: salida JSON.
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. Resolver la identidad del par desde la base del servidor de rendezvous.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4-validacion.md:268`

### C-299 · Comprobar si hay cambios en la UI sin exportar (propuesto, «sin ejecutarlo»)

```bash
./fase2-orquestador/n8n/export-workflow.sh TUzKK9OBP39SYILa /tmp/export-check.json
diff fase2-orquestador/n8n/workflows/wazuh-alert-handler.json /tmp/export-check.json
```

- **Qué hace (genérico):** Script del proyecto `fase2-orquestador/n8n/export-workflow.sh [ID] [SALIDA]`. `diff A B`: diferencias entre ficheros.
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. Comprobar si hay cambios en la UI sin exportar (propuesto, «sin ejecutarlo»).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/revision-workflow1-caso-iris-warroom.md:661`

### C-378 · Exportar un workflow saneado para versionarlo (sin id, credenciales a…

```bash
./export-workflow.sh [WORKFLOW_ID] [RUTA_SALIDA]
```

- **Qué hace (genérico):** Script del proyecto `fase2-orquestador/n8n/export-workflow.sh [ID] [SALIDA]`.
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. Exportar un workflow saneado para versionarlo (sin id, credenciales a REEMPLAZAR, active false, staticData vacío); sale con 2 si detecta cadenas sospechosas.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:1377`

### C-379 · Dentro de export-workflow.sh

```bash
docker exec "$CONTAINER" n8n export:workflow --id="$WORKFLOW_ID" --pretty --output=/tmp/export-workflow.json
docker cp "$CONTAINER:/tmp/export-workflow.json" "$TMP_RAW"
docker exec "$CONTAINER" rm /tmp/export-workflow.json
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `docker cp ORIGEN DESTINO`: copia ficheros entre el host y un contenedor (`contenedor:ruta`). `n8n export:workflow --id=ID --pretty --output=FICHERO`: exporta un workflow a JSON legible. `rm`: borra ficheros (`-f` sin preguntar ni fallar si no existen).
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. Dentro de export-workflow.sh: n8n export:workflow en el contenedor y copia al host.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase2-orquestador/n8n/export-workflow.sh:39`

### C-380 · Volcar el inventario de peers a JSON desde el host, en solo lectura

```bash
sqlite3 -readonly -json "$BASE/data/db_v2.sqlite3" \
  "SELECT id, note FROM peer;" > "$BASE/peers.json"
```

- **Qué hace (genérico):** `sqlite3 BASE "SQL"`: consulta una base SQLite. `-readonly`: sin escritura; `-json`: salida JSON.
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. Volcar el inventario de peers a JSON desde el host, en solo lectura (la base usa WAL; cron cada 30 min).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase4-breakglass-dc/rustdesk/export-peers.sh:15`

### C-446 · Consultar execution_entity sobre una copia de database.sqlite junto con su…

```bash
docker cp n8n:/home/node/.n8n/database.sqlite /tmp/n8n-ref.sqlite && docker cp n8n:/home/node/.n8n/database.sqlite-wal /tmp/n8n-ref.sqlite-wal 2>/dev/null ; sqlite3 /tmp/n8n-ref.sqlite "SELECT id, status, startedAt FROM execution_entity WHERE workflowId='TUzKK9OBP39SYILa' AND id > 2468 ORDER BY id;" ; rm -f /tmp/n8n-ref.sqlite /tmp/n8n-ref.sqlite-wal /tmp/n8n-ref.sqlite-shm
```

- **Qué hace (genérico):** `docker cp ORIGEN DESTINO`: copia ficheros entre el host y un contenedor (`contenedor:ruta`). `sqlite3 BASE "SQL"`: consulta una base SQLite. `-readonly`: sin escritura; `-json`: salida JSON. `rm`: borra ficheros (`-f` sin preguntar ni fallar si no existen).
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. L-4: consultar execution_entity sobre una copia de database.sqlite junto con su -wal (docker cp puede adelantarse a la escritura diferida). Evidencia registrada: «2469, success, 2026-09-24 19:21:26.993» (columnas id, status, startedAt), línea base previa al cambio de Authelia en n8n.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/LECCIONES-OPERATIVAS-conversaciones.md:55`

## I.8 MinIO (`mc`)

**(en este proyecto)** Bucket `evidence` de la cadena de custodia de la Fase 5.

### C-218 · Verificar las evidencias del incidente en MinIO

```bash
mc ls minio/evidence/INC-2026-042/HOST-DC01/
```

- **Qué hace (genérico):** `mc ls [--recursive] RUTA`: lista objetos. `ls PATRÓN…`: lista ficheros; el código de salida es distinto de 0 si algún patrón no coincide con nada.
- **En este proyecto:** Fase 5 · MinIO · directorio: no consta. Verificar las evidencias del incidente en MinIO (resultado esperado: manifest.json, sha256.txt).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase5-orchestrator-api/README.md:336`

### C-229 · Comprobado experimentalmente

```bash
mc cp
```

- **Qué hace (genérico):** `mc cp`: copia objetos (sobrescribe si existe).
- **En este proyecto:** Fase 5 · MinIO · directorio: no consta. Comprobado experimentalmente: el usuario del orchestrator no borra objetos pero sí los sobrescribe con mc cp.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase5-velociraptor/SECURITY-NOTICE.md:276`

### C-297 · Verificar el bucket evidence

```bash
mc alias set tfm http://localhost:9000 "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY"
mc ls --recursive tfm/evidence
```

- **Qué hace (genérico):** `mc alias set ALIAS URL USUARIO CLAVE`: registra un servidor S3/MinIO. `mc ls [--recursive] RUTA`: lista objetos.
- **En este proyecto:** Fase 5 · MinIO · directorio: no consta. Verificar el bucket evidence (propuesto, «sin ejecutarlo»; claves por variable).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/revision-workflow1-caso-iris-warroom.md:341`

### C-352 · D-28 (propuesta)

```bash
mc admin policy info
```

- **Qué hace (genérico):** `mc admin policy info`: muestra una política de acceso.
- **En este proyecto:** Fase 5 · MinIO · directorio: no consta. D-28 (propuesta): tfm-orchestrator sin s3:DeleteObject; versionado del bucket con mc version info.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/AUDITORIA-CIERRE-2026-09-23.md:470`, `docs/AUDITORIA-CIERRE-2026-09-23.md:470`

### C-381 · Init-minio-bucket.sh

```bash
mc alias set oob http://minio:9000 "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"
mc mb --ignore-existing "oob/${MINIO_BUCKET}"
mc anonymous set none "oob/${MINIO_BUCKET}"
```

- **Qué hace (genérico):** `mc alias set ALIAS URL USUARIO CLAVE`: registra un servidor S3/MinIO. `mc mb --ignore-existing ALIAS/BUCKET`: crea el bucket si no existe. `mc anonymous set none`: retira cualquier acceso anónimo al bucket.
- **En este proyecto:** Fase 5 · MinIO · directorio: no consta. init-minio-bucket.sh: alias, bucket y sin acceso anónimo (credenciales por variable).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase5-velociraptor/init-minio-bucket.sh:3`

## I.9 Edición de ficheros y permisos

**(en este proyecto)** Creación de ficheros de configuración, heredocs, permisos y propietarios; incluye el patrón de edición que conserva el inodo.

### C-011 · Crear la estructura de carpetas de la Fase 1

```bash
mkdir -p fase1-infraestructura/{traefik/dynamic,authelia,rocketchat,wazuh,portainer}
```

- **Qué hace (genérico):** `mkdir -p`: crea el directorio y los padres que falten.
- **En este proyecto:** Fase 1 · host · directorio: `/home/jose/tfm-alerta-temprana-oob`. Crear la estructura de carpetas de la Fase 1.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:116`

### C-012 · Crear .env de la Fase 1 a partir de .env.example

```bash
cp fase1-infraestructura/.env.example fase1-infraestructura/.env
nano fase1-infraestructura/.env
```

- **Qué hace (genérico):** `nano`: editor de texto en terminal. `cp ORIGEN DESTINO`: copia ficheros.
- **En este proyecto:** Fase 1 · host · directorio: no consta. Crear .env de la Fase 1 a partir de .env.example.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:137`

### C-013 · Editar /etc/docker/daemon.json (min-api-version 1.24)

```bash
sudo nano /etc/docker/daemon.json
```

- **Qué hace (genérico):** `nano`: editor de texto en terminal.
- **En este proyecto:** Fase 1 · host · directorio: no consta. Editar /etc/docker/daemon.json (min-api-version 1.24).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:246`

### C-015 · Crear la unidad systemd docker-oob-network que recrea la red al arrancar…

```bash
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
```

- **Qué hace (genérico):** `docker network create RED`: crea una red de Docker. `docker network ls`: lista las redes. Directivas de unidad systemd: `ExecStartPre` se ejecuta antes del arranque, `ExecStart` arranca (varias líneas se ejecutan en orden con `Type=oneshot`) y `ExecStop` al parar. En `Exec*` systemd sustituye `$VAR`; `$$` produce un `$` literal para el shell. `tee FICHERO << 'EOF'`: escribe el heredoc en el fichero (con `sudo`, como root). `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto). `ls PATRÓN…`: lista ficheros; el código de salida es distinto de 0 si algún patrón no coincide con nada.
- **En este proyecto:** Fase 1 · host · directorio: no consta. Crear la unidad systemd docker-oob-network que recrea la red al arrancar (Problema 2).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:260`

### C-017 · Crear acme.json con permisos 600

```bash
touch traefik/acme.json
chmod 600 traefik/acme.json
ls -la traefik/acme.json
```

- **Qué hace (genérico):** `chmod MODO`: permisos (p. ej. `600` solo el propietario lee y escribe; `755` todos leen y ejecutan; `400` solo lectura del propietario; `+x` ejecutable). `touch`: crea el fichero vacío si no existe. `ls -l` (`-a` ocultos, `-i` número de inodo).
- **En este proyecto:** Fase 1 · Traefik · directorio: `/home/jose/tfm-alerta-temprana-oob/fase1-infraestructura`. Crear acme.json con permisos 600.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:288`

### C-025 · Crear el directorio de Authelia

```bash
mkdir -p ~/tfm-alerta-temprana-oob/fase1-infraestructura/authelia
```

- **Qué hace (genérico):** `mkdir -p`: crea el directorio y los padres que falten.
- **En este proyecto:** Fase 1 · Authelia · directorio: no consta. Crear el directorio de Authelia.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1b-authelia.md:214`

### C-029 · Leer el enlace de registro TOTP de notification.txt

```bash
cat ~/tfm-alerta-temprana-oob/fase1-infraestructura/authelia/notification.txt
```

- **Qué hace (genérico):** `cat`: muestra el contenido.
- **En este proyecto:** Fase 1 · Authelia · directorio: no consta. Leer el enlace de registro TOTP de notification.txt.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1b-authelia.md:242`

### C-036 · Crear docker-entrypoint-keyfile.sh (copia el keyFile con permisos 400)

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

- **Qué hace (genérico):** `chmod MODO`: permisos (p. ej. `600` solo el propietario lee y escribe; `755` todos leen y ejecutan; `400` solo lectura del propietario; `+x` ejecutable). `chown USUARIO:GRUPO`: cambia el propietario. `cat > FICHERO << 'MARCA'`: escribe el heredoc en el fichero; con la marca entrecomillada no se expanden variables. `cp ORIGEN DESTINO`: copia ficheros.
- **En este proyecto:** Fase 1 · MongoDB · directorio: `~/tfm-alerta-temprana-oob/fase1-infraestructura/mongodb`. Crear docker-entrypoint-keyfile.sh (copia el keyFile con permisos 400).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1c-mongodb-rocketchat.md:144`

### C-048 · Persistir vm.max_map_count

```bash
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.d/99-wazuh.conf
```

- **Qué hace (genérico):** `tee -a FICHERO`: añade la entrada al final del fichero (con `sudo tee`, como root).
- **En este proyecto:** Fase 1 · Wazuh · directorio: no consta. Persistir vm.max_map_count.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1d-wazuh.md:56`, `docs/README-fase1d-wazuh.md:119`

### C-054 · Comprobar que existen los .pem y .key

```bash
ls -la config/wazuh_indexer_ssl_certs/
```

- **Qué hace (genérico):** `ls -l` (`-a` ocultos, `-i` número de inodo).
- **En este proyecto:** Fase 1 · Wazuh · directorio: `single-node`. Comprobar que existen los .pem y .key.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1d-wazuh.md:135`

### C-055 · Crear serversTransport con insecureSkipVerify

```bash
cat > ~/tfm-alerta-temprana-oob/fase1-infraestructura/traefik/dynamic/wazuh-transport.yml << 'EOF'
http:
  serversTransports:
    wazuhtransport:
      insecureSkipVerify: true
EOF
```

- **Qué hace (genérico):** `cat > FICHERO << 'MARCA'`: escribe el heredoc en el fichero; con la marca entrecomillada no se expanden variables.
- **En este proyecto:** Fase 1 · Traefik · directorio: no consta. Crear serversTransport con insecureSkipVerify: true para Wazuh. Sigue vigente: registrado como hallazgo abierto P1-1f (véase Parte III).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1d-wazuh.md:175`

### C-056 · Añadir wazuh.oob.local a /etc/hosts

```bash
echo "127.0.0.1   wazuh.oob.local" | sudo tee -a /etc/hosts
```

- **Qué hace (genérico):** `tee -a FICHERO`: añade la entrada al final del fichero (con `sudo tee`, como root).
- **En este proyecto:** Fase 1 · host · directorio: no consta. Añadir wazuh.oob.local a /etc/hosts.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1d-wazuh.md:185`

### C-074 · Contenido mínimo del .env de la Fase 1 (valores como marcadores)

```bash
ENCLAVE_DOMAIN=oob.local
AUTHELIA_JWT_SECRET=[REDACTADO]
AUTHELIA_SESSION_SECRET=[REDACTADO]
AUTHELIA_STORAGE_ENCRYPTION_KEY=[REDACTADO]
MONGO_INITDB_ROOT_USERNAME=rcuser
MONGO_INITDB_ROOT_PASSWORD=[REDACTADO]
ROCKETCHAT_VERSION=8.4.1
ROOT_URL=https://chat.oob.local
```

- **Qué hace (genérico):** Asignaciones `VAR=valor` de un fichero de entorno o de cabecera de script.
- **En este proyecto:** Fase 1 · host · directorio: no consta. Contenido mínimo del .env de la Fase 1 (valores como marcadores). Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase1-infraestructura/README.md:119`

### C-083 · Preparar el cuerpo de la alerta de prueba sin salto de línea final

```bash
printf '%s' '{"id":"<ID-NUEVO>","timestamp":"2026-09-13T20:00:00.000+0200","oob_timestamp":"2026-09-13T20:00:02.000+0200","rule":{"id":"5710","level":10,"description":"PRUEBA MANUAL - intento de acceso SSH fallido","groups":["sshd","authentication_failed"]},"agent":{"name":"DC01-TFM","ip":"192.168.127.140"},"data":{"srcip":"185.220.101.5"}}' > /tmp/alerta-prueba.json
```

- **Qué hace (genérico):** `printf '%s'`: imprime la cadena sin salto de línea final.
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. Preparar el cuerpo de la alerta de prueba sin salto de línea final.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/PROCEDIMIENTO-prueba-manual-webhook.md:46`

### C-091 · Permisos del script custom-n8n

```bash
chmod 755 /var/ossec/integrations/custom-n8n
chown root:wazuh /var/ossec/integrations/custom-n8n
```

- **Qué hace (genérico):** `chmod MODO`: permisos (p. ej. `600` solo el propietario lee y escribe; `755` todos leen y ejecutan; `400` solo lectura del propietario; `+x` ejecutable). `chown USUARIO:GRUPO`: cambia el propietario.
- **En este proyecto:** Fase 2 · Wazuh · directorio: no consta. Permisos del script custom-n8n: 755 y root:wazuh (corregido desde 750: el demonio uid 999 no podía ejecutarlo).
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/README-fase2bcd-workflow-n8n.md:97`

### C-092 · Modo recomendado por Wazuh

```bash
chmod 750
```

- **Qué hace (genérico):** `chmod MODO`: permisos (p. ej. `600` solo el propietario lee y escribe; `755` todos leen y ejecutan; `400` solo lectura del propietario; `+x` ejecutable).
- **En este proyecto:** Fase 2 · Wazuh · directorio: no consta. Modo recomendado por Wazuh; con bind mount uid 1000 dejaba a wazuh-integratord (uid 999) sin permiso de ejecución.
- **Resultado:** **FALLÓ** (→ C-091)
- **Fuente:** `docs/README-fase2bcd-workflow-n8n.md:102`

### C-107 · Ciclo completo

```bash
echo "# test $(date)" | sudo tee -a /etc/hosts.allow
docker exec single-node-wazuh.manager-1 tail -5 /var/ossec/logs/integrations.log
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `tee -a FICHERO`: añade la entrada al final del fichero (con `sudo tee`, como root). `tail [-N]`: últimas líneas.
- **En este proyecto:** Fase 2 · Wazuh · directorio: no consta. Ciclo completo: provocar una alerta FIM y leer integrations.log. La tabla «Validación funcional» registra el caso FIM 550 verificado sobre tráfico real.
- **Resultado:** **VALIDADO**
- **Fuente:** `fase2-orquestador/README.md:474`

### C-134 · Crear la carpeta de configuración de Headscale UI

```bash
mkdir -p ~/tfm-alerta-temprana-oob/fase4-breakglass-dc/headscale-ui/container-config
```

- **Qué hace (genérico):** `mkdir -p`: crea el directorio y los padres que falten.
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. Crear la carpeta de configuración de Headscale UI.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4a-headscale-ui.md:22`

### C-168 · Crear la carpeta de datos de RustDesk Server

```bash
mkdir -p ~/tfm-alerta-temprana-oob/fase4-breakglass-dc/rustdesk/data
```

- **Qué hace (genérico):** `mkdir -p`: crea el directorio y los padres que falten.
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. Crear la carpeta de datos de RustDesk Server.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4e-rustdesk-breakglass.md:41`

### C-237 · P0-C

```bash
ls -la fase6-iris/certificates/rootCA/
```

- **Qué hace (genérico):** `ls -l` (`-a` ocultos, `-i` número de inodo).
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. P0-C: el ancla de confianza no existía en el anfitrión («No such file or directory»).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:193`

### C-287 · M-1

```bash
ls -la fase2-orquestador/n8n/n8n/certs/
```

- **Qué hace (genérico):** `ls -l` (`-a` ocultos, `-i` número de inodo).
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. M-1: misp.crt era un DIRECTORIO (bind con ruta que no resolvía): NODE_EXTRA_CA_CERTS inerte 23 días.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:116`

### C-324 · Vuelta atrás del script S01selfCloud desde la copia en /root

```bash
cp /root/S01selfCloud.bak /etc/kvmd/user/scripts/S01selfCloud
pkill -f rtty-loop.sh; pkill -f 'rtty -s'; sleep 2
/etc/kvmd/user/scripts/S01selfCloud start
```

- **Qué hace (genérico):** `cp ORIGEN DESTINO`: copia ficheros. `sleep N`: espera N segundos. `pkill -f PATRÓN`: envía la señal a los procesos cuya línea de comando coincide. `S01selfCloud start|restart`: script de arranque del cliente rtty en el GL-RM1 (firmware del fabricante, adaptado).
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. En el GL-RM1: vuelta atrás del script S01selfCloud desde la copia en /root.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/mejora2-tls-canal-rtty.md:107`

### C-343 · Variables de cabecera de S01selfCloud (token y contraseña TURN como…

```bash
HOSTNAME="192.168.0.70"
PORT=":5912"
TOKEN=[REDACTADO]
WEBRTC_IP="192.168.0.70"
WEBRTC_PORT="3478"
WEBRTC_USERNAME="glkvmcloudwebrtcuser"
WEBRTC_PASSWORD=[REDACTADO]
```

- **Qué hace (genérico):** Asignaciones `VAR=valor` de un fichero de entorno o de cabecera de script.
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. En el GL-RM1: variables de cabecera de S01selfCloud (token y contraseña TURN como marcadores). Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase8-kvm/README.md:193`

### C-357 · Añadir entradas a /etc/hosts a mano

```bash
sudo nano /etc/hosts
```

- **Qué hace (genérico):** `nano`: editor de texto en terminal.
- **En este proyecto:** Fase transversal · host · directorio: no consta. Añadir entradas a /etc/hosts a mano.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/INFORME-P1-0-correcciones.md:75`

### C-365 · Paso 1

```bash
awk -F'\t' 'BEGIN{OFS="\t"} $1=="ubuntu" && $2=="auth.oob.local" { $3="127.0.0.9" } { print }' docs/resolucion-nombres.tsv > /tmp/resolucion-nombres.tsv.divergencia && mv /tmp/resolucion-nombres.tsv.divergencia docs/resolucion-nombres.tsv
```

- **Qué hace (genérico):** `mv`: mueve o renombra. `awk`: procesa campos (`-F` separador, `$N` campo N).
- **En este proyecto:** Fase transversal · host · directorio: `~/tfm-alerta-temprana-oob`. Paso 1: introducir una divergencia deliberada en el .tsv. Sin ejecutar.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/pruebas/negativa-check-doc.md:77`

### C-375 · Entrypoint versionado

```bash
cp /tmp/mongo-keyfile /etc/mongodb/mongo-keyfile
chown mongodb:mongodb /etc/mongodb/mongo-keyfile
chmod 400 /etc/mongodb/mongo-keyfile
exec docker-entrypoint.sh "$@"
```

- **Qué hace (genérico):** `chmod MODO`: permisos (p. ej. `600` solo el propietario lee y escribe; `755` todos leen y ejecutan; `400` solo lectura del propietario; `+x` ejecutable). `chown USUARIO:GRUPO`: cambia el propietario. `cp ORIGEN DESTINO`: copia ficheros.
- **En este proyecto:** Fase 1 · MongoDB · directorio: no consta. Entrypoint versionado: copiar el keyFile con propietario mongodb y permisos 400 antes de mongod (sustituye al chown desde el host, que no funcionaba con LXD).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase1-infraestructura/mongodb/docker-entrypoint-keyfile.sh:3`

### C-377 · Con LXD el UID 999 está mapeado a lxd:systemd-journal

```bash
sudo chown 999:999 mongo-keyfile
```

- **Qué hace (genérico):** `chown USUARIO:GRUPO`: cambia el propietario.
- **En este proyecto:** Fase 1 · MongoDB · directorio: no consta. Con LXD el UID 999 está mapeado a lxd:systemd-journal: el fichero seguía perteneciendo a otro usuario.
- **Resultado:** **FALLÓ** (→ C-375)
- **Fuente:** `docs/README-fase1c-mongodb-rocketchat.md:92`

### C-425 · Limpiar los ficheros temporales de la medición

```bash
rm /tmp/rttys.bin
```

- **Qué hace (genérico):** `rm`: borra ficheros (`-f` sin preguntar ni fallar si no existen).
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. Limpiar los ficheros temporales de la medición.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/cierre-mejora1-hook.md:216`, `docs/cierre-mejora1-hook.md:216`

### C-438 · Patrón seguro de edición

```bash
tmp=$(mktemp); sed ... > "$tmp" && cat "$tmp" > .env && rm "$tmp"
```

- **Qué hace (genérico):** `cat`: muestra el contenido. `mktemp`: crea un fichero temporal único; `cat "$tmp" > FICHERO` reescribe el contenido sobre el mismo inodo (no lo sustituye). `rm`: borra ficheros (`-f` sin preguntar ni fallar si no existen).
- **En este proyecto:** Fase 6 · MISP · directorio: no consta. Patrón seguro de edición: sed a un temporal y volcado con cat sobre el mismo fichero (conserva el inodo), seguido de un diff de un par de líneas y la recreación de misp-core.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:119`

### C-441 · sed -i sobre custom-n8n, montado como bind mount de fichero en el manager

```bash
sed -i
```

- **Qué hace (genérico):** `sed -i`: edita el fichero «en sitio» escribiendo uno nuevo y renombrándolo sobre el original (inodo nuevo).
- **En este proyecto:** Fase 2 · Wazuh · directorio: no consta. L-2: sed -i sobre custom-n8n, montado como bind mount de fichero en el manager: el diff mostró los dos cambios y no hubo error, pero el contenedor siguió ejecutando el fichero anterior (hash previo 41890ce63ebb). sed -i sustituye el inodo y el montaje queda anclado al antiguo.
- **Resultado:** **FALLÓ** (→ C-438;C-443)
- **Fuente:** `docs/LECCIONES-OPERATIVAS-conversaciones.md:22`

### C-443 · Patrón seguro para futuras ediciones

```bash
tmp=$(mktemp)
sed 's/...//' fichero > "$tmp" && cat "$tmp" > fichero && rm "$tmp"
```

- **Qué hace (genérico):** `cat`: muestra el contenido. `mktemp`: crea un fichero temporal único; `cat "$tmp" > FICHERO` reescribe el contenido sobre el mismo inodo (no lo sustituye). `rm`: borra ficheros (`-f` sin preguntar ni fallar si no existen).
- **En este proyecto:** Fase transversal · host · directorio: no consta. L-2: patrón seguro para futuras ediciones: cat > trunca y reescribe el mismo inodo; sed -i lo sustituye.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/LECCIONES-OPERATIVAS-conversaciones.md:38`

## I.10 Git

**(en este proyecto)** Comprobaciones sobre el propio repositorio (qué está versionado o ignorado, historial, remotos) y operaciones de publicación y purga.

### C-010 · Clonar el repositorio (URL con marcador TU_USUARIO en la fuente)

```bash
git clone https://github.com/TU_USUARIO/tfm-alerta-temprana-oob.git
```

- **Qué hace (genérico):** `git clone URL [DIR]`: clona un repositorio (`--branch`: rama o tag; `--mirror`: copia completa de todas las referencias).
- **En este proyecto:** Fase 1 · git · directorio: `/home/jose`. Clonar el repositorio (URL con marcador TU_USUARIO en la fuente).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:112`

### C-023 · Comprobar las etiquetas existentes

```bash
git tag
```

- **Qué hace (genérico):** `git tag`: lista las etiquetas.
- **En este proyecto:** Fase transversal · git · directorio: no consta. Comprobar las etiquetas existentes: la corrección de 2026-09-24 registra que fase1a-ok no existe.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:333`, `docs/README-fase1e-validacion.md:227`, `docs/README-fase2a-n8n.md:109`, `docs/AUDITORIA-CIERRE-2026-09-23.md:260`

### C-052 · Clonar wazuh-docker v4.11.0

```bash
mkdir -p ~/tfm-alerta-temprana-oob/fase1-infraestructura/wazuh
cd ~/tfm-alerta-temprana-oob/fase1-infraestructura/wazuh
git clone https://github.com/wazuh/wazuh-docker.git --branch v4.11.0 .
cd single-node
```

- **Qué hace (genérico):** `git clone URL [DIR]`: clona un repositorio (`--branch`: rama o tag; `--mirror`: copia completa de todas las referencias). `mkdir -p`: crea el directorio y los padres que falten. `cd DIR`: cambia el directorio de trabajo.
- **En este proyecto:** Fase 1 · Wazuh · directorio: `~/tfm-alerta-temprana-oob/fase1-infraestructura/wazuh`. Clonar wazuh-docker v4.11.0.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1d-wazuh.md:124`

### C-064 · Buscar en el historial el plan citado

```bash
git log --all -- '*PLAN-P1-1a*'
```

- **Qué hace (genérico):** `git log`: historial de commits. `--all`: todas las referencias.
- **En este proyecto:** Fase transversal · git · directorio: no consta. Buscar en el historial el plan citado: «sin resultados».
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/DECISION-dashboard-traefik.md:9`, `docs/DECISION-velociraptor-fuera-sso.md:9`, `docs/DECISION-p0-6-pospuesto.md:34`

### C-080 · Comprobar que users_database.yml ya no está versionado

```bash
git ls-files fase1-infraestructura/authelia/
```

- **Qué hace (genérico):** `git ls-files [RUTA]`: ficheros versionados (en el índice).
- **En este proyecto:** Fase transversal · git · directorio: no consta. Comprobar que users_database.yml ya no está versionado (corrección 2026-09-24: no lo lista).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase1-infraestructura/README.md:323`

### C-081 · Retirar del índice un fichero ya versionado pese a .gitignore (se hizo en…

```bash
git rm --cached
```

- **Qué hace (genérico):** `git rm [--cached] [-r]`: retira ficheros del índice (`--cached` los conserva en disco).
- **En este proyecto:** Fase transversal · git · directorio: no consta. Retirar del índice un fichero ya versionado pese a .gitignore (se hizo en 4417467).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase1-infraestructura/README.md:323`, `docs/AUDITORIA-CIERRE-2026-09-23.md:217`

### C-082 · Localizar dónde se aplica secure-headers@file

```bash
git grep secure-headers@file
```

- **Qué hace (genérico):** `git grep PATRÓN`: busca en los ficheros versionados.
- **En este proyecto:** Fase transversal · git · directorio: no consta. Localizar dónde se aplica secure-headers@file.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase1-infraestructura/README.md:325`

### C-096 · Commit y push de cierre de subfase

```bash
cd ~/tfm-alerta-temprana-oob
git add .
git commit -m "fase2e: integrar Ollama y AI Agent en n8n para triage inteligente local"
git push
```

- **Qué hace (genérico):** `git push [REMOTO RAMA]`: envía commits al remoto (`--force` sobrescribe su historial). `git commit -m`: registra un commit; `git add .` prepara todos los cambios. `cd DIR`: cambia el directorio de trabajo.
- **En este proyecto:** Fase transversal · git · directorio: `~/tfm-alerta-temprana-oob`. Commit y push de cierre de subfase.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase2e-ollama-ai-agent.md:262`, `docs/README-fase2f-cti-enrichment.md:369`

### C-103 · Comprobar que n8n/.env.example nunca se versionó

```bash
git log --all -- fase2-orquestador/n8n/.env.example
```

- **Qué hace (genérico):** `git log`: historial de commits. `--all`: todas las referencias.
- **En este proyecto:** Fase transversal · git · directorio: no consta. Comprobar que n8n/.env.example nunca se versionó: sin resultados.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase2-orquestador/README.md:453`

### C-118 · Comprobar que una_alerta.json existe pero está ignorado

```bash
git ls-files --others --ignored --exclude-standard fase3-agentic/bench
```

- **Qué hace (genérico):** `git ls-files [RUTA]`: ficheros versionados (en el índice). `--others --ignored --exclude-standard`: ficheros no versionados que las reglas estándar ignoran.
- **En este proyecto:** Fase transversal · git · directorio: no consta. Comprobar que una_alerta.json existe pero está ignorado.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase3-agentic/README.md:583`

### C-153 · Identificar la versión desplegada del agente por hash

```bash
git show 8b00bdf:fase4-breakglass-dc/dcagent/agent_dc.py
```

- **Qué hace (genérico):** `git show REV:RUTA`: contenido de un fichero en un commit.
- **En este proyecto:** Fase transversal · git · directorio: no consta. Identificar la versión desplegada del agente por hash: coincide con 8b00bdf en CRLF.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/HITO-dominio-tfm-local-2026-09-26.md:277`

### C-224 · Git check-ignore -v sobre ficheros ya versionados

```bash
git check-ignore -v fase5-velociraptor/velociraptor-config/server.config.yaml
```

- **Qué hace (genérico):** `git check-ignore RUTA`: indica si una ruta está ignorada. `-v`: muestra la regla (fichero:línea) que coincide, incluidas las de negación.
- **En este proyecto:** Fase transversal · git · directorio: no consta. git check-ignore -v sobre ficheros ya versionados: sin salida y exit 1, no porque el patrón falle sino porque no aplica .gitignore a ficheros trackeados.
- **Resultado:** **FALLÓ** (→ C-225)
- **Fuente:** `fase5-velociraptor/INFORME-P0-1.md:36`, `fase5-velociraptor/INFORME-P0-1.md:39`, `fase5-velociraptor/INFORME-P0-1.md:42`

### C-225 · Check-ignore que evalúa el patrón aunque el fichero esté versionado (salida…

```bash
git check-ignore -v --no-index
```

- **Qué hace (genérico):** `git check-ignore RUTA`: indica si una ruta está ignorada. `-v`: muestra la regla (fichero:línea) que coincide, incluidas las de negación. `--no-index`: evalúa las reglas aunque el fichero esté versionado.
- **En este proyecto:** Fase transversal · git · directorio: no consta. check-ignore que evalúa el patrón aunque el fichero esté versionado (salida literal en el informe). También sobre una ruta no versionada (INFORME-P0-1:62).
- **Resultado:** **VALIDADO**
- **Fuente:** `fase5-velociraptor/INFORME-P0-1.md:51`

### C-226 · Sacar del índice el material de Velociraptor

```bash
git rm -r --cached fase5-velociraptor/velociraptor-config/
```

- **Qué hace (genérico):** `git rm [--cached] [-r]`: retira ficheros del índice (`--cached` los conserva en disco).
- **En este proyecto:** Fase transversal · git · directorio: no consta. Sacar del índice el material de Velociraptor (acción para el usuario; el informe no la ejecuta).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase5-velociraptor/INFORME-P0-1.md:163`, `fase5-velociraptor/INFORME-P0-1.md:165`, `fase5-velociraptor/INFORME-P0-1.md:166`, `fase5-velociraptor/INFORME-P0-1.md:167`

### C-227 · Purga del historial con git filter-repo (scripts/purge-history.sh)

```bash
git filter-repo
```

- **Qué hace (genérico):** `git filter-repo`: reescribe el historial (`--path P --invert-paths`: elimina esas rutas de todos los commits; `--force`: sin exigir un clon recién hecho).
- **En este proyecto:** Fase transversal · git · directorio: no consta. Purga del historial con git filter-repo (scripts/purge-history.sh).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase5-velociraptor/SECURITY-NOTICE.md:76`, `fase6-iris/SECURITY-NOTICE.md:71`

### C-228 · Tras la purga, restaurar remotos y forzar el push a origin y backup

```bash
git push --force
```

- **Qué hace (genérico):** `git push [REMOTO RAMA]`: envía commits al remoto (`--force` sobrescribe su historial).
- **En este proyecto:** Fase transversal · git · directorio: no consta. Tras la purga, restaurar remotos y forzar el push a origin y backup.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase5-velociraptor/INFORME-P0-1.md:178`, `fase5-velociraptor/INFORME-P0-1.md:178`

### C-231 · Consolidar el renombrado env.example → .env.example en el índice (acción…

```bash
rm fase5-velociraptor/.env.example
git mv fase5-velociraptor/env.example fase5-velociraptor/.env.example
```

- **Qué hace (genérico):** `git mv ORIGEN DESTINO`: renombra un fichero versionado. `rm`: borra ficheros (`-f` sin preguntar ni fallar si no existen).
- **En este proyecto:** Fase transversal · git · directorio: no consta. Consolidar el renombrado env.example → .env.example en el índice (acción pendiente para el usuario).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/INFORME-P0-3.md:150`, `docs/INFORME-hallazgos-detector.md:253`, `docs/INFORME-hallazgos-detector.md:412`

### C-232 · Estado del árbol al cerrar la sesión

```bash
git status --porcelain
```

- **Qué hace (genérico):** `git status`: estado del árbol (`--porcelain`/`--short`: formato estable y breve).
- **En este proyecto:** Fase transversal · git · directorio: no consta. Estado del árbol al cerrar la sesión.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/INFORME-P0-3.md:282`, `docs/INFORME-P0-4-implementacion.md:237`, `docs/INFORME-hallazgos-detector.md:274`, `docs/INFORME-P1-0-correcciones.md:239`, `docs/INFORME-P1-0.md:173`

### C-252 · Comprobar qué se versionaría tras cambiar .gitignore

```bash
git add --dry-run
```

- **Qué hace (genérico):** `git add --dry-run`: muestra qué se añadiría al índice sin hacerlo.
- **En este proyecto:** Fase transversal · git · directorio: no consta. Comprobar qué se versionaría tras cambiar .gitignore (autoritativo; check-ignore -v da exit 0 también en negaciones). P2-3 de Fase 6: solo los dos certificados públicos; Fase 8: backup-dispositivo/ excluido.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:700`, `docs/INFORME-AUDITORIA-FASE8.md:346`, `docs/api-reconocimiento-fase8.md:128`

### C-253 · Buscar la clave privada de la CA demo en la historia

```bash
git log
```

- **Qué hace (genérico):** `git log`: historial de commits.
- **En este proyecto:** Fase transversal · git · directorio: no consta. Buscar la clave privada de la CA demo en la historia: git log y git rev-list no devuelven nada.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:708`

### C-255 · Error de inferencia

```bash
git check-ignore -v
```

- **Qué hace (genérico):** `git check-ignore RUTA`: indica si una ruta está ignorada. `-v`: muestra la regla (fichero:línea) que coincide, incluidas las de negación.
- **En este proyecto:** Fase transversal · git · directorio: no consta. Error de inferencia: con -v el código de salida refleja coincidencia de patrón, incluidas las negaciones, no exclusión.
- **Resultado:** **FALLÓ** (→ C-252)
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:860`, `docs/CATALOGO-fallos-silenciosos.md:84`

### C-256 · Devolvió «644edf8..99844be main -> main» pero empujó al remoto de backup, no…

```bash
git push
```

- **Qué hace (genérico):** `git push [REMOTO RAMA]`: envía commits al remoto (`--force` sobrescribe su historial).
- **En este proyecto:** Fase transversal · git · directorio: no consta. Devolvió «644edf8..99844be main -> main» pero empujó al remoto de backup, no al principal; detectado con git log origin/main.
- **Resultado:** **FALLÓ** (→ C-257)
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:887`, `docs/CATALOGO-fallos-silenciosos.md:93`

### C-257 · Comprobar el estado resultante del remoto en lugar del código de retorno de…

```bash
git log origin/main
```

- **Qué hace (genérico):** `git log`: historial de commits.
- **En este proyecto:** Fase transversal · git · directorio: no consta. Comprobar el estado resultante del remoto en lugar del código de retorno de git push.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:892`

### C-265 · Comprobar si el material de certificados entró alguna vez en el historial

```bash
git log --all --oneline --name-status -- 'fase6-iris/certificates/*'
```

- **Qué hace (genérico):** `git log`: historial de commits. `--all`: todas las referencias.
- **En este proyecto:** Fase transversal · git · directorio: no consta. Comprobar si el material de certificados entró alguna vez en el historial: sin salida.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase6-iris/SECURITY-NOTICE.md:64`

### C-266 · Buscar la clave de la CA demo en todos los objetos

```bash
git rev-list --objects --all | grep -i 'irisRootCAKey\|iris_dev_key'
```

- **Qué hace (genérico):** `git rev-list --objects --all`: todos los objetos alcanzables. `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto).
- **En este proyecto:** Fase transversal · git · directorio: no consta. Buscar la clave de la CA demo en todos los objetos: sin rastro.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase6-iris/SECURITY-NOTICE.md:66`

### C-273 · Push al remoto de respaldo, segundo paso del protocolo (git push + git push…

```bash
git push backup main
```

- **Qué hace (genérico):** `git push [REMOTO RAMA]`: envía commits al remoto (`--force` sobrescribe su historial).
- **En este proyecto:** Fase transversal · git · directorio: no consta. Push al remoto de respaldo, segundo paso del protocolo (git push + git push backup main). Verificado: git ls-remote backup main = git rev-parse HEAD = 759f77f.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:17`, `docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:17`, `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:269`, `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:266`

### C-274 · Verificar el efecto de un cambio de .gitignore con check-ignore y status, no…

```bash
git status --short
```

- **Qué hace (genérico):** `git status`: estado del árbol (`--porcelain`/`--short`: formato estable y breve).
- **En este proyecto:** Fase transversal · git · directorio: no consta. Verificar el efecto de un cambio de .gitignore con check-ignore y status, no darlo por hecho.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:94`

### C-275 · Git check-ignore devolvió 1 (no ignorado)

```bash
git check-ignore
```

- **Qué hace (genérico):** `git check-ignore RUTA`: indica si una ruta está ignorada.
- **En este proyecto:** Fase transversal · git · directorio: no consta. git check-ignore devolvió 1 (no ignorado): el compose de KVM vivía en otra ruta.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:319`

### C-289 · M-10

```bash
git config --unset-all remote.origin.pushurl
```

- **Qué hace (genérico):** `git config --unset-all CLAVE`: elimina todas las entradas de esa clave.
- **En este proyecto:** Fase transversal · git · directorio: no consta. M-10: remote.origin.pushurl duplicado hacía que git push a secas empujara a los dos remotos; corregido.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:268`

### C-292 · Buscar el token del bot en HEAD

```bash
git grep
```

- **Qué hace (genérico):** `git grep PATRÓN`: busca en los ficheros versionados.
- **En este proyecto:** Fase transversal · git · directorio: no consta. Buscar el token del bot en HEAD: no devolvió nada (premisa falsa).
- **Resultado:** **FALLÓ** (→ C-293)
- **Fuente:** `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:1346`, `docs/CATALOGO-fallos-silenciosos.md:71`

### C-293 · Comprobación correcta

```bash
git show HEAD:<fichero>
```

- **Qué hace (genérico):** `git show REV:RUTA`: contenido de un fichero en un commit.
- **En este proyecto:** Fase transversal · git · directorio: no consta. Comprobación correcta: ocho apariciones con el valor real; la decisión de aplazar la rotación cambió.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:1347`

### C-300 · Historial completo de un fichero, incluidos borrados

```bash
git log --all --full-history -- <fichero>
```

- **Qué hace (genérico):** `git log`: historial de commits. `--all`: todas las referencias.
- **En este proyecto:** Fase transversal · git · directorio: no consta. Historial completo de un fichero, incluidos borrados.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/revision-workflow1-caso-iris-warroom.md:689`

### C-314 · Confirmar que los secretos de la Fase 8 nunca estuvieron en el repositorio

```bash
git ls-files --error-unmatch .env.example
git cat-file -p HEAD:.env.example
```

- **Qué hace (genérico):** `git ls-files [RUTA]`: ficheros versionados (en el índice). `--error-unmatch`: falla si la ruta no está en el índice. `git cat-file -p REV:RUTA`: contenido de un objeto.
- **En este proyecto:** Fase transversal · git · directorio: no consta. Confirmar que los secretos de la Fase 8 nunca estuvieron en el repositorio: «no conocido por git», 0 coincidencias.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE8.md:338`

### C-344 · Comprobar el contenido de un fichero en un commit concreto

```bash
git show 3f26c07:<fichero>
```

- **Qué hace (genérico):** `git show REV:RUTA`: contenido de un fichero en un commit.
- **En este proyecto:** Fase transversal · git · directorio: no consta. Comprobar el contenido de un fichero en un commit concreto.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/CATALOGO-fallos-silenciosos.md:13`

### C-346 · A40

```bash
git ls-files
```

- **Qué hace (genérico):** `git ls-files [RUTA]`: ficheros versionados (en el índice).
- **En este proyecto:** Fase transversal · git · directorio: no consta. A40: sin resultado se leyó como «fuera del repositorio»; el fichero no existía en esa ruta y el comando no distingue las dos causas.
- **Resultado:** **FALLÓ** (→ C-275)
- **Fuente:** `docs/CATALOGO-fallos-silenciosos.md:95`, `docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:315`

### C-354 · Buscar en qué commits aparece un literal

```bash
git log -S
```

- **Qué hace (genérico):** `git log`: historial de commits. `-S CADENA`: commits que añaden o quitan esa cadena.
- **En este proyecto:** Fase transversal · git · directorio: no consta. Buscar en qué commits aparece un literal: presente en 2 commits.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/AUDITORIA-CIERRE-2026-09-23.md:239`

### C-364 · Prueba negativa de --check-doc, paso 0 y 4

```bash
git diff --stat docs/resolucion-nombres.tsv
```

- **Qué hace (genérico):** `git diff [--stat] [RUTA]`: cambios sin preparar (`--stat`: resumen).
- **En este proyecto:** Fase transversal · git · directorio: `~/tfm-alerta-temprana-oob`. Prueba negativa de --check-doc, paso 0 y 4: el fichero debe estar limpio. Sin ejecutar.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/pruebas/negativa-check-doc.md:65`, `docs/pruebas/negativa-check-doc.md:108`

### C-366 · Confirmar que el cambio está aislado

```bash
git diff docs/resolucion-nombres.tsv
```

- **Qué hace (genérico):** `git diff [--stat] [RUTA]`: cambios sin preparar (`--stat`: resumen).
- **En este proyecto:** Fase transversal · git · directorio: `~/tfm-alerta-temprana-oob`. Confirmar que el cambio está aislado. Sin ejecutar.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/pruebas/negativa-check-doc.md:83`

### C-368 · Paso 3

```bash
git checkout -- docs/resolucion-nombres.tsv
```

- **Qué hace (genérico):** `git checkout -- RUTA`: descarta los cambios locales del fichero.
- **En este proyecto:** Fase transversal · git · directorio: `~/tfm-alerta-temprana-oob`. Paso 3: restaurar el fichero. Sin ejecutar.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/pruebas/negativa-check-doc.md:102`

### C-391 · Backup mirror previo a la purga (purge-history.sh aborta si no existe)

```bash
mkdir -p ~/tfm-backups && git clone --mirror . ~/tfm-backups/repo-mirror-pre-purga.git
```

- **Qué hace (genérico):** `git clone URL [DIR]`: clona un repositorio (`--branch`: rama o tag; `--mirror`: copia completa de todas las referencias). `mkdir -p`: crea el directorio y los padres que falten.
- **En este proyecto:** Fase transversal · git · directorio: no consta. Backup mirror previo a la purga (purge-history.sh aborta si no existe).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase5-velociraptor/INFORME-P0-1.md:175`

### C-392 · Purga del historial

```bash
scripts/purge-history.sh
```

- **Qué hace (genérico):** Script del proyecto `scripts/purge-history.sh` (pide confirmar con `PURGAR`).
- **En este proyecto:** Fase transversal · git · directorio: no consta. Purga del historial: pide escribir PURGAR y al terminar imprime git remote add + git push --force por remoto.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase5-velociraptor/INFORME-P0-1.md:176`

### C-393 · Dentro de purge-history.sh

```bash
git filter-repo "${FR_ARGS[@]}"
```

- **Qué hace (genérico):** `git filter-repo`: reescribe el historial (`--path P --invert-paths`: elimina esas rutas de todos los commits; `--force`: sin exigir un clon recién hecho).
- **En este proyecto:** Fase transversal · git · directorio: no consta. Dentro de purge-history.sh: git filter-repo --force --invert-paths con las rutas a purgar.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `scripts/purge-history.sh:81`

### C-395 · Dentro de verify-no-secrets.sh

```bash
done < <(git grep "${GIT_GREP_SCOPE[@]}" -I -n -E "$ere" -- . ":(exclude)${SELF}" 2>/dev/null | cut -d: -f1-2 || true)
```

- **Qué hace (genérico):** `git grep PATRÓN`: busca en los ficheros versionados. `cut -d SEP -f N`: extrae campos.
- **En este proyecto:** Fase transversal · git · directorio: no consta. Dentro de verify-no-secrets.sh: git grep sobre los ficheros versionados, solo ruta y línea, nunca el valor.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `scripts/verify-no-secrets.sh:307`

### C-435 · Listar los ficheros versionados de una fase para contrastar lo que declara la…

```bash
git ls-files fase5-orchestrator-api
```

- **Qué hace (genérico):** `git ls-files [RUTA]`: ficheros versionados (en el índice).
- **En este proyecto:** Fase transversal · git · directorio: no consta. Listar los ficheros versionados de una fase para contrastar lo que declara la documentación.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase5-orchestrator-api/README.md:79`

### C-437 · Ficheros versionados de n8n/

```bash
git ls-files fase2-orquestador/n8n
```

- **Qué hace (genérico):** `git ls-files [RUTA]`: ficheros versionados (en el índice).
- **En este proyecto:** Fase transversal · git · directorio: no consta. Ficheros versionados de n8n/: no incluye .env.example.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase2-orquestador/README.md:453`, `fase2-orquestador/README.md:583`, `fase2-orquestador/n8n/README.md:62`

## I.11 Otras herramientas

**(en este proyecto)** Herramientas del host Ubuntu y del dispositivo GL-RM1, scripts de verificación del proyecto, órdenes de chat de la war room y fragmentos de código ejecutados en línea.

### C-001 · Eliminar el snap de Docker que convivía con Docker Engine .deb

```bash
sudo snap stop docker
sudo snap remove --purge docker
```

- **Qué hace (genérico):** `snap stop/remove --purge`: para y elimina un paquete snap con sus datos.
- **En este proyecto:** Fase 1 · host · directorio: no consta. Eliminar el snap de Docker que convivía con Docker Engine .deb (Problema 1: «exec /entrypoint.sh: operation not permitted»).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:31`, `docs/README-fase1a-traefik-portainer.md:87`

### C-002 · Retirar los perfiles AppArmor residuales del snap de Docker

```bash
sudo apparmor_parser -R /var/lib/snapd/apparmor/profiles/snap.docker.dockerd
sudo apparmor_parser -R /var/lib/snapd/apparmor/profiles/snap.docker.docker
sudo apparmor_parser -R /var/lib/snapd/apparmor/profiles/snap.docker.compose
sudo apparmor_parser -R /var/lib/snapd/apparmor/profiles/snap-update-ns.docker
sudo rm -f /var/lib/snapd/apparmor/profiles/snap.docker.*
sudo rm -f /var/lib/snapd/apparmor/profiles/snap-update-ns.docker
```

- **Qué hace (genérico):** `rm`: borra ficheros (`-f` sin preguntar ni fallar si no existen). `apparmor_parser -R PERFIL`: descarga un perfil AppArmor del kernel.
- **En este proyecto:** Fase 1 · host · directorio: no consta. Retirar los perfiles AppArmor residuales del snap de Docker.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:34`

### C-005 · Instalar prerrequisitos para el repositorio oficial de Docker

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `apt update` / `apt install -y`: actualiza índices e instala paquetes sin preguntar.
- **En este proyecto:** Fase 1 · host · directorio: no consta. Instalar prerrequisitos para el repositorio oficial de Docker.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:92`

### C-006 · Descargar la clave GPG del repositorio de Docker

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg   -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-S`: muestra el error aunque se use `-s`. `-f`: falla sin cuerpo de salida ante errores HTTP. `-L`: sigue las redirecciones. `-o FICHERO`: escribe el cuerpo en un fichero (`/dev/null` lo descarta). `chmod MODO`: permisos (p. ej. `600` solo el propietario lee y escribe; `755` todos leen y ejecutan; `400` solo lectura del propietario; `+x` ejecutable). `install -m 0755 -d DIR`: crea el directorio con esos permisos.
- **En este proyecto:** Fase 1 · host · directorio: no consta. Descargar la clave GPG del repositorio de Docker.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:94`

### C-007 · Declarar el repositorio apt de Docker

```bash
echo "deb [arch=$(dpkg --print-architecture)   signed-by=/etc/apt/keyrings/docker.asc]   https://download.docker.com/linux/ubuntu   $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" |   sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

- **Qué hace (genérico):** Línea de repositorio apt: `dpkg --print-architecture` da la arquitectura, `signed-by` fija la clave que firma el repositorio y `sudo tee` la escribe en `/etc/apt/sources.list.d/`.
- **En este proyecto:** Fase 1 · host · directorio: no consta. Declarar el repositorio apt de Docker.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:98`

### C-008 · Instalar Docker Engine y el plugin Compose

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io                     docker-buildx-plugin docker-compose-plugin
```

- **Qué hace (genérico):** `apt update` / `apt install -y`: actualiza índices e instala paquetes sin preguntar.
- **En este proyecto:** Fase 1 · host · directorio: no consta. Instalar Docker Engine y el plugin Compose.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:100`

### C-009 · Añadir el usuario al grupo docker

```bash
sudo usermod -aG docker $USER
newgrp docker
```

- **Qué hace (genérico):** `usermod -aG GRUPO USUARIO`: añade el usuario a un grupo; `newgrp` aplica el grupo en la sesión actual.
- **En este proyecto:** Fase 1 · host · directorio: no consta. Añadir el usuario al grupo docker.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:102`

### C-022 · Mostrar la URL de Portainer

```bash
echo "Portainer disponible en: https://$(hostname -I | awk '{print $1}'):9443"
```

- **Qué hace (genérico):** `awk`: procesa campos (`-F` separador, `$N` campo N).
- **En este proyecto:** Fase 1 · Traefik · directorio: no consta. Mostrar la URL de Portainer.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1a-traefik-portainer.md:318`

### C-047 · Subir vm.max_map_count para el indexer

```bash
sudo sysctl -w vm.max_map_count=262144
```

- **Qué hace (genérico):** `sysctl -w CLAVE=VALOR`: cambia un parámetro del kernel en caliente.
- **En este proyecto:** Fase 1 · Wazuh · directorio: no consta. Subir vm.max_map_count para el indexer.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1d-wazuh.md:53`, `docs/README-fase1d-wazuh.md:118`

### C-049 · Recargar sysctl

```bash
sudo sysctl --system
```

- **Qué hace (genérico):** `sysctl --system`: recarga todos los ficheros de `/etc/sysctl.d/`.
- **En este proyecto:** Fase 1 · Wazuh · directorio: no consta. Recargar sysctl.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase1d-wazuh.md:57`

### C-050 · Verificar vm.max_map_count (esperado 262144)

```bash
sysctl vm.max_map_count
```

- **Qué hace (genérico):** `sysctl CLAVE`: lee el valor actual.
- **En este proyecto:** Fase 1 · Wazuh · directorio: no consta. Verificar vm.max_map_count (esperado 262144).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase1d-wazuh.md:60`

### C-084 · Comprobar que el último byte es 7d y no 0a

```bash
xxd /tmp/alerta-prueba.json | tail -1
```

- **Qué hace (genérico):** `xxd`: volcado hexadecimal (aquí, la última línea, para ver el byte final). `tail [-N]`: últimas líneas.
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. Comprobar que el último byte es 7d y no 0a.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/PROCEDIMIENTO-prueba-manual-webhook.md:48`

### C-085 · Cargar el secreto HMAC en la shell con read -s, en su propia línea

```bash
read -s -p "Secret: " OOB_SECRET; echo; export OOB_SECRET
```

- **Qué hace (genérico):** `read -s -p "texto" VAR`: lee sin eco en pantalla; `export` la pasa a los procesos hijos. `export VAR`: exporta la variable al entorno.
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. Cargar el secreto HMAC en la shell con read -s, en su propia línea.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/PROCEDIMIENTO-prueba-manual-webhook.md:61`

### C-086 · Comprobar la longitud del secreto (debe dar 64)

```bash
echo "${#OOB_SECRET}"
```

- **Qué hace (genérico):** `${#VAR}`: longitud de la variable.
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. Comprobar la longitud del secreto (debe dar 64).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/PROCEDIMIENTO-prueba-manual-webhook.md:62`

### C-143 · Instalar Tailscale en el orquestador

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

- **Qué hace (genérico):** `curl URL`: cliente HTTP(S). `-s`: modo silencioso (sin barra de progreso ni errores, salvo que se añada `-S`). `-S`: muestra el error aunque se use `-s`. `-f`: falla sin cuerpo de salida ante errores HTTP. `-L`: sigue las redirecciones. Descarga y ejecuta el instalador oficial de Tailscale.
- **En este proyecto:** Fase 4 · host · directorio: no consta. Instalar Tailscale en el orquestador.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4b-tailnet.md:54`

### C-152 · Validación previa de reglas del SIEM antes de reiniciar (incorporada tras…

```bash
wazuh-analysisd -t
```

- **Qué hace (genérico):** `wazuh-analysisd -t`: comprueba la configuración y las reglas sin arrancar el demonio.
- **En este proyecto:** Fase 4 · Wazuh · directorio: no consta. Validación previa de reglas del SIEM antes de reiniciar (incorporada tras dejar el manager sin analysisd).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4-validacion.md:489`

### C-172 · Orden en la war room para pedir la ejecución de un script del agente (regla…

```bash
!ir run disable_account.ps1 tfmuser
```

- **Qué hace (genérico):** Orden de chat del proyecto en la war room de Rocket.Chat (no es un comando de shell).
- **En este proyecto:** Fase 4 · n8n · directorio: no consta. Orden en la war room para pedir la ejecución de un script del agente (regla de dos personas). Prueba real: REQ-b2a531dc, código 0. Variante: !ir run enable_account.ps1 tfmuser (HITO:152), REQ-cf55f263, código 0.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/HITO-dominio-tfm-local-2026-09-26.md:143`

### C-173 · Aprobación por una segunda persona (aprobador ≠ solicitante)

```bash
!ir approve REQ-b2a531dc
```

- **Qué hace (genérico):** Orden de chat del proyecto en la war room de Rocket.Chat (no es un comando de shell).
- **En este proyecto:** Fase 4 · n8n · directorio: no consta. Aprobación por una segunda persona (aprobador ≠ solicitante): acción ejecutada, código 0. Variante: !ir approve REQ-cf55f263 (HITO:155).
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/HITO-dominio-tfm-local-2026-09-26.md:146`

### C-174 · Comprobar que n8n firma con el mismo secreto que el agente

```bash
!ir run collect_logs.ps1 dc-signed-selftest
```

- **Qué hace (genérico):** Orden de chat del proyecto en la war room de Rocket.Chat (no es un comando de shell).
- **En este proyecto:** Fase 4 · n8n · directorio: no consta. Comprobar que n8n firma con el mismo secreto que el agente: REQ-9253813e se ejecuta con código 0 con la firma exigida.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/HITO-dominio-tfm-local-2026-09-26.md:479`

### C-216 · Verificación estática de main.py → «sintaxis OK»

```bash
python3 -m py_compile main.py
```

- **Qué hace (genérico):** `python3 -m py_compile`: compila el módulo para comprobar la sintaxis, sin ejecutarlo.
- **En este proyecto:** Fase 5 · orchestrator · directorio: no consta. Verificación estática de main.py → «sintaxis OK».
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/INFORME-P0-4-implementacion.md:136`

### C-217 · Verificación estática de collect-signed.sh → «script OK»

```bash
bash -n scripts/collect-signed.sh
```

- **Qué hace (genérico):** `bash -n SCRIPT`: comprueba la sintaxis sin ejecutar. Script del proyecto `scripts/collect-signed.sh <incidentid> <host> <profile> [source]`; `SIGN_TS`, `SIGN_NONCE` y `SIGN_CORRUPT` fuerzan los casos de prueba.
- **En este proyecto:** Fase 5 · orchestrator · directorio: no consta. Verificación estática de collect-signed.sh → «script OK».
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/INFORME-P0-4-implementacion.md:137`

### C-242 · Buscar integraciones con IRIS en los flujos

```bash
grep -rn --include='*.json' --include='*.py' -iE 'iris\.oob|iriswebapp|/api/case|iris_api' \
    fase2-orquestador/ fase3-agentic/ fase5-orchestrator-api/
```

- **Qué hace (genérico):** `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto).
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. Buscar integraciones con IRIS en los flujos: sin salida (el README declaraba capacidades inexistentes).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:334`

### C-249 · Verify-fase6.sh tras la prueba de reinicio

```bash
./scripts/verify-fase6.sh; echo "exit=$?"
```

- **Qué hace (genérico):** `$?`: código de salida del último comando (en una tubería, el del último comando de la tubería). Script del proyecto `scripts/verify-fase6.sh` (16 comprobaciones; 0 = OK, 1 = fallo).
- **En este proyecto:** Fase 6 · IRIS · directorio: `~/tfm-alerta-temprana-oob`. verify-fase6.sh tras la prueba de reinicio: 16 comprobaciones OK, exit=0.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:472`, `docs/INFORME-AUDITORIA-FASE6.md:983`, `docs/INFORME-AUDITORIA-FASE6.md:1004`

### C-258 · Error de inferencia

```bash
ls LICENSE* COPYING*
```

- **Qué hace (genérico):** `ls PATRÓN…`: lista ficheros; el código de salida es distinto de 0 si algún patrón no coincide con nada.
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. Error de inferencia: código ≠ 0 por el patrón inexistente, aunque LICENSE.txt sí existía.
- **Resultado:** **FALLÓ**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE6.md:863`

### C-270 · Verificador de la fase

```bash
./scripts/verify-fase6.sh
```

- **Qué hace (genérico):** Script del proyecto `scripts/verify-fase6.sh` (16 comprobaciones; 0 = OK, 1 = fallo).
- **En este proyecto:** Fase 6 · IRIS · directorio: `raíz del repositorio`. Verificador de la fase: 0 = todo OK, 1 = alguna comprobación falla. Acreditado con tres pruebas negativas; tras la prueba de reinicio refutó la primera corrección de P1-11 (RESULTADO: FALLO).
- **Resultado:** **VALIDADO**
- **Fuente:** `fase6-iris/README.md:202`, `fase6-iris/README.md:329`, `docs/INFORME-AUDITORIA-FASE6.md:406`

### C-276 · Comprobar la configuración embebida en el MSI de Velociraptor

```bash
grep -a -o
```

- **Qué hace (genérico):** `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto).
- **En este proyecto:** Fase 5 · Velociraptor · directorio: no consta. Comprobar la configuración embebida en el MSI de Velociraptor: correcta.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:336`

### C-277 · Confirmar que un override pendiente es duplicado

```bash
grep -F -x -c -v
```

- **Qué hace (genérico):** `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto).
- **En este proyecto:** Fase 6 · IRIS · directorio: no consta. Confirmar que un override pendiente es duplicado: 0 líneas ausentes.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:345`

### C-290 · Leer el ZIP de la colección por gRPC

```bash
read_file(accessor='fs') por gRPC
```

- **Qué hace (genérico):** Función VQL de Velociraptor que lee un fichero con el accessor indicado.
- **En este proyecto:** Fase 5 · Velociraptor · directorio: no consta. Leer el ZIP de la colección por gRPC: 0 bytes, sha256 e3b0c442… (fichero vacío). El orchestrator pasa a leer el filestore por un volumen de solo lectura (fase5-velociraptor/README.md, «Volumen compartido»).
- **Resultado:** **FALLÓ** (→ C-426)
- **Fuente:** `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:579`

### C-291 · Hash de referencia del ZIP en el filestore

```bash
sha256sum del ZIP en el filestore
```

- **Qué hace (genérico):** `sha256sum [-c FICHERO]`: calcula o comprueba (con `-c`) resúmenes SHA-256.
- **En este proyecto:** Fase 5 · Velociraptor · directorio: no consta. Hash de referencia del ZIP en el filestore; la prueba end to end da el mismo hash en filestore, manifest.json y objeto de MinIO.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:580`

### C-295 · Buscar tailscale en el orquestador

```bash
grep -rl tailscale fase2-orquestador/
```

- **Qué hace (genérico):** `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto).
- **En este proyecto:** Fase 6 · n8n · directorio: no consta. Buscar tailscale en el orquestador: sin resultados.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/revision-workflow1-caso-iris-warroom.md:157`

### C-298 · Propuesta no aplicada

```bash
jq -e '[.. | objects | select(has("credentials")) | .credentials[] | .id] | all(. == "REEMPLAZAR")' "$OUTPUT" >/dev/null \
  || { echo "ERROR: quedó un id de credencial real sin sanear" >&2; exit 1; }
```

- **Qué hace (genérico):** `jq FILTRO`: procesa JSON (`-e` devuelve error si el resultado es falso o nulo).
- **En este proyecto:** Fase 2 · n8n · directorio: no consta. Propuesta no aplicada: que export-workflow.sh falle si queda un id de credencial real.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/revision-workflow1-caso-iris-warroom.md:645`

### C-301 · Cómo se importaron las métricas de prueba

```bash
python3 import_fase7_metrics.py --csv fase7_metrica_datos_test_200.csv --url https://localhost:9200
```

- **Qué hace (genérico):** Script de importación de métricas, fuera del repositorio.
- **En este proyecto:** Fase 7 · OpenSearch · directorio: no consta. Cómo se importaron las métricas de prueba. No reproducible: el script es un artefacto huérfano fuera del repositorio.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase7-observabilidad/README.md:200`

### C-313 · Prueba negativa fallida en silencio

```bash
ssh '...'
```

- **Qué hace (genérico):** `ssh HOST 'CMD'`: ejecuta el comando en el equipo remoto; la cadena pasa por el shell remoto, con sus propias reglas de comillas y expansión.
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. Prueba negativa fallida en silencio: pkill a través de ssh '...' no expandió el patrón; se midió un sistema sano creyéndolo caído.
- **Resultado:** **FALLÓ**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE8.md:270`

### C-316 · El comando falló por sintaxis del shell, no por falta del binario, y el «o…

```bash
cmd || echo "sin sqlite3"
```

- **Qué hace (genérico):** Sin explicación genérica aplicable: sintaxis propia del producto o del proyecto; ver la fuente.
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. El comando falló por sintaxis del shell, no por falta del binario, y el «o echo» imprimió un diagnóstico falso con forma de resultado.
- **Resultado:** **FALLÓ** (→ C-317)
- **Fuente:** `docs/api-reconocimiento-fase8.md:42`

### C-317 · Comprobar por separado si existe sqlite3 (un «cmd o echo» imprimió un…

```bash
command -v sqlite3
```

- **Qué hace (genérico):** `command -v PROGRAMA`: indica si existe en el PATH.
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. Comprobar por separado si existe sqlite3 (un «cmd o echo» imprimió un diagnóstico falso con forma de resultado).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/api-reconocimiento-fase8.md:42`

### C-334 · Busybox ps w sin argumentos devolvió 5 procesos de 162 (solo los del terminal)

```bash
ps w
```

- **Qué hace (genérico):** `ps`: lista procesos (`-eo` elige las columnas de salida).
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. En el GL-RM1: busybox ps w sin argumentos devolvió 5 procesos de 162 (solo los del terminal).
- **Resultado:** **FALLÓ** (→ C-335)
- **Fuente:** `docs/mejora6-endurecimiento-dispositivo.md:354`, `docs/CATALOGO-fallos-silenciosos.md:67`

### C-336 · Filtro sobre top que no filtró nada (la columna de estado no es la novena) y…

```bash
awk '$9!="S"'
```

- **Qué hace (genérico):** `awk`: procesa campos (`-F` separador, `$N` campo N).
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. Filtro sobre top que no filtró nada (la columna de estado no es la novena) y devolvió la lista entera.
- **Resultado:** **FALLÓ**
- **Fuente:** `docs/mejora6-endurecimiento-dispositivo.md:359`

### C-339 · Qué hace el cliente rtty en el dispositivo

```bash
ssh root@192.168.0.36 'logread | grep -i rtty | tail -5'
```

- **Qué hace (genérico):** `ssh usuario@host 'CMD'`: ejecuta el comando en el equipo remoto. `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto). `tail [-N]`: últimas líneas. `logread` (OpenWrt/busybox): lee el log del sistema en memoria.
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. Qué hace el cliente rtty en el dispositivo.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase8-kvm/README.md:279`

### C-340 · Prueba de arranque en frío del dispositivo tras cualquier cambio (esperado 1…

```bash
ssh root@192.168.0.36 reboot
sleep 90
docker exec glkvm_cloud sh -c 'netstat -tn | grep -c ":5912.*ESTABLISHED"'   #
```

- **Qué hace (genérico):** `docker exec CONTENEDOR CMD`: ejecuta un comando dentro de un contenedor en marcha. `netstat -tn`: conexiones TCP numéricas (`-p` añade el PID). `ssh usuario@host 'CMD'`: ejecuta el comando en el equipo remoto. `grep`: filtra líneas (`-E` expresión extendida, `-c` cuenta, `-q` silencioso, `-v` invierte, `-A N` N líneas tras cada coincidencia, `-F` literal, `-x` línea completa, `-r/-n` recursivo con número de línea, `-o` solo la coincidencia, `-a` trata binarios como texto). `sleep N`: espera N segundos. `reboot`: reinicia el equipo.
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. Prueba de arranque en frío del dispositivo tras cualquier cambio (esperado 1 conexión ESTABLISHED).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase8-kvm/README.md:300`

### C-341 · Prueba negativa de la sonda

```bash
ssh root@192.168.0.36
~/tfm-scripts/check-kvm-lastseen.sh; echo "exit=$?"
ssh root@192.168.0.36 '/etc/kvmd/user/scripts/S01selfCloud start'
```

- **Qué hace (genérico):** `ssh usuario@host 'CMD'`: ejecuta el comando en el equipo remoto. `$?`: código de salida del último comando (en una tubería, el del último comando de la tubería). Script del proyecto `fase8-kvm/scripts/check-kvm-lastseen.sh` (0 conectado, 1 sin conexión, 2 no consultable). `S01selfCloud start|restart`: script de arranque del cliente rtty en el GL-RM1 (firmware del fabricante, adaptado).
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. Prueba negativa de la sonda: matar rtty en el dispositivo, la sonda debe dar exit 1, y relanzar. Validada en los cuatro casos (auditoría Fase 8).
- **Resultado:** **VALIDADO**
- **Fuente:** `fase8-kvm/README.md:331`

### C-342 · Reiniciar el cliente tras cambiar las variables de cabecera

```bash
/etc/kvmd/user/scripts/S01selfCloud restart
```

- **Qué hace (genérico):** `S01selfCloud start|restart`: script de arranque del cliente rtty en el GL-RM1 (firmware del fabricante, adaptado).
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. En el GL-RM1: reiniciar el cliente tras cambiar las variables de cabecera.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase8-kvm/README.md:202`

### C-355 · Verificación estática de verify-hosts.sh → «sintaxis OK»

```bash
bash -n scripts/verify-hosts.sh
```

- **Qué hace (genérico):** `bash -n SCRIPT`: comprueba la sintaxis sin ejecutar. Script del proyecto `scripts/verify-hosts.sh` (sin argumentos: hosts local; `--emit`/`--check HOST`: hosts remotos; `--check-doc`: .tsv frente al README).
- **En este proyecto:** Fase transversal · host · directorio: no consta. Verificación estática de verify-hosts.sh → «sintaxis OK».
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/INFORME-P1-0.md:96`

### C-356 · Verify-hosts.sh --check-doc

```bash
./scripts/verify-hosts.sh --check-doc
```

- **Qué hace (genérico):** Script del proyecto `scripts/verify-hosts.sh` (sin argumentos: hosts local; `--emit`/`--check HOST`: hosts remotos; `--check-doc`: .tsv frente al README).
- **En este proyecto:** Fase transversal · host · directorio: no consta. verify-hosts.sh --check-doc: el .tsv y la tabla del README coinciden, exit=0.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/INFORME-P1-0.md:99`

### C-367 · Paso 2

```bash
bash scripts/verify-hosts.sh --check-doc
echo "codigo de salida: $?"
```

- **Qué hace (genérico):** `$?`: código de salida del último comando (en una tubería, el del último comando de la tubería). Script del proyecto `scripts/verify-hosts.sh` (sin argumentos: hosts local; `--emit`/`--check HOST`: hosts remotos; `--check-doc`: .tsv frente al README).
- **En este proyecto:** Fase transversal · host · directorio: `~/tfm-alerta-temprana-oob`. Paso 2: ejecutar el control y registrar el código (aprobado si 1). Resultado «Sin ejecutar: pendiente».
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/pruebas/negativa-check-doc.md:89`

### C-383 · Ejecutar la sonda y ver su código de salida (cron cada 5 min)

```bash
~/tfm-scripts/check-kvm-lastseen.sh; echo "exit=$?"
```

- **Qué hace (genérico):** `$?`: código de salida del último comando (en una tubería, el del último comando de la tubería). Script del proyecto `fase8-kvm/scripts/check-kvm-lastseen.sh` (0 conectado, 1 sin conexión, 2 no consultable).
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. Ejecutar la sonda y ver su código de salida (cron cada 5 min). Validada en los cuatro casos.
- **Resultado:** **VALIDADO**
- **Fuente:** `fase8-kvm/README.md:332`

### C-389 · Control de /health del agente

```bash
scripts/verify-dcagent-health.sh
```

- **Qué hace (genérico):** Script del proyecto `scripts/verify-dcagent-health.sh` (0 correcto, 1 control fallido, 2 uso incorrecto).
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. Control de /health del agente: falla si no declara hmac_required true. Fixtures: 1 antes y 0 después; primera ejecución real 2026-09-27, RESULTADO: OK, codigo=0.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/HITO-dominio-tfm-local-2026-09-26.md:490`, `docs/README-fase4c-dcagent.md:674`

### C-394 · Detector de secretos sobre los ficheros versionados

```bash
./scripts/verify-no-secrets.sh
```

- **Qué hace (genérico):** Script del proyecto `scripts/verify-no-secrets.sh` (0 sin hallazgos, 1 hallazgos, 2 uso incorrecto; solo `--staged`, `--selftest`, `--help` o nada).
- **En este proyecto:** Fase transversal · git · directorio: no consta. Detector de secretos sobre los ficheros versionados. Registrado: exit 1 con 56 (P0-3) y 24 hallazgos (auditoría de cierre); exit 0 tras los ajustes. No acepta rutas: solo --staged, --selftest, --help o nada (rc=2 por error de uso).
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/INFORME-CIERRE-P0-1-P0-2.md:56`, `docs/INFORME-P0-3.md:64`, `docs/INFORME-hallazgos-detector.md:208`, `docs/INFORME-hallazgos-detector.md:394`, `docs/AUDITORIA-CIERRE-2026-09-23.md:225`

### C-396 · Control de divergencia de /etc/hosts en el Ubuntu (exit 1 si no coincide con…

```bash
scripts/verify-hosts.sh
```

- **Qué hace (genérico):** Script del proyecto `scripts/verify-hosts.sh` (sin argumentos: hosts local; `--emit`/`--check HOST`: hosts remotos; `--check-doc`: .tsv frente al README).
- **En este proyecto:** Fase transversal · host · directorio: no consta. Control de divergencia de /etc/hosts en el Ubuntu (exit 1 si no coincide con el .tsv); pendiente de exit 0 por un chat.oob.local duplicado.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-resolucion-nombres.md:286`, `docs/INFORME-P1-0.md:152`

### C-397 · Generar el comando PowerShell de recogida del hosts de w11 o dc01

```bash
scripts/verify-hosts.sh --emit w11
```

- **Qué hace (genérico):** Script del proyecto `scripts/verify-hosts.sh` (sin argumentos: hosts local; `--emit`/`--check HOST`: hosts remotos; `--check-doc`: .tsv frente al README).
- **En este proyecto:** Fase transversal · host · directorio: no consta. Generar el comando PowerShell de recogida del hosts de w11 o dc01.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-resolucion-nombres.md:287`, `docs/INFORME-P1-0.md:153`

### C-398 · Verificar el hosts recogido en w11 o dc01

```bash
scripts/verify-hosts.sh --check w11 <fichero>
```

- **Qué hace (genérico):** Script del proyecto `scripts/verify-hosts.sh` (sin argumentos: hosts local; `--emit`/`--check HOST`: hosts remotos; `--check-doc`: .tsv frente al README).
- **En este proyecto:** Fase transversal · host · directorio: no consta. Verificar el hosts recogido en w11 o dc01.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/INFORME-P1-0.md:155`

### C-418 · Sha256.txt compatible con sha256sum -c

```bash
sha256sum -c
```

- **Qué hace (genérico):** `sha256sum [-c FICHERO]`: calcula o comprueba (con `-c`) resúmenes SHA-256.
- **En este proyecto:** Fase 5 · MinIO · directorio: no consta. sha256.txt compatible con sha256sum -c: un tercero verifica el ZIP fuera del workflow.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:605`

### C-419 · Verificación propuesta en la auditoría

```bash
crontab -l
```

- **Qué hace (genérico):** `crontab -l`: lista las tareas programadas del usuario.
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. Verificación propuesta en la auditoría: que la sonda está programada.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/AUDITORIA-CIERRE-2026-09-23.md:466`

### C-421 · Verificación propuesta en la auditoría

```bash
tail integrations.log
```

- **Qué hace (genérico):** `tail [-N]`: últimas líneas.
- **En este proyecto:** Fase 2 · Wazuh · directorio: no consta. Verificación propuesta en la auditoría: log de integraciones de Wazuh.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/AUDITORIA-CIERRE-2026-09-23.md:463`

### C-423 · Log del cliente rtty

```bash
tail /tmp/rtty.log
```

- **Qué hace (genérico):** `tail [-N]`: últimas líneas.
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. En el GL-RM1: log del cliente rtty.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/mejora2-tls-canal-rtty.md:92`

### C-424 · Prueba de la sonda

```bash
kill -9
```

- **Qué hace (genérico):** `kill -9 PID`: termina el proceso con SIGKILL.
- **En este proyecto:** Fase 8 · rttys/KVM · directorio: no consta. Prueba de la sonda: al matar rtty, el contador de conexiones baja a 0 de inmediato.
- **Resultado:** **CONTROL-NEGATIVO**
- **Fuente:** `docs/INFORME-AUDITORIA-FASE8.md:278`

### C-426 · Hash del ZIP leído del volumen compartido

```bash
sha256sum
```

- **Qué hace (genérico):** `sha256sum [-c FICHERO]`: calcula o comprueba (con `-c`) resúmenes SHA-256.
- **En este proyecto:** Fase 5 · Velociraptor · directorio: no consta. Hash del ZIP leído del volumen compartido.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase5-velociraptor/README.md:419`

### C-430 · Leer el código de salida y el mensaje de cada comando

```bash
echo $?
```

- **Qué hace (genérico):** `$?`: código de salida del último comando (en una tubería, el del último comando de la tubería).
- **En este proyecto:** Fase transversal · host · directorio: no consta. Leer el código de salida y el mensaje de cada comando: sin ello, un restart fallido era indistinguible de «reiniciado y sin efecto».
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/HALLAZGO-headscale-politica-modo-file.md:251`

### C-444 · $? tras una tubería es el del último comando

```bash
cmd | tail; echo $?
```

- **Qué hace (genérico):** `$?`: código de salida del último comando (en una tubería, el del último comando de la tubería).
- **En este proyecto:** Fase transversal · host · directorio: no consta. L-3: $? tras una tubería es el del último comando: devolvió 0 aunque el comando había fallado y causó dos diagnósticos falsos.
- **Resultado:** **FALLÓ** (→ C-445)
- **Fuente:** `docs/LECCIONES-OPERATIVAS-conversaciones.md:42`

### C-445 · Obtener el código real del comando

```bash
cmd >/dev/null 2>&1; echo $?
```

- **Qué hace (genérico):** `$?`: código de salida del último comando (en una tubería, el del último comando de la tubería). `>/dev/null 2>&1`: descarta salida estándar y de error, sin tubería, de modo que `$?` es el del comando.
- **En este proyecto:** Fase transversal · host · directorio: no consta. L-3: obtener el código real del comando. Alternativas en la misma línea de la fuente: set -o pipefail y ${PIPESTATUS[0]}.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/LECCIONES-OPERATIVAS-conversaciones.md:46`

### C-452 · Sustitución

```bash
process.hrtime.bigint()
```

- **Qué hace (genérico):** `process.hrtime.bigint()` (Node.js): tiempo monótono de alta resolución en nanosegundos.
- **En este proyecto:** Fase 8 · n8n · directorio: no consta. L-7: sustitución: medir con un script de Node.js dentro de n8n (/tmp/mide2.js, no transcrito); en glkvm_cloud, sin node, se midió por lotes.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/LECCIONES-OPERATIVAS-conversaciones.md:101`

---

## Parte II — Por fase

Secuencia de despliegue, verificación y diagnóstico de cada fase, en el orden de las fuentes. Solo referencias; el comando está en la Parte I o en la Parte IV.

### Fase 1 — Infraestructura (Traefik, Portainer, Authelia, MongoDB, Rocket.Chat, Wazuh)

1. C-001 — Eliminar el snap de Docker que convivía con Docker Engine .deb · `PROCEDIMIENTO`
2. C-002 — Retirar los perfiles AppArmor residuales del snap de Docker · `PROCEDIMIENTO`
3. C-003 — Reiniciar el demonio Docker tras limpiar el snap o editar… · `PROCEDIMIENTO`
4. C-004 — Comprobar que Docker es el .deb oficial y no el snap · `DIAGNÓSTICO`
5. C-005 — Instalar prerrequisitos para el repositorio oficial de Docker · `PROCEDIMIENTO`
6. C-006 — Descargar la clave GPG del repositorio de Docker · `PROCEDIMIENTO`
7. C-007 — Declarar el repositorio apt de Docker · `PROCEDIMIENTO`
8. C-008 — Instalar Docker Engine y el plugin Compose · `PROCEDIMIENTO`
9. C-009 — Añadir el usuario al grupo docker · `PROCEDIMIENTO`
10. C-010 — Clonar el repositorio (URL con marcador TU_USUARIO en la fuente) · `PROCEDIMIENTO`
11. C-011 — Crear la estructura de carpetas de la Fase 1 · `PROCEDIMIENTO`
12. C-012 — Crear .env de la Fase 1 a partir de .env.example · `PROCEDIMIENTO`
13. C-013 — Editar /etc/docker/daemon.json (min-api-version 1.24) · `PROCEDIMIENTO`
14. C-014 — Crear la red externa oob-network · `PROCEDIMIENTO`
15. C-015 — Crear la unidad systemd docker-oob-network que recrea la red al arrancar… · `PROCEDIMIENTO`
16. C-016 — Recargar systemd y habilitar/arrancar docker-oob-network · `PROCEDIMIENTO`
17. C-017 — Crear acme.json con permisos 600 · `PROCEDIMIENTO`
18. C-018 — Levantar Traefik y Portainer · `PROCEDIMIENTO`
19. C-019 — Estado de los contenedores del proyecto Compose (la fuente da el resultado… · `DIAGNÓSTICO`
20. C-020 — Puertos 80/443/9443 en escucha · `DIAGNÓSTICO`
21. C-021 — Revisar el log de Traefik · `DIAGNÓSTICO`
22. C-022 — Mostrar la URL de Portainer · `DIAGNÓSTICO`
23. C-024 — Generar los secretos hexadecimales de Authelia (Base64 rompía la… · `PROCEDIMIENTO`
24. C-025 — Crear el directorio de Authelia · `PROCEDIMIENTO`
25. C-026 — Generar el hash argon2 de la contraseña de usuario (marcador… · `PROCEDIMIENTO`
26. C-027 — Arrancar Authelia · `PROCEDIMIENTO`
27. C-028 — Seguir el log de arranque (esperado «Startup complete») · `DIAGNÓSTICO`
28. C-029 — Leer el enlace de registro TOTP de notification.txt · `DIAGNÓSTICO`
29. C-030 — Estado del contenedor de Authelia · `DIAGNÓSTICO`
30. C-031 — Últimas 20 líneas del log de Authelia · `DIAGNÓSTICO`
31. C-032 — Código HTTP del portal (esperado 200 o 302) · `DIAGNÓSTICO`
32. C-033 — Puerto 9091 en escucha · `DIAGNÓSTICO`
33. C-034 — Desactivar la verificación de email de Rocket.Chat 8.x en MongoDB… · `PROCEDIMIENTO`
34. C-035 — Generar el keyFile del replica set · `PROCEDIMIENTO`
35. C-036 — Crear docker-entrypoint-keyfile.sh (copia el keyFile con permisos 400) · `PROCEDIMIENTO`
36. C-037 — Primer arranque de MongoDB sin keyFile · `PROCEDIMIENTO`
37. C-038 — Inicializar el replica set rs0 · `PROCEDIMIENTO`
38. C-039 — Comprobar que el miembro es PRIMARY (esperado) · `DIAGNÓSTICO`
39. C-040 — Crear el usuario rcuser con roles root y clusterAdmin (contraseña como… · `PROCEDIMIENTO`
40. C-041 — Recrear MongoDB con el keyFile activado · `PROCEDIMIENTO`
41. C-042 — Vigilar hasta «healthy» · `DIAGNÓSTICO`
42. C-043 — Arrancar Rocket.Chat y seguir su log (esperado «SERVER RUNNING») · `PROCEDIMIENTO`
43. C-044 — Estado de mongodb y rocketchat · `DIAGNÓSTICO`
44. C-045 — Rocket.Chat responde (esperado 200) · `DIAGNÓSTICO`
45. C-046 — Listar canales por la API REST (token e id como marcadores) · `DIAGNÓSTICO`
46. C-047 — Subir vm.max_map_count para el indexer · `PROCEDIMIENTO`
47. C-048 — Persistir vm.max_map_count · `PROCEDIMIENTO`
48. C-049 — Recargar sysctl · `PROCEDIMIENTO`
49. C-050 — Verificar vm.max_map_count (esperado 262144) · `DIAGNÓSTICO`
50. C-051 — Instalar sudo en el indexer y cambiar la contraseña con… · `PROCEDIMIENTO`
51. C-052 — Clonar wazuh-docker v4.11.0 · `PROCEDIMIENTO`
52. C-053 — Generar los certificados TLS del indexer · `PROCEDIMIENTO`
53. C-054 — Comprobar que existen los .pem y .key · `DIAGNÓSTICO`
54. C-055 — Crear serversTransport con insecureSkipVerify · `PROCEDIMIENTO`
55. C-056 — Añadir wazuh.oob.local a /etc/hosts · `PROCEDIMIENTO`
56. C-057 — Arrancar indexer, manager y dashboard en orden estricto · `PROCEDIMIENTO`
57. C-058 — Consultar la API del manager (credencial vía variable API_PASSWORD, nunca en… · `DIAGNÓSTICO`
58. C-059 — Dashboard accesible (esperado 200) · `DIAGNÓSTICO`
59. C-060 — Medir desde n8n si la API de Traefik es alcanzable sin autenticar · `DIAGNÓSTICO`
60. C-061 — V1 · `VALIDADO`
61. C-062 — V2 · `VALIDADO`
62. C-063 — V3/V4 · `CONTROL-NEGATIVO`
63. C-065 — Comprobar la vigencia de la credencial versionada · `DIAGNÓSTICO`
64. C-066 — Segunda rotación a 48 hex · `VALIDADO`
65. C-067 — Dashboard vía Traefik (esperado 200) · `DIAGNÓSTICO`
66. C-068 — Validación integral de la Fase 1 · `VALIDADO`
67. C-069 — Contenedores conectados a oob-network · `DIAGNÓSTICO`
68. C-070 — Puertos activos del host de la Fase 1 · `DIAGNÓSTICO`
69. C-071 — Test de URLs de la Fase 1 · `VALIDADO`
70. C-072 — MongoDB PRIMARY · `VALIDADO`
71. C-073 — Login del bot orchestrator-bot por la API · `VALIDADO`
72. C-074 — Contenido mínimo del .env de la Fase 1 (valores como marcadores) · `PROCEDIMIENTO`
73. C-075 — Generar el keyfile del replica set con permisos 400 (versión del README de… · `PROCEDIMIENTO`
74. C-076 — Estado de los servicios · `DIAGNÓSTICO`
75. C-077 — Segmentación · `DIAGNÓSTICO`
76. C-078 — Rs.status().ok con credenciales por variable (esperado 1) · `DIAGNÓSTICO`
77. C-079 — Alcance de Authelia desde Traefik · `DIAGNÓSTICO`
78. C-097 — Generar la CA del enclave y recrear Traefik · `PROCEDIMIENTO`
79. C-175 — La API 8080 de Traefik no es alcanzable por LAN ni tailnet → False, con ping… · `CONTROL-NEGATIVO`
80. C-176 — Control positivo, 443 alcanzable → True · `VALIDADO`
81. C-278 — El dashboard por IP ya no es alcanzable (TcpTestSucceeded False, ping True) y… · `DIAGNÓSTICO`
82. C-370 — Generar la CA del enclave y el certificado *.oob.local (aborta si ya existe… · `PROCEDIMIENTO`
83. C-371 — Dentro de generate-oob-ca.sh · `PROCEDIMIENTO`
84. C-372 — Petición del certificado de servidor con la lista de SAN de san.cnf · `PROCEDIMIENTO`
85. C-373 — Firmar el certificado de servidor con la CA del enclave (825 días) · `PROCEDIMIENTO`
86. C-374 — Verificación final del script · `DIAGNÓSTICO`
87. C-375 — Entrypoint versionado · `PROCEDIMIENTO`
88. C-376 — Init-mongo.sh · `PROCEDIMIENTO`
89. C-377 — Con LXD el UID 999 está mapeado a lxd:systemd-journal · `FALLÓ` → C-375
90. C-401 — Comando de MongoDB · `PROCEDIMIENTO`
91. C-402 — Healthcheck de MongoDB con la contraseña por variable (el literal versionado… · `VALIDADO`
92. C-416 — Acceso remoto a Portainer por túnel SSH tras restringir 9443 a loopback · `PROCEDIMIENTO`
93. C-436 — Formato hexadecimal obligatorio para los secretos · `PROCEDIMIENTO`
94. C-449 — Devolvió 404 · `FALLÓ` → C-450
95. C-450 — Misma prueba con --resolve, que envía el SNI correcto · `VALIDADO`

### Fase 2 — Orquestador n8n e integración Wazuh

1. C-083 — Preparar el cuerpo de la alerta de prueba sin salto de línea final · `PROCEDIMIENTO`
2. C-084 — Comprobar que el último byte es 7d y no 0a · `DIAGNÓSTICO`
3. C-085 — Cargar el secreto HMAC en la shell con read -s, en su propia línea · `PROCEDIMIENTO`
4. C-086 — Comprobar la longitud del secreto (debe dar 64) · `DIAGNÓSTICO`
5. C-087 — Calcular la firma HMAC-SHA256 del fichero con openssl dgst -r · `PROCEDIMIENTO`
6. C-088 — Enviar la alerta firmada al webhook de test con --data-binary y cabecera… · `PROCEDIMIENTO`
7. C-089 — Diagnóstico de firma rechazada · `DIAGNÓSTICO`
8. C-090 — Validación de n8n tras Traefik · `VALIDADO`
9. C-091 — Permisos del script custom-n8n · `VALIDADO`
10. C-092 — Modo recomendado por Wazuh · `FALLÓ` → C-091
11. C-093 — Test del flujo con payload a mano desde el host, sin firma · `FALLÓ` → C-088
12. C-094 — Verificar desde n8n que mistral:7b está cargado · `VALIDADO`
13. C-095 — Prueba manual del webhook en modo test · `FALLÓ` → C-088
14. C-099 — Crear .env de n8n desde .env.example y levantar · `FALLÓ`
15. C-100 — Copiar la CA del enclave al manager de Wazuh · `PROCEDIMIENTO`
16. C-101 — Reiniciar el manager tras configurar la integración · `PROCEDIMIENTO`
17. C-102 — Importar el workflow y reiniciar n8n (hay que reasignar credenciales a mano) · `PROCEDIMIENTO`
18. C-104 — TLS del enclave verificado contra la CA (--cacert, sin -k) · `DIAGNÓSTICO`
19. C-105 — Integratord activo · `DIAGNÓSTICO`
20. C-107 — Ciclo completo · `VALIDADO`
21. C-108 — Generar N8N_ENCRYPTION_KEY (va en fase2-orquestador/n8n/.env, no en el… · `PROCEDIMIENTO`
22. C-109 — Levantar n8n · `PROCEDIMIENTO`
23. C-110 — Verificar el volumen n8n_data si los workflows no persisten · `DIAGNÓSTICO`
24. C-287 — M-1 · `DIAGNÓSTICO`
25. C-288 — Comprobar que la indirección por $env y el literal son funcionalmente… · `DIAGNÓSTICO`
26. C-298 — Propuesta no aplicada · `PROCEDIMIENTO`
27. C-299 — Comprobar si hay cambios en la UI sin exportar (propuesto, «sin ejecutarlo») · `PROCEDIMIENTO`
28. C-348 — D-5 (verificación propuesta) · `DIAGNÓSTICO`
29. C-378 — Exportar un workflow saneado para versionarlo (sin id, credenciales a… · `PROCEDIMIENTO`
30. C-379 — Dentro de export-workflow.sh · `PROCEDIMIENTO`
31. C-421 — Verificación propuesta en la auditoría · `DIAGNÓSTICO`
32. C-428 — Las copias con docker cp no sobreviven a docker compose up --force-recreate · `FALLÓ`
33. C-441 — sed -i sobre custom-n8n, montado como bind mount de fichero en el manager · `FALLÓ` → C-438;C-443
34. C-442 — Reparación propuesta · `PROCEDIMIENTO`
35. C-446 — Consultar execution_entity sobre una copia de database.sqlite junto con su… · `VALIDADO`
36. C-447 — El 2026-08-30 la respuesta del historial de la integración saliente de… · `FALLÓ` → C-446

### Fase 3 — Motor agéntico (LangGraph)

1. C-098 — Configurar .env y construir/levantar el motor de triage · `PROCEDIMIENTO`
2. C-106 — Salud del motor de triage desde n8n · `DIAGNÓSTICO`
3. C-111 — Copiar el banco de pruebas al contenedor langgraph-agent · `PROCEDIMIENTO`
4. C-112 — Suite de rendimiento en tres modos · `VALIDADO`
5. C-113 — Batería de inyección indirecta · `VALIDADO`
6. C-114 — Recuperar los resultados del contenedor · `PROCEDIMIENTO`
7. C-115 — Consumo de CPU de ollama y langgraph-agent durante la inferencia · `DIAGNÓSTICO`
8. C-116 — Salud y modo efectivo del agente · `DIAGNÓSTICO`
9. C-117 — Triage de una alerta desde la red de n8n · `PROCEDIMIENTO`
10. C-119 — Plan (no ejecutado, según la cabecera del documento) · `PROCEDIMIENTO`
11. C-120 — Plan (no ejecutado) · `PROCEDIMIENTO`
12. C-121 — Plan (no ejecutado) · `PROCEDIMIENTO`
13. C-122 — Plan (no ejecutado) · `PROCEDIMIENTO`
14. C-123 — Plan (no ejecutado) · `PROCEDIMIENTO`
15. C-124 — Plan (no ejecutado) · `PROCEDIMIENTO`
16. C-125 — Plan (no ejecutado) · `PROCEDIMIENTO`
17. C-349 — D-10 (propuesta) · `DIAGNÓSTICO`
18. C-350 — D-11 (propuesta) · `DIAGNÓSTICO`
19. C-403 — Healthcheck del agente LangGraph · `PROCEDIMIENTO`

### Fase 4 — Break-glass (Headscale, Tailscale, agente del DC, RustDesk)

1. C-126 — Valida la sintaxis del fichero · `FALLÓ` → C-129
2. C-127 — Imprime el fichero configurado, no la política aplicada · `FALLÓ` → C-129
3. C-128 — Actualizar la política · `FALLÓ` → C-132
4. C-129 — Única forma de ver la política vigente · `VALIDADO`
5. C-130 — Localizar el directorio del proyecto Compose por la etiqueta que guarda Docker · `DIAGNÓSTICO`
6. C-131 — Primer intento de reinicio · `FALLÓ` → C-132
7. C-132 — Reiniciar Headscale para recargar la ACL en modo file · `VALIDADO`
8. C-133 — Comprobar el túnel desde el W11 · `VALIDADO`
9. C-134 — Crear la carpeta de configuración de Headscale UI · `PROCEDIMIENTO`
10. C-135 — Generar la API key de Headscale para la UI (90 días) · `PROCEDIMIENTO`
11. C-136 — Levantar Headscale UI y comprobar que el contenedor corre · `PROCEDIMIENTO`
12. C-137 — Arrancar Headscale · `PROCEDIMIENTO`
13. C-138 — Invocar -f con ruta absoluta desde otro directorio · `FALLÓ` → C-137
14. C-139 — Log de arranque · `VALIDADO`
15. C-140 — Healthcheck de Headscale · `VALIDADO`
16. C-141 — Comprobar que la UI pasa por Authelia · `VALIDADO`
17. C-142 — Crear y listar el usuario tfm-oob en Headscale · `PROCEDIMIENTO`
18. C-143 — Instalar Tailscale en el orquestador · `PROCEDIMIENTO`
19. C-144 — Pre-auth key de un solo uso para el orquestador (1 h, tag:orchestrator) · `PROCEDIMIENTO`
20. C-145 — Unir el orquestador a la tailnet vía https://hs.oob.local con… · `PROCEDIMIENTO`
21. C-146 — Listar nodos (debe mostrar orchestrator-tfm y dc01-tfm) · `DIAGNÓSTICO`
22. C-147 — Conectividad de la tailnet desde el orquestador · `DIAGNÓSTICO`
23. C-148 — Etiquetar un nodo desde el plano de control · `PROCEDIMIENTO`
24. C-149 — Confirmar que RustDesk fluye por la tailnet tras la ACL · `VALIDADO`
25. C-150 — Resolver la identidad del par desde la base del servidor de rendezvous · `PROCEDIMIENTO`
26. C-151 — Estado del agente del DC por la tailnet · `VALIDADO`
27. C-152 — Validación previa de reglas del SIEM antes de reiniciar (incorporada tras… · `PROCEDIMIENTO`
28. C-154 — Mostraba hbbs y hbbr como running con la columna de puertos vacía · `FALLÓ` → C-156
29. C-155 — Devolvía los bindings correctos (100.64.0.1:21115-21118), sin efecto real · `FALLÓ` → C-156
30. C-156 — Discriminador · `DIAGNÓSTICO`
31. C-157 — Ningún docker-proxy en 21115-21119 · `DIAGNÓSTICO`
32. C-158 — Reparación manual · `VALIDADO`
33. C-159 — Log del demonio Docker en el arranque · `DIAGNÓSTICO`
34. C-160 — Regla de operación si el canal está caído · `PROCEDIMIENTO`
35. C-161 — Prueba en arranque en frío · `VALIDADO`
36. C-162 — Confirmar que hubo arranque nuevo tras el apagado no limpio · `VALIDADO`
37. C-163 — Confirmar MagicDNS con sufijo tailnet.internal tras cambiar base_domain… · `VALIDADO`
38. C-164 — Petición directa al agente equivalente al nodo Call DC Agent · `VALIDADO`
39. C-165 — Disparar el webhook de test dc-action · `VALIDADO`
40. C-166 — Control negativo · `CONTROL-NEGATIVO`
41. C-167 — Control negativo · `CONTROL-NEGATIVO`
42. C-168 — Crear la carpeta de datos de RustDesk Server · `PROCEDIMIENTO`
43. C-169 — Arrancar hbbs/hbbr y comprobar que están activos (hoy los levanta la unidad… · `PROCEDIMIENTO`
44. C-170 — Validación de activación del break-glass · `VALIDADO`
45. C-171 — Validación de desactivación · `VALIDADO`
46. C-172 — Orden en la war room para pedir la ejecución de un script del agente (regla… · `VALIDADO`
47. C-173 — Aprobación por una segunda persona (aprobador ≠ solicitante) · `VALIDADO`
48. C-174 — Comprobar que n8n firma con el mismo secreto que el agente · `VALIDADO`
49. C-177 — 443 y 4833 → False (la política nueva aún no se aplicaba) · `DIAGNÓSTICO`
50. C-178 — Puertos 22 y 8000 del orquestador → False · `CONTROL-NEGATIVO`
51. C-179 — False antes de reconectar los contenedores a la red, True después · `VALIDADO`
52. C-180 — IP de la tailnet → 100.64.0.2 · `VALIDADO`
53. C-181 — Localizar el DC de tfm.local → \\DC01-TFM.tfm.local · `VALIDADO`
54. C-182 — «401 Unauthorized · `FALLÓ`
55. C-183 — Estado de la cuenta tras enable_account.ps1 → True · `VALIDADO`
56. C-184 — Leer el final del log del agente (pendiente en la versión inicial del hito) · `DIAGNÓSTICO`
57. C-185 — SHA-256 del log conservado · `VALIDADO`
58. C-186 — Comprobar el atributo de solo lectura del log conservado → True · `VALIDADO`
59. C-187 — Fijar el log original como solo lectura · `VALIDADO`
60. C-188 — Instalar Tailscale · `PROCEDIMIENTO`
61. C-189 — Unir el DC a Headscale con tag:dc y --accept-dns=false · `PROCEDIMIENTO`
62. C-190 — Conectividad de la tailnet · `DIAGNÓSTICO`
63. C-191 — Instalar Python 3.11 para todos los usuarios · `PROCEDIMIENTO`
64. C-192 — Verificar Python y pip · `DIAGNÓSTICO`
65. C-193 — Crear C:\tfm-dc-agent y C:\tfm-scripts · `PROCEDIMIENTO`
66. C-194 — ACL de directorios (SYSTEM RX sobre código y scripts, M solo sobre logs) —… · `VALIDADO`
67. C-195 — El puerto 8000 del agente solo desde 100.64.0.0/10 · `PROCEDIMIENTO`
68. C-196 — Entorno virtual y dependencias del agente · `PROCEDIMIENTO`
69. C-197 — Registrar TFM-DC-Agent con NSSM, ligado a 100.64.0.2 y no a 0.0.0.0, con log… · `PROCEDIMIENTO`
70. C-198 — Entorno del servicio con AppEnvironmentExtra · `PROCEDIMIENTO`
71. C-199 — Dependencia de Tailscale, reinicio automático y arranque del servicio · `PROCEDIMIENTO`
72. C-200 — Estado del servicio y /health local (debe incluir hmac_required y… · `DIAGNÓSTICO`
73. C-201 — Instalar el cliente RustDesk · `PROCEDIMIENTO`
74. C-202 — Entorno virtual en C:\tfm-agent con pip install fastapi uvicorn · `PROCEDIMIENTO`
75. C-203 — NSSM con --host 0.0.0.0 · `PROCEDIMIENTO`
76. C-204 — Núcleo de collect_logs.ps1 · `VALIDADO`
77. C-205 — Disable_account.ps1 en el repositorio · `VALIDADO`
78. C-206 — Enable_account.ps1 en el repositorio · `VALIDADO`
79. C-207 — Isolate_host.ps1 · `PROCEDIMIENTO`
80. C-208 — Reset_password.ps1 · `PROCEDIMIENTO`
81. C-209 — Rustdesk_enable.ps1 · `VALIDADO`
82. C-210 — Contraseña de un solo uso con RandomNumberGenerator en vez de Get-Random · `VALIDADO`
83. C-211 — Versión inicial · `FALLÓ` → C-210
84. C-212 — Tarea RustDesk-AutoOff con -Principal SYSTEM explícito (sin él falla con… · `VALIDADO`
85. C-213 — Rustdesk_disable.ps1 · `VALIDADO`
86. C-337 — Altas futuras con preauthkey creada en el momento · `PROCEDIMIENTO`
87. C-347 — Nearest DERP · `FALLÓ` → C-147
88. C-351 — D-27 (propuesta) · `DIAGNÓSTICO`
89. C-358 — Listar nodos · `DIAGNÓSTICO`
90. C-359 — ControlURL del cliente → https://hs.oob.local · `VALIDADO`
91. C-362 — Diez claves · `DIAGNÓSTICO`
92. C-363 — Expirar la clave reutilizable · `VALIDADO`
93. C-380 — Volcar el inventario de peers a JSON desde el host, en solo lectura · `PROCEDIMIENTO`
94. C-388 — Dentro de dc-signed.sh · `PROCEDIMIENTO`
95. C-389 — Control de /health del agente · `VALIDADO`
96. C-390 — Dentro de verify-dcagent-health.sh · `DIAGNÓSTICO`
97. C-404 — Hbbs con relay rustdesk-hbbr:21117 y -k _ (exige clave) · `PROCEDIMIENTO`
98. C-405 — Hbbr con -k _ · `PROCEDIMIENTO`
99. C-406 — Comando de Headscale · `PROCEDIMIENTO`
100. C-411 — Esperar hasta 300 s a que exista TAILNET_IP antes de levantar hbbs/hbbr · `VALIDADO`
101. C-412 — Down + up --wait sin --remove-orphans (borraría headscale-ui, que comparte… · `VALIDADO`
102. C-413 — ExecStop down · `VALIDADO`
103. C-422 — Implementación de referencia, no abordada · `PROCEDIMIENTO`
104. C-429 — En analyst-w11, control negativo a 100.64.0.2:3389 · `CONTROL-NEGATIVO`
105. C-431 — Lectura del netmap cortada en la primera regla · `FALLÓ` → C-129
106. C-432 — Validar la sintaxis de la ACL antes de reiniciar (paso no opcional) · `VALIDADO`
107. C-433 — Deprecado y ausente en PowerShell 7 · `FALLÓ` → C-204

### Fase 5 — Orchestrator, Velociraptor y MinIO

1. C-214 — Lanzar una colección sin firma HMAC · `FALLÓ` → C-384
2. C-215 — Caso 1 de las pruebas previstas para el usuario · `PROCEDIMIENTO`
3. C-216 — Verificación estática de main.py → «sintaxis OK» · `VALIDADO`
4. C-217 — Verificación estática de collect-signed.sh → «script OK» · `VALIDADO`
5. C-218 — Verificar las evidencias del incidente en MinIO · `DIAGNÓSTICO`
6. C-219 — Regenerar server.config.yaml (no se versiona) · `PROCEDIMIENTO`
7. C-220 — Regenerar client.config.yaml desde la configuración de servidor · `PROCEDIMIENTO`
8. C-221 — Reempaquetar el MSI de cliente con config repack --msi (la fuente pide… · `PROCEDIMIENTO`
9. C-222 — Generar el cliente API orchestrator con rol investigator · `PROCEDIMIENTO`
10. C-223 — Control negativo→positivo del gRPC desde el orchestrator · `PROCEDIMIENTO`
11. C-229 — Comprobado experimentalmente · `DIAGNÓSTICO`
12. C-230 — Medir que la consola 9001 de MinIO ya no está publicada · `VALIDADO`
13. C-276 — Comprobar la configuración embebida en el MSI de Velociraptor · `VALIDADO`
14. C-290 — Leer el ZIP de la colección por gRPC · `FALLÓ` → C-426
15. C-291 — Hash de referencia del ZIP en el filestore · `VALIDADO`
16. C-297 — Verificar el bucket evidence · `PROCEDIMIENTO`
17. C-352 — D-28 (propuesta) · `DIAGNÓSTICO`
18. C-381 — Init-minio-bucket.sh · `PROCEDIMIENTO`
19. C-384 — Petición firmada al orchestrator · `VALIDADO`
20. C-385 — Pruebas negativas de la firma · `CONTROL-NEGATIVO`
21. C-386 — Casos de validación del modelo y de la lista de perfiles (422/400) previstos… · `PROCEDIMIENTO`
22. C-387 — Dentro de collect-signed.sh · `PROCEDIMIENTO`
23. C-407 — MinIO con consola en :9001 interna · `PROCEDIMIENTO`
24. C-408 — Healthcheck de MinIO · `PROCEDIMIENTO`
25. C-418 — Sha256.txt compatible con sha256sum -c · `PROCEDIMIENTO`
26. C-426 — Hash del ZIP leído del volumen compartido · `DIAGNÓSTICO`

### Fase 6 — DFIR-IRIS

1. C-233 — Discriminar el camino n8n→IRIS por el 4833 · `PROCEDIMIENTO`
2. C-234 — IRIS solo escucha en la IP de la tailnet → «LISTEN 0 4096 100.64.0.1:4833» · `VALIDADO`
3. C-235 — Desde la raíz, -f descarta docker-compose.override.yml · `FALLÓ` → C-260
4. C-236 — Verificación previa a cualquier recreación · `PROCEDIMIENTO`
5. C-237 — P0-C · `DIAGNÓSTICO`
6. C-238 — P0-C · `DIAGNÓSTICO`
7. C-239 — Restaurar el ancla con la CA del enclave y recrear app, worker y nginx · `VALIDADO`
8. C-240 — Comprobar sujeto y huella del ancla · `VALIDADO`
9. C-241 — El ancla valida el certificado del enclave → OK (se usa con éxito, no solo… · `VALIDADO`
10. C-242 — Buscar integraciones con IRIS en los flujos · `DIAGNÓSTICO`
11. C-243 — Tras el reinicio del anfitrión · `DIAGNÓSTICO`
12. C-244 — Log de nginx · `DIAGNÓSTICO`
13. C-245 — Diagnóstico decisivo · `DIAGNÓSTICO`
14. C-246 — Primera corrección (healthcheck + depends_on) validada con up · `FALLÓ` → C-415
15. C-247 — up -d sobre un contenedor exited lo arranca sin recrear («Started») y… · `FALLÓ` → C-260
16. C-248 — Prueba de reinicio · `VALIDADO`
17. C-249 — Verify-fase6.sh tras la prueba de reinicio · `VALIDADO`
18. C-250 — P1-6 · `VALIDADO`
19. C-251 — P1-7 · `DIAGNÓSTICO`
20. C-254 — Prueba negativa del verificador · `CONTROL-NEGATIVO`
21. C-258 — Error de inferencia · `FALLÓ`
22. C-259 — Recuperación si ninguna cuenta tiene MFA · `PROCEDIMIENTO`
23. C-260 — Nginx en bucle de reinicio con endpoint obsoleto · `PROCEDIMIENTO`
24. C-261 — La pila no levanta tras reiniciar · `PROCEDIMIENTO`
25. C-262 — P0-E · `VALIDADO`
26. C-263 — Prueba de arranque en frío, criterio de aceptación de la fase · `VALIDADO`
27. C-264 — En arranque manual, comprobar antes que tailscale0 tiene 100.64.0.1 · `DIAGNÓSTICO`
28. C-267 — Verificación TLS contra la CA del enclave · `VALIDADO`
29. C-268 — Arranque manual de la pila esperando a los healthchecks (normalmente lo hace… · `PROCEDIMIENTO`
30. C-269 — Tras cambiar .env o montajes · `PROCEDIMIENTO`
31. C-270 — Verificador de la fase · `VALIDADO`
32. C-271 — Instalar y habilitar la unidad tfm-fase6-iris.service · `PROCEDIMIENTO`
33. C-272 — Medir la redirección de MISP · `DIAGNÓSTICO`
34. C-277 — Confirmar que un override pendiente es duplicado · `VALIDADO`
35. C-279 — Iris.oob.local dentro de n8n → OK 100.64.0.1 · `VALIDADO`
36. C-280 — Alcance de n8n a la tailnet · `VALIDADO`
37. C-281 — Authelia ante un Bearer por el 443 · `DIAGNÓSTICO`
38. C-282 — Puerto real del nginx de IRIS en la tailnet · `VALIDADO`
39. C-283 — Llamada real a la API de IRIS por la tailnet con --cacert ca-bundle-oob.crt · `VALIDADO`
40. C-285 — Cadena de resolución dentro de n8n · `DIAGNÓSTICO`
41. C-286 — Nombres .oob.local de servicio dentro de n8n · `DIAGNÓSTICO`
42. C-294 — Propuesto, sin ejecutar en este documento ([PENDIENTE DE MEDICIÓN]) · `PROCEDIMIENTO`
43. C-295 — Buscar tailscale en el orquestador · `DIAGNÓSTICO`
44. C-296 — Prueba antes/después propuesta para un alias de red · `PROCEDIMIENTO`
45. C-353 — D-19 (propuesta) · `DIAGNÓSTICO`
46. C-399 — Dentro de verify-fase6.sh · `VALIDADO`
47. C-400 — Dentro de verify-fase6.sh · `CONTROL-NEGATIVO`
48. C-409 — Healthcheck de app (/login 200) · `FALLÓ` → C-415
49. C-414 — Esperar a 100.64.0.1 · `VALIDADO`
50. C-415 — down --remove-orphans + up --wait · `VALIDADO`
51. C-417 — Medición desde n8n · `VALIDADO`
52. C-438 — Patrón seguro de edición · `PROCEDIMIENTO`
53. C-439 — M-29 · `FALLÓ`

### Fase 7 — Observabilidad

1. C-301 — Cómo se importaron las métricas de prueba · `PROCEDIMIENTO`
2. C-302 — Prueba unitaria de emisión de métricas del triage · `PROCEDIMIENTO`
3. C-303 — Prueba unitaria de emisión de la colección · `FALLÓ`
4. C-304 — Contar eventos en tfm-metrics-events (credencial por variable OS_PASS) · `VALIDADO`
5. C-305 — Reimportar el dashboard en otro despliegue («procedimiento no ejecutado») · `PROCEDIMIENTO`
6. C-306 — Consulta propuesta · `PROCEDIMIENTO`
7. C-307 — Consulta propuesta · `PROCEDIMIENTO`

### Fase 8 — KVM (rttys, GL-RM1, hook de autorización)

1. C-308 — P1-2 · `DIAGNÓSTICO`
2. C-309 — Copia local de la imagen fijada por digest (namespace personal de Docker Hub) · `PROCEDIMIENTO`
3. C-310 — Respondió «sintaxis OK» mientras Compose fusionaba las listas de ports y el… · `FALLÓ`
4. C-311 — El certificado del GL-RM1 valida contra la CA del enclave sin -k · `VALIDADO`
5. C-312 — Criterio de la sonda · `VALIDADO`
6. C-313 — Prueba negativa fallida en silencio · `FALLÓ`
7. C-315 — Instrumento invalidado · `FALLÓ`
8. C-316 — El comando falló por sintaxis del shell, no por falta del binario, y el «o… · `FALLÓ` → C-317
9. C-317 — Comprobar por separado si existe sqlite3 (un «cmd o echo» imprimió un… · `DIAGNÓSTICO`
10. C-318 — Instrumento de referencia del hook · `PROCEDIMIENTO`
11. C-319 — Conectividad glkvm_cloud → n8n verificada → 200 · `VALIDADO`
12. C-320 — N8n → /auth-config de rttys con cabecera Host obligatoria → 200 (sin Host,… · `VALIDADO`
13. C-321 — V6 · `VALIDADO`
14. C-322 — El cliente rtty verifica el canal con -C oob-rootCA.crt (antes -sx sin… · `VALIDADO`
15. C-323 — El certificado del 5912 valida → Verify return code · `VALIDADO`
16. C-324 — Vuelta atrás del script S01selfCloud desde la copia en /root · `PROCEDIMIENTO`
17. C-325 — Prueba mensual M1 · `PROCEDIMIENTO`
18. C-326 — M2 · `VALIDADO`
19. C-327 — M3 · `VALIDADO`
20. C-328 — M3 · `VALIDADO`
21. C-329 — M4 · `PROCEDIMIENTO`
22. C-330 — Restablecer n8n para M5 · `PROCEDIMIENTO`
23. C-331 — M6 · `PROCEDIMIENTO`
24. C-332 — M6, en el dispositivo · `PROCEDIMIENTO`
25. C-333 — M7 · `PROCEDIMIENTO`
26. C-334 — Busybox ps w sin argumentos devolvió 5 procesos de 162 (solo los del terminal) · `FALLÓ` → C-335
27. C-335 — Identificar el watchdog por conexión y PID en lugar de por nombre · `VALIDADO`
28. C-336 — Filtro sobre top que no filtró nada (la columna de estado no es la novena) y… · `FALLÓ`
29. C-338 — ¿Hay conexión real del dispositivo? · `DIAGNÓSTICO`
30. C-339 — Qué hace el cliente rtty en el dispositivo · `DIAGNÓSTICO`
31. C-340 — Prueba de arranque en frío del dispositivo tras cualquier cambio (esperado 1… · `PROCEDIMIENTO`
32. C-341 — Prueba negativa de la sonda · `VALIDADO`
33. C-342 — Reiniciar el cliente tras cambiar las variables de cabecera · `PROCEDIMIENTO`
34. C-343 — Variables de cabecera de S01selfCloud (token y contraseña TURN como… · `PROCEDIMIENTO`
35. C-382 — Núcleo de la sonda de capacidad · `VALIDADO`
36. C-383 — Ejecutar la sonda y ver su código de salida (cron cada 5 min) · `VALIDADO`
37. C-410 — Entrypoint que genera rttys.conf desde la plantilla · `PROCEDIMIENTO`
38. C-419 — Verificación propuesta en la auditoría · `DIAGNÓSTICO`
39. C-423 — Log del cliente rtty · `DIAGNÓSTICO`
40. C-424 — Prueba de la sonda · `CONTROL-NEGATIVO`
41. C-425 — Limpiar los ficheros temporales de la medición · `PROCEDIMIENTO`
42. C-434 — P2-6 · `DIAGNÓSTICO`
43. C-448 — Identificar el modo de respuesta del webhook kvm-hook · `DIAGNÓSTICO`
44. C-451 — En glkvm_cloud y en n8n, date +%s%N devolvió 1789040529 (diez dígitos) · `FALLÓ` → C-452
45. C-452 — Sustitución · `PROCEDIMIENTO`

### Transversal — repositorio, resolución de nombres y controles comunes

1. C-023 — Comprobar las etiquetas existentes · `DIAGNÓSTICO`
2. C-064 — Buscar en el historial el plan citado · `DIAGNÓSTICO`
3. C-080 — Comprobar que users_database.yml ya no está versionado · `DIAGNÓSTICO`
4. C-081 — Retirar del índice un fichero ya versionado pese a .gitignore (se hizo en… · `PROCEDIMIENTO`
5. C-082 — Localizar dónde se aplica secure-headers@file · `DIAGNÓSTICO`
6. C-096 — Commit y push de cierre de subfase · `PROCEDIMIENTO`
7. C-103 — Comprobar que n8n/.env.example nunca se versionó · `DIAGNÓSTICO`
8. C-118 — Comprobar que una_alerta.json existe pero está ignorado · `DIAGNÓSTICO`
9. C-153 — Identificar la versión desplegada del agente por hash · `VALIDADO`
10. C-224 — Git check-ignore -v sobre ficheros ya versionados · `FALLÓ` → C-225
11. C-225 — Check-ignore que evalúa el patrón aunque el fichero esté versionado (salida… · `VALIDADO`
12. C-226 — Sacar del índice el material de Velociraptor · `PROCEDIMIENTO`
13. C-227 — Purga del historial con git filter-repo (scripts/purge-history.sh) · `PROCEDIMIENTO`
14. C-228 — Tras la purga, restaurar remotos y forzar el push a origin y backup · `PROCEDIMIENTO`
15. C-231 — Consolidar el renombrado env.example → .env.example en el índice (acción… · `PROCEDIMIENTO`
16. C-232 — Estado del árbol al cerrar la sesión · `DIAGNÓSTICO`
17. C-252 — Comprobar qué se versionaría tras cambiar .gitignore · `VALIDADO`
18. C-253 — Buscar la clave privada de la CA demo en la historia · `DIAGNÓSTICO`
19. C-255 — Error de inferencia · `FALLÓ` → C-252
20. C-256 — Devolvió «644edf8..99844be main -> main» pero empujó al remoto de backup, no… · `FALLÓ` → C-257
21. C-257 — Comprobar el estado resultante del remoto en lugar del código de retorno de… · `DIAGNÓSTICO`
22. C-265 — Comprobar si el material de certificados entró alguna vez en el historial · `DIAGNÓSTICO`
23. C-266 — Buscar la clave de la CA demo en todos los objetos · `DIAGNÓSTICO`
24. C-273 — Push al remoto de respaldo, segundo paso del protocolo (git push + git push… · `VALIDADO`
25. C-274 — Verificar el efecto de un cambio de .gitignore con check-ignore y status, no… · `PROCEDIMIENTO`
26. C-275 — Git check-ignore devolvió 1 (no ignorado) · `DIAGNÓSTICO`
27. C-284 — Censo de oob-network · `DIAGNÓSTICO`
28. C-289 — M-10 · `VALIDADO`
29. C-292 — Buscar el token del bot en HEAD · `FALLÓ` → C-293
30. C-293 — Comprobación correcta · `DIAGNÓSTICO`
31. C-300 — Historial completo de un fichero, incluidos borrados · `DIAGNÓSTICO`
32. C-314 — Confirmar que los secretos de la Fase 8 nunca estuvieron en el repositorio · `DIAGNÓSTICO`
33. C-344 — Comprobar el contenido de un fichero en un commit concreto · `DIAGNÓSTICO`
34. C-345 — A21 · `FALLÓ`
35. C-346 — A40 · `FALLÓ` → C-275
36. C-354 — Buscar en qué commits aparece un literal · `DIAGNÓSTICO`
37. C-355 — Verificación estática de verify-hosts.sh → «sintaxis OK» · `VALIDADO`
38. C-356 — Verify-hosts.sh --check-doc · `VALIDADO`
39. C-357 — Añadir entradas a /etc/hosts a mano · `PROCEDIMIENTO`
40. C-360 — Hs.oob.local duplicado con dos IP · `DIAGNÓSTICO`
41. C-361 — Leer y reescribir el propio hosts en la misma tubería lo bloquea · `FALLÓ`
42. C-364 — Prueba negativa de --check-doc, paso 0 y 4 · `PROCEDIMIENTO`
43. C-365 — Paso 1 · `PROCEDIMIENTO`
44. C-366 — Confirmar que el cambio está aislado · `PROCEDIMIENTO`
45. C-367 — Paso 2 · `PROCEDIMIENTO`
46. C-368 — Paso 3 · `PROCEDIMIENTO`
47. C-369 — Propuesta v3 (no ejecutada) · `PROCEDIMIENTO`
48. C-391 — Backup mirror previo a la purga (purge-history.sh aborta si no existe) · `PROCEDIMIENTO`
49. C-392 — Purga del historial · `PROCEDIMIENTO`
50. C-393 — Dentro de purge-history.sh · `PROCEDIMIENTO`
51. C-394 — Detector de secretos sobre los ficheros versionados · `VALIDADO`
52. C-395 — Dentro de verify-no-secrets.sh · `DIAGNÓSTICO`
53. C-396 — Control de divergencia de /etc/hosts en el Ubuntu (exit 1 si no coincide con… · `PROCEDIMIENTO`
54. C-397 — Generar el comando PowerShell de recogida del hosts de w11 o dc01 · `PROCEDIMIENTO`
55. C-398 — Verificar el hosts recogido en w11 o dc01 · `PROCEDIMIENTO`
56. C-420 — Verificación propuesta en la auditoría · `DIAGNÓSTICO`
57. C-427 — Renderiza y valida el compose (fusión de ficheros) · `DIAGNÓSTICO`
58. C-430 — Leer el código de salida y el mensaje de cada comando · `PROCEDIMIENTO`
59. C-435 — Listar los ficheros versionados de una fase para contrastar lo que declara la… · `DIAGNÓSTICO`
60. C-437 — Ficheros versionados de n8n/ · `DIAGNÓSTICO`
61. C-440 — La clave queda solo con comentarios y YAML la lee como nula · `FALLÓ` → C-427
62. C-443 — Patrón seguro para futuras ediciones · `PROCEDIMIENTO`
63. C-444 — $? tras una tubería es el del último comando · `FALLÓ` → C-445
64. C-445 — Obtener el código real del comando · `PROCEDIMIENTO`

---

## Parte III — Comandos que fallaron y su corrección

| Id fallido | Síntoma | Causa | Id correcto | Fuente |
|---|---|---|---|---|
| C-092 | wazuh-integratord no puede ejecutar custom-n8n | Con bind mount el script es de uid 1000; el demonio (uid 999) cae en «otros» y 750 no le da ejecución | C-091 | `docs/README-fase2bcd-workflow-n8n.md:102` |
| C-093 | El flujo «funciona» con un payload a mano | curl desde el host, sin firma y por un camino que el tráfico real no recorría; el camino real nunca funcionó en 2c–2f | C-088 | `docs/README-fase2bcd-workflow-n8n.md:223` |
| C-095 | Mensaje correcto en Rocket.Chat | Misma causa: prueba sintética que no ejercita el canal real ni la firma HMAC | C-088 | `docs/README-fase2e-ollama-ai-agent.md:185` |
| C-099 | El paso 3 no se puede ejecutar | fase2-orquestador/n8n/.env.example no existe ni se ha versionado; el .env se crea a mano | — (sin corrección con comando en la fuente) | `fase2-orquestador/README.md:434` |
| C-126 | «Policy is valid», rc=0 | Valida la sintaxis del fichero, no la política cargada; en modo file la ACL solo se lee al arrancar | C-129 | `docs/HALLAZGO-headscale-politica-modo-file.md:19` |
| C-127 | Muestra la regla nueva | Imprime el fichero configurado, no lo que tienen los nodos | C-129 | `docs/HALLAZGO-headscale-politica-modo-file.md:20` |
| C-128 | «update is disabled for modes other than database» | En modo file la política no se puede cargar en caliente | C-132 | `docs/HALLAZGO-headscale-politica-modo-file.md:21` |
| C-131 | «no configuration file provided: not found»; netmap sin cambios | El compose de Headscale vive en headscale/config/, no en fase4-breakglass-dc/ | C-132 | `docs/HALLAZGO-headscale-politica-modo-file.md:93` |
| C-138 | «No config file found, using defaults» | -f con ruta absoluta desde otro directorio; el contenedor montó otra carpeta | C-137 | `docs/README-fase4a-headscale.md:291` |
| C-154 | hbbs/hbbr en running | Contenedores sin red (Networks {}): running no implica alcanzable | C-156 | `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:22` |
| C-155 | PortBindings correctos | Bindings declarados sin docker-proxy: sin red no tienen efecto | C-156 | `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:24` |
| C-182 | 401 Unauthorized en analyst-w11 | tailscaled en server mode ligado a la cuenta local W11\jose; la sesión de dominio no lo controla (pendiente) | — (sin corrección con comando en la fuente) | `docs/HITO-dominio-tfm-local-2026-09-26.md:120` |
| C-211 | Contraseña de un solo uso débil | Get-Random usa un PRNG no apto para material criptográfico | C-210 | `docs/README-fase4-validacion.md:250` |
| C-214 | 400 Missing signature headers | Desde P0-4 el endpoint exige firma HMAC (ORCH_REQUIRE_HMAC=true) | C-384 | `fase5-orchestrator-api/README.md:316` |
| C-224 | Sin salida, exit 1 | check-ignore no aplica .gitignore a ficheros ya versionados | C-225 | `fase5-velociraptor/INFORME-P0-1.md:36` |
| C-235 | «Contenedores recreados»; puerto de nuevo en 0.0.0.0:4833 | Con -f explícito Compose no carga docker-compose.override.yml | C-260 | `docs/INFORME-AUDITORIA-FASE6.md:308` |
| C-246 | Healthy en 33,5 s y orden correcto | depends_on es de Compose; al reiniciar el anfitrión el demonio lo ignora | C-415 | `docs/INFORME-AUDITORIA-FASE6.md:399` |
| C-247 | «Started»; nginx en bucle | up sobre un contenedor exited lo arranca sin recrear y conserva el endpoint de red obsoleto | C-260 | `docs/INFORME-AUDITORIA-FASE6.md:430` |
| C-255 | Exit 0 leído como «excluido» | Con -v el código refleja coincidencia de patrón, incluidas las negaciones | C-252 | `docs/INFORME-AUDITORIA-FASE6.md:860` |
| C-256 | «644edf8..99844be main -> main» | Empujó al remoto de backup, no al principal | C-257 | `docs/INFORME-AUDITORIA-FASE6.md:887` |
| C-258 | Código ≠ 0: «no hay licencia» | El código venía del patrón COPYING* inexistente; LICENSE.txt sí existía | — (sin corrección con comando en la fuente) | `docs/INFORME-AUDITORIA-FASE6.md:863` |
| C-290 | Respuesta sin error, hash e3b0c442… | Devolvió 0 bytes; el hash es el del fichero vacío | C-426 | `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:579` |
| C-292 | Sin coincidencias: se aplazó la rotación | La premisa era falsa: git show HEAD:<fichero> mostró ocho apariciones | C-293 | `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:1346` |
| C-303 | La prueba unitaria falla | Desde P0-4 collect(request) verifica la firma HMAC antes de procesar el cuerpo | — (sin corrección con comando en la fuente) | `fase7-observabilidad/README.md:220` |
| C-310 | «Sintaxis OK» | Compose fusionaba las listas de ports de base y override; lo resolvió la etiqueta !override | — (sin corrección con comando en la fuente) | `docs/INFORME-AUDITORIA-FASE8.md:223` |
| C-313 | Se «midió» un sistema caído | El patrón de pkill no se expandió por las capas de comillas: el proceso siguió vivo | — (sin corrección con comando en la fuente) | `docs/INFORME-AUDITORIA-FASE8.md:270` |
| C-315 | Cinco endpoints «vacíos» | --cacert a una ruta inexistente: curl falla y con -s no imprime nada | — (sin corrección con comando en la fuente) | `docs/api-reconocimiento-fase8.md:40` |
| C-316 | «sin sqlite3» | El comando falló por sintaxis del shell; el \|\| imprimió un diagnóstico falso | C-317 | `docs/api-reconocimiento-fase8.md:42` |
| C-334 | 5 procesos; watchdog «muerto» | busybox ps w sin argumentos solo lista los del terminal (162 procesos reales) | C-335 | `docs/mejora6-endurecimiento-dispositivo.md:354` |
| C-336 | Lista completa sin filtrar | La columna de estado no es la novena en ese top | — (sin corrección con comando en la fuente) | `docs/mejora6-endurecimiento-dispositivo.md:359` |
| C-345 | Inventario de servicios | head -20 cortó ocho servicios vivos | — (sin corrección con comando en la fuente) | `docs/CATALOGO-fallos-silenciosos.md:78` |
| C-346 | «Fuera del repositorio» | El fichero no existía en esa ruta; git ls-files no distingue las dos causas | C-275 | `docs/CATALOGO-fallos-silenciosos.md:95` |
| C-347 | Nearest DERP: unknown | La sonda de netcheck no cubre el DERP embebido de Headscale; el servicio estaba sano | C-147 | `docs/CATALOGO-fallos-silenciosos.md:200` |
| C-361 | hosts bloqueado | Leer y reescribir el mismo fichero en la misma tubería lo bloquea | — (sin corrección con comando en la fuente) | `docs/INFORME-P1-0.md:62` |
| C-377 | El keyFile sigue con otro propietario | Con LXD el UID 999 está mapeado a lxd:systemd-journal | C-375 | `docs/README-fase1c-mongodb-rocketchat.md:92` |
| C-409 | Corrección «verificada» | Healthcheck + depends_on no actúan en el arranque en frío | C-415 | `fase6-iris/docker-compose.override.yml:10` |
| C-428 | El script de integración desaparece | Las copias con docker cp se pierden en cada --force-recreate | — (sin corrección con comando en la fuente) | `fase2-orquestador/README.md:124` |
| C-431 | «La ACL no concede acceso a DC01» | grep -A 40 cortó la lectura en la primera regla; la tercera lo concedía | C-129 | `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:123` |
| C-433 | collect_logs.ps1 inservible en PowerShell 7 | Get-EventLog está deprecado y ausente | C-204 | `docs/README-fase4c-dcagent.md:341` |
| C-439 | 500 Internal Server Error | KeyError en el control de acceso para peticiones por API key: «caso inexistente» y «servidor roto» son indistinguibles | — (sin corrección con comando en la fuente) | `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:1013` |
| C-440 | El contenedor no se recrea | Al retirar la única entrada de ports: la clave queda nula y el comando aborta; validar antes con docker compose config | C-427 | `docs/LECCIONES-OPERATIVAS-conversaciones.md:15` |
| C-441 | diff correcto, sin errores, pero el contenedor ejecuta el fichero anterior | sed -i sustituye el inodo; el bind mount de fichero sigue anclado al inodo antiguo | C-438, C-443 | `docs/LECCIONES-OPERATIVAS-conversaciones.md:22` |
| C-444 | Código 0 con el comando fallido | $? tras una tubería es el del último comando (tail) | C-445 | `docs/LECCIONES-OPERATIVAS-conversaciones.md:42` |
| C-447 | «La integración funciona» sin ejecución visible | El 200 y «Workflow was started» son acuse de recepción (Respond: Immediately), no ejecución | C-446 | `docs/LECCIONES-OPERATIVAS-conversaciones.md:64` |
| C-449 | 404 contra Portainer | Traefik enruta TLS por SNI antes de mirar Host; con -H el SNI va vacío | C-450 | `docs/LECCIONES-OPERATIVAS-conversaciones.md:75` |
| C-451 | Marca de tiempo de diez dígitos | El date de busybox descarta %N sin avisar | C-452 | `docs/LECCIONES-OPERATIVAS-conversaciones.md:96` |

### Trampas conocidas con fuente en el repositorio (Paso 2)

Cruce de las trampas recogidas de las conversaciones de trabajo con el repositorio (`git grep`). Solo se integran las que tienen fuente; la parte sin fuente de una trampa se lista en la Parte V.

| # | Trampa | Fuente | Entradas |
|---|---|---|---|
| 1 | `docker compose -f` fuera de `fase6-iris/` descarta en silencio el override y revierte la restricción de puertos | `docs/INFORME-AUDITORIA-FASE6.md:305-321`, `:861`; `fase6-iris/README.md:155-160`; `docs/CATALOGO-fallos-silenciosos.md:117` | C-235, C-260, C-236 |
| 2 | Un cambio en el compose no actúa sin recrear; comprobar el efecto con `docker exec … grep` | `docs/README-fase4-validacion.md:543-546`; `docs/README-fase4a-headscale.md:37-46`; `docs/CATALOGO-fallos-silenciosos.md:116`; comprobación: `docs/mejora5-prueba-mensual-resiliencia.md:191`, `docs/cierre-mejora1-hook.md:34` | C-269, C-321, C-333 |
| 3 | `docker compose config` como validación previa a `--force-recreate` (y su límite: valida sintaxis y fusión, no la semántica); retirar la única entrada de `ports:` deja la clave nula | `docs/INFORME-AUDITORIA-FASE6.md:320`, `:994`; `fase6-iris/README.md:162-165`; `docs/INFORME-AUDITORIA-FASE8.md:223`; `docs/LECCIONES-OPERATIVAS-conversaciones.md:11-17` (L-1) | C-236, C-427, C-310, C-440 |
| 4 | RustDesk `running` con `.NetworkSettings.Networks` = `{}`; discriminadores: `docker inspect` y `relay-servers=[]` en el log de hbbs | `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:22-30`, `:77-81`, `:196-207` | C-154, C-155, C-156, C-404 |
| 5 | `sed -i` sobre un bind mount de fichero cambia el inodo y el contenedor sigue con el fichero anterior; patrón seguro `tmp=$(mktemp); sed … > "$tmp" && cat "$tmp" > FICHERO && rm "$tmp"` | `docs/LECCIONES-OPERATIVAS-conversaciones.md:19-39` (L-2); `docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:119`; principio: «un bind mount vincula inodos, no rutas», `docs/INFORME-AUDITORIA-FASE6.md:262-265` | C-441, C-438, C-443, C-442 |
| 6 | `cmd \| tail; echo $?` mide el código de salida de la tubería, no el del comando | `docs/LECCIONES-OPERATIVAS-conversaciones.md:42-46` (L-3) | C-444, C-445 |
| 7 | Headscale: reinicio desde `headscale/config/`; `policy check/get/set` no muestran la política aplicada; la verdad está en `tailscale debug netmap` del nodo destino | `docs/HALLAZGO-headscale-politica-modo-file.md:17-35`, `:92-110`, `:240-247`; `docs/README-fase4a-headscale.md:47-66` | C-126, C-127, C-128, C-131, C-132, C-129 |
| 8 | En las unidades systemd los `$` del shell van duplicados (`$$`) | `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:227-229`; `fase4-breakglass-dc/systemd/tfm-fase4-rustdesk.service:17` | C-411, C-414 |
| 9 | Sin `--remove-orphans` en la unidad de RustDesk: borraría `headscale-ui` | `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:221-223`; `fase4-breakglass-dc/systemd/tfm-fase4-rustdesk.service:19` | C-412 |
| 10 | `docker cp` de `database.sqlite` puede adelantarse a la escritura diferida de SQLite: copiar también el `-wal` antes de consultar `execution_entity` | `docs/LECCIONES-OPERATIVAS-conversaciones.md:48-58` (L-4); medición con la copia y su `-wal`: `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:1533-1536` | C-446 |
| 12 | El «HTTP 200» del integrador y `{"message":"Workflow was started"}` son acuse de recibo, no prueba de ejecución; el testigo fiable es la fila en `execution_entity` | `docs/LECCIONES-OPERATIVAS-conversaciones.md:61-73` (L-5); `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:1526-1536`; `docs/CATALOGO-fallos-silenciosos.md:150`; `fase8-kvm/README.md:410-416` | C-447, C-448, C-446, C-093, C-095 |
| 13 | Firma HMAC con curl: `--data-binary @fichero`, `openssl dgst -sha256 -hmac … -r` y cabecera `x-oob-signature` | `docs/PROCEDIMIENTO-prueba-manual-webhook.md:12-22`, `:73-80`; `docs/INFORME-P0-4-implementacion.md:94` | C-087, C-088, C-387 |
| 14 | `curl -H 'Host: …'` sin `--resolve` no envía el SNI que Traefik usa para enrutar TLS | `docs/LECCIONES-OPERATIVAS-conversaciones.md:75-88` (L-6) | C-449, C-450 |
| 15 | Herramientas con salida plausible pero errónea: `date +%s%N` de busybox devuelve segundos; `grep` de busybox sobre binarios trunca; `ps w` solo muestra procesos con terminal | `docs/LECCIONES-OPERATIVAS-conversaciones.md:90-102` (L-7); `docs/cierre-mejora1-hook.md:144-146`; `docs/CATALOGO-fallos-silenciosos.md:67`, `:80`; `docs/mejora6-endurecimiento-dispositivo.md:354-358` | C-451, C-452, C-334, C-335 |
| 16 | `grep -A 40` truncó la lectura del netmap y llevó a una conclusión falsa sobre la ACL | `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:122-124`; `docs/CATALOGO-fallos-silenciosos.md:90` | C-431, C-129 |
| 17 | Códigos de salida de `git check-ignore -v` mal interpretados | `docs/INFORME-AUDITORIA-FASE6.md:860`; `docs/CATALOGO-fallos-silenciosos.md:84`; `docs/INFORME-AUDITORIA-FASE8.md:346`; `fase5-velociraptor/INFORME-P0-1.md:33-49` | C-255, C-224, C-225, C-252 |
| 18 | Contraseña de MongoDB con carácter reservado de URI → `ReplicaSetNoPrimary` con host `32:27017`; regla: alfanumérica y longitud comprobada antes de recrear | `docs/HALLAZGO-credencial-mongodb-2026-09-23.md:84-106` | C-066 |
| 19 | `read_file` por gRPC de Velociraptor devolvía 0 bytes (`e3b0c442…`); la vía correcta es el volumen compartido `:ro` | `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:579`, `:617-624`; `fase5-velociraptor/README.md:400-420` | C-290, C-426 |
| 20 | IRIS devuelve HTTP 500 (no 404) para un id de caso inexistente | `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:1011-1026` | C-439 |
| 21 | Lo prohibido es desactivar la verificación TLS en la configuración de servicios y nodos («Ignore SSL Issues», `insecureSkipVerify`, `ssl.CERT_NONE`); la salida es la CA del enclave (`ca-bundle-oob.crt`, `NODE_EXTRA_CA_CERTS`). `curl -k` en sondas no consta prohibido | `docs/LECCIONES-OPERATIVAS-conversaciones.md:104-109` (L-8); `fase1-infraestructura/traefik/generate-oob-ca.sh:13-18`, `:121`; `docs/README-fase2bcd-workflow-n8n.md:92`; `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:80`, `:124-132`. `insecureSkipVerify` sigue como riesgo aceptado: `fase1-infraestructura/README.md:309` | C-104, C-283, C-287, C-055 |
| 22 | `git push` a los dos remotos; un force-push no limpia los objetos huérfanos en GitHub; resuelto con `git filter-repo` y borrando y recreando los repositorios | `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md:262-272`; `fase5-velociraptor/SECURITY-NOTICE.md:76`, `:104-109`; `docs/HALLAZGO-credencial-mongodb-2026-09-23.md:78-81` | C-289, C-273, C-393, C-228 |
| 23 | `Test-NetConnection` desde analyst-w11 salía por `Ethernet0` y no por la tailnet | `docs/HALLAZGO-headscale-politica-modo-file.md:85-89` | C-429 |

---

## Parte IV — Anexo Windows (DC01-TFM y analyst-w11)

**(en este proyecto)** DC01-TFM ejecuta el agente del DC (FastAPI bajo NSSM, en `C:\tfm-dc-agent`), los scripts de respuesta de `C:\tfm-scripts` y el cliente RustDesk; analyst-w11 es el puesto del analista. Ambos se unen a la tailnet con Tailscale. Los scripts `.ps1` se catalogan por su invocación (`!ir run`, en la Parte I) y sus cmdlets principales.

### C-175 · La API 8080 de Traefik no es alcanzable por LAN ni tailnet → False, con ping…

```powershell
Test-NetConnection 192.168.127.138 -Port 8080
```

- **Qué hace (genérico):** `Test-NetConnection HOST -Port N` (PowerShell): prueba de conexión TCP; informa `TcpTestSucceeded`, `PingSucceeded` y la interfaz de salida (`InterfaceAlias`).
- **En este proyecto:** Fase 1 · Traefik · directorio: no consta. En analyst-w11, V6/V7: la API 8080 de Traefik no es alcanzable por LAN ni tailnet → False, con ping OK.
- **Resultado:** **CONTROL-NEGATIVO**
- **Fuente:** `docs/DECISION-dashboard-traefik.md:125`, `docs/DECISION-dashboard-traefik.md:126`

### C-176 · Control positivo, 443 alcanzable → True

```powershell
Test-NetConnection 192.168.127.138 -Port 443
```

- **Qué hace (genérico):** `Test-NetConnection HOST -Port N` (PowerShell): prueba de conexión TCP; informa `TcpTestSucceeded`, `PingSucceeded` y la interfaz de salida (`InterfaceAlias`).
- **En este proyecto:** Fase 1 · Traefik · directorio: no consta. En analyst-w11, V8: control positivo, 443 alcanzable → True.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/DECISION-dashboard-traefik.md:127`

### C-177 · 443 y 4833 → False (la política nueva aún no se aplicaba)

```powershell
Test-NetConnection 100.64.0.1 -Port 443
```

- **Qué hace (genérico):** `Test-NetConnection HOST -Port N` (PowerShell): prueba de conexión TCP; informa `TcpTestSucceeded`, `PingSucceeded` y la interfaz de salida (`InterfaceAlias`).
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. En analyst-w11, antes de reiniciar Headscale: 443 y 4833 → False (la política nueva aún no se aplicaba).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/HALLAZGO-headscale-politica-modo-file.md:62`

### C-178 · Puertos 22 y 8000 del orquestador → False

```powershell
Test-NetConnection 100.64.0.1 -Port 22
```

- **Qué hace (genérico):** `Test-NetConnection HOST -Port N` (PowerShell): prueba de conexión TCP; informa `TcpTestSucceeded`, `PingSucceeded` y la interfaz de salida (`InterfaceAlias`).
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. En DC01-TFM con la ACL activa: puertos 22 y 8000 del orquestador → False.
- **Resultado:** **CONTROL-NEGATIVO**
- **Fuente:** `docs/README-fase4-pendientes.md:34`, `docs/README-fase4-validacion.md:523`

### C-179 · False antes de reconectar los contenedores a la red, True después

```powershell
Test-NetConnection 100.64.0.1 -Port 21116
```

- **Qué hace (genérico):** `Test-NetConnection HOST -Port N` (PowerShell): prueba de conexión TCP; informa `TcpTestSucceeded`, `PingSucceeded` y la interfaz de salida (`InterfaceAlias`).
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. En DC01-TFM, par diferencial: False antes de reconectar los contenedores a la red, True después; True también tras el arranque en frío y tras el apagado no limpio.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:56`, `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:57`, `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:256`, `docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:293`

### C-180 · IP de la tailnet → 100.64.0.2

```bash
tailscale ip -4
```

- **Qué hace (genérico):** `tailscale ip -4`: dirección IPv4 del nodo en la tailnet.
- **En este proyecto:** Fase 4 · host · directorio: no consta. En DC01-TFM tras la promoción a controlador: IP de la tailnet → 100.64.0.2.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/HITO-dominio-tfm-local-2026-09-26.md:79`

### C-181 · Localizar el DC de tfm.local → \\DC01-TFM.tfm.local

```powershell
nltest /dsgetdc:tfm.local
```

- **Qué hace (genérico):** `nltest /dsgetdc:DOMINIO` (Windows): localiza un controlador del dominio.
- **En este proyecto:** Fase 4 · host · directorio: no consta. En analyst-w11: localizar el DC de tfm.local → \\DC01-TFM.tfm.local.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/HITO-dominio-tfm-local-2026-09-26.md:108`

### C-182 · «401 Unauthorized

```bash
tailscale status
```

- **Qué hace (genérico):** `tailscale status`: pares visibles y estado de la conexión.
- **En este proyecto:** Fase 4 · host · directorio: no consta. En analyst-w11 con cuenta de dominio: «401 Unauthorized: Tailscale running in server mode ("W11\\jose")». El túnel funciona; el cliente solo se controla desde la cuenta local (pendiente §5.4).
- **Resultado:** **FALLÓ**
- **Fuente:** `docs/HITO-dominio-tfm-local-2026-09-26.md:120`, `docs/HITO-dominio-tfm-local-2026-09-26.md:134`

### C-183 · Estado de la cuenta tras enable_account.ps1 → True

```powershell
Get-ADUser … .Enabled
```

- **Qué hace (genérico):** `Get-ADUser IDENTIDAD`: cuenta de Active Directory (`.Enabled`: si está habilitada).
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. En DC01-TFM: estado de la cuenta tras enable_account.ps1 → True. El estado intermedio tras disable no se capturó.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/HITO-dominio-tfm-local-2026-09-26.md:223`

### C-184 · Leer el final del log del agente (pendiente en la versión inicial del hito)

```powershell
Get-Content C:\tfm-dc-agent\logs\agent.log -Tail 10
```

- **Qué hace (genérico):** `Get-Content F [-Tail N]`: lee un fichero (últimas N líneas).
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. En DC01-TFM: leer el final del log del agente (pendiente en la versión inicial del hito).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/HITO-dominio-tfm-local-2026-09-26.md:327`, `docs/HITO-dominio-tfm-local-2026-09-26.md:326`

### C-185 · SHA-256 del log conservado

```powershell
Get-FileHash
```

- **Qué hace (genérico):** `Get-FileHash`: resumen SHA-256 de un fichero.
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. En DC01-TFM: SHA-256 del log conservado; coincide con sha256sum de la copia en el enclave.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/HITO-dominio-tfm-local-2026-09-26.md:521`

### C-186 · Comprobar el atributo de solo lectura del log conservado → True

```powershell
(Get-Item C:\tfm-agent\logs\agent.log).IsReadOnly
```

- **Qué hace (genérico):** `Set-ItemProperty -Name IsReadOnly -Value $true` / `(Get-Item F).IsReadOnly`: fija o lee el atributo de solo lectura.
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. En DC01-TFM: comprobar el atributo de solo lectura del log conservado → True.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/HITO-dominio-tfm-local-2026-09-26.md:519`

### C-187 · Fijar el log original como solo lectura

```powershell
Set-ItemProperty … -Name IsReadOnly -Value $true
```

- **Qué hace (genérico):** `Set-ItemProperty -Name IsReadOnly -Value $true` / `(Get-Item F).IsReadOnly`: fija o lee el atributo de solo lectura.
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. En DC01-TFM: fijar el log original como solo lectura.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/HITO-dominio-tfm-local-2026-09-26.md:519`

### C-188 · Instalar Tailscale

```powershell
winget install tailscale.tailscale
```

- **Qué hace (genérico):** `winget install [-e --id ID] [--scope machine]`: instala un paquete (coincidencia exacta, para todos los usuarios).
- **En este proyecto:** Fase 4 · host · directorio: no consta. En DC01-TFM: instalar Tailscale.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4b-tailnet.md:83`

### C-189 · Unir el DC a Headscale con tag:dc y --accept-dns=false

```bash
tailscale up --login-server https://hs.oob.local `
  --authkey [REDACTADO] --hostname dc01-tfm `
  --advertise-tags=tag:dc --accept-dns=false
```

- **Qué hace (genérico):** `tailscale up`: conecta el nodo a la tailnet. `--login-server URL`: servidor de control (aquí Headscale); `--authkey`: clave de pre-autorización; `--hostname`: nombre del nodo; `--advertise-tags`: etiquetas que solicita; `--accept-dns=false`: no aplica la configuración DNS de la tailnet.
- **En este proyecto:** Fase 4 · host · directorio: no consta. En DC01-TFM: unir el DC a Headscale con tag:dc y --accept-dns=false. Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4b-tailnet.md:96`

### C-190 · Conectividad de la tailnet

```bash
tailscale status
ping <IP_TAILSCALE_ORQUESTADOR>
```

- **Qué hace (genérico):** `tailscale status`: pares visibles y estado de la conexión. `ping` (`-c N` en Linux): eco ICMP.
- **En este proyecto:** Fase 4 · host · directorio: no consta. En DC01-TFM: conectividad de la tailnet.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase4b-tailnet.md:127`

### C-191 · Instalar Python 3.11 para todos los usuarios

```powershell
winget install -e --id Python.Python.3.11 --scope machine
```

- **Qué hace (genérico):** `winget install [-e --id ID] [--scope machine]`: instala un paquete (coincidencia exacta, para todos los usuarios).
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. En DC01-TFM: instalar Python 3.11 para todos los usuarios.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4c-dcagent.md:35`

### C-192 · Verificar Python y pip

```powershell
python --version
pip --version
```

- **Qué hace (genérico):** `python -m venv DIR`: crea un entorno virtual; `--version`: versión.
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. En DC01-TFM: verificar Python y pip.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-fase4c-dcagent.md:41`

### C-193 · Crear C:\tfm-dc-agent y C:\tfm-scripts

```powershell
mkdir C:\tfm-dc-agent
mkdir C:\tfm-scripts
```

- **Qué hace (genérico):** `mkdir` (PowerShell): crea un directorio.
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. En DC01-TFM: crear C:\tfm-dc-agent y C:\tfm-scripts.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4c-dcagent.md:79`

### C-194 · ACL de directorios (SYSTEM RX sobre código y scripts, M solo sobre logs) —…

```powershell
icacls C:\tfm-scripts /inheritance:r
icacls C:\tfm-scripts /grant:r "SYSTEM:(OI)(CI)(RX)"
icacls C:\tfm-scripts /grant:r "Administradores:(OI)(CI)(F)"
icacls C:\tfm-dc-agent /inheritance:r
icacls C:\tfm-dc-agent /grant:r "SYSTEM:(OI)(CI)(RX)"
icacls C:\tfm-dc-agent /grant:r "Administradores:(OI)(CI)(F)"
icacls C:\tfm-dc-agent\logs /inheritance:r
icacls C:\tfm-dc-agent\logs /grant:r "SYSTEM:(OI)(CI)(M)"
icacls C:\tfm-dc-agent\logs /grant:r "Administradores:(OI)(CI)(F)"
```

- **Qué hace (genérico):** `icacls RUTA`: ACL de Windows. `/inheritance:r` quita los permisos heredados; `/grant:r` concede sustituyendo; `(OI)(CI)` herencia a ficheros y subcarpetas; `RX` lectura y ejecución, `M` modificación, `F` control total.
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. En DC01-TFM: ACL de directorios (SYSTEM RX sobre código y scripts, M solo sobre logs) — «Configuración aplicada».
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/README-fase4-validacion.md:179`, `docs/README-fase4c-dcagent.md:701`, `fase4-breakglass-dc/dcagent/README-despliegue.md:52`

### C-195 · El puerto 8000 del agente solo desde 100.64.0.0/10

```powershell
New-NetFirewallRule `
  -DisplayName "TFM DC Agent - Solo Tailscale" `
  -Direction Inbound `
  -Protocol TCP `
  -LocalPort 8000 `
  -RemoteAddress 100.64.0.0/10 `
  -Action Allow
```

- **Qué hace (genérico):** `New-NetFirewallRule`: crea una regla del firewall de Windows (`-Direction`, `-Protocol`, `-LocalPort`, `-RemoteAddress`, `-Action Allow`).
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. En DC01-TFM: el puerto 8000 del agente solo desde 100.64.0.0/10.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4c-dcagent.md:560`, `fase4-breakglass-dc/dcagent/README-despliegue.md:129`

### C-196 · Entorno virtual y dependencias del agente

```powershell
cd C:\tfm-dc-agent
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

- **Qué hace (genérico):** `cd DIR`: cambia el directorio de trabajo. `python -m venv DIR`: crea un entorno virtual; `--version`: versión. `pip install [-r requirements.txt]`: instala dependencias.
- **En este proyecto:** Fase 4 · DC-agent · directorio: `C:\tfm-dc-agent`. En DC01-TFM: entorno virtual y dependencias del agente.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4c-dcagent.md:612`, `fase4-breakglass-dc/dcagent/README-despliegue.md:85`

### C-197 · Registrar TFM-DC-Agent con NSSM, ligado a 100.64.0.2 y no a 0.0.0.0, con log…

```powershell
nssm install TFM-DC-Agent "C:\tfm-dc-agent\.venv\Scripts\python.exe"
nssm set TFM-DC-Agent AppParameters "-m uvicorn agent_dc:app --host 100.64.0.2 --port 8000"
nssm set TFM-DC-Agent AppDirectory "C:\tfm-dc-agent"
nssm set TFM-DC-Agent DisplayName "TFM DC Agent"
nssm set TFM-DC-Agent Start SERVICE_AUTO_START
nssm set TFM-DC-Agent AppStdout C:\tfm-dc-agent\logs\service.log
nssm set TFM-DC-Agent AppStderr C:\tfm-dc-agent\logs\service.log
nssm set TFM-DC-Agent AppRotateFiles 1
nssm set TFM-DC-Agent AppRotateBytes 10485760
```

- **Qué hace (genérico):** `nssm install SERVICIO PROGRAMA [ARGS]`: registra un ejecutable como servicio de Windows. `nssm set SERVICIO PARÁMETRO VALOR`: `AppParameters` argumentos, `AppDirectory` directorio, `Start` tipo de arranque, `AppStdout/AppStderr` ficheros de salida, `AppRotate*` rotación, `AppEnvironmentExtra` variables (sustituye el conjunto completo), `DependOnService` dependencia, `AppExit Default Restart` y `AppRestartDelay` reinicio.
- **En este proyecto:** Fase 4 · DC-agent · directorio: `C:\tfm-dc-agent`. En DC01-TFM: registrar TFM-DC-Agent con NSSM, ligado a 100.64.0.2 y no a 0.0.0.0, con log rotado.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4c-dcagent.md:617`, `fase4-breakglass-dc/dcagent/README-despliegue.md:90`

### C-198 · Entorno del servicio con AppEnvironmentExtra

```powershell
nssm set TFM-DC-Agent AppEnvironmentExtra `
  "AGENT_TOKEN=[REDACTADO]" `
  "AGENT_HMAC_SECRET=[REDACTADO]" `
  "AGENT_REQUIRE_HMAC=true" `
  "TFM_SCRIPTS_DIR=C:\tfm-scripts" `
  "TFM_LOG_PATH=C:\tfm-dc-agent\logs\agent.log" `
  "TFM_HEADSCALE_IP=<IP_TRAEFIK>"
```

- **Qué hace (genérico):** `nssm set SERVICIO PARÁMETRO VALOR`: `AppParameters` argumentos, `AppDirectory` directorio, `Start` tipo de arranque, `AppStdout/AppStderr` ficheros de salida, `AppRotate*` rotación, `AppEnvironmentExtra` variables (sustituye el conjunto completo), `DependOnService` dependencia, `AppExit Default Restart` y `AppRestartDelay` reinicio.
- **En este proyecto:** Fase 4 · DC-agent · directorio: `C:\tfm-dc-agent`. En DC01-TFM: entorno del servicio con AppEnvironmentExtra (reemplaza el conjunto completo: hay que reescribir todas las líneas). El HITO §5.6 registra que faltaba TFM_LOG_PATH y el agente escribía en C:\tfm-agent\logs desde el 12/09. Credencial sustituida por [REDACTADO]; el valor real se introduce con read -s en su propia línea.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4c-dcagent.md:630`, `fase4-breakglass-dc/dcagent/README-despliegue.md:103`

### C-199 · Dependencia de Tailscale, reinicio automático y arranque del servicio

```powershell
nssm set TFM-DC-Agent DependOnService Tailscale
nssm set TFM-DC-Agent AppExit Default Restart
nssm set TFM-DC-Agent AppRestartDelay 15000
Start-Service TFM-DC-Agent
```

- **Qué hace (genérico):** `nssm set SERVICIO PARÁMETRO VALOR`: `AppParameters` argumentos, `AppDirectory` directorio, `Start` tipo de arranque, `AppStdout/AppStderr` ficheros de salida, `AppRotate*` rotación, `AppEnvironmentExtra` variables (sustituye el conjunto completo), `DependOnService` dependencia, `AppExit Default Restart` y `AppRestartDelay` reinicio. `Get-/Start-/Stop-/Set-Service`: consulta, arranca, para o configura (`-StartupType`) un servicio de Windows.
- **En este proyecto:** Fase 4 · DC-agent · directorio: `C:\tfm-dc-agent`. En DC01-TFM: dependencia de Tailscale, reinicio automático y arranque del servicio.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4c-dcagent.md:639`, `fase4-breakglass-dc/dcagent/README-despliegue.md:111`

### C-200 · Estado del servicio y /health local (debe incluir hmac_required y…

```powershell
Get-Service TFM-DC-Agent
Invoke-RestMethod http://localhost:8000/health
```

- **Qué hace (genérico):** `Get-/Start-/Stop-/Set-Service`: consulta, arranca, para o configura (`-StartupType`) un servicio de Windows. `Invoke-RestMethod URL`: petición HTTP que devuelve el JSON como objeto.
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. En DC01-TFM: estado del servicio y /health local (debe incluir hmac_required y token_configured true).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `fase4-breakglass-dc/dcagent/README-despliegue.md:138`

### C-201 · Instalar el cliente RustDesk

```powershell
winget install RustDesk.RustDesk
```

- **Qué hace (genérico):** `winget install [-e --id ID] [--scope machine]`: instala un paquete (coincidencia exacta, para todos los usuarios).
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. En DC01-TFM: instalar el cliente RustDesk.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4e-rustdesk-breakglass.md:93`

### C-202 · Entorno virtual en C:\tfm-agent con pip install fastapi uvicorn

```powershell
cd C:\tfm-agent
python -m venv .venv
.\.venv\Scripts\activate
pip install fastapi uvicorn
```

- **Qué hace (genérico):** `cd DIR`: cambia el directorio de trabajo. `python -m venv DIR`: crea un entorno virtual; `--version`: versión. `pip install [-r requirements.txt]`: instala dependencias.
- **En este proyecto:** Fase 4 · DC-agent · directorio: `C:\tfm-agent`. En DC01-TFM, versión de la Fase 4e: entorno virtual en C:\tfm-agent con pip install fastapi uvicorn. Sustituida por el despliegue en C:\tfm-dc-agent con requirements.txt.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4e-rustdesk-breakglass.md:233`

### C-203 · NSSM con --host 0.0.0.0

```powershell
cd C:\Tools\nssm\win64
./nssm.exe install TFM-DC-Agent C:\tfm-agent\.venv\Scripts\python.exe -m uvicorn agent_dc:app --host 0.0.0.0 --port 8000
./nssm.exe set TFM-DC-Agent Start SERVICE_AUTO_START
./nssm.exe set TFM-DC-Agent AppStdout C:\tfm-agent\logs\stdout.log
./nssm.exe set TFM-DC-Agent AppStderr C:\tfm-agent\logs\stderr.log
./nssm.exe start TFM-DC-Agent
```

- **Qué hace (genérico):** `cd DIR`: cambia el directorio de trabajo. `nssm install SERVICIO PROGRAMA [ARGS]`: registra un ejecutable como servicio de Windows. `nssm set SERVICIO PARÁMETRO VALOR`: `AppParameters` argumentos, `AppDirectory` directorio, `Start` tipo de arranque, `AppStdout/AppStderr` ficheros de salida, `AppRotate*` rotación, `AppEnvironmentExtra` variables (sustituye el conjunto completo), `DependOnService` dependencia, `AppExit Default Restart` y `AppRestartDelay` reinicio. `nssm start SERVICIO`: arranca el servicio.
- **En este proyecto:** Fase 4 · DC-agent · directorio: `C:\Tools\nssm\win64`. En DC01-TFM, versión de la Fase 4e: NSSM con --host 0.0.0.0 (desaconsejado después: escucharía también en la interfaz corporativa).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4e-rustdesk-breakglass.md:244`

### C-204 · Núcleo de collect_logs.ps1

```powershell
$events = Get-WinEvent -FilterHashtable @{LogName='Security'} -MaxEvents 50 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, LevelDisplayName, MachineName,
                  @{N='Message';E={ $_.Message -replace '[\r\n]+',' ' }}
```

- **Qué hace (genérico):** `Get-WinEvent -FilterHashtable @{LogName=...} -MaxEvents N`: lee eventos del registro de Windows.
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. Núcleo de collect_logs.ps1: 50 eventos de Security en JSON con SHA-256 (Get-WinEvent sustituye a Get-EventLog, ausente en PowerShell 7). Ejecutado con código 0 en REQ-9253813e.
- **Resultado:** **VALIDADO**
- **Fuente:** `fase4-breakglass-dc/scripts/collect_logs.ps1:5`, `docs/README-fase4c-dcagent.md:350`

### C-205 · Disable_account.ps1 en el repositorio

```powershell
Write-Host "DRY-RUN OK - Disable-ADAccount -Identity $target"
```

- **Qué hace (genérico):** `Write-Host`: escribe en la consola.
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. disable_account.ps1 en el repositorio: modo simulación. En el DC se activó la orden real Disable-ADAccount (HITO §1); código 0 en la prueba real.
- **Resultado:** **VALIDADO**
- **Fuente:** `fase4-breakglass-dc/scripts/disable_account.ps1:4`, `docs/README-fase4c-dcagent.md:326`

### C-206 · Enable_account.ps1 en el repositorio

```powershell
Write-Host "DRY-RUN OK - Enable-ADAccount -Identity $target"
```

- **Qué hace (genérico):** `Write-Host`: escribe en la consola.
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. enable_account.ps1 en el repositorio: modo simulación. En el DC se activó Enable-ADAccount; estado final True.
- **Resultado:** **VALIDADO**
- **Fuente:** `fase4-breakglass-dc/scripts/enable_account.ps1:3`, `docs/README-fase4c-dcagent.md:335`

### C-207 · Isolate_host.ps1

```powershell
New-NetFirewallRule -DisplayName "TFM-OOB-Keepalive-Control" -Direction Outbound `
  -RemoteAddress $HeadscaleIP -Action Allow -Enabled True -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "TFM-OOB-Keepalive-Tailnet" -Direction Outbound `
  -RemoteAddress $TailnetCIDR -Action Allow -Enabled True -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "TFM-OOB-Keepalive-Wireguard" -Direction Outbound `
  -Protocol UDP -LocalPort 41641 -Action Allow -Enabled True -ErrorAction SilentlyContinue | Out-Null
```

- **Qué hace (genérico):** `New-NetFirewallRule`: crea una regla del firewall de Windows (`-Direction`, `-Protocol`, `-LocalPort`, `-RemoteAddress`, `-Action Allow`).
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. isolate_host.ps1: crear primero reglas Allow que preservan el canal OOB; el bloqueo sigue comentado (simulación). No se ejecutó en la prueba real.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase4-breakglass-dc/scripts/isolate_host.ps1:11`, `docs/README-fase4c-dcagent.md:388`

### C-208 · Reset_password.ps1

```powershell
Add-Type -AssemblyName System.Web
$newPass = [System.Web.Security.Membership]::GeneratePassword(20, 5)
```

- **Qué hace (genérico):** `[System.Web.Security.Membership]::GeneratePassword(N, M)`: contraseña de N caracteres con al menos M no alfanuméricos. `Add-Type -AssemblyName`: carga un ensamblado .NET.
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. reset_password.ps1: generar la contraseña con System.Web.Security.Membership (Read-Host -AsSecureString no funciona en un servicio). P1 latente: la contraseña se publicaría en la war room (HITO §5.5).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `fase4-breakglass-dc/scripts/reset_password.ps1:5`, `docs/README-fase4c-dcagent.md:411`

### C-209 · Rustdesk_enable.ps1

```powershell
Set-Service -Name RustDesk -StartupType Manual
Start-Service -Name RustDesk
```

- **Qué hace (genérico):** `Get-/Start-/Stop-/Set-Service`: consulta, arranca, para o configura (`-StartupType`) un servicio de Windows.
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. rustdesk_enable.ps1: revertir el Disabled que deja rustdesk_disable.ps1 (la primera versión no lo hacía y el break-glass quedaba muerto tras el primer ciclo).
- **Resultado:** **VALIDADO**
- **Fuente:** `fase4-breakglass-dc/scripts/rustdesk_enable.ps1:7`, `docs/README-fase4e-rustdesk-breakglass.md:138`, `docs/README-fase4c-dcagent.md:439`

### C-210 · Contraseña de un solo uso con RandomNumberGenerator en vez de Get-Random

```powershell
$bytes = New-Object byte[] 16
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
$pass = -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
```

- **Qué hace (genérico):** `[System.Security.Cryptography.RandomNumberGenerator]`: generador criptográficamente seguro.
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. Contraseña de un solo uso con RandomNumberGenerator en vez de Get-Random.
- **Resultado:** **VALIDADO**
- **Fuente:** `fase4-breakglass-dc/scripts/rustdesk_enable.ps1:23`, `docs/README-fase4e-rustdesk-breakglass.md:154`

### C-211 · Versión inicial

```powershell
Get-Random
```

- **Qué hace (genérico):** `Get-Random`: número pseudoaleatorio (no criptográfico).
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. Versión inicial: PRNG no apto para material criptográfico.
- **Resultado:** **FALLÓ** (→ C-210)
- **Fuente:** `docs/README-fase4-validacion.md:250`, `docs/README-fase4d-flujo-aprobacion.md:154`, `docs/README-fase4e-rustdesk-breakglass.md:123`

### C-212 · Tarea RustDesk-AutoOff con -Principal SYSTEM explícito (sin él falla con…

```powershell
$action    = New-ScheduledTaskAction -Execute "PowerShell.exe" `
               -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\tfm-scripts\rustdesk_disable.ps1"
$trigger   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes($TTLMinutes)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "RustDesk-AutoOff" -Action $action `
  -Trigger $trigger -Principal $principal -Force | Out-Null
```

- **Qué hace (genérico):** `New-ScheduledTaskAction/Trigger/Principal` y `Register-ScheduledTask`: crea una tarea programada; `-Principal` con `-LogonType ServiceAccount` la registra para SYSTEM.
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. Tarea RustDesk-AutoOff con -Principal SYSTEM explícito (sin él falla con 0x80070534 bajo el servicio, no en sesión interactiva). ttl_task Ready en la validación.
- **Resultado:** **VALIDADO**
- **Fuente:** `fase4-breakglass-dc/scripts/rustdesk_enable.ps1:38`, `docs/README-fase4e-rustdesk-breakglass.md:169`

### C-213 · Rustdesk_disable.ps1

```powershell
Stop-Service -Name RustDesk -ErrorAction SilentlyContinue
Set-Service -Name RustDesk -StartupType Disabled
Unregister-ScheduledTask -TaskName "RustDesk-AutoOff" -Confirm:$false -ErrorAction SilentlyContinue
```

- **Qué hace (genérico):** `Get-/Start-/Stop-/Set-Service`: consulta, arranca, para o configura (`-StartupType`) un servicio de Windows. `Unregister-ScheduledTask -Confirm:$false`: borra la tarea sin preguntar.
- **En este proyecto:** Fase 4 · RustDesk · directorio: no consta. rustdesk_disable.ps1: parar y deshabilitar RustDesk y cancelar el TTL. Validado: returncode 0.
- **Resultado:** **VALIDADO**
- **Fuente:** `fase4-breakglass-dc/scripts/rustdesk_disable.ps1:3`, `docs/README-fase4e-rustdesk-breakglass.md:193`, `docs/README-fase4c-dcagent.md:484`

### C-278 · El dashboard por IP ya no es alcanzable (TcpTestSucceeded False, ping True) y…

```powershell
Test-NetConnection 192.168.127.138 -Port 4443
```

- **Qué hace (genérico):** `Test-NetConnection HOST -Port N` (PowerShell): prueba de conexión TCP; informa `TcpTestSucceeded`, `PingSucceeded` y la interfaz de salida (`InterfaceAlias`).
- **En este proyecto:** Fase 1 · Wazuh · directorio: no consta. En analyst-w11: el dashboard por IP ya no es alcanzable (TcpTestSucceeded False, ping True) y wazuh.oob.local no resuelve.
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:173`

### C-359 · ControlURL del cliente → https://hs.oob.local

```bash
tailscale debug prefs
```

- **Qué hace (genérico):** `tailscale debug prefs`: preferencias del cliente (p. ej. `ControlURL`).
- **En este proyecto:** Fase 4 · host · directorio: no consta. En DC01-TFM: ControlURL del cliente → https://hs.oob.local.
- **Resultado:** **VALIDADO**
- **Fuente:** `docs/README-resolucion-nombres.md:137`

### C-360 · Hs.oob.local duplicado con dos IP

```powershell
Resolve-DnsName
```

- **Qué hace (genérico):** `Resolve-DnsName NOMBRE` (PowerShell): resolución DNS, incluido el fichero hosts.
- **En este proyecto:** Fase transversal · host · directorio: no consta. En DC01-TFM: hs.oob.local duplicado con dos IP; Test-NetConnection eligió la del tailnet, que falla (D2).
- **Resultado:** **DIAGNÓSTICO**
- **Fuente:** `docs/README-resolucion-nombres.md:237`

### C-361 · Leer y reescribir el propio hosts en la misma tubería lo bloquea

```powershell
Get-Content | Set-Content
```

- **Qué hace (genérico):** `Get-Content F [-Tail N]`: lee un fichero (últimas N líneas).
- **En este proyecto:** Fase transversal · host · directorio: no consta. En Windows: leer y reescribir el propio hosts en la misma tubería lo bloquea.
- **Resultado:** **FALLÓ**
- **Fuente:** `docs/INFORME-P1-0.md:62`

### C-369 · Propuesta v3 (no ejecutada)

```powershell
cloudflared.exe service install
Start-Service cloudflared
```

- **Qué hace (genérico):** `cloudflared service install`: instala el túnel de Cloudflare como servicio de Windows. `Get-/Start-/Stop-/Set-Service`: consulta, arranca, para o configura (`-StartupType`) un servicio de Windows.
- **En este proyecto:** Fase transversal · host · directorio: no consta. Propuesta v3 (no ejecutada): cloudflared como servicio Windows. El diseño final no lo usa.
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/propuesta_tfm_alerta_temprana_v3.md:252`

### C-422 · Implementación de referencia, no abordada

```powershell
Set-AuthenticodeSignature
```

- **Qué hace (genérico):** `Set-AuthenticodeSignature`: firma un script con un certificado de firma de código.
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. Implementación de referencia, no abordada: firmar los scripts con la CA del enclave y validar con Get-AuthenticodeSignature (preferido a Set-ExecutionPolicy AllSigned).
- **Resultado:** **PROCEDIMIENTO**
- **Fuente:** `docs/README-fase4-pendientes.md:259`

### C-429 · En analyst-w11, control negativo a 100.64.0.2:3389

```powershell
Test-NetConnection
```

- **Qué hace (genérico):** `Test-NetConnection HOST -Port N` (PowerShell): prueba de conexión TCP; informa `TcpTestSucceeded`, `PingSucceeded` y la interfaz de salida (`InterfaceAlias`).
- **En este proyecto:** Fase 4 · Headscale · directorio: no consta. En analyst-w11, control negativo a 100.64.0.2:3389: False correcto, pero salió por Ethernet0 (origen 192.168.127.151), no por la tailnet; mecanismo distinto del supuesto.
- **Resultado:** **CONTROL-NEGATIVO**
- **Fuente:** `docs/HALLAZGO-headscale-politica-modo-file.md:85`

### C-433 · Deprecado y ausente en PowerShell 7

```powershell
Get-EventLog
```

- **Qué hace (genérico):** `Get-EventLog`: cmdlet antiguo de lectura de registros, no disponible en PowerShell 7.
- **En este proyecto:** Fase 4 · DC-agent · directorio: no consta. Deprecado y ausente en PowerShell 7; sustituido por Get-WinEvent en collect_logs.ps1.
- **Resultado:** **FALLÓ** (→ C-204)
- **Fuente:** `docs/README-fase4c-dcagent.md:341`

---

## Parte V — Pendiente de fuente

Trampas conocidas de las conversaciones de trabajo sin registro en el repositorio. No se redactan como hechos.

- Trampa 11: `n8n import:workflow` con un JSON sin `id` falla con `SQLITE_CONSTRAINT` y deja el workflow desactivado. No localizada en las conversaciones.
- Trampa 15, parte `docker exec … true` (falla en silencio): no localizada.
- Trampa 10, episodio original (la copia sin `-wal` que omitió una ejecución recién enviada): no localizado. La regla y el patrón ya tienen fuente en L-4.

---

## Observaciones sobre las fuentes

Errores o divergencias evidentes en las fuentes. Se anotan; los comandos se mantienen literales.

- `fase2-orquestador/README.md:424-436` (C-097, C-098, C-099): los `cd` del bloque de despliegue son relativos y encadenados (`cd fase1-infraestructura/traefik`, después `cd fase3-agentic`, después `cd fase2-orquestador/n8n`); tal cual, el segundo y el tercero fallan salvo que se vuelva a la raíz entre pasos.
- Permisos del keyfile de MongoDB: `docs/README-fase1c-mongodb-rocketchat.md:139` usa `chmod 644` (los ajusta después el entrypoint) y `fase1-infraestructura/README.md:152` usa `chmod 400` (C-035, C-075).
- `docs/README-fase1a-traefik-portainer.md:112` (C-010) clona desde una URL con el marcador `TU_USUARIO`.
- Las guías de la Fase 1 usan `curl -k` en sondas de verificación (C-032, C-045, C-059, C-071); las fases posteriores verifican con `--cacert` (C-104). Según L-8 (`docs/LECCIONES-OPERATIVAS-conversaciones.md:109`) no consta ninguna prohibición sobre `curl -k` en sondas: la regla del proyecto se aplica a la configuración de servicios y nodos. **Corrección de la trampa 21:** la versión anterior de esta guía listaba como pendiente una «prohibición explícita de `curl -k`»; era un error de la lista original de trampas, no una regla del proyecto, y se ha retirado.
- `docs/README-fase4e-rustdesk-breakglass.md:244-249` (C-203) registra el agente con `--host 0.0.0.0` en `C:\tfm-agent`; la versión vigente (C-197) lo liga a `100.64.0.2` en `C:\tfm-dc-agent`.
- `docs/README-fase1d-wazuh.md:175-180` (C-055) crea un `serversTransport` con `insecureSkipVerify: true` que sigue en `fase1-infraestructura/traefik/dynamic/wazuh-transport.yml` (hallazgo abierto P1-1f).
- Los scripts de cuentas del repositorio (`disable_account.ps1`, `enable_account.ps1`) están en modo simulación, mientras que en el DC ejecutan la orden real (`docs/HITO-dominio-tfm-local-2026-09-26.md:33-38`, C-205, C-206).
- **Hipótesis no verificada.** `fase2-orquestador/n8n/export-workflow.sh:5` elimina el `id` del JSON exportado. Si es así, importar el fichero versionado (`fase2-orquestador/README.md:447`, C-102) sería precisamente el caso de la trampa 11 (Parte V). No conviene reproducirla para comprobarlo: la importación fallida desactivaría el workflow principal.
- `docs/revision-workflow1-caso-iris-warroom.md` está marcado por su autor como «PARCIALMENTE REFUTADO»; sus comandos se catalogan como propuestos, sin resultado.
- Ya anotados por las propias fuentes: el `curl` sin firma de `fase5-orchestrator-api/README.md:316` (C-214) y la prueba unitaria de `fase7-observabilidad/README.md:220` (C-303) dejaron de funcionar con el P0-4.
- `curl -H 'Host: …'` sin `--resolve`: C-141 (`docs/README-fase4-pendientes.md:36`) registra `302` hacia Authelia con `-H "Host: hs.oob.local"` contra `https://localhost/web`, y C-272 (`docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:105`) obtuvo una redirección de MISP con el mismo método, mientras L-6 registra `404` contra Portainer con `-H` y explica que así no se envía SNI (C-449). La guía no concilia los resultados: L-6 no registra el literal del primer `404`.
