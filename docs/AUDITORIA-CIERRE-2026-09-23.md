# Auditoría de cierre del repositorio — 2026-09-23

**Tipo:** auditoría documental de solo lectura. No se ha modificado ningún fichero
del repositorio salvo la creación de este informe. No se ha ejecutado Docker ni se
ha consultado el sistema desplegado. No se ha leído ningún `.env`.

**Estado de partida del árbol de trabajo.** `main` en `9d69042`, con **9 ficheros
modificados sin commitear** (`README.md`, `docs/INFORME-AUDITORIA-FASE6.md`,
`docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md`, `docs/api-reconocimiento-fase8.md`,
`docs/cierre-mejora1-hook.md`, `docs/propuesta-v4.md`, `fase5-orchestrator-api/README.md`,
`fase5-velociraptor/README.md`, `fase6-iris/README.md`) y `docs/tfm/` sin seguimiento.
**La auditoría describe el árbol de trabajo tal como está en disco**, incluidas esas
ediciones pendientes. Los números de línea se refieren a esa versión.

**Única medición ejecutada:** `scripts/verify-no-secrets.sh` en modo por defecto
(`git grep` sobre ficheros versionados, solo lectura, imprime ruta y línea, nunca el
valor). Se cita en A-20.

---

## Resumen ejecutivo

- **A · Contradicciones:** 27 hallazgos (A-1 … A-27), 3 de ellos marcados como dudosos.
- **B · Estado de las fases:** 9 fases inventariadas (1, 2, 3, 4, 5A, 5B, 6, 7, 8). No falta ningún README de fase. El README raíz marca las nueve como `✅ Completada`; **3 son incoherentes** con su propio README (5B, 7, 8) y **5 lo son en parte** (1, 3, 4, 6, 2).
- **C · Deuda declarada:** 88 pendientes reconocidos por el propio repositorio, agrupados en 11 temas.
- **D · Afirmaciones por verificar contra el sistema:** 30 afirmaciones (D-1 … D-30).

Los que más importan para cerrar el desarrollo:

1. **A-1.** La aprobación por segunda persona de `/cmd/` y `/web/` del KVM **está en el workflow versionado** (commit `f2b9399`, 2026-09-13), pero ocho documentos, incluidos el README de la Fase 8 y `docs/tfm/insumos-presentacion.md`, siguen diciendo que «no está construida». Ningún documento registra que se haya verificado por comportamiento. Es la contradicción de más peso para la memoria, en las dos direcciones: o se documenta y se mide, o se retira del código.
2. **A-2.** El commit de hoy (`9d69042`) revela que la verificación HMAC de la Fase 2 **descartaba en silencio toda alerta con acentos**, mientras el README de la Fase 2, el registro de cambios y el procedimiento de prueba afirmaban que se firmaba sobre los bytes crudos. No hay registro documental del hallazgo ni de sus consecuencias sobre la «validación sobre tráfico real».
3. **A-21.** La **contraseña de administración de MongoDB está en claro en 3 ficheros versionados** (7 apariciones). El detector de secretos no la ve, y `docs/revision-credenciales-fases1-8.md` afirma que ningún secreto revisado está expuesto en git.
4. **A-3 / A-4.** El README raíz, la puerta de entrada al tribunal, describe una Fase 2 con FastAPI+PostgreSQL+Redis que según el README de la Fase 2 «nunca llegó a implementarse», webhooks de IRIS que su propia nota al pie niega, y un «Plan C con doble aprobación» que la Fase 8 declara no construible.
5. **A-6 / A-7 / A-8.** El estado de la protección del borde (Authelia delante de IRIS, Portainer, Wazuh, MinIO y MISP; consumo real de la API de IRIS) se hizo en la Fase C, pero los README de las fases 1 y 6 y la auditoría de la Fase 6 siguen describiendo el estado anterior.

---

## A. Contradicciones

> Criterio: dos sitios del repositorio incompatibles, o documentación que contradice
> al código o a la configuración versionada. Cuando el propio repositorio resuelve
> cuál es el vigente (commit o documento fechado posterior), se indica.
> Lo aceptado a conciencia está en C, no aquí.

### A-1 · Aprobación de segunda persona del KVM: documentada como «no construida», presente en el código

**Lado 1: los documentos dicen que no está construida.**
- `fase8-kvm/README.md:44-45` — «`[ ]` Flujo de solicitud de sesión con aprobación de segunda persona — diseñado (F8-D5), **no construido**. `/cmd/` y `/web/` deniegan incondicionalmente».
- `fase8-kvm/README.md:359-360` — «**No construido:** la aprobación de segunda persona […] motivo `aprobacion no implementada`».
- `fase8-kvm/README.md:104` — proxy de vídeo por subdominio «(no operativo)».
- `docs/cierre-mejora1-hook.md:3-5`, `:36` (V8 «No aplica todavía»), `:182-183`.
- `docs/diseno-hook-autorizacion.md:334-336`; `docs/webhook-kvm-hook-construccion.md:4`, `:187-188`, `:205`.
- `docs/mejora4-consola-subdominio.md:75-76`.
- `docs/tfm/insumos-presentacion.md:254` y `:385` (sin seguimiento en git, pero es la fuente de la presentación).

**Lado 2: el código y el historial dicen que sí.**
- `fase8-kvm/workflows/kvm-hook.json`: ya no contiene la cadena `aprobacion no implementada`. Incluye el nodo `Aprobacion`, una llamada HTTP a `http://localhost:5678/webhook/kvm-approval` con `username`, `devid` y `accion`.
- Commit `f2b9399` (2026-09-13 00:18): «Fase 8: aprobación de segunda persona para /cmd/ y /web/ del KVM […] verbo `!ir kvm <devid> <cmd|web> <usuario>`. Dos IR Lead conceden una ventana de 15 minutos […] Proxy /web/ operativo». Toca `fase4d-breakglass.json` (+321 líneas) y `kvm-hook.json`.
- `docs/resolucion-nombres.tsv:31` y `:42` ya declaran `zsb25f8.oob.local` como «destino del redirect de rttys tras la aprobacion del hook».

**Por qué son incompatibles:** la capacidad existe en los flujos versionados y los documentos afirman lo contrario. El commit (del 2026-09-13) es posterior al cierre del hook (2026-09-11), así que el repositorio indica que lo vigente es el código. Pero **ningún documento registra la verificación** (V8, rechazo de la autoaprobación) → ver D-1.

### A-2 · Firma HMAC «sobre los bytes crudos»: afirmada en la documentación, corregida hoy en el código

- `fase2-orquestador/README.md:173` — «**Raw Body activado** […]: el script firma los bytes exactos que envía; firmar sobre una reserialización alteraría separadores».
- `fase2-orquestador/CAMBIOS-WORKFLOW-N8N.md:103-104` — misma afirmación.
- `docs/PROCEDIMIENTO-prueba-manual-webhook.md:17-19` — «El webhook tiene `rawBody: true` y el verificador firma la cadena literal recibida».
- **Frente a** el commit `9d69042` (2026-09-23): «El nodo Code reserializaba item.body ya parseado con JSON.stringify […] Toda alerta con un acento (100% de eventos de un DC en español) se descartaba en silencio en la firma». La corrección usa `getBinaryDataBuffer(0, 'data')` en `fase2-orquestador/n8n/workflows/wazuh-alert-handler.json`.

**Por qué son incompatibles:** los tres documentos describen como hecho un comportamiento que el código no tuvo hasta hoy. El commit resuelve cuál es el correcto hoy, pero:
- no hay entrada en `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md` (la última es M-45);
- la «Validación funcional — verificado sobre tráfico real» de `fase2-orquestador/README.md:436-447` no cubría alertas con caracteres no ASCII, y el README no lo acota.

### A-3 · README raíz: arquitectura de la Fase 2 y del flujo principal

- `README.md:49` («Orquestación: FastAPI + PostgreSQL + Redis»), `:79` (`Orquestador FastAPI` en el diagrama), `:127` (`POST /wazuh/alert`), `:128` («deduplica […] mediante Redis TTL»), `:149` (Fase 2 = «FastAPI, PostgreSQL, Redis»).
  - **Frente a** `fase2-orquestador/README.md:10-11`: «El README previo describía una arquitectura basada en FastAPI, PostgreSQL y Redis […] **Esa arquitectura nunca llegó a implementarse**».
  - **Y frente al propio `README.md:193`**: «el mecanismo de deduplicación vive en memoria del proceso de n8n».
- `README.md:107` (`IRIS -->|webhooks de caso| ORC`) **frente a** `README.md:158`, la nota al pie del mismo fichero: «Ningún componente del proyecto consume webhooks salientes de IRIS […] La integración es **unidireccional**». Contradicción dentro del mismo fichero.
- `README.md:105` (`RC -->|/approve /reject| ORC`) **frente a** `fase4-breakglass-dc/README.md:50-58`: comandos `!ir run` / `!ir approve REQ-…` por webhook saliente hacia n8n.

