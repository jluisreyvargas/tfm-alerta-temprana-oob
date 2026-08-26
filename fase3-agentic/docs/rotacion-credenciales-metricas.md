# Rotación de credenciales de métricas (Fase 3 → indexador de Fase 1)

> **Este documento es solo de planificación.** Ninguno de los comandos siguientes
> se ha ejecutado. No contiene valores reales de contraseña ni de usuario: todos
> los campos sensibles están marcados con `<PLACEHOLDER>`. La rotación debe
> aplicarla el operador manualmente, revisando cada paso.

## Por qué se hace

`fase3-agentic/app/main.py` llama a `log_event(...)` (`fase7-observabilidad/shared/metrics_client.py`)
en cada `POST /triage`, autenticándose contra el indexador OpenSearch de Wazuh
(`OS_URL`, `OS_USER=admin`, `OS_PASS`) para escribir en el índice `tfm-metrics-events`.

Ese único índice es todo lo que el contenedor `langgraph-agent` necesita escribir.
Hoy usa la cuenta **administrativa** del indexador, que además de poder escribir en
cualquier índice puede **leer los índices de alertas de Wazuh** (`wazuh-alerts-*`)
y administrar el propio cluster.

`langgraph-agent` es, de los servicios del enclave, el que procesa el contenido
**menos confiable**: campos de alerta (`rule_desc`, `agent_name`, `src_ip`) que un
atacante controla llegan literalmente al prompt del modo `llm`/`hybrid` (ver
`README.md` → *Controles frente al LLM*). Si ese contenedor se ve comprometido —
vía una cadena de inyección que escapa del saneado actual, vía una dependencia de
`requirements.txt`, o vía el propio runtime de Python — la credencial que tenga en
memoria se ve comprometida con él.

Con la cuenta `admin` del indexador, ese compromiso escala directamente a:
lectura de todas las alertas de Wazuh del enclave (incluida cualquier IOC o cuenta
de usuario que aparezca en ellas), y capacidad de modificar o borrar índices.

Con una cuenta de **mínimo privilegio** limitada a `write` + `create_index` sobre
`tfm-metrics-events*`, el mismo compromiso solo permite escribir eventos de
métrica falsos o corruptos en un índice que ya se trata como telemetría de
mejor esfuerzo (`log_event` nunca bloquea el flujo principal, ver
`app/main.py`). El radio de impacto pasa de "todo el SIEM" a "un índice de
métricas descartable".

## Pasos para crear el rol y el usuario en el indexador

El indexador de Wazuh es un fork de OpenSearch; su plugin de seguridad expone
tanto `securityadmin.sh` (aplica YAML de configuración) como una API REST bajo
`_plugins/_security`. Se documentan ambas rutas; usa la que ya siga el resto del
enclave para gestionar roles.

### Opción A — `securityadmin.sh` (YAML declarativo)

1. Añadir el rol en `roles.yml` (dentro del contenedor del indexador, típicamente
   `/usr/share/wazuh-indexer/opensearch-security/roles.yml`):

   ```yaml
   tfm_metrics_writer:
     cluster_permissions:
       - "cluster:admin/opensearch/indices/create"  # necesario para create_index
     index_permissions:
       - index_patterns:
           - "tfm-metrics-events*"
         allowed_actions:
           - "write"
           - "create_index"
   ```

2. Añadir el usuario interno en `internal_users.yml`:

   ```yaml
   tfm_metrics_svc:
     hash: "<HASH_BCRYPT_DE_LA_CONTRASENA>"   # generar con hash.sh, no escribir la contraseña en claro
     backend_roles: []
     description: "Cuenta de servicio de langgraph-agent (Fase 3) para tfm-metrics-events*"
   ```

   El hash se genera con la utilidad incluida en el propio contenedor del
   indexador, sin que la contraseña en claro quede en ningún fichero:

   ```bash
   docker exec -it <CONTENEDOR_INDEXADOR> \
     /usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh -p '<PASSWORD>'
   ```

3. Mapear el usuario al rol en `roles_mapping.yml`:

   ```yaml
   tfm_metrics_writer:
     users:
       - "tfm_metrics_svc"
   ```

4. Aplicar la configuración:

   ```bash
   docker exec -it <CONTENEDOR_INDEXADOR> \
     /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
     -cd /usr/share/wazuh-indexer/opensearch-security/ \
     -icl -key /usr/share/wazuh-indexer/certs/admin-key.pem \
     -cert /usr/share/wazuh-indexer/certs/admin.pem \
     -cacert /usr/share/wazuh-indexer/certs/root-ca.pem \
     -nhnv
   ```

