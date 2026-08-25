# Cambios a aplicar en el workflow `Wazuh Alert Handler`

Orden recomendado. El punto 1 es el que desbloquea la ingesta de alertas reales.

---

## 1. Sustituir `Edit Fields` por un nodo Code de normalización

**Motivo.** `Edit Fields` evalúa `{{ $json.body.data.srcip }}` sin guarda. La
alerta de regla 550 (`Integrity checksum changed`, nivel 7) no tiene clave `data`,
así que la expresión lanza una excepción y la ejecución muere en el segundo nodo.
Esas alertas se están generando de forma rutinaria en el servidor, de modo que
hoy la mayor parte del tráfico real no llega a Rocket.Chat.

Las expresiones de n8n son frágiles para este tipo de normalización defensiva.
Un nodo Code resuelve el caso de una vez y además permite consumir el mapeo
ATT&CK nativo de Wazuh.

Nuevo nodo **`Normalize Alert`**, entre `Webhook` e `If`:

```javascript
const body = $input.first().json.body ?? {};

const rule  = body.rule  ?? {};
const agent = body.agent ?? {};
const data  = body.data  ?? {};
const mitre = rule.mitre ?? {};

// RFC1918, loopback, link-local y CGNAT. Consultar reputación de estas
// direcciones no aporta nada y consume cuota de las APIs externas.
function isPrivateIp(ip) {
  if (!ip) return true;
  const m = ip.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (!m) return true;
  const [a, b] = [Number(m[1]), Number(m[2])];
  return a === 10 || a === 127 || (a === 172 && b >= 16 && b <= 31) ||
         (a === 192 && b === 168) || (a === 169 && b === 254) ||
         (a === 100 && b >= 64 && b <= 127);
}

const srcIp = String(data.srcip ?? data.src_ip ?? '').trim();
const enrichable = Boolean(srcIp) && !isPrivateIp(srcIp);

return [{ json: {
  wazuh: {
    alert_id:   String(body.id ?? ''),
    rule_id:    String(rule.id ?? ''),
    rule_desc:  String(rule.description ?? ''),
    rule_level: Number(rule.level ?? 0),
    rule_groups: Array.isArray(rule.groups) ? rule.groups : [],
    agent_name: String(agent.name ?? ''),
    agent_ip:   String(agent.ip ?? ''),
    src_ip:     srcIp,
    // Tiempo del evento según Wazuh. Es el que debe figurar en el informe.
    event_timestamp: String(body.timestamp ?? ''),
    // Tiempo de ingesta en el enclave, añadido por custom-n8n.
    ingest_timestamp: String(body.oob_timestamp ?? ''),
    // Mapeo ATT&CK nativo del ruleset de Wazuh. Wazuh lo entrega como arrays.
    mitre_id:        mitre.id        ?? [],
    mitre_tactic:    mitre.tactic    ?? [],
    mitre_technique: mitre.technique ?? [],
  },
  enrichable,
  enrichment_skipped: enrichable ? '' :
    (srcIp ? `IP origen privada (${srcIp})` : 'alerta sin IP origen'),
}}];
```

El nodo `If` pasa a comparar `{{ $json.wazuh.rule_level }} >= 7`.

---

## 2. Verificar la firma HMAC en el webhook

**Motivo.** Cualquiera que alcance `n8n.oob.local` puede hoy inyectar alertas
arbitrarias y forzar consultas salientes a VirusTotal y AbuseIPDB con IPs
elegidas, agotando la cuota y revelando qué está observando el SOC.

El script corregido firma el cuerpo. Primer nodo tras `Webhook`, **`Code in JavaScript`**:

