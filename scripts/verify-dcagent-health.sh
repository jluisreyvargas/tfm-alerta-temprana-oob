#!/usr/bin/env bash
# verify-dcagent-health.sh — control del estado declarado por el agente del DC.
#
# Del 12/09/2026 al 27/09/2026 el servicio TFM-DC-Agent corrió con
# AppEnvironmentExtra incompleto: /health respondía "status":"ok" mientras
# "hmac_required" era false (la firma no se exigía) y el registro de auditoría
# se escribía fuera de la ruta que lee Wazuh. Ningún componente lo señaló
# (docs/HITO-dominio-tfm-local-2026-09-26.md §5.6). Este script convierte la
# lectura de /health en un control que falla (exit 1) en ese estado.
#
# Solo lectura: una petición GET a /health, que no requiere token. No lee ni
# imprime secretos.
#
# Comprueba:
#   - la respuesta es JSON (objeto);
#   - "hmac_required" es exactamente true (booleano).
# Informa, sin fallar:
#   - "token_configured", si la versión desplegada lo emite (8b00bdf no lo hace);
#   - "scripts_dir", que debe ser C:\tfm-scripts.
# No comprueba la ruta del log (TFM_LOG_PATH): /health no la expone. Esa parte
# del fallo solo se detecta por la llegada de la alerta 100601 a Wazuh.
#
# Uso:
#   verify-dcagent-health.sh                     Consulta http://100.64.0.2:8000/health
#   verify-dcagent-health.sh URL                 Consulta la URL indicada
#   verify-dcagent-health.sh --from-file FICHERO Evalúa una respuesta guardada
#   verify-dcagent-health.sh --help
#
# Códigos de salida: 0 correcto · 1 control fallido · 2 uso incorrecto o
# petición imposible.
#
# Fixtures (scripts/fixtures/): dcagent-health-antes-correccion.json y
# dcagent-health-despues-correccion.json. Reproducen la forma de /health de la
# versión desplegada (8b00bdf) con el valor de hmac_required informado antes y
# después de la corrección; no son capturas literales.

set -euo pipefail

DEFAULT_URL="http://100.64.0.2:8000/health"

usage() { sed -n '2,/^$/{s/^# \{0,1\}//;p}' "$0"; }

body=""
origen=""
desde_fichero=0
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --from-file)
    [[ $# -eq 2 ]] || { echo "Uso: $0 --from-file FICHERO" >&2; exit 2; }
    [[ -r "$2" ]] || { echo "ERROR: no se puede leer $2" >&2; exit 2; }
    body="$(cat -- "$2")"
    origen="$2"
    desde_fichero=1
    ;;
  "")
    origen="$DEFAULT_URL"
    ;;
  -*)
    echo "Opción desconocida: $1 (ver --help)" >&2; exit 2 ;;
  *)
    [[ $# -eq 1 ]] || { echo "Uso: $0 [URL]" >&2; exit 2; }
    origen="$1"
    ;;
esac

if [[ $desde_fichero -eq 0 ]]; then
  if ! body="$(curl -sS --max-time 10 "$origen")"; then
    echo "ERROR: no se pudo consultar $origen" >&2
    exit 2
  fi
fi

echo "Origen: $origen"

python3 - "$body" <<'PY'
import json, sys

raw = sys.argv[1]
try:
    data = json.loads(raw)
except ValueError:
    print("FALLO: la respuesta no es JSON")
    sys.exit(1)
if not isinstance(data, dict):
    print("FALLO: la respuesta JSON no es un objeto")
    sys.exit(1)

fallos = 0

status = data.get("status")
print(f"  status           = {status!r}")

hmac = data.get("hmac_required")
if hmac is True:
    print("  hmac_required    = true   OK")
else:
    print(f"  hmac_required    = {json.dumps(hmac)}   FALLO: la firma HMAC no se exige")
    fallos += 1

if "token_configured" in data:
    tc = data["token_configured"]
    nota = "" if tc is True else "   AVISO: AGENT_TOKEN no definido en el servicio"
    print(f"  token_configured = {json.dumps(tc)}{nota}")
else:
    print("  token_configured = (no emitido por esta versión del agente)")

sd = data.get("scripts_dir")
nota = "" if sd == "C:\\tfm-scripts" else "   AVISO: se esperaba C:\\tfm-scripts"
print(f"  scripts_dir      = {sd}{nota}")

if fallos:
    print(f"RESULTADO: FALLO ({fallos})")
    sys.exit(1)
print("RESULTADO: OK")
PY