El repositorio resuelve la primera sin ambigüedad: `fase2-orquestador/README.md` y el código (n8n) son lo vigente.

### A-4 · README raíz: Plan C «con doble aprobación» y «fallback a KVM»

- `README.md:136` — «Si RustDesk falla, se ofrece el **Plan C mediante KVM**, con doble aprobación para acciones disruptivas».
- `README.md:156` — Fase 8: «Fallback a GL.iNet KVM».
- **Frente a** `fase8-kvm/README.md:46-50`: la política de dos personas para `powerreset` «**no es construible tal como estaba enunciada**»; queda como vía de emergencia auditada a posteriori (RA-1).
- **Frente a** `fase8-kvm/README.md:57-60` y `docs/INFORME-AUDITORIA-FASE8.md:298-300`: el «fallback automático RustDesk→KVM» se marcó como `[ ]` por no implementado.

**Matiz:** la doble aprobación sí existe hoy para `/cmd/` y `/web/` (A-1). No existe para la acción disruptiva (`powerreset`), que es la que nombra el README raíz.

### A-5 · README raíz: la Fase 3 como «triage con CTI»

- `README.md:129` — «El **Triage Agent** realiza el análisis y el enriquecimiento con CTI».
- `README.md:150` — Fase 3 = «LangGraph, Ollama, triage inteligente y CTI».
- **Frente a** `fase3-agentic/README.md:26-38`: la consulta a AbuseIPDB, VirusTotal y MISP vive en la **Fase 2**; la Fase 3 «**no** habla con MISP»; `tool_format_cti_*` solo formatea.
- **Y frente a** `fase3-agentic/README.md:9-15` y `:418`: en producción se despliega el motor determinista; Ollama se descarta.

### A-6 · Consumo de la API de IRIS: «sin consumidor» frente a «n8n la consume»

**Lado «no hay consumidor»:**
- `fase6-iris/README.md:50-51` (nota «Estado de seguridad», fechada **2026-09-21**) — «P1-4, API key aprovisionada sin consumidor».
- `fase6-iris/README.md:265` — «**Ningún componente del proyecto la consume actualmente.**»
- `fase6-iris/README.md:406-410` — trabajo futuro 1: «falta implementar […] Creación de caso al abrir incidente».
- `docs/INFORME-AUDITORIA-FASE6.md:79` y `:667-671` — P1-4 «Abierto […] Tendrá consumidor cuando se implemente la automatización».
- `docs/tfm/insumos-presentacion.md:359`.

**Lado «sí se consume»:**
- `fase6-iris/README.md:19-30` (corrección «vigente desde 2026-09-13») y `:81`.
- `docs/DECISION-n8n-iris-ruta-directa.md:99-107` — «**El control que protege la llamada es la API key de IRIS** […] tiene el bitmask completo de permisos (65535)».

El mismo README se contradice: la nota del 21-09 reafirma un estado que la corrección del 13-09 dio por superado.

### A-7 · IRIS detrás de Traefik+Authelia: hecho en la configuración, «pendiente» en la documentación

- `fase6-iris/README.md:71` («Publicación restringida al tailnet (`100.64.0.1:4833`)»), `:128` (la fila del override omite el router de Traefik), `:249` (acceso por `https://iris.oob.local:4833`), `:384` («**Pendiente:** MFA en el borde vía Traefik/Authelia»), `:420` (trabajo futuro 1).
- `fase6-iris/SECURITY-NOTICE.md:192` — «Pendiente: MFA en el borde».
- **Frente a** `fase6-iris/docker-compose.override.yml:31-40`: router `iris` con `secure-headers@file,authelia@file`.
- **Frente a** `fase1-infraestructura/authelia/configuration.yml`: regla `iris.oob.local`, `two_factor`. Commit `c5faa1c` (2026-09-13, «DFIR-IRIS tras Traefik con Authelia»).
- **Frente a** `docs/HALLAZGO-headscale-politica-modo-file.md:82-83`: «El acceso a IRIS por `https://iris.oob.local` desde el navegador del W11, con Authelia + TOTP, funciona».

Lo vigente, según el commit posterior: IRIS tiene dos caminos, el 443 por Traefik con Authelia (humanos) y el 4833 en el tailnet (n8n, DECISION-n8n-iris).

### A-8 · Alcance de Authelia y exposición de puertos en la Fase 1

**Lado documentación:**
- `fase1-infraestructura/README.md:24` — `[ ]` «Extensión del middleware de autenticación al resto de servicios».
- `:42-43` — diagrama: Wazuh `:4443`, Portainer `:9443 directo`.
- `:76` — dashboard de Traefik en `:8080`.
- `:80-81` — Portainer `https://<HOST>:9443`, Wazuh dashboard `:4443`.
- `:162` — «Solo los usuarios del grupo `ir_lead` acceden a Rocket.Chat» como única regla.
- `:239-245` — tabla: Portainer, Traefik y Wazuh «❌ No» protegidos, publicados en `:9443`, `:8080`, `:4443`.
- `:270-271` — Portainer «publicado directamente en `:9443`».
- `docs/README-fase1b-authelia.md:90` («la política solo protege Rocket.Chat, el único servicio detrás de Authelia»), `:92` y `:178` («Portainer nunca estuvo detrás de Authelia»).

**Lado configuración:**
- `fase1-infraestructura/docker-compose.yml:20` (`127.0.0.1:8080`), `:37` (`127.0.0.1:9443`), `:46-52` (router `portainer.oob.local` con `secure-headers@file,authelia@file`).
- `fase1-infraestructura/wazuh/single-node/docker-compose.yml:78-81` («el 4443 se retiró en el P1-1a Fase C») y `:107-116` (router `wazuh` con Authelia).
- `configuration.yml` — 8 reglas (chat, minio, wazuh, hs, misp, iris, portainer, n8n/bg-credential).
- `docs/DECISION-dashboard-traefik.md`.

Los commits posteriores (`6b1197e`, `4de838e`, `c5faa1c`, 10-13 sep) resuelven que lo vigente es la configuración.

### A-9 · Interfaz de n8n «protegida con Authelia»

- `fase2-orquestador/README.md:378-379` — «el compose de n8n define **dos routers**: la interfaz de usuario protegida con Authelia, y el path del webhook fuera de Authelia».
- **Frente a** `fase2-orquestador/n8n/docker-compose.yml:37-48`: el router principal `n8n` (`Host(n8n.oob.local)`) **no lleva middleware**; el único con `authelia@file` es `n8n-cred` (`PathPrefix(/webhook/bg-credential)`).
- `configuration.yml` solo tiene la regla `n8n.oob.local` con `resources: '^/webhook/bg-credential.*'`.

El README describe al revés qué ruta lleva Authelia. Ver D-5.

### A-10 · Extractos de compose y pruebas de `fase7-observabilidad/README.md` desfasados

- `:95-96` — `langgraph-agent` con `ports: "8000:8000"` **frente a** `fase3-agentic/docker-compose.yml:7-11` (`expose` sin publicar; el README de la Fase 3 lo trata como hallazgo corregido).
- `:132-133` — orchestrator `"8020:8000"` **frente a** `fase5-orchestrator-api/docker-compose.yml:7` (`127.0.0.1:8020:8000`).
- `:34` y `:249-255` — dashboard en `https://<HOST>:4443` **frente a** `fase1-infraestructura/wazuh/single-node/docker-compose.yml:78-81` (4443 retirado).
- `:190-197` — prueba `collect(CollectRequest(...))` **frente a** `fase5-orchestrator-api/main.py:149-157`: `collect(request: Request)`, con verificación HMAC previa. La prueba documentada ya no puede ejecutarse así.

Parcialmente reconocido: `docs/INFORME-hallazgos-detector.md:208-216` y `:243-244` («Sincronizar los extractos […] pendiente»). Queda en A porque el README sigue afirmando el estado anterior sin marca.

### A-11 · `fase5-orchestrator-api/README.md` frente a su propio código y compose

- `:183-184` y `:234` (`8020:8000`, «Puerto publicado `8020:8000/tcp`») **frente a** `docker-compose.yml:7` (`127.0.0.1:8020:8000`).
- `:177-212` — el extracto «copia literal del fichero real» (según `docs/INFORME-P0-3.md:41`) no incluye `VELOCIRAPTOR_API_CONFIG`, `VELOCIRAPTOR_DOWNLOADS` ni los montajes de `api_client.yaml` y `downloads` **frente a** `docker-compose.yml:21-40`.
- El README no menciona la autenticación HMAC, y el `curl` sin firma de `:303-311` devolvería `400` (`main.py:49-107`, `ORCH_REQUIRE_HMAC=true` por defecto; `docs/INFORME-P0-4-implementacion.md:184`).
- `:69-76` — la estructura omite `velociraptor_client.py` y `.env.example`.
- `:340` — «MinIO publica su API (`0.0.0.0:9000`) y su consola (`0.0.0.0:9001`) sin TLS» **frente a** `fase5-velociraptor/docker-compose.yml:40-44` (9001 retirado en la Fase B, servido por Traefik).
- Residuos sin corrección puntual pese a la declaración de `:396-397`: `:274` («actualmente simulado en pruebas»), `:369` («preparado para una futura integración completa con Velociraptor Server y DFIR-IRIS»).