```javascript
const crypto = require('crypto');

const secret = $env.OOB_WEBHOOK_SECRET;
if (!secret) throw new Error('OOB_WEBHOOK_SECRET no configurado');

const received = String($input.first().json.headers['x-oob-signature'] ?? '');
const payload  = JSON.stringify($input.first().json.body);
const expected = 'sha256=' + crypto.createHmac('sha256', secret)
                                   .update(payload).digest('hex');

// Comparación en tiempo constante: una comparación con === filtra información
// sobre el prefijo correcto de la firma.
const a = Buffer.from(received), b = Buffer.from(expected);
if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
  throw new Error('Firma HMAC inválida: alerta descartada');
}
return $input.all();
```

Requiere `NODE_FUNCTION_ALLOW_BUILTIN=crypto` en el entorno del contenedor.

En el nodo `Webhook`, activar además **Raw Body** para que la firma se calcule
sobre los bytes exactos recibidos y no sobre una reserialización.

---

## 3. Condicionar el enriquecimiento CTI y tolerar sus fallos

**Motivo.** Ningún nodo HTTP tiene `onError`. VirusTotal devuelve 404 para
direcciones privadas o reservadas, y su API pública admite 500 peticiones diarias
y 4 por minuto. Cualquiera de esos dos casos mata la ejecución completa, de modo
que un fallo del enriquecimiento impide la notificación del incidente. Un sistema
de alerta temprana no debe fallar cerrado en el canal de aviso.

- Añadir un nodo `If` **`CTI aplicable`** sobre `{{ $json.enrichable }}`.
  Rama verdadera hacia AbuseIPDB, VirusTotal y MISP. Rama falsa directa al
  merge, de forma que la alerta se publique igualmente sin datos CTI.
- En los tres nodos HTTP, panel **Settings**:
  - `On Error` → **Continue** (`continueRegularOutput`: el error se fusiona en la
    salida normal, sin una rama de salida de error separada — no
    `continueErrorOutput`, que sí la crearía)
  - `Retry On Fail` → activado, 2 intentos, 1000 ms
  - `Always Output Data` → activado
- En `Merge` y `Merge1`, activar `Always Output Data`. En modo
  `combineByPosition`, una rama sin ítems deja el merge sin salida.

---

## 4. Corregir el nodo MISP

La URL actual, `https://misp:443`, no es un endpoint: un POST contra la raíz
devuelve HTML. Eso explica que tanto `JSON Structured` como `Code CTI Context`
implementen decodificación de entidades HTML sobre la respuesta.

- URL → `https://misp/attributes/restSearch`
- Desactivar `allowUnauthorizedCerts` una vez corregido el montaje del CA en el
  compose (ver comentario en `docker-compose.yml`).
- Dejar una sola credencial: `mispApi`. Retirar el header `Authorization` suelto.

---

## 5. Eliminar nodos huérfanos y duplicados

- **`AI Agent`**, **`Ollama Chat Model`** y **`Simple Memory`**: sin entrada ni
  salida `main`, no se ejecutan nunca. El LLM pasa a vivir dentro del grafo
  LangGraph, seleccionable con `TRIAGE_MODE`. Además `Simple Memory` usaba
  `sessionKey` fijo `oob-session-global`, lo que habría mezclado el contexto de
  todos los incidentes en una única conversación.
- **`JSON Structured`**: su salida entra en `Merge` y se descarta, porque
  `Code CTI Context` vuelve a parsear `$('MISP')` por su cuenta. Dos
  implementaciones divergentes del mismo parseo.

---

## 6. Simplificar `Code CTI Context`

Con la normalización del punto 1, desaparece el `body.body ?? body` y el nodo
solo consolida CTI:

