# Decisión — n8n llega a IRIS por el 4833 de la tailnet, no por el 443

**Fecha:** 2026-09-13
**Decide:** Jose Luis Rey
**Afecta a:** Workflow 1 de Fase 2 (`docs/revision-workflow1-caso-iris-warroom.md`, nodo «Crear Caso IRIS»), `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md`
**Estado del servicio:** IRIS sigue detrás de Traefik + Authelia en el 443 (Fase C, sin cambios); n8n llama en cambio al 4833 publicado en la interfaz de la tailnet.

---

## Qué se decide

n8n llama a IRIS en `https://iris.oob.local:4833/manage/cases/add`, el puerto
que el override de `fase6-iris` publica en la interfaz de la tailnet
(`100.64.0.1:4833`). No se creó ningún alias de red Docker en `oob-network`, no
se tocó el compose de fase 6, y no se añadió ninguna excepción de ruta en
Authelia.

Esto corrige un borrador previo que circuló durante la revisión del Workflow 1
y que proponía un alias de red Docker en `oob-network` para llegar
directamente al nginx de IRIS sin pasar por Traefik, con el fin de esquivar
Authelia. Esa vía nunca se implementó. Las mediciones del 2026-09-13
(`docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md`) demuestran que no hacía
falta: el 4833 de la tailnet ya era alcanzable y ya resolvía tal como estaba
desplegado desde el cierre de la Fase C.

---

## Por qué Authelia no interviene

Porque no está en ese camino de red — no porque se le esquive. Traefik
escucha en el 443 con `secure-headers@file` + `authelia@file`; el 4833 va
directo al nginx de IRIS, sin pasar por el router de Traefik en ningún punto.
La distinción importa: no se está sorteando un control puesto para proteger
este servicio, se está usando un puerto distinto que el propio proyecto
publicó en la Fase C para acceso no interactivo, sobre la misma interfaz de
tailnet que ya protege el resto del acceso remoto del enclave.

---

## Qué se midió (2026-09-13)

- `iris.oob.local` resuelve a `100.64.0.1` dentro del contenedor n8n,
  heredado del `/etc/hosts` del host vía `systemd-resolved` y el resolver
  embebido de Docker.
- `100.64.0.1:4833` alcanzable desde el contenedor; `ss -ltnp` confirma
  `docker-proxy` escuchando ahí.
- `GET /manage/customers/list` por ese puerto, con la CA del enclave y la
  API key de IRIS: `200`, sin ninguna intervención de Authelia.
- Por el 443, Authelia responde `302` a `auth.oob.local`, no `401`.

Detalle completo de comandos y salidas en
`docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md`, sección 2.

---

## Las alternativas descartadas, y con qué criterio

**Alias de red Docker en `oob-network` hacia `iriswebapp_nginx`.** Es la vía
que el borrador previo de la revisión recomendaba. Se descarta **por
innecesaria, no por defectuosa**: la medición confirmó que el 4833 de la
tailnet ya resuelve y ya es alcanzable sin tocar el compose de fase 6. Abrir
un segundo camino de red hacia IRIS habría añadido superficie sin ningún
beneficio sobre la que ya existía.

**Nombre de servicio Docker (`https://iriswebapp_nginx:4833`).** Sigue
descartada por el motivo ya documentado en la revisión: el CN del
certificado de IRIS es `iris.oob.local`, no `iriswebapp_nginx`; usar el
nombre de servicio Docker obligaría a `allowUnauthorizedCerts`, el mismo
patrón ya abierto como hallazgo en el nodo MISP.

**Excepción de ruta en Authelia para `/manage/cases/add`.** No hizo falta
evaluarla: al no estar Authelia en el camino de red del 4833, no hay ninguna
regla que excepcionar.

**Pasar por el 443 tal cual.** Descartado, con el peor síntoma de los tres:
Authelia no responde `401` a una petición sin sesión válida contra
`iris.oob.local` — responde `302` a `auth.oob.local`. El nodo HTTP Request de
n8n sigue redirecciones por defecto, así que el resultado habría sido
`HTTP 200` con el HTML de la página de login de Authelia, sin `data.case_id`
en ningún sitio del cuerpo — un éxito aparente. No habría sido solo
inviable: habría sido inviable **en silencio**, exactamente el defecto que
el proyecto evita en otros sitios.