### A-12 · `fase5-velociraptor/README.md` y su aviso de seguridad

- `:195` — «Despliegue de Velociraptor server | 🟡 Parcial / lógico» **frente a** `:217-222` del mismo fichero y el commit `456fbf9` (recolección real por gRPC).
- `:209` — «Las dos filas marcadas `🟡 Pendiente` en la tabla anterior»: la tabla (`:193-203`) ya no tiene ninguna fila `🟡 Pendiente`.
- `:425` — «más adelante, sustituir el ZIP lógico por un artefacto real», frente a su propia sección de cierre.
- `fase5-velociraptor/SECURITY-NOTICE.md:276-278` («`incidentid` y `host` sin validar»), `:153` y `:279` («MinIO […] `0.0.0.0` […] `:9001` consola») **frente a** `fase5-orchestrator-api/main.py:134-135` (patrón desde `36d40b2`, 2026-09-03) y `fase5-velociraptor/docker-compose.yml:40-44`. El README 5A se corrigió el 2026-09-21; el aviso de seguridad no.

### A-13 · Estado de las mejoras de la Fase 8 entre documentos

- `fase8-kvm/README.md:335` — riesgo aceptado «Canal rtty cifrado sin validar certificado | […] pendiente de corrección» **frente a** `:35-38` y `:405-417` del mismo fichero (mejora 2 implementada con prueba negativa, 11 sep).
- `docs/INFORME-AUDITORIA-FASE8.md:25-29` y `:286-296` («9.2 Prueba funcional mensual ⏳», «9.3 Reescritura del README ⏳», «Validación TLS del canal rtty ⏳», «Trazabilidad del operador ⏳») **frente a** `fase8-kvm/README.md:35-55` (resueltas el 11 sep) y `docs/mejora2…`, `mejora3…`, `mejora5…`. El informe de auditoría no lleva marca de superación. Lo vigente es lo posterior (README y documentos de mejora).
- `docs/diseno-hook-autorizacion.md:3` («**Estado:** diseño cerrado, pendiente de construcción») **frente a** `:334` del mismo fichero y `docs/cierre-mejora1-hook.md:3` («construido, activo y verificado»).

### A-14 · Fase 4: casillas de estado frente a hechos posteriores

- `fase4-breakglass-dc/README.md:40` (`[ ]` Callback y registro en DFIR-IRIS) **frente a** `:130` del mismo fichero («✅ completada»).
- `fase4-breakglass-dc/README.md:41` y `docs/README-fase4-pendientes.md:136-139` — «Workflow exportado […] hoy vive solo en el volumen de n8n» **frente a** `fase4-breakglass-dc/workflows/fase4d-breakglass.json`, versionado desde `759f77f` (2026-09-12).
- `fase4-breakglass-dc/README.md:42`, `docs/README-fase4-pendientes.md:59-61` y `docs/INFORME-P1-0-correcciones.md:351-353` y `:413` — «Etiquetar `glkvm` como `tag:kvm` cuando vuelva a conectar» **frente a** `fase8-kvm/README.md:112-116`: se desactivó Tailscale en el dispositivo y **se eliminó el nodo `glkvm` de Headscale** (decisión D1). También `docs/README-resolucion-nombres.md:34`, que sigue listando `glkvm` entre los nodos de MagicDNS. Las reglas `tag:kvm` siguen en `fase4-breakglass-dc/headscale/config/acl.hujson:11` y `:24` (ver C-6).
- `docs/README-fase4-validacion.md:443` — «Verificación de integridad | Firma Authenticode» listada como trabajo pendiente **frente a** `fase4-breakglass-dc/README.md:118` y `docs/README-fase4-pendientes.md` §12 («Evaluado y descartado»).
- `docs/README-fase4-pendientes.md:180-181` — «Rotación de los secretos de la Fase 8 […] deben rotarse» **frente a** `docs/INFORME-AUDITORIA-FASE8.md:14` («1. Generación de secretos ✅ Aplicado», 4-5 sep). *Dudoso:* no se ha podido determinar si la generación del 4 de septiembre cubre los tres secretos citados.

### A-15 · (Dudoso) IP del host del enclave: 192.168.127.138 frente a 192.168.0.70

- `docs/resolucion-nombres.tsv:41` y `docs/README-resolucion-nombres.md:24` y `:101`: el puesto `w11` debe resolver `kvm.oob.local` → **`192.168.127.138`** («la interfaz del enclave donde escucha Traefik»). Mismo valor en `DECISION-dashboard-traefik.md:117-122` y `HALLAZGO-headscale…:59`.
- `fase8-kvm/README.md:130-131`: «En cada equipo de analista […] `192.168.0.70 kvm.oob.local`»; `:118-119`: el break-glass KVM se ejecuta «desde un equipo en `192.168.0.0/24`». También `docs/revision-credenciales-fases1-8.md:62` (`ssh … jose@192.168.0.70`) y `fase8-kvm/glkvm-cloud/docker-compose/docker-compose.override.yml:14-15`.

**Por qué es dudoso:** ambas IPs pueden pertenecer al mismo host con dos interfaces, pero **ningún documento del repositorio lo declara**. Las dos instrucciones de `hosts` para el mismo nombre en el puesto de analista no coinciden. Ver D-4.

### A-16 · `README-resolucion-nombres.md`: el W11 «no resuelve MISP», pero lo declara

- `docs/README-resolucion-nombres.md:107-109` («El puesto de analista (`w11`) **no** resuelve `traefik`, `portainer`, `wazuh` ni `misp`») y `:151-159` («`misp.oob.local` no se declara en el puesto de analista. Es una decisión»).
- **Frente a** `:99` del mismo fichero y `docs/resolucion-nombres.tsv:47` (`w11 misp.oob.local 192.168.127.138`, «Única ruta a la UI de MISP»), añadida en la sesión de `docs/REGISTRO-HALLAZGOS-P1-1a-FaseC-2026-09-12.md:16`.

### A-17 · Hardware y tiempo de espera del motor de triage

- `fase2-orquestador/README.md:338` («**32 vCPU**, sin GPU») y `:343` (`hybrid` «~50 s») **frente a** `fase3-agentic/README.md:228` («1 socket × **16 vCPU**», ejecución del 26 de agosto) y `:264` (p50 56,5 s). La propia Fase 3 explica que 32 vCPU (8×4) era la topología inicial, descartada, así que el repositorio resuelve a favor de la Fase 3.
- `fase3-agentic/README.md:596` — «aceptable con 32 vCPU» **frente a** `:228` del mismo fichero.
- `fase3-agentic/README.md:480` — `OLLAMA_TIMEOUT_SECONDS` por defecto `45` (coincide con `app/config.py:44`) **frente a** `fase3-agentic/docker-compose.yml:20` (`${OLLAMA_TIMEOUT_SECONDS:-60}`): el valor efectivo sin `.env` es 60. Ver D-11.

### A-18 · `fase3-agentic/README.md`, contradicciones internas y referencia rota

- `:612` (`[x]` «Ejecución del banco y volcado de resultados») **frente a** `:617` («Próximos pasos: 1. Ejecutar el banco y completar Resultados»); `:618-623` enumera como próximas las fases 4 a 6, ya cerradas.
- `:578` — `< bench/una_alerta.json`: el fichero no existe en el repositorio (en `bench/` solo hay los dos corpus, `replay_alerts.py` y `resultados/`).

### A-19 · Fase 1: deuda declarada que ya no es tal, y plantilla `.env.example`

- `fase1-infraestructura/README.md:276` — «`authelia/users_database.yml` **está versionado** […] Debe retirarse con `git rm --cached`» **frente a** `git ls-files`: no está versionado; retirado en `4417467` (2026-08-20).
- `fase1-infraestructura/README.md:278` — «Middleware `secure-headers` definido pero no aplicado» **frente a** `fase1-infraestructura/docker-compose.yml:49` (aplicado en Portainer) y los compose de MinIO, Velociraptor, IRIS y Wazuh.
- `fase1-infraestructura/.env.example` (`ROCKETCHAT_VERSION=6.12.0`, `ENCLAVE_DOMAIN=oob.tudominio.com`) **frente a** `fase1-infraestructura/README.md:95` y `:107` (`oob.local`, `8.4.1`) y `docs/README-fase1c-mongodb-rocketchat.md:9` (8.4.1). Además, el dominio está fijado como `oob.local` en `traefik/dynamic/middlewares.yml:13` y en `configuration.yml`: la plantilla no reproduce el despliegue.
- `docs/revision-credenciales-fases1-8.md:163-175` (§4.4: el `.env.example` «trae valor en las doce variables», «Vaciar esos campos es trabajo de cinco minutos») **frente al** fichero actual: las cinco variables sensibles están vacías (`d64d2d5`, 2026-09-11). Resuelto por el commit; el documento no lo refleja.

