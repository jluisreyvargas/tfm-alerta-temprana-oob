#!/usr/bin/env bash
# collect-signed.sh — cliente de prueba firmado para POST /velociraptor/collect
# del orchestrator (fase5-orchestrator-api).
#
# Construye una peticion con firma HMAC-SHA256 coherente con verify_signature()
# de fase5-orchestrator-api/main.py, que replica el patron de
# fase4-breakglass-dc/dcagent/agent_dc.py:
#
#   firma = HMAC_SHA256( secret , "{ts}.{nonce}." + cuerpo_crudo )   (hex, sin prefijo)
#
# Cabeceras enviadas: x-timestamp, x-nonce, x-signature.
# Firma exactamente los mismos bytes que se envian: el cuerpo JSON se genera
# una sola vez, se escribe a un fichero temporal y ese mismo fichero es el que
# se firma y el que se manda con --data-binary. No hay reserializacion.
#
# Uso:
#   collect-signed.sh <incidentid> <host> <profile> [source]
#
# Variables de entorno:
#   ORCH_URL       Endpoint. Por defecto http://127.0.0.1:8020
#   SIGN_TS        Fuerza el timestamp (epoch). Para probar la ventana temporal.
#   SIGN_NONCE     Fuerza el nonce. Reutilizar el mismo valor prueba el anti-replay.
#   SIGN_CORRUPT   Si vale 1, altera el ultimo caracter de la firma. Para probar
#                  el rechazo por firma invalida (403).
#
# El secreto se lee de fase5-orchestrator-api/.env (campo ORCH_HMAC_SECRET) y
# nunca se imprime ni se pasa por argv: se entrega al proceso Python por entorno.
#
# No requiere que el orchestrator este desplegado para construir la peticion,
# pero si para obtener respuesta. El despliegue lo hace el usuario.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../fase5-orchestrator-api/.env"
ORCH_URL="${ORCH_URL:-http://127.0.0.1:8020}"

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Uso: $(basename "$0") <incidentid> <host> <profile> [source]" >&2
  exit 2
fi

incidentid="$1"
host="$2"
profile="$3"
source_field="${4:-}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: no existe $ENV_FILE" >&2
  exit 1
fi

# Ultima aparicion del campo, sin volcarlo a stdout. cut -d= -f2- conserva
# cualquier '=' interno del valor. Se recortan comillas y CR envolventes.
secret_line="$(grep -E '^ORCH_HMAC_SECRET=' "$ENV_FILE" | tail -n1 || true)"
secret="${secret_line#ORCH_HMAC_SECRET=}"
secret="$(printf '%s' "$secret" | tr -d '\r')"
secret="${secret%\"}"
secret="${secret#\"}"
if [[ -z "$secret" ]]; then
  echo "ERROR: ORCH_HMAC_SECRET no definido o vacio en $ENV_FILE" >&2
  exit 1
fi

body_file="$(mktemp)"
resp_file="$(mktemp)"
trap 'rm -f "$body_file" "$resp_file"' EXIT

# Genera cuerpo + ts + nonce + firma en un unico proceso. El cuerpo se escribe
# a $body_file; ts/nonce/firma salen por stdout. El secreto entra por entorno.
read -r ts nonce sig < <(
  ORCH_HMAC_SECRET="$secret" \
  SIGN_TS="${SIGN_TS:-}" \
  SIGN_NONCE="${SIGN_NONCE:-}" \
  SIGN_CORRUPT="${SIGN_CORRUPT:-}" \
  python3 - "$body_file" "$incidentid" "$host" "$profile" "$source_field" <<'PY'
import hashlib
import hmac
import json
import os
import secrets
import sys
import time

body_path, incidentid, host, profile, source_field = sys.argv[1:6]

payload = {"incidentid": incidentid, "host": host, "profile": profile}
if source_field != "":
    payload["source"] = source_field

body = json.dumps(payload).encode("utf-8")
with open(body_path, "wb") as fh:
    fh.write(body)

ts = os.environ.get("SIGN_TS") or str(int(time.time()))
nonce = os.environ.get("SIGN_NONCE") or secrets.token_hex(16)

key = os.environ["ORCH_HMAC_SECRET"].encode("utf-8")
sig = hmac.new(key, f"{ts}.{nonce}.".encode("utf-8") + body, hashlib.sha256).hexdigest()

if os.environ.get("SIGN_CORRUPT") == "1":
    last = sig[-1]
    sig = sig[:-1] + ("0" if last != "0" else "1")

print(ts, nonce, sig)
PY
)

if [[ ${#sig} -ne 64 ]]; then
  echo "ERROR: no se pudo calcular la firma (Python fallo)" >&2
  exit 1
fi

code="$(curl -sS -X POST "${ORCH_URL}/velociraptor/collect" \
  -H 'Content-Type: application/json' \
  -H "x-timestamp: ${ts}" \
  -H "x-nonce: ${nonce}" \
  -H "x-signature: ${sig}" \
  --data-binary "@${body_file}" \
  -w '%{http_code}' -o "${resp_file}")"

echo "HTTP ${code}"
cat "${resp_file}"
echo
