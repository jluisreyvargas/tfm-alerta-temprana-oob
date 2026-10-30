# Lecciones operativas recuperadas de las conversaciones de trabajo

**Procedencia.** Estas entradas proceden de las transcripciones de las conversaciones de trabajo del proyecto, que no están versionadas. Se han transcrito el 2026-10-29 para que la guía de comandos (`docs/GUIA-COMANDOS.md`) pueda citarlas con fuente en el repositorio.

**Estado de acreditación.** Ninguna se ha vuelto a medir para este documento. Cada entrada dice qué observó la conversación y qué queda sin registrar. Donde la conversación no registra el resultado de un comando, se indica.

**Formato.** Cada entrada recoge procedencia (título de la conversación y fecha), síntoma, causa, comando incorrecto, comando correcto y evidencia registrada.

---

## L-1 · Retirar la única entrada de `ports:` deja la clave nula

- **Procedencia:** TFM-Fase5_2, lección operativa 3 del prompt de continuación (sesión cerrada el 2026-09-10).
- **Síntoma:** el contenedor no se recrea.
- **Causa:** al retirar la única entrada de `ports:`, la clave queda solo con comentarios y YAML la lee como nula. El comando aborta. Un comando que falla y otro que no llega a ejecutarse producen el mismo estado.
- **Control:** validar con `docker compose config` antes de cualquier `--force-recreate`.
- **No registrado:** el servicio concreto afectado.

## L-2 · `sed -i` rompe el bind mount de un fichero individual

- **Procedencia:** TFM-Fase5_2 (sesión cerrada el 2026-09-10).
- **Caso:** edición con `sed -i` de `fase2-orquestador/wazuh-integration/custom-n8n`, montado en `single-node-wazuh.manager-1:/var/ossec/integrations/custom-n8n`.
- **Síntoma:** el `diff` mostró exactamente los dos cambios esperados y no hubo ningún error, pero el contenedor siguió ejecutando el fichero anterior (hash previo `41890ce63ebb`).
- **Causa:** `sed -i` sustituye el inodo. El montaje queda anclado al inodo antiguo, que ya no es alcanzable por ruta.
- **Reparación propuesta** (el resultado no consta transcrito):

```bash
docker restart single-node-wazuh.manager-1
sleep 20
docker exec single-node-wazuh.manager-1 sha256sum /var/ossec/integrations/custom-n8n | cut -c1-16
sha256sum ~/tfm-alerta-temprana-oob/fase2-orquestador/wazuh-integration/custom-n8n | cut -c1-16
```

- **Criterio:** los dos hashes son iguales y distintos de `41890ce63ebb`.
- **Patrón seguro para futuras ediciones.** El `cat >` trunca y reescribe el mismo inodo; el `sed -i` lo sustituye:

```bash
tmp=$(mktemp)
sed 's/...//' fichero > "$tmp" && cat "$tmp" > fichero && rm "$tmp"
```

## L-3 · `cmd | tail; echo $?` mide la tubería, no el comando

- **Procedencia:** TFM-Fase5_2, lección operativa 1 del prompt de continuación (sesión cerrada el 2026-09-10).
- **Síntoma:** un código de salida 0 aunque el comando haya fallado. Causó dos diagnósticos falsos.
- **Alternativas para obtener el código real:** `cmd >/dev/null 2>&1; echo $?`, o `set -o pipefail`, o `${PIPESTATUS[0]}`.

## L-4 · Consultar `execution_entity` de n8n sobre una copia de SQLite

- **Procedencia:** «TFM: validación de hallazgos y deuda técnica» (2026-09-24).
- **Regla:** `docker cp` de `database.sqlite` puede adelantarse a la escritura diferida de SQLite, así que hay que copiar también el fichero `-wal`.
- **Patrón usado:**

```bash
docker cp n8n:/home/node/.n8n/database.sqlite /tmp/n8n-ref.sqlite && docker cp n8n:/home/node/.n8n/database.sqlite-wal /tmp/n8n-ref.sqlite-wal 2>/dev/null ; sqlite3 /tmp/n8n-ref.sqlite "SELECT id, status, startedAt FROM execution_entity WHERE workflowId='TUzKK9OBP39SYILa' AND id > 2468 ORDER BY id;" ; rm -f /tmp/n8n-ref.sqlite /tmp/n8n-ref.sqlite-wal /tmp/n8n-ref.sqlite-shm
```

- **Evidencia registrada:** `2469|success|2026-09-24 19:21:26.993`, que es la línea base previa al cambio de Authelia en n8n.
- **No localizado:** el episodio original en que la copia sin `-wal` omitió una ejecución recién enviada.

