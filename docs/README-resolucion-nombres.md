# Resolución de nombres del enclave

Fuente de verdad de qué nombre debe existir en qué host, y control que lo
verifica. El enclave no despliega DNS propio: la resolución es por ficheros
`hosts`. Este documento y `scripts/verify-hosts.sh` son el mecanismo que impide
que las tres copias diverjan sin que nadie lo note — que es exactamente lo que
ocurrió (defectos D1–D3, más abajo).

## Principio

La resolución de nombres debe reflejar la segmentación de red, no puentearla. Un
enclave con microsegmentación rigurosa y resolución global no está segmentado:
cualquier host alcanza cualquier servicio si conoce la IP, y el `hosts` se la da.
El DNS es superficie de control.

De ahí, dos reglas:

1. **Cada host recibe solo los nombres que su rol necesita y que su política de
   red le permite alcanzar.** El puesto de analista no resuelve el panel de
   Traefik ni Portainer; el Domain Controller no resuelve ningún servicio del
   enclave salvo el `ControlURL` de su propio cliente de red.
2. **Los nombres del enclave resuelven a la interfaz por la que el tráfico debe
   circular.** En el host que corre la pila, a loopback. En los demás, a la
   interfaz del enclave (`192.168.127.138`) donde escucha Traefik — nunca a la
   IP del tailnet (`100.64.0.0/10`), que está reservada para el rendezvous de
   RustDesk y gobernada por la ACL de Headscale.

## Alcance del control

Vigilado: el espacio de nombres `*.oob.local` en los tres hosts, más los nombres
declarados explícitamente en `resolucion-nombres.tsv` (hoy, `dc01-tfm` y
`velociraptor.local`).

Fuera de alcance: los alias `.local` de servicios que no pasan por Traefik
(`velociraptor.local` en el host que corre la pila, `minio.local`), el nombre de
frontend `VelociraptorServer`, `localhost` y la pila IPv6. `verify-hosts.sh` los
lista como informativos pero no falla por ellos.

## Estado declarado

El fichero legible por máquina es
[`resolucion-nombres.tsv`](resolucion-nombres.tsv); `verify-hosts.sh` lee de ahí.
La tabla siguiente se deriva de ese fichero y debe coincidir con él
(`verify-hosts.sh --check-doc` lo comprueba). **Al añadir o cambiar un nombre se
edita el `.tsv`; esta tabla se actualiza a mano para que sigan cuadrando.**

| host | nombre | ip | servicio | justificación |
|---|---|---|---|---|
| ubuntu | traefik.oob.local | 127.0.0.1 | Traefik — panel y router del enclave | Host que ejecuta la pila Docker; panel y rutas HTTP servidos en loopback. |
| ubuntu | portainer.oob.local | 127.0.0.1 | Portainer — gestión de contenedores | Administración de la pila desde el propio host. |
| ubuntu | auth.oob.local | 127.0.0.1 | Authelia — IdP y MFA del enclave | SSO de todas las UIs; resuelto en loopback vía Traefik. |
| ubuntu | chat.oob.local | 127.0.0.1 | Rocket.Chat — War Rooms | Coordinación de incidentes desde el host operador. |
| ubuntu | wazuh.oob.local | 127.0.0.1 | Wazuh — panel del SIEM | Revisión de alertas y reglas desde el host operador. |
| ubuntu | n8n.oob.local | 127.0.0.1 | n8n — orquestador de workflows | Edición y supervisión de los workflows del enclave. |
| ubuntu | misp.oob.local | 127.0.0.1 | MISP — CTI | Fuente de inteligencia consultada por el triaje. |
| ubuntu | iris.oob.local | 127.0.0.1 | DFIR-IRIS — gestión de casos | Registro de incidentes; la misma línea de `hosts` comparte el alias local `iris.local`. |
| ubuntu | kvm.oob.local | 127.0.0.1 | GL.iNet KVM — Plan C | Consola de contingencia accedida vía Traefik. |
| ubuntu | hs.oob.local | 192.168.127.138 | Headscale — plano de control | El cliente Tailscale del propio orquestador usa `--login-server https://hs.oob.local`; resuelve a la interfaz del enclave, no a loopback, para que el tráfico del plano de control circule por la interfaz prevista (regla 2). |
| ubuntu | dc01-tfm | 100.64.0.2 | Agente DC (FastAPI) en el Domain Controller | El orquestador llama al agente por su nombre de nodo del tailnet; entrada documentada en `README-fase4c-dcagent.md`. Añadida en P1-0. |
| w11 | velociraptor.local | 192.168.127.138 | Velociraptor — GUI forense (:8889) | Puesto de analista. Velociraptor se sirve en su propio puerto TLS, fuera del espacio `.oob.local` de Traefik; por eso el nombre es `.local`. |
| w11 | hs.oob.local | 192.168.127.138 | Headscale — plano de control / Headscale UI | El analista consulta el estado del tailnet y el registro del canal break-glass. |
| w11 | auth.oob.local | 192.168.127.138 | Authelia — SSO | Autenticación previa a las UIs del enclave. |
| w11 | chat.oob.local | 192.168.127.138 | Rocket.Chat — War Rooms | Canal primario de coordinación del analista. |
| w11 | n8n.oob.local | 192.168.127.138 | n8n — orquestador | Revisión de ejecuciones y aprobaciones desde el War Room. |
| w11 | iris.oob.local | 192.168.127.138 | DFIR-IRIS — gestión de casos | Documentación del incidente. |
| w11 | kvm.oob.local | 192.168.127.138 | GL.iNet KVM — Plan C | Consola de contingencia si RustDesk falla. |
| dc01 | hs.oob.local | 192.168.127.138 | ControlURL del cliente Tailscale del DC | Ver Excepciones. |

