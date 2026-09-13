# Hallazgo — La política de Headscale en modo `file` no es consultable ni recargable

**Fecha:** 2026-09-13
**Severidad:** P1 (arquitectural, sobre el plano de control del canal de contingencia)
**Descubierto durante:** P1-1a Fase C, al verificar el acceso del analista a IRIS
**Estado:** remediado el síntoma (regla añadida y aplicada); el mecanismo sigue igual

---

## 1. Resumen

Con `policy.mode: file`, Headscale carga la ACL **al arrancar**. Un cambio en el
fichero no llega a los nodos hasta que el contenedor se reinicia, y ninguno de
los tres comandos que Headscale ofrece para gestionar la política revela esa
diferencia:

| Comando | Qué hace | Qué devolvió con el cambio sin aplicar |
|---|---|---|
| `headscale policy check --file ...` | Valida la **sintaxis del fichero** | `Policy is valid`, `rc=0` |
| `headscale policy get` | Imprime el **fichero configurado** | La regla nueva, presente |
| `headscale policy set --file ...` | Actualiza la política | `Failed to set ACL Policy: rpc error: code = Unknown desc = update is disabled for modes other than 'database'` |

Los dos primeros dan verde sobre un cambio que no está en producción. El tercero,
que sería el que lo aplicaría, está deshabilitado en este modo.

**La única forma de saber qué política está vigente** es inspeccionar el netmap
de un nodo destino:

```bash
sudo tailscale debug netmap | python3 -c 'import sys,json
d=json.load(sys.stdin)
for r in (d.get("PacketFilterRules") or []):
    print(r["SrcIPs"][0], sorted(set((p["Ports"]["First"], p["Ports"]["Last"])
          for p in r["DstPorts"] if ":" not in p["IP"])))'
```

Ese comando no aparece en la ayuda de `headscale`, ni en la documentación de la
Fase 4, ni en el comentario de cabecera del propio `acl.hujson` — que recomienda
justamente `policy check`, el que no mide lo que importa.

---

## 2. La evidencia

### Antes del reinicio: fichero cambiado, política vieja aplicada

Fichero en disco (`sha256 ef408fb3…`), con la regla nueva; `policy check` en
verde; `policy get` mostrando la regla. Netmap del orchestrator:

```
100.64.0.4/32 [(22, 22), (21115, 21119)]
100.64.0.2/32 [(21115, 21119)]
```

Sin el 443. El contenedor llevaba arrancado desde `2026-09-11T17:17:39Z`, antes
de la edición.

Desde el W11 (`100.64.0.4`), con el tailnet operativo —`tailscale ping`
respondiendo en 1 ms, sesión directa a `192.168.127.138:41641`—:

```
Test-NetConnection 100.64.0.1 -Port 443   → TcpTestSucceeded: False
Test-NetConnection 100.64.0.1 -Port 4833  → TcpTestSucceeded: False
```

### Después del reinicio

```
100.64.0.4/32 [(22, 22), (21115, 21119)]
100.64.0.4/32 [(443, 443)]
100.64.0.2/32 [(21115, 21119)]
```

Y desde el W11:

| Prueba | Resultado | Qué demuestra |
|---|---|---|
| `100.64.0.1:443` | **True** | La regla nueva se aplica (control positivo) |
| `100.64.0.1:4833` | False, con ping OK | La política sigue denegando lo no concedido (control negativo) |
| `100.64.0.2:3389` | False | El analista no alcanza RDP del DC |

El acceso a IRIS por `https://iris.oob.local` desde el navegador del W11, con
Authelia + TOTP, funciona a partir de ese momento.

**Matiz sobre el tercer control:** el `Test-NetConnection` al DC salió por
`Ethernet0` con origen `192.168.127.151`, no por el tailnet, y el ping falló. El
`False` es correcto pero su causa no es un filtro rechazando el paquete: es que
sin regla que lo conceda, el W11 no tiene ruta al DC por el tailnet. Control
negativo válido, mecanismo distinto del supuesto.

### El comando de reinicio no es el obvio

El primer intento fue `cd fase4-breakglass-dc && docker compose restart
headscale`, que devolvió `no configuration file provided: not found`. El compose
de Headscale vive en `fase4-breakglass-dc/headscale/config/`, el **mismo
directorio que se monta como `/etc/headscale`**, así que el contenedor ve por
dentro el fichero que lo define.

Localizado con la etiqueta que Docker guarda, no buscando:

```bash
docker inspect headscale -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'
```

El comando correcto es:

```bash
cd ~/tfm-alerta-temprana-oob/fase4-breakglass-dc/headscale/config
docker compose -f docker-compose.headscale.yml restart headscale
```

Merece una línea en el README de la Fase 4: el procedimiento para recargar la
microsegmentación del enclave no se deduce de la estructura del repositorio.

---

## 3. El hallazgo que lo destapó: capacidad declarada que la red nunca permitió

`docs/resolucion-nombres.tsv` declara desde el P0-D:

```
w11  iris.oob.local  100.64.0.1  DFIR-IRIS — gestion de casos  Documentacion del incidente.
```

La ACL vigente concedía a `tag:analyst` exactamente dos destinos:

```
tag:analyst → tag:orchestrator:21115-21119,22
tag:analyst → tag:kvm:443,80,22
```

Ninguno cubre el 443 ni el 4833 del orchestrator. **El acceso del analista a IRIS
por el tailnet nunca ha estado permitido desde el P0-D.** El criterio declarado de
la Fase 4 —que el analista alcance en contingencia lo crítico— no se había
traducido a regla.

