# shellcheck shell=bash
# shellcheck disable=SC2034  # ASK_VALUE y SECRET_VALUE los lee quien llama
# ui.sh — salida por pantalla, registro y preguntas.
#
# Regla de este fichero: aquí no entra ningún secreto. Las funciones de
# registro reciben solo texto descriptivo; ask_secret devuelve el valor en una
# variable y no lo escribe ni en pantalla ni en el log.

LOG_FILE="${LOG_FILE:-}"

_log() {
  [ -n "$LOG_FILE" ] || return 0
  printf '%s %s\n' "$(date -Is)" "$*" >>"$LOG_FILE" 2>/dev/null || true
}

step() { printf '\n==> %s\n' "$*" >&2; _log "ETAPA  $*"; }
info() { printf '    %s\n' "$*" >&2; _log "INFO   $*"; }
warn() { printf '    AVISO: %s\n' "$*" >&2; _log "AVISO  $*"; }
die()  { printf '\nERROR: %s\n' "$*" >&2; _log "ERROR  $*"; exit 1; }

# ask "pregunta" "valor por defecto"  -> resultado en ASK_VALUE
ask() {
  local prompt="$1" def="${2:-}" ans
  if [ -n "$def" ]; then
    printf '    %s [%s]: ' "$prompt" "$def" >&2
  else
    printf '    %s: ' "$prompt" >&2
  fi
  IFS= read -r ans || die "no hay entrada interactiva: el instalador necesita un terminal"
  ASK_VALUE="${ans:-$def}"
}

# ask_secret "pregunta"  -> resultado en SECRET_VALUE (sin eco, sin registro)
ask_secret() {
  local ans
  printf '    %s: ' "$1" >&2
  IFS= read -rs ans || die "no hay entrada interactiva: el instalador necesita un terminal"
  printf '\n' >&2
  SECRET_VALUE="$ans"
}

# confirm "pregunta"  -> 0 si la respuesta es s/S/si/sí
confirm() {
  local ans
  printf '    %s [s/N]: ' "$1" >&2
  IFS= read -r ans || die "no hay entrada interactiva: el instalador necesita un terminal"
  case "$ans" in s|S|si|Si|SI|sí|Sí|SÍ) return 0 ;; *) return 1 ;; esac
}

# is_ipv4 "texto"  -> 0 si es una IPv4 con cuatro octetos 0-255
is_ipv4() {
  local ip="$1" o
  [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1
  local IFS=.
  for o in $ip; do
    [ "$((10#$o))" -le 255 ] || return 1
  done
}

# ask_ipv4 "pregunta" "defecto"  -> ASK_VALUE, repite hasta que sea válida
ask_ipv4() {
  while :; do
    ask "$1" "${2:-}"
    is_ipv4 "$ASK_VALUE" && return 0
    warn "'$ASK_VALUE' no es una dirección IPv4"
  done
}
