# Fase 8 · Mejora 2 — Validación TLS del canal rtty

**Estado:** completada y verificada, incluida la prueba negativa.

**Precondición:** exigió primero corregir el certificado que presenta rttys. Ver
`docs/credenciales-de-arranque.md`, §2.

---

## 1. El punto de partida

El canal entre el GL-RM1 y rttys se levantaba con `rtty -sx`:

- `-s` — SSL activado
- `-x, --insecure` — **permitir conexiones inseguras al usar SSL**

Cifrado sin verificación de la identidad del servidor. Cualquiera capaz de
interponerse entre `192.168.0.36` y `192.168.0.70:5912` podía presentar su propio
certificado y el dispositivo lo habría aceptado.

El `-x` no era un descuido: era lo que hacía funcionar el canal. rttys presentaba
el certificado de la CA raíz del enclave como certificado de servidor —subject e
issuer idénticos, sin extensiones, sin SAN—, y ningún verificador lo habría
aceptado. Quitar el `-x` sin corregir el servidor habría dejado el KVM fuera del
nivel 1.

---

## 2. Dónde va el cambio

No en `rtty-loop.sh`. Ese fichero lo regenera `S01selfCloud` con un heredoc
incondicional en cada arranque en frío (P1-1), de modo que una edición allí
desaparece sin aviso — el mismo patrón que la plantilla de rttys en la mejora 1.

El cambio va en el heredoc de `/etc/kvmd/user/scripts/S01selfCloud`, línea 48:

```sh
# antes
rtty -sx -T 2 -I "$device_id" -h $HOSTNAME$PORT -t "$TOKEN" -d "$device_mac" &

# después
rtty -s -C /etc/kvmd/user/oob-rootCA.crt -T 2 -I "$device_id" \
     -h $HOSTNAME$PORT -t "$TOKEN" -d "$device_mac" &
```

`oob-rootCA.crt` copiado a `/etc/kvmd/user/`, que está bajo el overlay
persistente (`upperdir=/userdata/overlay/upper`).

**Verificado que `rtty` del firmware acepta `-C`.** La ayuda del binario lo
declara: `-C, --cacert  CA certificate to verify peer against`. No se dio por
supuesto.

---

## 3. Verificación previa, en frío

Antes de tocar el script, comprobación de que el certificado valida — de modo que
un fallo apareciera antes de que el canal dependiera de ello:

```sh
openssl s_client -connect 192.168.0.70:5912 \
  -CAfile /etc/kvmd/user/oob-rootCA.crt -verify_return_error < /dev/null
# subject=... CN=glkvm-cloud.oob.local
# Verify return code: 0 (ok)

openssl s_client -connect 192.168.0.70:5912 \
  -CAfile /etc/kvmd/user/oob-rootCA.crt -verify_ip 192.168.0.70 -verify_return_error
# Verify return code: 0 (ok)
```

El `-verify_ip` importa: es la comprobación de nombre, que es la que más
probabilidades tenía de fallar y la que el SAN `IP:192.168.0.70` satisface.

---

## 4. Verificación posterior

| Prueba | Criterio | Resultado |
|---|---|---|
| Conexión con `-C` | `ESTABLISHED` hacia `192.168.0.70:5912` | Establecida |
| `rtty-loop.sh` tras reinicio | Contiene `-C`, regenerado desde `S01selfCloud` | Correcto |
| Proceso tras reinicio | Sin `pts`: arrancado por `S99custom`, no por la sesión | `?` en ambos |
| Dispositivo en la UI de rttys | `zsb25f8` online | Online |
| **Prueba negativa** | Con `-C` apuntando a un fichero que no es la CA emisora, **no** debe conectar | Sin conexión, reintentos en el log |

**La prueba negativa es la que cuenta.** Que el canal funcione con `-C` demuestra
que la verificación pasa; no demuestra que rechace un certificado inválido. Sin
ella no se distingue "verifica y acepta" de "ignora el parámetro". Es la misma
lógica que la prueba negativa obligatoria del §7 del reconocimiento para el hook:
un control probado sólo por el lado que aprueba no está probado.

Un matiz de instrumentación: al comprobar el caso negativo, `tail /tmp/rtty.log`
no discrimina, porque el watchdog escribe sólo cuando rtty no corre y las líneas
acumuladas son idénticas a las nuevas. Lo concluyente es la **ausencia de
`ESTABLISHED`** en `netstat`, que es inequívoca.

---

## 5. Marcha atrás

Respaldo en `/root/S01selfCloud.bak`, deliberadamente **fuera** de
`/etc/kvmd/user/scripts/`: el patrón `S??*` de `S99custom` ejecuta como root todo
lo que empiece por `S` en ese directorio, y una copia de seguridad allí se
ejecutaría en cada arranque. Ese fue uno de los hallazgos de la mejora 6.

```sh
cp /root/S01selfCloud.bak /etc/kvmd/user/scripts/S01selfCloud
pkill -f rtty-loop.sh; pkill -f 'rtty -s'; sleep 2
/etc/kvmd/user/scripts/S01selfCloud start
```

Si el canal no volviera tras un reinicio, la vía es el acceso directo a
`https://192.168.0.36` — que es para lo que RA-1 existe.

---

## 6. Lo que esto no cubre

- **El token sigue viajando como argumento de línea de comando** y es visible en
  `/proc/<pid>/cmdline` (RA-5). La verificación TLS protege el canal en tránsito,
  no la exposición local en el dispositivo.
- **rttys no verifica al dispositivo.** El certificado `glkvm-device.crt` existe
  en `fase1-infraestructura/traefik/certs/` con SAN `IP:192.168.0.36` y
  `serverAuth`, y `rtty` admite `-c` y `-k` para presentar certificado de
  cliente. No está en uso: la autenticación del dispositivo sigue siendo el token
  (`device.go:470`). Autenticación mutua queda como mejora posible, no incluida
  aquí.
- **Divergencia respecto al firmware.** El cambio vive en `S01selfCloud`, que es
  un script de operación, no del fabricante. Una actualización de firmware que
  reponga `/etc/kvmd/user/scripts/` lo eliminaría. Verificar tras cada
  actualización, igual que la plantilla de rttys en la mejora 1.