```javascript
const norm = $('Normalize Alert').first().json;

const abuse = $('AbuseIPDB').first()?.json?.data ?? {};
const vt    = $('VirusTotal').first()?.json?.data?.attributes ?? {};

let mispCount = 0;
try {
  const resp = $('MISP').first()?.json?.response ?? {};
  mispCount = Array.isArray(resp.Attribute) ? resp.Attribute.length : 0;
} catch (e) { mispCount = 0; }

return [{ json: {
  wazuh: norm.wazuh,
  cti: {
    abuse_confidence:    Number(abuse.abuseConfidenceScore ?? 0),
    abuse_total_reports: Number(abuse.totalReports ?? 0),
    abuse_country:       String(abuse.countryCode ?? 'N/A'),
    abuse_isp:           String(abuse.isp ?? 'N/A'),
    abuse_is_tor:        Boolean(abuse.isTor ?? false),
    // last_analysis_stats son detecciones de motores; total_votes son votos de
    // la comunidad. El doc de Fase 2f afirmaba que el objeto IP de VirusTotal v3
    // no tiene last_analysis_stats, lo cual es incorrecto: tiene ambos campos y
    // significan cosas distintas. Aquí se usan motores, y así se etiqueta.
    vt_malicious:  Number(vt.last_analysis_stats?.malicious  ?? 0),
    vt_suspicious: Number(vt.last_analysis_stats?.suspicious ?? 0),
    vt_harmless:   Number(vt.last_analysis_stats?.harmless   ?? 0),
    vt_asn:        String(vt.asn ?? 'N/A'),
    vt_as_owner:   String(vt.as_owner ?? 'N/A'),
    vt_network:    String(vt.network ?? 'N/A'),
    misp_total:    mispCount,
    src_ip_is_private:  !norm.enrichable && Boolean(norm.wazuh.src_ip),
    enrichment_skipped: norm.enrichment_skipped,
  }
}}];
```

> [!NOTE]
> **Nota posterior.** Este fragmento envuelve la lectura de `MISP` en `try/catch`, pero no las de `AbuseIPDB` ni `VirusTotal` (`$('AbuseIPDB').first()?.json?.data`). Eso reproduce el mismo problema que motiva el punto 3 del apartado "🐛 Correcciones aplicadas" del README de la fase: `$('Nodo').first()` lanza excepción si el nodo no llegó a ejecutarse, y el encadenamiento opcional (`?.`) no protege porque el error ocurre antes de evaluarlo — justo el caso en que `CTI Aplicable` deriva a `Code CTI Context` sin pasar por las tres ramas CTI. La versión finalmente desplegada envuelve las tres lecturas (AbuseIPDB, VirusTotal y MISP) en una única función `salidaDe()` con `try/catch`, no solo la de MISP como se muestra aquí.

---

## 7. Deduplicación

**Motivo.** Una campaña de fuerza bruta genera decenas de alertas idénticas.
Sin deduplicación, cada una abre su propio ciclo de enriquecimiento y notificación,
agotando la cuota de las APIs y saturando el canal.

Sin introducir infraestructura nueva (Redis quedó fuera del diseño), basta con
el almacén estático del workflow. Nodo **`Dedup`** tras `If`:

```javascript
const store = $getWorkflowStaticData('global');
store.seen = store.seen || {};

const VENTANA_MS = 15 * 60 * 1000;
const ahora = Date.now();

for (const k of Object.keys(store.seen)) {
  if (ahora - store.seen[k] > VENTANA_MS) delete store.seen[k];
}

const out = [];
for (const item of $input.all()) {
  const w = item.json.wazuh;
  const clave = `${w.rule_id}|${w.agent_name}|${w.src_ip}`;
  if (!store.seen[clave]) {
    store.seen[clave] = ahora;
    out.push(item);
  }
}
return out;
```

Limitación a documentar: el estado vive en memoria del proceso y se pierde al
reiniciar el contenedor. Es suficiente para amortiguar ráfagas, no para
correlación persistente entre incidentes.

---

## 8. Plantilla de Rocket.Chat

Dos correcciones. La primera es de trazabilidad: la plantilla actual imprime
`{{ $now.format(...) }}`, que es la hora de **notificación**, no la del evento.
El único registro legible por humanos pierde el instante del incidente.

La segunda es de honestidad: el mensaje atribuye a Mistral 7B un veredicto que
produce el motor de reglas. El campo `analysis_mode` que devuelve el servicio
indica qué motor decidió realmente, y renderizarlo evita que el informe pueda
volver a mentir aunque alguien cambie la configuración sin actualizar la
documentación.