### Opción B — API REST de seguridad (sin reiniciar el plugin)

1. Crear el rol:

   ```bash
   curl -sk -u '<USUARIO_ADMIN>:<PASSWORD_ADMIN>' \
     -X PUT "https://<HOST_INDEXADOR>:9200/_plugins/_security/api/roles/tfm_metrics_writer" \
     -H "Content-Type: application/json" -d '{
       "cluster_permissions": ["cluster:admin/opensearch/indices/create"],
       "index_permissions": [{
         "index_patterns": ["tfm-metrics-events*"],
         "allowed_actions": ["write", "create_index"]
       }]
     }'
   ```

2. Crear el usuario interno (la API acepta la contraseña en claro solo en esta
   llamada, que nunca debe quedar en shell history ni en logs — usar un fichero
   temporal con `--data @archivo.json` y borrarlo después, o una variable de
   entorno no persistida):

   ```bash
   curl -sk -u '<USUARIO_ADMIN>:<PASSWORD_ADMIN>' \
     -X PUT "https://<HOST_INDEXADOR>:9200/_plugins/_security/api/internalusers/tfm_metrics_svc" \
     -H "Content-Type: application/json" -d '{
       "password": "<PASSWORD_NUEVA>",
       "backend_roles": [],
       "description": "Cuenta de servicio de langgraph-agent (Fase 3) para tfm-metrics-events*"
     }'
   ```

3. Mapear el usuario al rol:

   ```bash
   curl -sk -u '<USUARIO_ADMIN>:<PASSWORD_ADMIN>' \
     -X PUT "https://<HOST_INDEXADOR>:9200/_plugins/_security/api/rolesmapping/tfm_metrics_writer" \
     -H "Content-Type: application/json" -d '{
       "users": ["tfm_metrics_svc"]
     }'
   ```

## Verificación posterior

1. **El usuario nuevo puede escribir en su índice:**

   ```bash
   curl -sk -u 'tfm_metrics_svc:<PASSWORD_NUEVA>' \
     -X POST "https://<HOST_INDEXADOR>:9200/tfm-metrics-events/_doc" \
     -H "Content-Type: application/json" \
     -d '{"@timestamp":"<ISO8601>","event_type":"rotation_smoke_test","source":"manual-check"}'
   ```

   Debe devolver `"result":"created"` con código HTTP 201.

2. **El usuario nuevo NO puede leer los índices de alertas de Wazuh:**

   ```bash
   curl -sk -o /dev/null -w '%{http_code}\n' -u 'tfm_metrics_svc:<PASSWORD_NUEVA>' \
     "https://<HOST_INDEXADOR>:9200/wazuh-alerts-*/_search"
   ```

   Debe devolver `403 Forbidden`. Si devuelve `200`, el rol tiene permisos de
   más y hay que revisar `index_permissions` antes de continuar.

3. **El usuario nuevo NO puede administrar el cluster:**

   ```bash
   curl -sk -o /dev/null -w '%{http_code}\n' -u 'tfm_metrics_svc:<PASSWORD_NUEVA>' \
     "https://<HOST_INDEXADOR>:9200/_cluster/health"
   ```

   Comportamiento esperado: `403 Forbidden` (o, como mínimo, sin permisos de
   escritura/administración sobre el cluster).

4. Una vez verificado, actualizar `fase3-agentic/.env` (manualmente, fuera de
   este documento y fuera del repositorio) con:

   ```
   OS_USER=tfm_metrics_svc
   OS_PASS=<PASSWORD_NUEVA>
   ```

   y reiniciar `langgraph-agent` para que recoja las nuevas credenciales.

## Nota sobre la contraseña anterior

La contraseña `admin` que `fase3-agentic/app/main.py` ha usado hasta ahora para
escribir métricas debe considerarse **comprometida** a efectos de higiene de
credenciales: ha estado presente en el entorno de un contenedor que procesa
entrada no confiable, en un `.env` local y (según el historial documentado en
`.env.example`) en un momento anterior estuvo además escrita en claro dentro de
un `docker-compose.yml`. Rotarla no es opcional aunque no haya evidencia de
explotación: es la misma lógica de "asumir compromiso" que justifica el resto
del enclave Out-of-Band. Tras crear `tfm_metrics_svc`, la cuenta `admin` debe
recibir una contraseña nueva (uso administrativo humano, no de servicio) y, si
el indexador lo soporta, revisar sus sesiones/tokens activos.
