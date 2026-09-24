# Procedimiento — Prueba manual del canal Wazuh → n8n

Cómo inyectar una alerta de prueba en el webhook `wazuh-alerts` sin depender de
que Wazuh genere una alerta real. Necesario para verificar cualquier cambio en
el workflow `Wazuh Alert Handler with Langgraph`.

Verificado funcionando el 2026-09-13 (caso IRIS #4).

---

## Lo que hay que saber antes

**El webhook exige firma HMAC-SHA256.** El nodo `Code in JavaScript` (primer
nodo tras el Webhook) verifica la cabecera `x-oob-signature` y lanza
`Firma HMAC invalida: alerta descartada` si no casa. No es opcional ni se puede
saltar: es el control que impide inyectar alertas falsas alcanzando la URL.

**La firma se calcula sobre los bytes exactos del cuerpo.** El webhook tiene
`rawBody: true` y el verificador firma la cadena literal recibida. Cualquier
diferencia —un salto de línea de más, un espacio, un reordenado de claves—
invalida la firma. De ahí que el JSON se escriba a fichero, se firme ese
fichero y se envíe con `--data-binary`, nunca con `-d` y el JSON inline.

> **Nota (2026-09-24).** «El verificador firma la cadena literal recibida» es cierto desde el commit `9d69042` (2026-09-23). Antes reserializaba el cuerpo ya parseado, así que la firma solo casaba cuando la serialización del emisor coincidía byte a byte con la de `JSON.stringify`; con caracteres no ASCII no coincidía nunca. Ver M-46 en `docs/REGISTRO-MEDICIONES-n8n-iris-2026-09-13.md`.

**Dos URLs distintas según el estado del workflow:**

| Estado | URL |
| --- | --- |
| Workflow inactivo, editor abierto | `https://n8n.oob.local/webhook-test/wazuh-alerts` |
| Workflow activo (`active: true`) | `https://n8n.oob.local/webhook/wazuh-alerts` |

La de test **solo escucha mientras el editor está abierto y se ha pulsado
«Execute workflow»**. Si devuelve 404, es que no está a la escucha.

**El nodo `Dedup` recuerda los `id` ya vistos.** Repetir un `id` corta la
ejecución ahí y no se llega a IRIS. Usar un `id` nuevo en cada prueba.

---

## Procedimiento

### 1. Preparar el cuerpo, sin salto de línea final

```bash
printf '%s' '{"id":"<ID-NUEVO>","timestamp":"2026-09-13T20:00:00.000+0200","oob_timestamp":"2026-09-13T20:00:02.000+0200","rule":{"id":"5710","level":10,"description":"PRUEBA MANUAL - intento de acceso SSH fallido","groups":["sshd","authentication_failed"]},"agent":{"name":"DC01-TFM","ip":"192.168.127.140"},"data":{"srcip":"185.220.101.5"}}' > /tmp/alerta-prueba.json

xxd /tmp/alerta-prueba.json | tail -1
```

El último byte debe ser `7d` (`}`), **no** `0a`. Si se usa un heredoc en vez de
`printf '%s'`, queda un `\n` final que entra en la firma y complica el
diagnóstico si algo falla.

Evitar caracteres UTF-8 multibyte (guiones largos, acentos) en el cuerpo de
prueba: funcionan, pero añaden una variable más si hay que depurar.

### 2. Cargar el secreto en la shell

```bash
read -s -p "Secret: " OOB_SECRET; echo; export OOB_SECRET
echo "${#OOB_SECRET}"    # debe dar 64
```

El valor es `OOB_WEBHOOK_SECRET` de `fase2-orquestador/n8n/.env`, y debe
coincidir con `WEBHOOK_SECRET` de `/var/ossec/etc/n8n-integration.conf` en el
host Wazuh. **Ejecutar `read` en su propia línea**, no pegado a un bloque: si se
pega el bloque entero, `read` consume la línea siguiente como si fuera la clave.

### 3. Firmar y enviar

```bash
SIG="sha256=$(openssl dgst -sha256 -hmac "$OOB_SECRET" -r /tmp/alerta-prueba.json | cut -d' ' -f1)"
echo "$SIG"    # sha256= + 64 hex

curl -sS -w '\nHTTP %{http_code}\n' -X POST \
  https://n8n.oob.local/webhook-test/wazuh-alerts \
  -H "Content-Type: application/json" \
  -H "x-oob-signature: $SIG" \
  --data-binary @/tmp/alerta-prueba.json
```

Pulsar «Execute workflow» en el editor **justo antes** del curl.

---

## Diagnóstico si la firma se rechaza

Calcular la firma desde dentro del contenedor, con el secreto que n8n ve:

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

- **Firmas iguales pero n8n rechaza** → el cuerpo se modifica en tránsito.
  Comprobar el campo `body` en la salida del nodo `Webhook` de la ejecución
  fallida y compararlo carácter a carácter con el fichero. Sería un hallazgo
  por derecho propio.
- **Firmas distintas** → el secreto difiere. Si `len secreto` da 66 en vez de
  64, el `.env` tiene el valor entre comillas y Compose las incluye en el
  secreto.
- **HTTP 404** → el webhook de test no está escuchando: volver al editor y
  pulsar «Execute workflow».

---

## Qué verificar tras una prueba correcta

Con el payload de ejemplo (nivel 10, `authentication_failed`, IP pública):

| Punto | Esperado |
| --- | --- |
| `Normalize Alert` | `enrichable: true` |
| Triaje | severidad ALTA o CRITICA |
| `Preparar Caso IRIS` | `severity_id` 5 o 6, `classification_id: 15` |
| IRIS | caso con la severidad correcta y `case_soc_id` = el `id` enviado |
| War Room | canal `inc-<rule_id>-<id-saneado>` creado con el contexto |

El `case_soc_id` conserva el punto del `alert_id` (`1789400000.9998`) para poder
buscarlo literalmente en Wazuh. El nombre del canal sí lo sanea, porque
Rocket.Chat no admite puntos.

---

## Limpieza

Cada prueba crea un caso real en IRIS y un canal real en Rocket.Chat. Ambos hay
que borrarlos a mano. Incluir `PRUEBA MANUAL` en `rule.description` hace que
aparezca en el `case_name` y sean fáciles de identificar.
