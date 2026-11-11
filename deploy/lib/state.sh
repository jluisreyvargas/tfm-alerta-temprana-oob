# shellcheck shell=bash
# shellcheck disable=SC2034  # variables que usan deploy.sh y las etapas
# state.sh — rutas, estado del instalador, parámetros y acceso a Docker.

DEPLOY_DIR="${DEPLOY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$DEPLOY_DIR/.." && pwd)}"
STATE_DIR="${STATE_DIR:-$DEPLOY_DIR/.state}"
OUT_DIR="${OUT_DIR:-$DEPLOY_DIR/out}"
PARAMS_FILE="$STATE_DIR/params.env"
SECRETS_FILE="$STATE_DIR/secrets.env"
STATE_MARKER="$STATE_DIR/.creado-por-deploy"

# Valores actuales del laboratorio, que se ofrecen por defecto y sirven para
# reconocer cada IP en los ficheros versionados (inventario, sección 3.1).
DEF_LAN_IP='192.168.0.70'
DEF_ENCLAVE_IP='192.168.127.138'
DEF_TAILNET_IP='100.64.0.1'
DEF_GLRM1_IP='192.168.0.36'
ENCLAVE_DOMAIN='oob.local'   # fijo por decisión; el instalador no pregunta otro

state_exists() { [ -f "$STATE_MARKER" ]; }

state_init() {
  mkdir -p "$STATE_DIR"
  chmod 700 "$STATE_DIR"
  [ -f "$STATE_MARKER" ] || date -Is >"$STATE_MARKER"
  local f
  for f in "$PARAMS_FILE" "$SECRETS_FILE" "$STATE_DIR/deploy.log"; do
    [ -e "$f" ] || : >"$f"
    chmod 600 "$f"
  done
  LOG_FILE="$STATE_DIR/deploy.log"
}

param_get() { kv_get "$PARAMS_FILE" "$1"; }
param_set() { kv_set "$PARAMS_FILE" "$1" "$2"; }
param_require() {
  local v; v=$(param_get "$1")
  [ -n "$v" ] || die "falta el parámetro $1 en $PARAMS_FILE: ejecuta antes la etapa 0"
  printf '%s' "$v"
}

# ─── Etapas ──────────────────────────────────────────────────────────────────
# Numeración de la sección 4.5 del inventario. El fichero de la etapa N es
# stages/<N*10 con dos cifras>-*.sh.

STAGE_MIN=0
STAGE_MAX=10

stage_file() {
  local f
  for f in "$DEPLOY_DIR/stages/$(printf '%02d' "$(( $1 * 10 ))")"-*.sh; do
    [ -f "$f" ] && { printf '%s' "$f"; return 0; }
  done
  return 1
}
stage_title()   { sed -n 's/^# TITULO: //p' "$(stage_file "$1")" | head -n1; }
stage_is_done() { [ -f "$STATE_DIR/etapa-$1.hecha" ]; }
stage_mark()    { date -Is >"$STATE_DIR/etapa-$1.hecha"; }

# ─── Docker ──────────────────────────────────────────────────────────────────
# El usuario se añade al grupo docker en la etapa 0, pero la sesión en curso no
# lo ve hasta volver a entrar. Para no obligar a cerrar sesión, mientras el
# acceso directo no funcione se ejecuta docker con el grupo docker por sudo
# (sudo -g conserva los argumentos tal cual, sin problemas de comillas).
DK_MODE=''
dk() {
  if [ -z "$DK_MODE" ]; then
    if docker info >/dev/null 2>&1; then DK_MODE=directo; else DK_MODE=grupo; fi
  fi
  if [ "$DK_MODE" = directo ]; then docker "$@"; else sudo -g docker docker "$@"; fi
}