### A-20 · Estado del detector de secretos: «0 hallazgos» documentado, `exit 1` medido

- `docs/INFORME-hallazgos-detector.md:190-195` y `:357-363`, y `docs/INFORME-CIERRE-P0-1-P0-2.md:280-286`: «`OK: 0 hallazgos` […] `exit 0`».
- **Ejecución de hoy** de `./scripts/verify-no-secrets.sh`: `FALLO: 24 hallazgos sobre 1819 ficheros trackeados`, `exit=1`. Reglas `credencial-conocida`, `auth-header`, `x-token-header` y `credencial-literal`, las tres últimas añadidas después (último cambio del script en `619b41a`, 2026-09-09).
- Reparto:
  - **15 en árboles vendorizados** (`fase1-infraestructura/wazuh/`, `fase6-iris/`, `fase8-kvm/glkvm-cloud/`, `misp/misp-docker/`);
  - **6 en `docs/INVENTARIO-artefactos-huerfanos.md`**, que **cita literalmente una credencial por defecto de fábrica** (pública; tipo: contraseña por defecto de un script de importación), contra el criterio de `INFORME-hallazgos-detector.md` de «describir, no citar»;
  - 2 en `docs/README-fase1c-mongodb-rocketchat.md:307-308`: marcadores de posición en mayúsculas;
  - **1 dudoso**, `docs/README-fase4d-n8n.md:191` (cabecera `Authorization: Bearer` con un valor de 16 caracteres en minúsculas y guiones; no se ha podido decidir sin imprimirlo si es un marcador o un token real).

### A-21 · Credencial de MongoDB en claro frente a «ningún secreto expuesto en git»

- **Secreto en claro versionado** (tipo: contraseña del usuario administrador root de MongoDB; **valor no reproducido**). 7 apariciones del mismo literal en 3 ficheros:
  - `fase1-infraestructura/docker-compose.yml:91` (healthcheck);
  - `docs/README-fase1c-mongodb-rocketchat.md` (5 apariciones, incluida `:270`, `MONGO_INITDB_ROOT_PASSWORD=`);
  - `docs/README-fase1e-validacion.md:81`.

  Presente en 2 commits del historial (`git log -S`). Reconocido como deuda en `fase1-infraestructura/README.md:277`.
- **Frente a** `docs/revision-credenciales-fases1-8.md:30` («Ninguna clave ni fichero de entorno revisado está expuesto en git») y `:168-170` («Verificado que ninguno sobrevivió al `.env` real: los cinco valores sensibles difieren del ejemplo»). La revisión comparó con `.env.example`, no con el literal del healthcheck.
- **Y frente a** la cobertura que se atribuye a `scripts/verify-no-secrets.sh`: el literal no lo detecta ninguna regla (medido hoy). Ver D-3.

### A-22 · (Dudoso) «Ocho casos» de instrumentos que fallan en silencio

- `README.md:219-223` — «Ocho casos registrados en el proyecto […] → `docs/api-reconocimiento-fase8.md` §1».
- **Frente a** `docs/api-reconocimiento-fase8.md:28`: «El reconocimiento produjo **cinco** instrumentos falsos», con una tabla de cinco filas.

Dudoso porque los ocho podrían sumar casos de otros documentos (M-24, `revision-credenciales` §5, etc.), pero el enlace del README apunta a un sitio que enumera cinco, y ningún documento enumera los ocho.

### A-23 · Identificador `P0-4` con dos significados

- Serie global: `docs/INFORME-P0-4-implementacion.md` (HMAC del orchestrator), citado en `fase5-orchestrator-api/README.md:339`, `:352`, `:362` y `:426`.
- Serie local: `docs/INFORME-AUDITORIA-FASE8.md:120` («**P0-4 · Plano de control del fabricante ACTIVO**»), citado en `docs/api-reconocimiento-fase8.md:251` y `:398`, y `docs/mejora6-endurecimiento-dispositivo.md:105`.

No figura en el inventario de colisiones de `docs/revision-workflow1-caso-iris-warroom.md` §P4 (`:424-505`), que cubre `P1-6`, `P0-3`, `P1-4`, `P1-1` y `F8`.

### A-24 · Etiquetas de git citadas que no existen

- `docs/README-fase1a-traefik-portainer.md:333` («Commit en Git con tag `fase1a-ok`»), `docs/README-fase1e-validacion.md:191` (tag `fase1a`) y `docs/README-fase2a-n8n.md:105` («tag fase2-orquestador»).
- **Frente a** `git tag`: `fase1-base fase1b fase1c fase1d fase2a fase2bcd`.

### A-25 · Referencias cruzadas rotas

- `PLAN-P1-1a-borde-tls.md`, citado como documento que las decisiones modifican, **no existe en el repositorio**: `docs/DECISION-dashboard-traefik.md:5`, `docs/DECISION-p0-6-pospuesto.md:30`, `docs/DECISION-velociraptor-fuera-sso.md:5`. Tampoco se cita como fichero local no versionado.
- `docs/DECISION-p0-6-pospuesto.md:63` — «F4, sección de Excepciones del README de resolución de nombres»: esa sección no tiene etiqueta F4 (ya señalado en `revision-workflow1…:486-489`, sin corregir).
- `fase2-orquestador/README.md:398` (`cp .env.example .env` en `n8n/`) y `:520` (estructura): `fase2-orquestador/n8n/.env.example` **no existe** y nunca se ha versionado.
- `docs/README-fase1a-traefik-portainer.md:340` — el texto del enlace dice `docs/fase1b-authelia.md` (no existe), aunque el destino (`README-fase1b-authelia.md`) es correcto. Menor.

### A-26 · `fase2-orquestador/n8n/README.md` describe el estado de mayo

- `:77-79` — los tres workflows «⏳ Pendiente» **frente a** `fase2-orquestador/README.md:17-27` (todo `[x]`).
- `:29` — «Editar docker-compose.yml y sustituir `N8N_ENCRYPTION_KEY`» **frente a** `n8n/docker-compose.yml:6-7` (`env_file: .env`).
- `:69` — `#alertas`, frente al flujo `#general` más `#inc-*` de `fase2-orquestador/README.md:355-369`.

### A-27 · Comentarios de configuración que describen otro estado (menores)

- `fase1-infraestructura/traefik/traefik.yml:52` — «SIN certificatesResolvers — Traefik usará self-signed automáticamente» **frente a** `traefik/dynamic/tls.yml` (certificado por defecto de la CA del enclave).
- `fase1-infraestructura/docker-compose.yml:69` y `:72` — «se resuelve a: Host(`auth.local`)» y «SIN certresolver → Traefik usa self-signed automático», frente a `oob.local` y la CA del enclave.
- `fase1-infraestructura/traefik/tls.yml` duplica `traefik/dynamic/tls.yml` y **no lo monta ningún volumen** (`docker-compose.yml:23-26` solo monta `traefik.yml` y `dynamic/`): fichero huérfano.
- `fase3-agentic/docker-compose.yml:28-29` — el mismo montaje `../fase7-observabilidad/shared:/app/shared:ro` aparece dos veces.
- `fase2-orquestador/README.md:169` (`NODE_FUNCTION_ALLOW_BUILTIN=crypto`) frente a `n8n/docker-compose.yml:15` (`crypto,fs`).

### Nota sobre `docs/tfm/insumos-presentacion.md` (sin seguimiento en git, fuente de la presentación)

Fechado el 2026-09-20. Arrastra varias afirmaciones que el repositorio ya supera:
- `:218` (workflow 4d «vive solo en el volumen») → A-14;
- `:254` y `:385` (segunda persona «no construida») → A-1;
- `:359` (P1-4) → A-6;
- `:366` (RA-6 «Abierto / Sin remediar»; en `fase8-kvm/README.md:492-506` figura como riesgo **aceptado**);
- `:369` (override de MISP «no confirmado si se aplicó»; versionado en `f818663`, 2026-09-12);
- `:373` (`incidentid`/`host`, corregido el 2026-09-21);
- `:282` y `:451` («Comparar Hash» pendiente; corregido el 2026-09-21 en los README de la Fase 5);
- `:181`: atribuye al README raíz la expresión «el argumento central de la tesis», que no está en `README.md`, sino en `docs/INFORME-AUDITORIA-FASE6.md:750`.

No se numeran aparte porque cada punto está cubierto por otro hallazgo o es una atribución de cita. Conviene regenerar o anotar el fichero antes de usarlo.

---

## B. Estado de las fases