```
🚨 *Alerta de seguridad — enclave OOB*

📋 *Regla:* {{$json.wazuh.rule_id}} — {{$json.wazuh.rule_desc}}
⚠ *Nivel Wazuh:* {{$json.wazuh.rule_level}}
🖥 *Agente:* {{$json.wazuh.agent_name}}
🌐 *IP origen:* {{ $json.wazuh.src_ip || 'no disponible' }}
🕐 *Evento:* {{$json.wazuh.event_timestamp}}
📥 *Ingesta:* {{$json.wazuh.ingest_timestamp}}

🔍 *CTI*
├ AbuseIPDB: {{$json.cti.abuse_confidence}}% ({{$json.cti.abuse_total_reports}} reportes, {{$json.cti.abuse_country}})
├ VirusTotal: {{$json.cti.vt_malicious}} motores maliciosos / {{$json.cti.vt_harmless}} inocuos
├ ASN: {{$json.cti.vt_asn}} ({{$json.cti.vt_as_owner}})
└ MISP: {{$json.cti.misp_total}} coincidencias

🧠 *Triage — motor: {{$json.decision.analysis_mode}}*
├ Severidad: {{$json.decision.severity_real}} (score {{$json.decision.score}})
├ ATT&CK: {{$json.decision.mitre_technique}} / {{$json.decision.mitre_tactic}}
├ Fuente ATT&CK: {{$json.decision.mitre_source}}
├ Resumen: {{$json.decision.summary}}
├ Recomendación: {{$json.decision.recommendation}}
├ Requiere bloqueo: {{$json.decision.requires_block}}
└ Abrir War Room: {{$json.decision.create_war_room}}
```

`mitre_source` toma el valor `wazuh_native`, `heuristic` o `unmapped`, de modo
que el analista sabe si la atribución procede del ruleset de Wazuh o de una
inferencia propia. Con `unmapped`, la técnica es `no determinado`: el motor ya no
inventa una técnica ATT&CK para alertas que no reconoce.

---

## 9. War Room

`create_war_room` ya viaja hasta el mensaje pero nadie lo consume. Nodo `If`
sobre ese campo y, en la rama verdadera, un `HTTP Request` a
`groups.create` (no `channels.create`: el War Room debe ser un **grupo
privado**, no un canal público — contiene indicadores, direcciones y
decisiones de respuesta) con nombre `inc-{{$json.wazuh.alert_id}}`, seguido del
`postMessage` sobre el grupo recién creado. La rama falsa mantiene la
publicación en `general`.

Si no da tiempo a implementarlo, documentarlo como brecha conocida: la señal ya
existe y falta únicamente la acción.

> [!NOTE]
> **Implementado.** Esta funcionalidad ya está desplegada: nodos `Abrir War Room`
> (`If`) → `Crear War Room` (`groups.create`) → `Contexto en War Room`
> (`chat.postMessage` sobre el grupo) → `Anuncio en General`
> (`chat.postMessage` sobre `#general`). El nombre del grupo combina
> `rule_id` y `alert_id` (`inc-{{rule_id}}-{{alert_id}}`, saneado), no solo
> `alert_id`.

### `roomId` frente a `channel` en `chat.postMessage`

`chat.postMessage` acepta dos parámetros para dirigir el mensaje y **no son
intercambiables**:

- `roomId` — identificador interno (`_id`) del grupo o canal. Sin prefijo.
- `channel` — nombre del canal, y **requiere el prefijo `#`** para canales
  públicos.

`Contexto en War Room` usa `roomId` (`{{ $json.group?._id ?? $json.channel?._id ?? '' }}`);
`Anuncio en General` usa `channel` (`"#general"`). Cruzarlos —enviar un nombre
en `roomId`, o un `_id` en `channel`— produce un 400:

```json
{"success":false,"error":"[invalid-channel]","errorType":"invalid-channel"}
```

