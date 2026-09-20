#!/usr/bin/env bash
# Exporta un workflow desde n8n y lo guarda saneado para versionarlo.
#
# Saneado aplicado antes de escribir el fichero:
#   - se eliminan id, versionId, webhookId y meta.instanceId (se regeneran
#     por instancia de n8n; conservarlos no sirve para restaurar)
#   - cada credentials.*.id se sustituye por REEMPLAZAR, conservando el name
#   - active se deja en false (el import no debe reactivar nada solo)
#   - se elimina shared (incluye el email del propietario del workflow)
#   - staticData se vacia: acumula hostnames y rutas reales de las ejecuciones
#     (M-6). El vaciado era manual y se olvido en tres commits de una semana
#     (M-36), asi que se automatiza.
#   - en parameters, el value de las cabeceras de autenticacion conocidas se
#     sustituye por REEMPLAZAR. El nombre de la cabecera se conserva: es
#     informacion legitima del workflow. Motivo: ocho nodos del workflow de
#     break-glass llevaban el token del bot de Rocket.Chat en claro dentro de
#     parameters, y se publico en los dos remotos (M-41).
#
# NO se sanea el X-User-Id literal: es la unica forma que funciona en nodos
# HTTP Request, porque $env no resuelve en sus expresiones (M-12). Es un
# identificador publico. Sustituirlo dejaria el fichero versionado sin servir
# para restaurar, que es el defecto de M-4 pero a proposito.
#
# Lista de supresion, nunca lista de permitidos: una cabecera nueva no
# contemplada se cuela y se ve; al reves, un nombre nuevo se borraria en
# silencio.
set -euo pipefail

# Uso: ./export-workflow.sh [WORKFLOW_ID] [RUTA_SALIDA]
# Sin argumentos exporta el workflow de Fase 2 a su ruta habitual.
# Fase 4d (break-glass): ./export-workflow.sh f3YEsKZqWKZm5qwg /ruta/fase4d-breakglass.json
WORKFLOW_ID="${1:-TUzKK9OBP39SYILa}"
CONTAINER="n8n"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${2:-${SCRIPT_DIR}/workflows/wazuh-alert-handler.json}"
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
  | .staticData = null
  | .nodes = [
      .nodes[]
      | del(.webhookId)
      | if has("credentials") then
          .credentials = (.credentials | with_entries(.value.id = "REEMPLAZAR"))
        else . end
      | if (.parameters.headerParameters.parameters? | type) == "array" then
          .parameters.headerParameters.parameters = [
            .parameters.headerParameters.parameters[]
             | if ((.name | ascii_downcase) as $n
                  | ["x-auth-token","authorization","x-api-key","apikey","key","token","x-token"]
                  | index($n)) and ((.value | type) == "string")
                  and ((.value | startswith("=")) | not)
              then .value = "REEMPLAZAR" else . end
          ]
        else . end
    ]
' "$TMP_RAW" > "$OUTPUT"

# Deteccion de secretos residuales en parameters. No borra: avisa y falla.
# El saneado por nombre de cabecera solo cubre las conocidas; una forma nueva
# de colar un secreto se escaparia en silencio, que es como se publico el token
# del bot (M-41). Este control existe para que la proxima vez no sea silenciosa.
# Los UUID v4 se excluyen: n8n los usa como identificadores internos dentro de
# parameters y no son secretos. Verificado 2026-09-20: silencio sobre los dos
# workflows actuales, y saca el token sobre el fichero que lo contenia.
SOSPECHOSOS="$(jq -r '
  [ .nodes[] | .parameters // {} | tostring ]
  | join(" ")
  | [scan("[A-Za-z0-9_-]{32,}")]
  | unique
  | .[]
' "$OUTPUT" \
  | grep -v '^REEMPLAZAR$' \
  | grep -vE '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' \
  || true)"

echo "Workflow saneado escrito en: $OUTPUT"

if [ -n "$SOSPECHOSOS" ]; then
  echo "" >&2
  echo "AVISO: cadenas largas en parameters que podrian ser secretos." >&2
  echo "No se han borrado. Revisalas ANTES de commitear:" >&2
  echo "$SOSPECHOSOS" | while read -r s; do
    echo "  ${s:0:8}… (${#s} caracteres)" >&2
  done
  echo "Si son legitimas, el fichero es valido y puedes commitear." >&2
  exit 2
fi