El puesto de analista (`w11`) **no** resuelve `traefik`, `portainer`, `wazuh` ni
`misp`: son superficies de operador y de infraestructura, no de análisis
(regla 1).

## Excepciones

### `hs.oob.local` en el DC01

Parece incoherente con la ACL de Headscale
(`fase4-breakglass-dc/headscale/config/acl.hujson`), que concede a `tag:dc` un
único destino, `tag:orchestrator:21115-21119` (rendezvous de RustDesk), con el
razonamiento «el DC nunca es origen» escrito en el propio fichero. **No lo es, y
no debe eliminarse.**

`tailscale debug prefs` en el DC01 devuelve `"ControlURL":
"https://hs.oob.local"`. Es la URL con la que el cliente Tailscale habla con su
plano de control. No es un servicio del enclave que el DC consuma como cliente
de aplicación: es la configuración de su propio agente de red. El registro
contra el control plane discurre por la red subyacente
(`192.168.127.0/24`), no por el tailnet, y por tanto no lo cubre la ACL.

Retirar la entrada rompería el registro del cliente en el próximo arranque, y
con él el canal break-glass al controlador de dominio. Queda escrito aquí para
que una limpieza futura no la elimine por parecer inconsistente.

## Defectos históricos (D1–D3)

Los tres se comprobaron en runtime antes de corregirlos. Son la razón de ser de
este control: **ningún control falló** — la ACL de Headscale hace exactamente lo
que dice y está bien razonada; los ficheros `hosts` también. La incoherencia
entre ambos abrió el camino, y no existía nada que la detectara.

### D1 — Nombre huérfano

`velociraptor.oob.local` existía solo en el `hosts` del W11, apuntando a un
servicio que nunca se enrutó: sin router de Traefik y sin ninguna mención en el
repositorio. Resolvía, conectaba al 443 de Traefik y devolvía `404`. Retirado.
La GUI de Velociraptor se alcanza por `velociraptor.local:8889`, que no pasa por
Traefik.

### D2 — Resolución no determinista

El DC01 tenía `hs.oob.local` duplicado con dos IPs: `192.168.127.138` y
`100.64.0.1`. `Resolve-DnsName` devolvía ambas y `Test-NetConnection` eligió la
del tailnet, que falla:

```
hs.oob.local -> 192.168.127.138   (subyacente, correcta)
hs.oob.local -> 100.64.0.1        (tailnet)
```

El acceso al plano de control desde el DC dependía de cuál ganara en cada
intento. La entrada del tailnet nunca pudo funcionar: la ACL concede a `tag:dc`
únicamente `tag:orchestrator:21115-21119`. El `hosts` prometía una ruta que la
política deniega por diseño. Corregido: una sola entrada, a `192.168.127.138`.