Este es el error observado y confirmado en esta instalación, no uno
hipotético. Se produce cuando `Crear War Room` falla (por ejemplo, nombre de
grupo duplicado) y devuelve, entre otros:

```json
{"success":false,"error":"A channel with name 'X' exists [error-duplicate-channel-name]","errorType":"error-duplicate-channel-name"}
```

`Crear War Room` tiene `On Error → Continue` (`continueRegularOutput`): si
falla, la ejecución sigue hacia `Contexto en War Room` con un ítem sin
`group`. La expresión `$json.group?._id ?? $json.channel?._id ?? ''` resuelve
entonces a cadena vacía, `roomId` viaja vacío, y `[invalid-channel]` aparece
dos nodos más allá del fallo real de `Crear War Room` — lejos de su causa.

> [!NOTE]
> **Causa raíz real del `[invalid-channel]` observado.** No fue, en origen, el
> cruce `roomId`/`channel` en sí, sino que `Code Merge Final` no tenía
> declarada la variable `wazuh` (usaba `wazuh.rule_id`/`wazuh.alert_id` sin
> extraer `input.wazuh` primero), así que `war_room_name` nunca se generaba
> con un valor válido y `groups.create` fallaba. Al corregir esa declaración
> en `Code Merge Final`, `groups.create` empezó a funcionar con normalidad.
> El mecanismo `roomId`/`channel` descrito arriba sigue siendo real y
> reproducible por otras causas — ver más abajo.

### Degradación cuando `groups.create` falla

Aunque la causa original ya está corregida, `groups.create` puede fallar por
otros motivos: nombre de grupo duplicado fuera de la ventana de
deduplicación, permisos revocados al bot, o Rocket.Chat caído. Con
`On Error → Continue`, cualquiera de esos fallos interrumpía toda la cadena
del War Room (`Contexto en War Room` reventaba con `[invalid-channel]` y
`Anuncio en General` no llegaba a ejecutarse): la alerta no llegaba ni al
grupo privado ni a `#general`. Es exactamente el fallo que un sistema de
alerta temprana no puede permitirse: perder la notificación por un fallo en
la coordinación, en lugar de degradarla.

> [!NOTE]
> **Implementado.** Nuevo nodo `If` **`War Room creado`**, entre
> `Crear War Room` y `Contexto en War Room`, con condición booleana sobre
> `{{ $json.success }}`:
> - Rama verdadera → `Contexto en War Room` → `Anuncio en General` (cadena sin cambios)
> - Rama falsa → `Post a message` (publicación directa en `#general`, la misma
>   ruta que ya usa `Abrir War Room` cuando `create_war_room` es falso)
>
> Con esto, si el grupo no se puede crear, la alerta se publica igualmente en
> `#general` en lugar de perderse: el mismo principio de degradación
> controlada ya aplicado al enriquecimiento CTI (punto 3) y al motor de
> triage — un fallo en la coordinación no debe implicar la pérdida de la
> notificación.
>
> Efecto secundario necesario: `Post a message` usaba expresiones `{{$json.*}}`
> directas, válidas solo cuando `$json` era la salida de `Code Merge Final`
> (el único camino hasta ahora, vía `Abrir War Room` en rama falsa). Alcanzado
> ahora también desde `War Room creado` en rama falsa, `$json` sería en su
> lugar la respuesta de `groups.create` — sin los campos `wazuh`, `cti`,
> `severity`, etc. Se corrigieron las expresiones de `Post a message` a
> `{{$('Code Merge Final').first().json.*}}`, igual que ya hacían
> `Contexto en War Room` y `Anuncio en General`, para que funcione desde
> ambos caminos.

### `error-not-allowed`

Es el error real de Rocket.Chat cuando el bot carece del permiso
`create-c`/`create-p` para crear canales o grupos. No se ha observado en esta
instalación: el rol `bot` siempre tuvo permisos suficientes. Queda documentado
como caso previsto sin salida capturada — para reproducirlo de forma
deliberada, retirar temporalmente ese permiso al bot y repetir la creación
del War Room.