## L-5 · `{"message":"Workflow was started"}` es acuse de recibo, no ejecución

- **Procedencia:** TFM-Fase4 (2026-08-30), TFM-Fase8_Upgrades_2 (2026-09-14) y «TFM: validación de hallazgos y deuda técnica» (2026-09-23 a 2026-09-25).
- **2026-08-30.** El historial de la integración saliente de Rocket.Chat hacia `http://n8n:5678/webhook/rc-breakglass` mostraba esa respuesta, y Claude la interpretó como prueba de que la integración funcionaba, aunque la ejecución no aparecía. Es la primera instancia registrada del error.
- **2026-09-14.** Una respuesta de 34 bytes con `Content-Type: application/json` corresponde al modo *Respond: Immediately* del nodo Webhook, que devuelve 200 al aceptar la petición, antes de ejecutar el flujo. Comprobación:

```bash
docker exec glkvm_cloud sh -c 'wget -q -O - http://n8n:5678/webhook/kvm-hook; echo'
```

- **Salida registrada:** `{"message":"Workflow was started"}`.
- **Corrección:** *Respond* configurado como «Using 'Respond to Webhook' node». Con ese modo, una rama que no alcance un nodo de respuesta deja a rttys sin respuesta, y rttys deniega al agotar 3 s.
- **Regla formalizada (2026-09-23 a 2026-09-25):** el HTTP 200 y ese mensaje son acuse de recepción. El único testigo fiable de ejecución es una fila en `execution_entity` (ver L-4).

## L-6 · `curl -H 'Host: …'` sin `--resolve` no envía SNI

- **Procedencia:** TFM-Fase8_Upgrades_2 (2026-09-14).
- **Síntoma:** `404` contra Portainer al probar con la cabecera `Host`.
- **Causa:** Traefik enruta TLS por SNI antes de mirar la cabecera. Con `-H` el SNI va vacío.
- **Comando correcto y salida registrada:**

```bash
curl -sk -o /dev/null -w 'con SNI: %{http_code}\n' --resolve portainer.oob.local:443:192.168.0.70 https://portainer.oob.local/
```

  Salida: `con SNI: 403`, que es Authelia denegando una petición sin sesión. Router `enabled` y servicio `UP` según la API de Traefik en `http://192.168.0.70:8080/api/http/routers/portainer@docker`.
- **Consecuencia:** una conclusión anterior sobre MISP, obtenida con `-H`, se repitió con `--resolve` (`misp con SNI: 404`). La conclusión se mantuvo, pero ahora con el instrumento correcto.
- **No registrado:** el comando `-H` literal que dio el primer `404`.

## L-7 · `date +%s%N` de busybox devuelve segundos

- **Procedencia:** TFM-Fase8_Upgrades_2 (2026-09-14).
- **Comandos:**

```bash
docker exec glkvm_cloud sh -c 'command -v curl; command -v wget; date +%s%N'
docker exec n8n sh -c 'command -v curl; command -v wget; command -v node; date +%s%N'
```

- **Salida registrada:** `1789040529` en ambos, diez dígitos. El `date` de busybox descarta `%N` sin avisar.
- **Sustitución:** un script de Node.js ejecutado dentro de `n8n` que mide con `process.hrtime.bigint()` (`/tmp/mide2.js`). En `glkvm_cloud`, que no tiene `node`, se midió por lotes.
- **No localizado:** el caso `docker exec … true`, citado en la misma serie de instrumentos falsos.

## L-8 · Verificación TLS: lo prohibido es la configuración del servicio, no la sonda

- **Procedencia:** TFM-End_to_End (2026-09-07), §4.4 del plan de integración IRIS–n8n.
- **Regla:** marcar «Ignore SSL Issues» en el nodo HTTP de n8n contradice el argumento del enclave como ancla de confianza propia. Si llegara a hacerse, debe constar como hallazgo.
- **Salida correcta:** alias de red `iris.oob.local` en `oob-network` (o `extra_hosts`) más `NODE_EXTRA_CA_CERTS` apuntando a la CA del enclave dentro del contenedor de n8n.
- **Aclaración:** `curl -k` sí se usó en sondas de diagnóstico desde el host (por ejemplo, en L-6), y no consta ninguna prohibición sobre ese uso. La regla se aplica a la configuración de servicios y nodos: «Ignore SSL Issues», `insecureSkipVerify`, `ssl.CERT_NONE`.
