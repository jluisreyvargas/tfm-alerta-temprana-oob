#!/usr/bin/env bash
# dc-signed.sh — cliente de prueba firmado para POST /run del agente del DC
# (fase4-breakglass-dc/dcagent/agent_dc.py). Analogo a scripts/collect-signed.sh,
# que firma para el orchestrator de la Fase 5, no para este agente.
#
# Construye una peticion con firma HMAC-SHA256 coherente con verify_signature()
# de agent_dc.py (lineas ~93-128):
#
#   firma = HMAC_SHA256( secret , "{ts}.{nonce}." + cuerpo_crudo )   (hex, sin prefijo)
#
# Cabeceras enviadas: X-Timestamp, X-Nonce, X-Signature, mas Authorization:
# Bearer. El nombre de cabecera HTTP es insensible a mayusculas, asi que esta
# forma es equivalente a la x-timestamp/x-nonce/x-signature que usa
# collect-signed.sh; agent_dc.py las lee con request.headers.get() en
# minuscula, que en Starlette normaliza ambas formas igual.
#
# Firma exactamente los mismos bytes que se envian: el cuerpo JSON se genera
# una sola vez dentro del proceso Python, se escribe a un fichero temporal y
# ese mismo fichero es el que se firma y el que se manda con --data-binary.
# No hay reserializacion entre firmar y enviar.
#
# Uso:
#   dc-signed.sh --script <nombre> --target <valor>   [--verbose]
#   dc-signed.sh --script rustdesk_enable.ps1 [--ttl <minutos>] [--verbose]
#   dc-signed.sh --script rustdesk_disable.ps1 [--verbose]
#   dc-signed.sh --selftest [--verbose]
#
# El mapeo script -> parametro (target/ttl/ninguno) replica SCRIPT_PARAMS en
# agent_dc.py. La lista de scripts permitidos que este script comprueba en
# cliente es SOLO informativa: la autoridad es ALLOWED_SCRIPTS en el propio
# agente, que puede rechazar por otras razones (ruta, allowlist del servidor).
#
# Variables de entorno requeridas (SIN valor por defecto — ver nota mas abajo):
#   AGENT_URL           URL base del agente, ej. https://dc01-tfm:8000
#   AGENT_TOKEN         Bearer token compartido con el agente (AGENT_TOKEN)
#   AGENT_HMAC_SECRET   Secreto HMAC compartido (AGENT_HMAC_SECRET)
#
# Se usa la forma ${VAR:?mensaje}, nunca ${VAR:-valor}: un default convierte la
# ausencia de configuracion en un sistema operativo con credencial conocida y
# sin ningun error visible — el defecto que corrigio el P0-3. Si existe un
# fichero dc-signed.env junto a este script, se carga automaticamente, pero
# eso no releva la comprobacion: una variable ausente o vacia en ese fichero
# sigue abortando la ejecucion.
#
# Variables de entorno opcionales (pruebas del canal de firma, usadas por
# --selftest y disponibles tambien para pruebas manuales):
#   SIGN_TS             Fuerza el timestamp (epoch). Prueba la ventana temporal.
#   SIGN_NONCE          Fuerza el nonce. Reutilizarlo prueba el anti-replay.
#   SIGN_CORRUPT=1      Altera el ultimo caracter de la firma. Prueba el 403.
#   SIGN_OMIT_HEADERS=1 No envia X-Timestamp/X-Nonce/X-Signature. Prueba el 400.
#
# Nunca se imprime el token ni el secreto, ni siquiera en modo verbose: con
# --verbose se muestra solo su longitud y los 8 primeros caracteres de su
# SHA-256.
#
# Codigo de salida: 0 solo si la peticion normal devuelve HTTP 200. En modo
# --selftest, 0 solo si las 5 comprobaciones coinciden con lo esperado.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/dc-signed.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

AGENT_URL="${AGENT_URL:?Falta AGENT_URL (ej. http://100.64.0.2:8000). Definir en el entorno o en $ENV_FILE}"
AGENT_TOKEN="${AGENT_TOKEN:?Falta AGENT_TOKEN. Definir en el entorno o en $ENV_FILE}"
AGENT_HMAC_SECRET="${AGENT_HMAC_SECRET:?Falta AGENT_HMAC_SECRET. Definir en el entorno o en $ENV_FILE}"

# Lista informativa: la autoridad real es ALLOWED_SCRIPTS en agent_dc.py.
ALLOWED_SCRIPTS=(
  "disable_account.ps1"
  "enable_account.ps1"
  "collect_logs.ps1"
  "isolate_host.ps1"
  "reset_password.ps1"
  "rustdesk_enable.ps1"
  "rustdesk_disable.ps1"
)

# Replica SCRIPT_PARAMS en agent_dc.py: rustdesk_enable.ps1 usa ttl,
# rustdesk_disable.ps1 no toma parametros, el resto usa target.
declare -A SCRIPT_PARAM_KIND=(
  ["rustdesk_enable.ps1"]="ttl"
  ["rustdesk_disable.ps1"]="none"
)