### D3 — La resolución eludía la microsegmentación

Verificado desde el DC01 antes de la corrección:

```
kvm.oob.local:443   -> 192.168.127.138   TcpTestSucceeded: True
iris.oob.local:4833 -> 192.168.127.138   TcpTestSucceeded: True
```

La ACL deniega ambos destinos por tailnet. Funcionaban porque el `hosts` los
dirigía por la red corporativa, el plano del que el enclave pretende ser
independiente. El caso de IRIS es el más grave: es el sistema donde se
documentan los incidentes, incluidos los que investigan al propio DC. El DC01 no
tiene ninguna necesidad de rol de resolver esos nombres. Corregido: retiradas
del `hosts` del DC01.

## Nota operativa — edición del `hosts` en Windows

En el W11, el fichero `hosts` se edita con Notepad como administrador. Un
`Get-Content | ... | Set-Content` sobre el mismo fichero lo bloquea, la escritura
falla y la caché DNS queda en un estado que tumba la resolución de **todos** los
nombres del enclave, no solo del que se editaba. Se recupera con `ipconfig
/flushdns`. Hacer copia del fichero antes de tocarlo.

El comando de recogida que emite `verify-hosts.sh --emit` solo **lee** el
`hosts` (`Get-Content`); no lo modifica.

## Procedimiento para añadir un nombre nuevo

En este orden, para que la declaración preceda a la configuración:

1. Añadir la fila (o filas, una por host) a `resolucion-nombres.tsv`.
2. Actualizar a mano la tabla «Estado declarado» de este documento para que
   coincida.
3. Editar el `hosts` de cada host afectado (en Windows, según la nota operativa).
4. Ejecutar el control:
   - `scripts/verify-hosts.sh` en el Ubuntu.
   - `scripts/verify-hosts.sh --emit w11` / `--emit dc01`, ejecutar la salida en
     ese host, pegar el resultado en un fichero y `scripts/verify-hosts.sh
     --check w11 <fichero>`.
5. `scripts/verify-hosts.sh --check-doc` para confirmar que `.tsv` y tabla
   siguen cuadrando.

## Decisión — no se despliega DNS propio

**Control evaluado.** Un resolver interno del enclave (`dnsmasq` o similar) en el
host que corre la pila, sirviendo la zona `oob.local` a los tres hosts, en lugar
de mantener tres ficheros `hosts` a mano.

**Amenaza / problema que cubriría.** Elimina la sincronización manual y con ella
la clase de defecto D1–D3: una única zona, servida a todos, no puede divergir
entre hosts. Un enclave OOB no puede depender del DNS corporativo por la misma
razón por la que no puede depender de la CA corporativa: es uno de los activos
que se asume comprometido.

**Control equivalente actual.** La declaración de este documento más
`verify-hosts.sh`: no impide la divergencia, pero la detecta antes de que un
servicio nuevo la herede. El P1-1 pondrá seis servicios más detrás de Traefik y
cada uno necesita un nombre en tres máquinas; el control se ejecuta una vez por
servicio añadido.

**Coste.** Un resolver es un punto único de fallo en el canal de recuperación:
si cae, se pierde la resolución de `hs.oob.local` y con ella el arranque en frío
del break-glass, justo durante un incidente. Ese modo de fallo exige su propia
monitorización y un `hosts` mínimo de respaldo en cada host de todas formas. Con
once nombres y tres máquinas, el volumen no justifica introducir esa
dependencia.

**Decisión.** No se despliega. Se ataca la causa real —ausencia de detección de
divergencia— con `verify-hosts.sh`. Reevaluar si el número de nombres o de hosts
crece hasta hacer inmanejable la edición manual.

## Referencias

- `fase4-breakglass-dc/headscale/config/acl.hujson` — política de
  microsegmentación; el razonamiento «el DC nunca es origen».
- `docs/README-fase4b-tailnet.md` — enrolado de nodos y por qué MagicDNS no
  cubre estos nombres (`base_domain: tailnet.internal`).
- `docs/README-fase4c-dcagent.md` — entrada `dc01-tfm` en el `hosts` del
  orquestador.
- `docs/README-fase4-pendientes.md` — formato de «mejora evaluada y descartada».
