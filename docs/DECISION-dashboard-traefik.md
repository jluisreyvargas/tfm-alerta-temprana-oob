# Decisión — El dashboard de Traefik se restringe por binding, no por autenticación

**Fecha:** 2026-09-13
**Decide:** Jose Luis Rey
**Afecta a:** `PLAN-P1-1a-borde-tls.md`, secciones 3 y 4 (Fase C, dashboard de Traefik)
**Estado del servicio:** publicado en `127.0.0.1:8080`, `api.insecure: true`, sin router

---

## Qué se decide

El dashboard y la API de Traefik se restringen cambiando la publicación del
puerto de `0.0.0.0:8080` a `127.0.0.1:8080` en
`fase1-infraestructura/docker-compose.yml`. **No se crea router hacia
`api@internal`, no se aplica Authelia, y `api.insecure` sigue en `true`.**

El plan pedía otra cosa: «requiere `api.insecure: false` en `traefik.yml` y un
router propio hacia `api@internal`». Esto se aparta de ahí y se documenta por esa
razón.

---

## Por qué

**El dashboard es superficie de operador, no de análisis.** Se concibió para
usarlo desde el propio servidor. No hay fila para `w11` en
`docs/resolucion-nombres.tsv`, y la de `ubuntu` apunta a `127.0.0.1`. Nadie lo
consulta desde otro equipo.

**El diagnóstico depende de él.** `http://localhost:8080/api/http/routers` es el
comando con el que se ha verificado cada servicio de la Fase C. Con
`api.insecure: false` ese endpoint desaparece y las consultas tendrían que pasar
por Authelia, lo que desde `curl` obliga a gestionar cookies de sesión. El coste
recae sobre la única herramienta de verificación por comportamiento que el
proyecto tiene para el estado del borde.

**El riesgo del cambio es mucho menor.** `traefik.yml` se monta `:ro` y no admite
recarga en caliente: un error de sintaxis ahí deja a Traefik sin arrancar, y con
él caen los seis servicios de la Fase C a la vez. `docker compose config` valida
el compose, no el contenido de `traefik.yml`, así que en esa vía no hay red de
seguridad. Cambiar una línea del compose sí está cubierto.

**No hay router que crear ni retirar.** `api@internal` y `dashboard@internal`
usan el entrypoint implícito `traefik`, ligado al 8080, no `websecure`.
Verificado en la API:

```
"entryPoints":["traefik"], "service":"api@internal",       "rule":"PathPrefix(`/api`)"
"entryPoints":["traefik"], "service":"dashboard@internal", "rule":"PathPrefix(`/`)"
```

Restringir dónde escucha ese entrypoint es, por tanto, la operación completa.

---

## Lo que esta decisión NO cierra

**Cualquier contenedor de `oob-network` sigue alcanzando la API sin autenticar.**
Medido antes de decidir, desde `n8n`:

```
wget http://172.18.0.1:8080/api/http/routers   →  HTTP/1.1 200 OK
wget http://traefik:8080/api/http/routers      →  HTTP/1.1 200 OK
```

El segundo es el que importa: va por la red de Docker, sin pasar por el
`docker-proxy` del host, así que el binding a loopback no lo afecta. La API
expone la topología completa del enclave —todos los routers, servicios,
middlewares y direcciones internas— a cualquier contenedor de esa red.

**Esta decisión se sostiene sobre una premisa explícita: el modelo de amenaza del
proyecto no incluye un contenedor comprometido dentro de `oob-network`.** Si esa
premisa cambia, la decisión se revisa entera y el camino es el del plan original,
`api.insecure: false` con router y Authelia, asumiendo el coste sobre el
diagnóstico.

Conviene anotar la tensión: el P1-1c justifica tratar Portainer aparte porque
monta el socket de Docker y «comprometerlo equivale a root en el host». Ese
argumento asume que un contenedor puede estar comprometido. La premisa de arriba
y la del P1-1c no son idénticas —una habla del contenedor como origen, la otra
como objetivo— pero están lo bastante cerca como para que merezca revisarse al
abordar el P1-1c.