usage() {
  cat <<EOF >&2
Uso:
  $(basename "$0") --script <nombre> --target <valor> [--verbose]
  $(basename "$0") --script rustdesk_enable.ps1 [--ttl <minutos, 1-480, def. 30>] [--verbose]
  $(basename "$0") --script rustdesk_disable.ps1 [--verbose]
  $(basename "$0") --selftest [--verbose]

Scripts permitidos (allowlist informativa; la real es del agente del DC):
  disable_account.ps1 enable_account.ps1 collect_logs.ps1 isolate_host.ps1
  reset_password.ps1                                  -> requieren --target
  rustdesk_enable.ps1                                  -> admite --ttl
  rustdesk_disable.ps1                                 -> sin parametros

Variables de entorno requeridas (sin valor por defecto):
  AGENT_URL, AGENT_TOKEN, AGENT_HMAC_SECRET
  (se cargan automaticamente desde ${ENV_FILE} si existe)

Variables de entorno opcionales para pruebas de firma:
  SIGN_TS, SIGN_NONCE, SIGN_CORRUPT=1, SIGN_OMIT_HEADERS=1
EOF
}

_mask_info() {  # $1=etiqueta $2=valor — nunca imprime el valor real
  local label="$1" value="$2" len prefix
  len=${#value}
  prefix="$(printf '%s' "$value" | sha256sum | cut -c1-8)"
  echo "  ${label}: longitud=${len} sha256[0:8]=${prefix}" >&2
}

# Construye el cuerpo UNA sola vez (en Python), lo firma y lo envia tal cual.
# $1=script  $2=target ("" si no aplica)  $3=ttl ("" si no aplica)
# Deja el resultado en RESP_CODE / RESP_BODY y LAST_TS / LAST_NONCE / LAST_SIG.
_send() {
  local script="$1" target="$2" ttl="$3"
  local body_file resp_file ts nonce sig
  body_file="$(mktemp)"
  resp_file="$(mktemp)"
  # Nota: NO se usa `trap ... RETURN` aqui. Un trap RETURN fijado dentro de
  # una funcion no se limita a esa invocacion: sigue activo y vuelve a
  # disparar cuando el llamador (_selftest) retorna, momento en el que
  # body_file/resp_file ya no existen y `set -u` aborta con "unbound
  # variable". Limpieza explicita en su lugar, en cada salida de la funcion.

  read -r ts nonce sig < <(
    AGENT_HMAC_SECRET="$AGENT_HMAC_SECRET" \
    SIGN_TS="${SIGN_TS:-}" \
    SIGN_NONCE="${SIGN_NONCE:-}" \
    SIGN_CORRUPT="${SIGN_CORRUPT:-}" \
    python3 - "$body_file" "$script" "$target" "$ttl" <<'PY'
import hashlib
import hmac
import json
import os
import secrets
import sys
import time

body_path, script, target, ttl = sys.argv[1:5]

payload = {"script": script}
if target != "":
    payload["target"] = target
if ttl != "":
    payload["ttl_minutes"] = int(ttl)

body = json.dumps(payload).encode("utf-8")
with open(body_path, "wb") as fh:
    fh.write(body)

ts = os.environ.get("SIGN_TS") or str(int(time.time()))
nonce = os.environ.get("SIGN_NONCE") or secrets.token_hex(16)

key = os.environ["AGENT_HMAC_SECRET"].encode("utf-8")
sig = hmac.new(key, f"{ts}.{nonce}.".encode("utf-8") + body, hashlib.sha256).hexdigest()

if os.environ.get("SIGN_CORRUPT") == "1":
    last = sig[-1]
    sig = sig[:-1] + ("0" if last != "0" else "1")

print(ts, nonce, sig)
PY
  )

  if [[ ${#sig} -ne 64 ]]; then
    echo "ERROR: no se pudo calcular la firma (Python fallo)" >&2
    rm -f "$body_file" "$resp_file"
    return 1
  fi
  LAST_TS="$ts"
  LAST_NONCE="$nonce"
  LAST_SIG="$sig"

  local -a headers=(
    -H "Content-Type: application/json"
    -H "Authorization: Bearer ${AGENT_TOKEN}"
  )
  if [[ "${SIGN_OMIT_HEADERS:-0}" != "1" ]]; then
    headers+=(
      -H "X-Timestamp: ${ts}"
      -H "X-Nonce: ${nonce}"
      -H "X-Signature: ${sig}"
    )
  fi

  RESP_CODE="$(curl -sS -X POST "${AGENT_URL%/}/run" \
    "${headers[@]}" \
    --data-binary "@${body_file}" \
    -w '%{http_code}' -o "${resp_file}")"
  RESP_BODY="$(cat "${resp_file}")"
  rm -f "$body_file" "$resp_file"
}

_check() {  # $1=etiqueta $2=obtenido $3=esperado
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    echo "  [OK]    ${label}: obtenido=${got} esperado=${want}"
    return 0
  else
    echo "  [FALLO] ${label}: obtenido=${got} esperado=${want}"
    return 1
  fi
}

# Reproduce las 5 comprobaciones del Paso 9, en el mismo orden en que
# verify_signature() las evalua (cabeceras -> ventana temporal -> replay ->
# firma), para que cada prueba aisle exactamente el fallo que dice aislar.
#
# Script elegido para la prueba 1: collect_logs.ps1. Es el unico de
# ALLOWED_SCRIPTS de solo lectura (Get-WinEvent sobre el log de Seguridad,
# ver fase4-breakglass-dc/scripts/collect_logs.ps1); el resto deshabilita
# cuentas, aisla el host o cambia contraseñas, y esta prueba se ejecuta de
# verdad en el DC.
_selftest() {
  local target="dc-signed-selftest" ok=1

  echo "== Selftest dc-signed.sh / verify_signature (agent_dc.py) =="
  echo "Script de prueba: collect_logs.ps1 (solo lectura, target=${target})"
  echo

  unset -v SIGN_TS SIGN_NONCE SIGN_CORRUPT SIGN_OMIT_HEADERS 2>/dev/null || true

  _send "collect_logs.ps1" "$target" ""
  _check "1. Firma valida"              "$RESP_CODE" "200" || ok=0
  local prev_ts="$LAST_TS" prev_nonce="$LAST_NONCE"

  SIGN_TS="$prev_ts" SIGN_NONCE="$prev_nonce" _send "collect_logs.ps1" "$target" ""
  _check "2. Replay (mismo nonce)"      "$RESP_CODE" "409" || ok=0

  SIGN_CORRUPT=1 _send "collect_logs.ps1" "$target" ""
  _check "3. Firma invalida"            "$RESP_CODE" "403" || ok=0

  local old_ts
  old_ts=$(( $(date +%s) - 600 ))
  SIGN_TS="$old_ts" _send "collect_logs.ps1" "$target" ""
  _check "4. Timestamp fuera de ventana" "$RESP_CODE" "400" || ok=0

  SIGN_OMIT_HEADERS=1 _send "collect_logs.ps1" "$target" ""
  _check "5. Sin cabeceras de firma"     "$RESP_CODE" "400" || ok=0

  echo
  if [[ "$ok" -eq 1 ]]; then
    echo "OK: selftest completo (5/5)."
    return 0
  else
    echo "FALLO: selftest con discrepancias (ver arriba)."
    return 1
  fi
}

# --------------------------------------------------------------------------
# Parseo de argumentos
# --------------------------------------------------------------------------
SCRIPT_NAME=""
TARGET=""
TTL=""
VERBOSE=0
SELFTEST=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --script) SCRIPT_NAME="${2:?falta valor para --script}"; shift 2 ;;
    --target) TARGET="${2:?falta valor para --target}"; shift 2 ;;
    --ttl) TTL="${2:?falta valor para --ttl}"; shift 2 ;;
    --verbose) VERBOSE=1; shift ;;
    --selftest) SELFTEST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: argumento desconocido: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "$VERBOSE" -eq 1 ]]; then
  _mask_info "AGENT_TOKEN" "$AGENT_TOKEN"
  _mask_info "AGENT_HMAC_SECRET" "$AGENT_HMAC_SECRET"