---

## Lo que esta decisión acepta

1. **La resolución depende de una cadena de tres capas, hasta ahora no
   declarada en ningún documento:** `/etc/hosts` del host →
   `systemd-resolved` (127.0.0.53) → resolver embebido de Docker
   (127.0.0.11) → los 24 contenedores de `oob-network`.
   `docs/resolucion-nombres.tsv` declara dos sujetos, `ubuntu` y `w11`; los
   contenedores son un tercer sujeto no declarado que consume el mismo
   fichero con semántica distinta para la misma IP. `iris.oob.local` es la
   única entrada del fichero con IP de tailnet (`100.64.0.1`); las otras
   doce apuntan a `127.0.0.1`, que dentro de un contenedor significa el
   propio contenedor, no el host. Queda pendiente declarar este tercer
   sujeto en el propio TSV o en un documento asociado.
2. **El control que protege la llamada es la API key de IRIS**, más el
   hecho de que el 4833 solo se publica en la interfaz de la tailnet. No
   hay segundo factor en este camino, a diferencia del acceso humano por el
   443 (`policy: two_factor` en
   `fase1-infraestructura/authelia/configuration.yml`).
3. **La API key en uso tiene el bitmask completo de permisos (65535)**,
   confirmado al decodificar el token de sesión que IRIS emite en la
   respuesta. Un usuario de API de IRIS dedicado, con permisos acotados a
   creación de casos, es lo correcto; queda pendiente.
4. **Revisión:** si el override de `fase6-iris` cambiara de puerto o de
   interfaz, o si la entrada de `/etc/hosts` desapareciera del host, esta
   decisión deja de sostenerse y hay que volver a medir (ver la prueba de
   detección de rotura, más abajo).

---

## Convención de nombres que esta decisión establece

Entre contenedores de `oob-network` se usa el nombre de servicio Docker
(`http://rocketchat:3000`, `http://langgraph-agent:8000`, etc.). **IRIS es
la excepción**, y usa `iris.oob.local` porque el CN de su certificado lo
exige — eso es lo que permite validar TLS por nombre sin
`allowUnauthorizedCerts`. Las demás entradas `.oob.local` del `/etc/hosts`
heredado resuelven a `127.0.0.1` dentro de los contenedores y **no deben
usarse desde n8n** ni desde ningún otro contenedor: ese loopback apunta al
propio contenedor que hace la petición, no al servicio que el nombre
sugiere.

---

## Detección de rotura

Prueba, ejecutable desde el host, que discrimina entre el camino sano y el
camino roto:

```
docker exec n8n node -e "
const https=require('https');
https.get({host:'iris.oob.local',port:4833,path:'/manage/customers/list'},
  r=>console.log('HTTP',r.statusCode))
 .on('error',e=>console.log('FAIL',e.code));"
```

`HTTP 401` = camino sano (falta la credencial en esta llamada de prueba,
nada más — la ruta de red, el nombre y el TLS funcionan). Cualquier `FAIL`
= el camino se rompió, y hay que volver a esta decisión antes de seguir.

---

## Aportación al TFM

**Un bloqueante que la lectura de configuración no podía predecir.** La
revisión inicial del Workflow 1 dedujo, leyendo el `docker-compose.yml` de
n8n y el override de fase 6, que el 4833 estaba fuera de alcance y que el
443 publicado quedaría bloqueado por Authelia de forma segura (`401`). Las
dos lecturas eran correctas sobre el fichero y equivocadas sobre el
sistema: el puerto real publicado en la tailnet era el 4833 (el `.env` de
fase 6 fija `INTERFACE_HTTPS_PORT=4833`, y el `443` del override es solo el
valor por defecto de esa variable cuando no está definida, no lo que
efectivamente ocurre en este despliegue), y la respuesta real de Authelia
ante una petición sin sesión es un `302`, no un `401`. Ningún fichero de
configuración documenta ninguna de las dos cosas — solo la medición contra
el sistema vivo las revela. Es la misma familia de defecto que motiva
`docs/DECISION-velociraptor-fuera-sso.md`: el artefacto leído es correcto,
la composición con el resto del sistema no se puede leer en él.
