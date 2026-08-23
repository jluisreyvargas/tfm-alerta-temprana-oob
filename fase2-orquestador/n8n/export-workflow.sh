#!/usr/bin/env bash
# Exporta el workflow "Wazuh Alert Handler with Langgraph" desde n8n y lo
# guarda saneado en fase2-orquestador/n8n/workflows/wazuh-alert-handler.json
# para que la lógica de orquestación quede versionada en el repo (hasta ahora
# solo vivía en el volumen Docker n8n_n8n_data).
#
# Saneado aplicado antes de escribir el fichero:
#   - se eliminan id, versionId, webhookId y meta.instanceId (se regeneran
#     por instancia de n8n; conservarlos no sirve para restaurar)
#   - cada credentials.*.id se sustituye por la cadena REEMPLAZAR,
#     conservando el name (el id de credencial es local a cada instancia)
#   - active se deja en false (el import no debe reactivar nada solo)
#   - se elimina shared (incluye el email del propietario del workflow en
#     esta instancia de n8n; no debe publicarse en el repo)
set -euo pipefail

WORKFLOW_ID="TUzKK9OBP39SYILa"
CONTAINER="n8n"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${SCRIPT_DIR}/workflows/wazuh-alert-handler.json"
TMP_RAW="$(mktemp)"
trap 'rm -f "$TMP_RAW"' EXIT

docker exec "$CONTAINER" n8n export:workflow --id="$WORKFLOW_ID" --pretty --output=/tmp/export-workflow.json
docker cp "$CONTAINER:/tmp/export-workflow.json" "$TMP_RAW"
docker exec "$CONTAINER" rm /tmp/export-workflow.json

mkdir -p "$(dirname "$OUTPUT")"

jq '
  .[0]
  | del(.id, .versionId, .meta.instanceId, .shared)
  | .active = false
  | .nodes = [
      .nodes[]
      | del(.webhookId)
      | if has("credentials") then
          .credentials = (.credentials | with_entries(.value.id = "REEMPLAZAR"))
        else
          .
        end
    ]
' "$TMP_RAW" > "$OUTPUT"

echo "Workflow saneado escrito en: $OUTPUT"