Y `verify-hosts.sh` lo daba por bueno, porque compara `(host, nombre, ip)` contra
el fichero `hosts`. El control existe, funciona correctamente, y verifica una cosa
distinta de la que el `.tsv` afirma en su columna de justificación.

**Rocket.Chat está en la misma situación**: `w11 chat.oob.local` se declara como
«canal primario de coordinación del analista» y tampoco tenía el 443. Pendiente
de verificar por el tailnet ahora que la regla existe.

### Familia del hallazgo

Es la misma que el P1-1g (el analista perdió el acceso al dashboard de Wazuh al
cerrar el 4443, sin decisión escrita). En los dos casos el `.tsv` describe una
capacidad que ningún control comprueba, y en los dos la divergencia se descubre
por accidente al probar otra cosa.

Diferencia útil: el P1-1g es una capacidad **perdida** por un cambio posterior;
este es una capacidad **nunca concedida**. El primero es una decisión que caducó,
el segundo una intención que no se implementó — las dos formas que el proyecto
viene documentando, sobre el mismo artefacto.

---

## 4. Lo que se cambió

En `fase4-breakglass-dc/headscale/config/acl.hujson`:

```
{ "action": "accept", "src": ["tag:analyst"], "dst": ["tag:orchestrator:443"] },
```

Conceder el 443 no concede los servicios: cada router conserva su middleware y su
regla de Authelia. El control pasa del nivel de red al de aplicación, que es
precisamente lo que la Fase C está construyendo. El 4833 **no** se concede: el
acceso a IRIS debe ir por Traefik, y su denegación es ahora el control negativo
que lo demuestra.

`analyst-w11` tiene `tag:analyst` asignado, verificado con `headscale nodes
list` — al contrario que `tag:kvm`, que aparece en dos reglas y no está asignado
a ningún nodo, así que esas reglas no tienen efecto (deuda ya conocida).

---

## 5. Pendiente, no remediado aquí

**El bloque `tests:` desapareció de la ACL.** La versión del 28 de agosto
(`acl.hujson.bak`) tenía pruebas de política:

```
"tests": [
  { "src": "tag:orchestrator", "accept": ["tag:dc:8000"], "deny": ["tag:dc:3389", "tag:dc:445"] },
  { "src": "tag:dc",           "deny":   ["tag:orchestrator:22", "tag:orchestrator:8000"] },
]
```

La edición del 30 de agosto —la que añadió `tag:kvm` y corrigió la topología de
RustDesk— las eliminó. Y `policy check` devuelve `Policy is valid` igual con
pruebas que sin ellas, así que la pérdida no produjo ninguna señal: el control
automático sobre la ACL desapareció justo cuando la ACL se volvió más compleja.

Propuesta para recuperarlas, ampliada con lo decidido hoy:

```
"tests": [
  { "src": "tag:orchestrator", "accept": ["tag:dc:8000"], "deny": ["tag:dc:3389", "tag:dc:445"] },
  { "src": "tag:dc",           "deny":   ["tag:orchestrator:22", "tag:orchestrator:8000", "tag:orchestrator:443"] },
  { "src": "tag:analyst",      "accept": ["tag:orchestrator:443"], "deny": ["tag:dc:3389", "tag:orchestrator:8080"] },
]
```

Antes de escribirlas hay que medir si `policy check` **ejecuta** los `tests:` o
solo valida que estén bien formados. Si no los ejecuta, recuperarlos es
documentación y no control, y conviene decirlo así en vez de darlo por hecho.

---

## 6. Aportación al TFM

**Un control cuyo estado no es consultable con sus propias herramientas.** La
microsegmentación del enclave es, según el comentario de cabecera del propio
fichero, lo que impide que un DC comprometido alcance n8n, Wazuh, MISP e IRIS.
Headscale ofrece tres subcomandos para gestionarla; dos informan sobre el fichero
y el tercero está deshabilitado. No hay ninguno que responda «qué política está
aplicándose ahora». La respuesta está en un nodo, con un comando de depuración de
otro producto.

Es una variante del patrón central: aquí el artefacto que documenta la intención
(el fichero) y el que la implementa (los filtros distribuidos) son distintos, y
**todas las herramientas del sistema miran el primero**. La diferencia con el
middleware comentado de Wazuh es que allí bastaba leer con atención; aquí leer
con atención lleva a la conclusión equivocada, porque el fichero es correcto.

**Un indicador alarmante que era correcto.** El W11 mostraba `"PacketFilter": []`
y `"PacketFilterRules": null` — ninguna regla aplicada. Se interpretó como fallo
de distribución. Es lo esperado: el filtro de Tailscale es de **entrada**, y como
ninguna regla concede a nadie conectarse al analista, su filtro está vacío con
razón. El orchestrator, que sí es destino, tenía sus dos reglas correctas.

Va en dirección contraria a todo lo demás del proyecto, y por eso vale la pena
registrarlo: el método busca controles que parecen activos y no lo están, pero
también produce falsos positivos en el sentido opuesto. Distinguirlos exigió
consultar el nodo que sí era destino, no insistir sobre el que no lo era.

**Un comando que falla y otro que no llega a ejecutarse.** El primer `docker
compose restart` devolvió `no configuration file provided: not found` y el
netmap siguió igual. Sin `echo $?` ni lectura del mensaje, el resultado era
indistinguible de «reiniciado y sin efecto», que habría llevado a buscar el fallo
en Headscale. La lección ya estaba registrada; el error se repitió igualmente.