| ID | Fase · directorio | Estado en README raíz | Estado en su README | Evidencia en el repositorio | ¿Coherente? |
|---|---|---|---|---|---|
| B-1 | 1 · `fase1-infraestructura/` | ✅ Completada | Checklist 10/12 `[x]`; sin etiqueta global. Subfases 1a-1e «✅ Completada» (mayo) | Las dos `[ ]` (`:24`, `:25`) están hechas en parte: Authelia se extendió a 7 servicios más (A-8); los backends siguen sin certificado de la CA (`insecureSkipVerify` global, C-1). Commits hasta el 2026-09-13 | **Parcial.** La casilla `:24` está desactualizada; la `:25` sigue abierta |
| B-2 | 2 · `fase2-orquestador/` | ✅ Completada («FastAPI, PostgreSQL, Redis…») | Checklist 11/13 `[x]`; `[ ]` `allowUnauthorizedCerts` MISP y métricas | La descripción del README raíz no corresponde (A-3). Corrección HMAC de hoy (`9d69042`, A-2) | **Parcial.** Coherente en sustancia con su README; incoherente con la fila del README raíz; la «validación sobre tráfico real» no cubría alertas no ASCII hasta hoy |
| B-3 | 3 · `fase3-agentic/` | ✅ Completada («triage inteligente y CTI») | «Resultado de la fase» explícito: determinista desplegado, LLM descartado. Checklist 8/9 (`[ ]` rol de métricas) | Banco ejecutado (`bench/resultados/`, 26 ago). «Próximos pasos» desfasados (A-18) | **Parcial.** La fase está cerrada; el README raíz le atribuye CTI (A-5); el rol de métricas sigue abierto (C-2) |
| B-4 | 4 · `fase4-breakglass-dc/` | ✅ Completada | Checklist 8/11; `[ ]` IRIS, `[ ]` export del workflow, `[ ]` `tag:kvm` | Workflow versionado (`759f77f`); IRIS contradictorio en el propio README (`:40` frente a `:130`); `tag:kvm` obsoleto por D1 (A-14) | **Parcial.** Las tres casillas abiertas están desactualizadas u obsoletas; la validación 9/9 + 5/5 + 11/11 es consistente con `README-fase4-validacion.md:20-24` |
| B-5 | 5A · `fase5-orchestrator-api/` | ✅ Completada | Checklist 9/9 `[x]`; tabla de limitaciones: 1 `🔴 Pendiente` (versionado del bucket) | Recolección real (`456fbf9`), enlace IRIS (Etapa D, caso #62), HMAC (`36d40b2`). README con residuos del estado de junio (A-11) | **Sí**, con deuda declarada (C-4) y documentación técnica desfasada |
| B-6 | 5B · `fase5-velociraptor/` | ✅ Completada | Tabla §8: «Despliegue de Velociraptor server 🟡 **Parcial / lógico**»; §«Resultado alcanzado» describe todavía el ZIP lógico | La sección de cierre del mismo README y `456fbf9` indican recolección real | **No.** El README declara la fase parcial en su tabla de estado y cerrada en su sección de cierre (A-12) |
| B-7 | 6 · `fase6-iris/` | ✅ Completada («integración unidireccional») | «Implementado y validado» + lista «No implementado» con 4 `[ ]`; nota de seguridad del 2026-09-21 | Creación de caso y evidencia automatizadas (n8n), Authelia en el borde (`c5faa1c`). P1-4 «sin consumidor» contradicho (A-6, A-7) | **Parcial.** El alcance declarado es correcto; el estado de seguridad y automatización tiene afirmaciones incompatibles dentro del mismo README |
| B-8 | 7 · `fase7-observabilidad/` | ✅ Completada («OpenSearch Dashboards y pipeline de métricas») | Checklist 5/6; `[ ]` métricas avanzadas | Solo 2 ficheros versionados (`README.md`, `shared/metrics_client.py`). **No hay** exportación del dashboard (objetos guardados), ni el CSV sintético, ni `import_fase7_metrics.py` (solo en la caché de VMware, `INVENTARIO…:200-205`). El acceso documentado (`:4443`) ya no existe (A-10). El README raíz declara «No calculable» 5 de las 8 métricas objetivo | **No.** «Completada» no es sostenible con lo versionado: el entregable no es reproducible desde el repositorio y su vía de acceso documentada está cerrada |
| B-9 | 8 · `fase8-kvm/` | ✅ Completada («Fallback a GL.iNet KVM, autorización por dispositivo…») | «Operativo y verificado» (8 `[x]`) + «Mejoras previstas» con `[ ]` segunda persona e `[ ]` integración IRIS/Rocket.Chat | La segunda persona está en el código (A-1); el fallback automático no está implementado (A-4); la integración con IRIS/Rocket.Chat solo existe a través del verbo `!ir kvm` de 4d | **No** en la fila del README raíz («Fallback», A-4); **parcial** en el propio README (A-1, A-13) |

**Notas.**
- **B-10 · README de fase.** Todas las fases tienen README en su carpeta. La Fase 5 se reparte en dos carpetas (5A y 5B) de forma deliberada y documentada (`README.md:142`, `docs/fase5-links.md`). No falta ningún README.
- **B-11 · Estado declarado.** Ningún README de fase usa una etiqueta única «completada / en curso / pendiente» salvo en las subfases de `docs/` y en el README raíz. El estado se infiere de checklists y tablas, lo que produce las casillas desfasadas de B-1, B-4 y B-9.
- **B-12 · Documentos históricos correctamente marcados** (no son incoherencias): `docs/propuesta-v4.md` (nota del 2026-09-21), `docs/propuesta_tfm_alerta_temprana_v3.md`, `docs/README-fase4d-n8n.md`, `docs/README-fase4e-rustdesk-breakglass.md`, `docs/README-fase1a…` (aviso sobre ACME), `docs/README-fase2bcd/2e/2f` (aviso de validación sintética y nodo huérfano), `docs/revision-workflow1-caso-iris-warroom.md` (cabecera «parcialmente refutado»), `docs/DECISION-p0-6-pospuesto.md` (cabecera de cierre).

---

## C. Deuda declarada y pendientes reconocidos

> Todo lo de esta sección lo reconoce el propio repositorio. Es material para
> «Limitaciones y trabajo futuro». Entre paréntesis, dónde se declara.

### C-1 · Borde TLS y exposición de red
1. `insecureSkipVerify: true` global en Traefik, sin ámbito, para los 11 routers (P1-1f) (`REGISTRO-HALLAZGOS-P1-1a-FaseC…:130-164`; `fase1-infraestructura/README.md:269`; `fase2-orquestador/README.md:471`).
2. `wazuhtransport` declarado y aplicado a nada (`REGISTRO-HALLAZGOS…:146-152`; `revision-credenciales…:201`).
3. `allowUnauthorizedCerts` en el nodo MISP de n8n; el certificado de MISP es `CN=localhost` (`fase2-orquestador/README.md:28`, `:470`, `:537`; `REGISTRO-HALLAZGOS…:159-162`).
4. La API del dashboard de Traefik es alcanzable sin autenticación desde cualquier contenedor de `oob-network` (`DECISION-dashboard-traefik.md:56-82`).
5. `docker.sock` montado en Traefik y Portainer (`fase1-infraestructura/README.md:272`).
6. MinIO API `:9000` sin TLS, «se trata en el P1-1b» (`fase5-velociraptor/docker-compose.yml:42-43`).
7. Indexer `0.0.0.0:9200` y API de Wazuh `0.0.0.0:55000` con certificado de fábrica `CN=wazuh.com` (`revision-credenciales…:144-159`).
8. `BASE_URL` de MISP apunta al puerto directo 12443; `template.env` sin la línea (`REGISTRO-HALLAZGOS…:97-128`).
9. Velociraptor fuera del SSO: un solo usuario `admin`, Basic, sin 2FA; OIDC identificado y pospuesto (`DECISION-velociraptor-fuera-sso.md:271-290`).
10. KVM nivel 1 fuera de Authelia; la ruta sigue dependiendo de Docker, Traefik y el DNS del enclave (`README-resolucion-nombres.md:171-180`).
11. OIDC Authelia↔Rocket.Chat como trabajo futuro (`fase1-infraestructura/README.md:181`).
12. Frontend de agentes de Velociraptor (`:8001`) y colección forense por el segmento corporativo, no por el canal OOB (`README-resolucion-nombres.md:143-149`).

### C-2 · Credenciales y secretos
13. Contraseña de MongoDB en el `healthcheck` (`fase1-infraestructura/README.md:277`) — y ver A-21.
14. Métricas escritas con la cuenta `admin` del indexador; rol `tfm_metrics_writer` solo planificado y la contraseña anterior se considera comprometida (`fase3-agentic/README.md:613`; `fase3-agentic/docs/rotacion-credenciales-metricas.md:3-6`, `:183-194`; `.env.example` con `OS_USER=admin`; `fase5-orchestrator-api/docker-compose.yml:27`).
15. API key de IRIS con bitmask completo (65535); usuario de API dedicado pendiente (`DECISION-n8n-iris-ruta-directa.md:104-107`).
16. Token del GL-RM1 volcado en claro en `/home/rttys.conf`: rotación «a decidir», P1-6 (GL-RM1) (`cierre-mejora1-hook.md:215-220`).
17. `AGENT_TOKEN` legible en el registro de Windows (`README-fase4-pendientes.md:162-167`).
18. Agente DC como `LocalSystem`; gMSA pendiente (`fase4-breakglass-dc/README.md:117`; `README-fase4-pendientes.md:157-160`).
19. Usuario operativo dedicado de Wazuh evaluado y no implementado (`README-fase1d-wazuh.md:270-292`).
20. `N8N_BLOCK_ENV_ACCESS_IN_NODE=false`: todas las variables, incluida `N8N_ENCRYPTION_KEY`, visibles para cualquier nodo Code (`fase2-orquestador/README.md:472`).
21. Rotación de `N8N_ENCRYPTION_KEY` con ventana de exposición (`fase2-orquestador/README.md:487`).
22. `S01selfCloud` guarda `TOKEN` y `WEBRTC_PASSWORD` en claro; el token es visible en `/proc/<pid>/cmdline` (RA-5) (`fase8-kvm/README.md:500-510`).
23. La CA del enclave se distribuye a mano; sin renovación automática (`README-fase4-pendientes.md:70-73`, `:87-88`).
24. Caducidades anotadas: Velociraptor 2027-09-01 (`validity_days: 730` sin efecto), API de Wazuh 2027-05-16, MISP 2027-05-24, TLS de IRIS 2028-12-05 (`fase5-velociraptor/SECURITY-NOTICE.md:112-119`; `revision-credenciales…:90`, `:147-154`; `INFORME-CIERRE-P0-1-P0-2.md:320-322`).
25. Preauthkeys sin inventariar / usuario `kvm-devices` huérfano (`README-fase4-pendientes.md:68-69`).

### C-3 · Orquestación (n8n)
26. Deduplicación en memoria, se pierde al reiniciar; ventana fija (`fase2-orquestador/README.md:477-481`).
27. El webhook en modo `onReceived` responde 200 antes de verificar la firma (`fase2-orquestador/README.md:490-494`; M-21 en `REGISTRO-MEDICIONES…:656`).
28. Hay que reasignar a mano las credenciales al importar (`fase2-orquestador/README.md:414-415`, `:486`).
29. `export-workflow.sh` debe sanear `parameters` y `staticData` (M-5, M-36, M-41, M-43; `REGISTRO-MEDICIONES…:1364`).
30. M-15: `misp_threat_level` y `misp_attributes_summary` viajan vacíos al triaje (`REGISTRO-MEDICIONES…:942-944`).
31. `abuse_disponible` no llega al motor determinista (`REGISTRO-MEDICIONES…:1493-1497`).
32. `rule_desc` interpolado en crudo en el JSON de `Anuncio en General` (`REGISTRO-MEDICIONES…:953-958`).
33. Síntoma «tres alertas en `#general`» sin causa identificada (`REGISTRO-MEDICIONES…:945-952`).
34. `ALTA`/`MEDIA`/`BAJA` → `severity_id` sin confirmar (`REGISTRO-MEDICIONES…:938-941`).
35. Flujo auxiliar `echo` sin autenticación en `oob-network` (`cierre-mejora1-hook.md:207-208`; `REGISTRO-HALLAZGOS…:269-271`).
36. Guardado de ejecuciones con la cookie del operador en la base de n8n (`cierre-mejora1-hook.md:196-199`).
37. Enlace de credencial no clicable; «desde .» en los mensajes (`README-fase4-pendientes.md:140-145`).
38. «Nueve servicios» con `:latest` sin anclar por digest (`fase2-orquestador/README.md:501`, `:541`; Authelia y Portainer en `fase1-infraestructura/README.md:83`, `:279`; `minio/minio:latest` en `fase5-velociraptor/SECURITY-NOTICE.md:280`).

### C-4 · Evidencia forense (Fase 5)
39. Bucket `evidence` sin versionado ni bloqueo de objetos: la sobrescritura es posible (`fase5-orchestrator-api/README.md:351`, `:361`; `fase5-velociraptor/SECURITY-NOTICE.md:268-275`).
40. Orchestrator como root (M-19); validación del SO del cliente contra el perfil (M-20); `.dockerignore` (M-18) (`REGISTRO-MEDICIONES…:646-652`).
41. «Añadir validación de integridad de evidencias» (`fase5-orchestrator-api/README.md:363`).
42. M-27: un campo mal nombrado da de alta una evidencia sin hash con HTTP 200 (`REGISTRO-MEDICIONES…:984`).
43. Anti-replay de nonces en memoria de un solo proceso, sin cota de tamaño; el patrón de `source` está por revisar (`INFORME-P0-4-implementacion.md:204-229`).

### C-5 · Triage e IA (Fase 3)
44. El saneado no cubre la inyección semántica: «ninguno de los dos protege al analista» (`fase3-agentic/README.md:181-186`, `:403-407`, `:595`).
45. El margen del guardrail `MAX_SEVERITY_DOWNGRADE=1` es explotado por 6/10 vectores (`fase3-agentic/README.md:372-383`).
46. Factor de confusión del prompt («prefiere la severidad más alta») sin aislar (`:298-304`).
47. Un único modelo (Mistral 7B); LLM remoto como sujeto de laboratorio pendiente (`:460-466`).
48. Hilo de inferencia huérfano al agotar el tiempo (`:596`).
49. Sin evaluación de precisión frente a un analista humano (`:599`; `README.md:194`).

### C-6 · Plano de control del tailnet (Headscale)
50. La política en modo `file` no es consultable ni recargable; solo el netmap la revela (`HALLAZGO-headscale-politica-modo-file.md` §1; «el mecanismo sigue igual», `:6`).
51. El bloque `tests:` desapareció de la ACL; hay que medir si `policy check` lo ejecuta (`HALLAZGO…:179-208`). Confirmado: `acl.hujson` no tiene `"tests"`.
52. El comentario de `acl.hujson:4` sigue recomendando `policy check` (`HALLAZGO…:37-39`).
53. Reglas `tag:kvm` sin ningún nodo (código muerto) (`INFORME-P1-0-correcciones.md:345-353`, `:413-414`; `HALLAZGO…:173-175`).
54. El plano de control viaja por la red corporativa (`fase4-breakglass-dc/README.md:116`; `README-fase4-pendientes.md:64-68`).
55. Sin monitorización de disponibilidad del tailnet (`README-fase4-pendientes.md:62-63`).
56. El agente Wazuh del DC reporta por la red corporativa (`README-fase4-pendientes.md:168-174`; `README-fase4-validacion.md:395-404`).
57. «Rocket.Chat por el tailnet — pendiente de verificar ahora que la regla existe» (`HALLAZGO…:141-143`).

### C-7 · DFIR-IRIS
58. Sincronización bidireccional; evidencias de RustDesk y KVM; cierre de caso con revocación de accesos; volcado de `agent_reasoning` (`fase6-iris/README.md:82-86`, `:406-413`).
59. P1-7: la aplicación corre como root (riesgo aceptado) (`fase6-iris/README.md:375-380`; `INFORME-AUDITORIA-FASE6.md:600`).
60. P1-8: `SECURITY_PASSWORD_SALT` se carga pero no se consume (`INFORME-AUDITORIA-FASE6.md:626`).
61. `verify-fase6.sh` es manual, sin hook ni CI (`fase6-iris/README.md:55-59`).

### C-8 · KVM (Fase 8)
62. RA-1 a RA-6: nivel 2 sin gobierno, cookie cruzando el bridge, vale de sesión persistente, SSH root con contraseña, token en `cmdline`, oráculo `/same_check` (`riesgos-aceptados-hook-nivel1.md`; `fase8-kvm/README.md:326-336`, `:492-506`).
63. Segundo factor de kvmd (P2-9); `ntpd` en `0.0.0.0:123`; `/same_check` por el puerto 80; rotación del syslog; `S99cloudflare`/`zerotier`/`netbird` inertes por falta de fichero; `docker save` de la imagen (`fase8-kvm/README.md:512-527`; `mejora6-endurecimiento-dispositivo.md` §9).
64. Paginación de `/api/devices`; C5, alcance real de RA-2 (`cierre-mejora1-hook.md:184-195`).
65. Divergencia de `rttys.conf.template` respecto al upstream sin registrar (`cierre-mejora1-hook.md:201-204`). Según git, el fichero se modificó en `a214052`; el registro como divergencia no se encuentra.
66. Cerrar las sesiones con `sid` expuesto y borrar ficheros temporales (`cierre-mejora1-hook.md:205-206`).
67. `glkvm-cloud/docker-compose/README.md:14` manda copiar un `.env.example` que no existe (`INFORME-AUDITORIA-FASE8.md` §6, 9.4). Confirmado: solo existe `.env.arm64.example`.
68. Consola por subdominio: obligatoria si se añade un segundo KVM (`fase8-kvm/README.md:448-450`).
69. Prueba mensual de resiliencia: solo consta la primera ejecución (11 sep) (`mejora5-prueba-mensual-resiliencia.md:3-4`, `:72-77`); no cubre la pérdida del host (`:221`).
70. Alertas de la sonda solo en cambio de estado y rotación de su log (`INFORME-AUDITORIA-FASE8.md:282`).
71. Las denegaciones del hook no dejan rastro (`fase8-kvm/README.md:429-431`).

### C-9 · Observabilidad y métricas
72. MTTA, MTTApprove, MTTAccess, Dedup rate y False positive rate no calculables por falta de instrumentación (`README.md:187-196`; `fase7-observabilidad/README.md:17`, `:261`, `:266`; `docs/tfm/metricas-calculadas.md` §5).
73. Mapping explícito para `tfm-metrics-events`, porque `incident_id.keyword` es inestable (`fase7-observabilidad/README.md:259`, `:265`).
74. Capturas o exportación del dashboard para los anexos (`fase7-observabilidad/README.md:268`).
75. Mezcla indistinguible de datos reales y sintéticos en el índice (`docs/tfm/metricas-calculadas.md:191`).
76. `metrics_client.py` con `CERT_NONE` («SSL sin validación estricta para el laboratorio») (`fase7-observabilidad/README.md:45`).
77. Script de carga y CSV sintético no versionados; el script tiene una contraseña por defecto que hay que corregir antes de rescatarlo (`INVENTARIO-artefactos-huerfanos.md:200-206`, `:263-264`).

### C-10 · Método, documentación y controles del propio repositorio
78. Colisiones de identificadores (`P1-6` ×4, `P0-3`, `P1-4`, `P1-1`, `F8`) sin índice central; se desambigua por documento de origen (`REGISTRO-HALLAZGOS…:230-254`; `revision-workflow1…:424-505`). Se añade `P0-4` (A-23).
79. `verify-no-secrets.sh` y `verify-fase6.sh` sin CI ni hook de pre-commit (`INFORME-hallazgos-detector.md:246-249`).
80. Prueba negativa de `verify-hosts.sh --check-doc` diseñada y «Sin ejecutar: pendiente» (`docs/pruebas/negativa-check-doc.md:115-121`).
81. `--check-doc` no verifica las columnas de texto (`README-resolucion-nombres.md:72-75`).
82. Declarar el «tercer sujeto» de resolución (los contenedores) y la convención de nombres (`DECISION-n8n-iris-ruta-directa.md:88-98`; `REGISTRO-MEDICIONES…:398-404`).
83. Sin «plan de pruebas E2E», sin «batería de negativas» y sin «escenario R2» como documentos formales (`docs/tfm/insumos-presentacion.md:265`, `:286`, `:307`, `:437-446`).
84. Sin justificación comparativa escrita de la elección de Wazuh, IRIS, Velociraptor, MinIO, Traefik, Authelia, Rocket.Chat, RustDesk y GL.iNet (`insumos-presentacion.md:143-157`).
85. `DECISION-velociraptor` y `DECISION-dashboard` dependen de premisas de modelo de amenaza escritas («un contenedor comprometido en `oob-network` no está en el modelo») (`DECISION-dashboard-traefik.md:71-82`).
86. Síntesis de la Fase 3 (`DECISION-fase3.md`, `RESULTADOS-fase3.md`) solo en la caché de VMware, con recomendación de rescatarla (`INVENTARIO…:190-198`).
87. Tres ficheros Python de otro proyecto posible en la caché, a revisar (`INVENTARIO…:157-166`).
88. Limitaciones de validez: laboratorio no continuo; tráfico de ataque real casi inexistente; el 71 % del volumen es el enclave vigilándose a sí mismo (M-24, `REGISTRO-MEDICIONES…:777`; `insumos-presentacion.md:320-325`).

---

## D. Afirmaciones que requieren verificación contra el sistema

> Criterio del proyecto: **nada se da por bueno si no se ha medido por comportamiento;
> leer un fichero de configuración no es verificar.** Ninguna de estas se ha
> comprobado en esta auditoría.

| ID | Afirmación (dónde) | Qué medir para confirmarla |
|---|---|---|
| D-1 | La segunda persona del KVM funciona para `/cmd/` y `/web/` (commit `f2b9399`; `kvm-hook.json`, nodo `Aprobacion`) | Sin ventana: `/cmd/<devid>` → 403. Con `!ir kvm` aprobado por **otro** IR Lead: 200 dentro de 15 min y 403 al caducar. **V8:** la autoaprobación es rechazada. Repetir con n8n parado (debe dar 403) |
| D-2 | La verificación HMAC acepta alertas con acentos y sigue rechazando firmas inválidas tras `9d69042` (el mensaje del commit cita las ejecuciones 2199 y 2243 y el caso #91) | Alerta no ASCII bien firmada → caso; la misma alerta con la firma alterada → rechazo. Control negativo registrado |
| D-3 | El literal del healthcheck de MongoDB es la contraseña vigente (A-21) | `docker inspect` del estado de salud de `mongodb` (healthy o unhealthy) **sin imprimir el valor**; si está healthy, el literal versionado es la credencial en uso y procede rotarla |
| D-4 | El host del enclave tiene 192.168.127.138 y 192.168.0.70 (A-15) | `ip -4 addr` en el host; `hosts` real del W11 para `kvm.oob.local`; alcance a `https://kvm.oob.local` desde el W11 |
| D-5 | La interfaz de n8n está (o no) detrás de Authelia (A-9) | `curl -I https://n8n.oob.local/` sin sesión desde el W11 y desde el host: ¿302 a `auth.oob.local` o 200? |
| D-6 | Authelia protege chat, minio, wazuh, hs, misp, iris y portainer (`configuration.yml`) | Sin sesión, cada `https://<servicio>.oob.local/` → 302 a `auth.oob.local`; más un control negativo con `noexiste.oob.local` → 404 (método de `REGISTRO-HALLAZGOS…` §2) |
| D-7 | Puertos cerrados o limitados: 4443, 9001, 8889, 12443 y 1280 cerrados; 8080, 9443 y 8020 solo en loopback | `ss -tlnp` en el host y `Test-NetConnection` desde el W11 (controles positivo y negativo, como en `DECISION-dashboard-traefik.md` V1-V8) |
| D-8 | `9000`, `9200`, `55000` y `8001` siguen publicados en `0.0.0.0` (C-1) | `ss -tlnp`; decidir si entran en la memoria como riesgo aceptado |
| D-9 | IRIS solo escucha en `100.64.0.1:4833`, MFA activo y 16 comprobaciones verdes (`fase6-iris/README.md:174-191`) | `./scripts/verify-fase6.sh` con exit 0 tras un reinicio en frío (criterio de aceptación de la propia fase) |
| D-10 | `langgraph-agent` no publica puerto y corre en modo `deterministic` | `docker port langgraph-agent` vacío; `/health` → `triage_mode: deterministic` |
| D-11 | Tiempo de espera efectivo de Ollama (45 frente a 60, A-17) | `docker exec langgraph-agent env` (solo la variable `OLLAMA_TIMEOUT_SECONDS`) |
| D-12 | El orchestrator exige HMAC (`ORCH_REQUIRE_HMAC=true`) | Casos 1 y 3-10 de `INFORME-P0-4-implementacion.md:182-198`: no consta en ningún documento su ejecución completa |
| D-13 | El agente DC corre con `AGENT_REQUIRE_HMAC=true` (el código tiene `false` por defecto, `agent_dc.py:35`) | Petición sin cabeceras de firma → 400 (prueba 5 de `README-fase4-validacion.md` §3.3) |
| D-14 | `iris.oob.local` → `100.64.0.1` dentro de n8n y el 4833 es alcanzable (`DECISION-n8n-iris…:129-144`) | La propia «Detección de rotura» de esa decisión: `HTTP 401` = camino sano |
| D-15 | Tabla `SEV` de ALTA/MEDIA/BAJA → `severity_id` 5/4/3 (en el workflow; `REGISTRO-MEDICIONES…:938-941` lo da por no confirmado) | Casos con severidad ALTA, MEDIA y BAJA; consultar el `severity_id` de cada caso |
| D-16 | La política ACL vigente concede `tag:analyst → tag:orchestrator:443` y deniega 4833 y 3389 | `tailscale debug netmap` en el orchestrator (`HALLAZGO…:30-34`) más `Test-NetConnection` desde el W11 |
| D-17 | El nodo `glkvm` ya no existe en Headscale (`fase8-kvm/README.md:115-116`) | `headscale nodes list` |
| D-18 | Resolución de nombres sin divergencias en los tres hosts | `verify-hosts.sh` en el Ubuntu; `--emit`/`--check` con los `hosts` **reales** de w11 y dc01 (`INFORME-P1-0-correcciones.md:393-398` solo lo hizo con muestras sintéticas); ejecutar `docs/pruebas/negativa-check-doc.md` |
| D-19 | `BASE_URL` de MISP corregido (o no) | `curl -I -H 'Host: misp.oob.local' https://127.0.0.1:12443/` → ¿`location` con `:12443`? (`REGISTRO-HALLAZGOS…:101-107`) |
| D-20 | Traefik con `api.insecure: true` alcanzable desde `oob-network` (riesgo aceptado) | Petición a `http://traefik:8080/api/http/routers` desde un contenedor (confirma el alcance que la decisión acepta) |
| D-21 | `wazuh-integratord` activo y bloque `<integration>` presente tras la última recreación | `wazuh-control status \| grep integrator`; `tail integrations.log` tras una alerta real (`fase2-orquestador/README.md:117-120`) |
| D-22 | Métricas: el índice existe, `duration_ms` es real (no 0) y `OS_USER` sigue siendo `admin` | Consultas de `docs/tfm/metricas-calculadas.md` §4; comprobar el usuario efectivo sin imprimir la contraseña |
| D-23 | Canal rtty validado con `-C` y certificado `glkvm-cloud.oob.local` en el 5912 | `openssl s_client -connect 192.168.0.70:5912 -verify_return_error` con la CA del enclave (`mejora2-tls-canal-rtty.md:61-67`) |
| D-24 | Sonda `check-kvm-lastseen.sh` en cron y en verde | `crontab -l`; ejecución con exit 0; repetir la prueba negativa (`fase8-kvm/README.md:317-322`) |
| D-25 | Flujo auxiliar `echo` borrado; sesiones rttys cerradas; `/tmp` limpio (`cierre-mejora1-hook.md:205-208`) | Listado de workflows activos en n8n; UI de rttys |
| D-26 | El workflow versionado coincide con el desplegado (4d, hook KVM y alert handler) | `export-workflow.sh` más `diff` contra `workflows/*.json` |
| D-27 | RustDesk `hbbs`/`hbbr` escuchan solo en `100.64.0.1:21115-21119` con `-k _` (`fase4-breakglass-dc/README.md:96-97`) | `ss -tlnup \| grep 2111`; `docker inspect` del comando |
| D-28 | Bucket `evidence` sin versionado y `tfm-orchestrator` sin `s3:DeleteObject` | `mc version info`; `mc admin policy info` |
| D-29 | Rocket.Chat alcanzable por el tailnet desde el W11 (`HALLAZGO…:141-143`, pendiente declarado) | `Test-NetConnection 100.64.0.1 -Port 443` y carga de `https://chat.oob.local` con `hosts` → `100.64.0.1` |
| D-30 | Autenticación de Authelia: solo TOTP (WebAuthn no configurado) y un único usuario `jose` (`README-fase1b-authelia.md:256-262`; `DECISION-velociraptor…:212`) | Portal de Authelia: métodos ofrecidos; recuento de usuarios **sin leer hashes** |

---

## Anexo: cobertura

**Universo:** 1.819 ficheros versionados más `docs/tfm/` (2 ficheros sin seguimiento).

**Excluido por ser código de terceros vendorizado** (revisado solo donde un documento propio lo cita):
- `fase1-infraestructura/wazuh/` (≈115 ficheros; wazuh-docker), salvo `single-node/docker-compose.yml`;
- `misp/misp-docker/` (≈48), salvo `.gitignore`, `template.env` y `docker-compose.override.yml` (propio);
- `fase6-iris/source`, `deploy`, `tests`, `docker` y `.github` (≈1.100; DFIR-IRIS), salvo el override, el compose, `.env.example`, `systemd/` y `SECURITY-NOTICE.md`;
- `fase8-kvm/glkvm-cloud/` (≈300; GL.iNet), salvo el override y el `README` de `docker-compose/`;
- `images/` (9 PNG, no inspeccionados).

**Ficheros propios revisados:** unos 220, entre código, configuración y scripts, más 82 Markdown (80 versionados y 2 en `docs/tfm/`).

- **Leídos completos (43):**
  - README raíz y los 9 README de fase;
  - `fase2-orquestador/n8n/README.md`;
  - `docs/`:
    - `README-fase1a`, `1b`, `1c`, `1d`, `1e`, `README-fase2a`;
    - `DECISION-*` (×4), `HALLAZGO-headscale…`;
    - `INFORME-CIERRE-P0-1-P0-2`, `INFORME-P0-3`, `INFORME-P0-4-implementacion`, `INFORME-P1-0`, `INFORME-P1-0-correcciones`, `INFORME-hallazgos-detector`;
    - `REGISTRO-HALLAZGOS-P1-1a-FaseC…`;
    - `README-resolucion-nombres.md`, `resolucion-nombres.tsv`;
    - `credenciales-de-arranque`, `revision-credenciales-fases1-8`;
    - `tfm/insumos-presentacion`, `tfm/metricas-calculadas`;
  - `fase3-agentic/docs/rotacion-credenciales-metricas.md`;
  - todos los `docker-compose*.yml` propios (fases 1, 2, 3, 5A, 5B, 6-override, 8-override, Wazuh single-node);
  - los `.env.example` propios (valores sensibles sin imprimir);
  - la configuración de Traefik (`traefik.yml`, `dynamic/*`);
  - `fase5-orchestrator-api/main.py` (líneas 1-160 y el uso de `log_event`);
  - `fase3-agentic/app/config.py`, `fase7-observabilidad/shared/metrics_client.py`.
- **Leídos parcialmente**, por secciones de estado, pendientes, cabeceras y búsquedas dirigidas:
  - Fase 4: `README-fase4-pendientes`, `README-fase4-validacion`, `README-fase4d-n8n`, `README-fase4e-rustdesk…`; `README-fase4a`, `4a-ui`, `4b`, `4c` y `4d-flujo-aprobacion` solo por búsqueda.
  - Fases 2 y 3: `README-fase2bcd`, `2e`, `2f`, `README-fase3a`, `3b`, `3c`; `CAMBIOS-WORKFLOW-N8N.md`.
  - Fase 6: `README-Fase6a`, `6b`; `INFORME-AUDITORIA-FASE6` (cuadro, P1-4 y el diff sin commitear).
  - Fase 8: `INFORME-AUDITORIA-FASE8` (§1, §6, búsquedas); `api-reconocimiento-fase8` (§1 y búsquedas); `cierre-mejora1-hook` (§1, §7, §8); `diseno-hook-autorizacion`, `webhook-kvm-hook-construccion`, `mejora2` a `mejora6`, `riesgos-aceptados-hook-nivel1` (búsquedas de estado y pendientes).
  - Registros y revisiones: `REGISTRO-MEDICIONES-n8n-iris…` (índice de secciones, §6-§7, §9 pendientes, §10 «Verificación adicional», final de M-45); `revision-workflow1…` (cabecera y §P4); `INVENTARIO-artefactos-huerfanos` (resumen, final y hallazgos del detector).
  - Resto: `PROCEDIMIENTO-prueba-manual-webhook` (cabecera); `docs/pruebas/negativa-check-doc.md` (resultado); `propuesta-v4.md` (nota histórica); `fase5-links.md`; los dos `SECURITY-NOTICE.md` e `INFORME-P0-1.md` (secciones de residuales y pendientes); `fase4-breakglass-dc/dcagent/agent_dc.py` y `README-despliegue.md` (búsquedas).
  - Workflows JSON (`wazuh-alert-handler`, `kvm-hook`): búsquedas dirigidas, no lectura completa.
- **No leídos:**
  - `docs/propuesta_tfm_alerta_temprana_v3.md` (histórico, marcado como tal);
  - el resto del código de `fase3-agentic/app/` (salvo `config.py` y el uso de métricas en `main.py`);
  - `fase3-agentic/bench/*.json`;
  - `fase4-breakglass-dc/scripts/*.ps1`, `headscale/config/config.yaml` (salvo búsqueda) y `headscale-ui/`;
  - `scripts/*.sh`, salvo la cabecera de `verify-no-secrets.sh` y las búsquedas en `verify-fase6.sh`;
  - `docs/evidencias/`.

**Fuera de alcance por las reglas de la tarea:**
- ficheros `.env` (existen, por ejemplo, en `fase1-infraestructura/`, `fase2-orquestador/n8n/` y `fase8-kvm/glkvm-cloud/docker-compose/`; no se han abierto);
- copias locales no versionadas de workflows en `fase2-orquestador/n8n/*.json`, ignoradas por `.gitignore:37`; no se han abierto;
- `fase5-velociraptor/velociraptor-config/` (estado de ejecución, no versionado; varios subdirectorios sin permiso de lectura);
- el sistema desplegado.

**Herramientas usadas:** `cat`, `grep`, `sed`, `awk`, `git log`, `git show`, `git ls-files`, `git grep`, `git tag`, `git diff`, y `scripts/verify-no-secrets.sh` en modo de solo lectura. Las búsquedas de secretos se hicieron clasificando longitud y forma del valor, sin imprimirlo.

**Limitación:** la cobertura de los documentos leídos parcialmente es por muestreo dirigido. Puede haber contradicciones internas adicionales en `docs/README-fase4*`, `REGISTRO-MEDICIONES…` y `revision-workflow1…` que esta auditoría no detecta.