---

## Un comentario que era falso y ahora es cierto

`fase1-infraestructura/traefik/traefik.yml:10`:

```yaml
api:
  dashboard: true
  insecure: true        # Dashboard accesible en :8080 sin auth (solo lab local)
```

«Solo lab local» describía una restricción que no existía: el puerto se publicaba
en `0.0.0.0:8080`, alcanzable desde el segmento corporativo y desde el tailnet.
El comentario decía el estado deseado, no el real, y cualquier lector concluiría
que el dashboard estaba confinado.

Es el patrón que recorre el proyecto, en su forma más económica: una línea de
comentario. **Desde hoy la afirmación es cierta por primera vez**, y lo es por el
compose, no por `traefik.yml`. Quien lea solo ese fichero sigue sin poder
comprobarlo, así que el comentario del compose es el que lleva la explicación.

---

## Verificación

Estado de partida: digest `sha256:2cd5cc75…`, `traefik.yml` con hash idéntico
dentro y fuera del contenedor (`062bd7dc…`, sin modificar).

| # | Prueba | Resultado |
|---|---|---|
| V1 | `ss -tlnp \| grep :8080` | `LISTEN 127.0.0.1:8080` únicamente |
| V2 | `curl http://localhost:8080/api/http/routers` | `200` — diagnóstico conservado |
| V3 | `curl http://192.168.127.138:8080/...` | `000` (timeout) |
| V4 | `curl http://100.64.0.1:8080/...` | `000` (timeout) |
| V5 | Los seis servicios de la Fase C | `302` los cinco con Authelia; `307` Velociraptor |
| V6 | Desde el W11: `Test-NetConnection 192.168.127.138 -Port 8080` | `False`, con ping OK |
| V7 | Desde el W11: `Test-NetConnection 100.64.0.1 -Port 8080` | `False`, con ping OK |
| V8 | Desde el W11: `Test-NetConnection 192.168.127.138 -Port 443` | **True** |

V8 es el control positivo que V5 no puede dar: V5 se ejecuta en el propio host,
donde todo es alcanzable por definición. V6 y V7 con `PingSucceeded: True`
discriminan entre «puerto cerrado» y «host inalcanzable».

El digest de Traefik no cambió al recrear.

**Sobre el `307` de Velociraptor**, que difiere de los demás: `location:
/app/index.html`, relativo y sin `WWW-Authenticate`. Es el backend redirigiendo a
su aplicación, no un redirect a `auth.oob.local`. Coherente con que Velociraptor
no lleve Authelia (ver `DECISION-velociraptor-fuera-sso.md`). Comprobado, no
supuesto.

---

## Aportación al TFM

**Un control cuyo alcance real es menor que su apariencia, y la medición que lo
delimita.** La tentación era dar por bueno el binding a loopback como «el
dashboard ya no está expuesto». La prueba desde `n8n` demuestra que sigue
estándolo para media pila del enclave. La decisión no cambia por eso —el modelo
de amenaza no cubre ese vector— pero **la afirmación defendible sí**: no es «el
dashboard está protegido», es «el dashboard no es alcanzable desde fuera del
host».

La diferencia entre las dos frases es exactamente lo que separa este documento de
un olvido, y solo se puede escribir porque se midió el caso que la decisión no
cubre. Medir únicamente lo que confirma la decisión habría producido la primera
frase, que es falsa.

**El coste de verificar recae sobre la propia herramienta de verificación.**
Endurecer el dashboard significa perder el endpoint con el que se verifica todo
lo demás. Es un caso concreto de un problema general: los controles sobre el
plano de observación degradan la capacidad de comprobar los otros controles. Aquí
se resolvió conservando el acceso local; en un entorno con modelo de amenaza más
amplio habría que construir antes la vía de diagnóstico autenticada, y solo
después cerrar la insegura.