fi

if [[ "$SELFTEST" -eq 1 ]]; then
  _selftest
  exit $?
fi

if [[ -z "$SCRIPT_NAME" ]]; then
  echo "ERROR: falta --script" >&2
  usage
  exit 2
fi

allowed=0
for s in "${ALLOWED_SCRIPTS[@]}"; do
  if [[ "$s" == "$SCRIPT_NAME" ]]; then
    allowed=1
    break
  fi
done
if [[ "$allowed" -ne 1 ]]; then
  # Comprobacion solo informativa/de bloqueo temprano: la autoridad es
  # ALLOWED_SCRIPTS en agent_dc.py, que rechazara igualmente con 400.
  echo "ERROR: '${SCRIPT_NAME}' no esta en la allowlist local de scripts permitidos." >&2
  exit 2
fi

param_kind="${SCRIPT_PARAM_KIND[$SCRIPT_NAME]:-target}"
case "$param_kind" in
  target)
    if [[ -z "$TARGET" ]]; then
      echo "ERROR: '${SCRIPT_NAME}' requiere --target" >&2
      exit 2
    fi
    _send "$SCRIPT_NAME" "$TARGET" ""
    ;;
  ttl)
    ttl_val="${TTL:-30}"
    if ! [[ "$ttl_val" =~ ^[0-9]+$ ]] || (( ttl_val < 1 || ttl_val > 480 )); then
      echo "ERROR: --ttl debe ser un entero entre 1 y 480" >&2
      exit 2
    fi
    _send "$SCRIPT_NAME" "" "$ttl_val"
    ;;
  none)
    if [[ -n "$TARGET" || -n "$TTL" ]]; then
      echo "AVISO: '${SCRIPT_NAME}' no toma parametros; se ignoran --target/--ttl." >&2
    fi
    _send "$SCRIPT_NAME" "" ""
    ;;
esac

echo "HTTP ${RESP_CODE}"
echo "${RESP_BODY}"

[[ "$RESP_CODE" == "200" ]]
