# shellcheck shell=bash
# checks.sh — comprobaciones de cierre de etapa.
#
# Una etapa abre con checks_begin, llama a las chk_* que le correspondan y
# cierra con checks_end. Cada comprobación imprime su propio mensaje; las
# fallidas dicen qué se esperaba y qué se encontró. Ninguna imprime secretos.

CHECK_FAILS=0
CHECK_TOTAL=0

checks_begin() { CHECK_FAILS=0; CHECK_TOTAL=0; }
chk_ok()  { CHECK_TOTAL=$((CHECK_TOTAL + 1)); printf '    OK     %s\n' "$1" >&2; _log "OK     $1"; }
# chk_bad "qué" "esperado" "encontrado"
chk_bad() {
  CHECK_TOTAL=$((CHECK_TOTAL + 1)); CHECK_FAILS=$((CHECK_FAILS + 1))
  printf '    FALLO  %s\n             esperado:   %s\n             encontrado: %s\n' "$1" "$2" "$3" >&2
  _log "FALLO  $1 | esperado: $2 | encontrado: $3"
}
checks_end() {
  if [ "$CHECK_FAILS" -eq 0 ]; then
    info "comprobaciones: $CHECK_TOTAL correctas"
    return 0
  fi
  warn "comprobaciones: $CHECK_FAILS de $CHECK_TOTAL fallidas"
  return 1
}

# ─── Ficheros ────────────────────────────────────────────────────────────────

chk_regular_file() {   # ruta  [descripción]
  local p="$1" d="${2:-$1}"
  if [ -f "$p" ] && [ ! -L "$p" ]; then chk_ok "fichero regular: $d"
  elif [ -d "$p" ]; then chk_bad "fichero regular: $d" "un fichero" "un directorio (Docker lo crea así cuando el origen de un montaje no existe)"
  elif [ -e "$p" ]; then chk_bad "fichero regular: $d" "un fichero regular" "otro tipo de entrada"
  else chk_bad "fichero regular: $d" "que exista" "no existe"; fi
}

chk_dir() {
  if [ -d "$1" ]; then chk_ok "directorio: $1"
  else chk_bad "directorio: $1" "un directorio" "$( [ -e "$1" ] && echo 'no es un directorio' || echo 'no existe')"; fi
}

chk_mode() {           # ruta  modo-esperado
  local m
  if [ ! -e "$1" ]; then chk_bad "modo $2: $1" "$2" "no existe"; return; fi
  m=$(stat -c %a "$1")
  if [ "$m" = "$2" ]; then chk_ok "modo $2: $1"; else chk_bad "modo $2: $1" "$2" "$m"; fi
}

chk_nonempty_file() {
  if [ -s "$1" ]; then chk_ok "no vacío: $1"; else chk_bad "no vacío: $1" "contenido" "vacío o inexistente"; fi
}

# ─── Certificados ────────────────────────────────────────────────────────────

# Huella de la clave pública, para comparar claves entre sí sin exponerlas.
pubkey_fp_of_key()  { openssl pkey -in "$1" -pubout -outform DER 2>/dev/null | openssl dgst -sha256 | awk '{print $NF}'; }
pubkey_fp_of_cert() { openssl x509 -in "$1" -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | openssl dgst -sha256 | awk '{print $NF}'; }

# cert_sans CERT  -> una entrada por línea: "DNS:nombre" o "IP Address:1.2.3.4"
cert_sans() {
  openssl x509 -in "$1" -noout -ext subjectAltName 2>/dev/null \
    | sed '1d' | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | sed '/^$/d'
}

chk_cert_verify() {    # CA  CERT  nombre
  local out
  if out=$(openssl verify -CAfile "$1" "$2" 2>&1); then chk_ok "$3: firmado por la CA del enclave"
  else chk_bad "$3: firmado por la CA del enclave" "openssl verify OK contra $1" "$(printf '%s' "$out" | tail -n1)"; fi
}

chk_cert_san() {       # CERT  nombre  entrada…   (entrada = "DNS:x" | "IP Address:y")
  local cert="$1" name="$2" want have missing=''
  shift 2
  have=$(cert_sans "$cert")
  for want in "$@"; do
    printf '%s\n' "$have" | grep -qxF "$want" || missing+="${missing:+, }$want"
  done
  if [ -z "$missing" ]; then chk_ok "$name: SAN con $*"
  else chk_bad "$name: SAN" "$*" "faltan: $missing (tiene: $(printf '%s' "$have" | tr '\n' ' '))"; fi
}

chk_key_matches_cert() {   # CLAVE  CERT  nombre
  local a b
  a=$(pubkey_fp_of_key "$1"); b=$(pubkey_fp_of_cert "$2")
  if [ -n "$a" ] && [ "$a" = "$b" ]; then chk_ok "$3: la clave corresponde al certificado"
  else chk_bad "$3: la clave corresponde al certificado" "misma clave pública" "distinta o ilegible"; fi
}

# La clave montada en un contenedor de terceros no puede ser la de la CA.
# Ya ocurrió una vez: docs/credenciales-de-arranque.md, sección 2.
chk_key_differs() {        # CLAVE  CLAVE_PROHIBIDA  descripción
  local a b
  a=$(pubkey_fp_of_key "$1"); b=$(pubkey_fp_of_key "$2")
  if [ -z "$a" ] || [ -z "$b" ]; then chk_bad "$3" "dos claves legibles y distintas" "alguna no se puede leer"
  elif [ "$a" != "$b" ]; then chk_ok "$3"
  else chk_bad "$3" "claves públicas distintas" "es la misma clave"; fi
}

# ─── Git ─────────────────────────────────────────────────────────────────────

# chk_ignored_or_tracked RUTA…
# Cada fichero sensible debe estar ignorado. Los que no lo estén y sean
# versionados se listan como «modificados a propósito»; el resto es un fallo.
CHK_TRACKED_MODIFIED=()
chk_ignored_or_tracked() {
  local p rel
  for p in "$@"; do
    rel="${p#"$REPO_ROOT"/}"
    if git -C "$REPO_ROOT" check-ignore -q -- "$rel"; then
      chk_ok "ignorado por git: $rel"
    elif git -C "$REPO_ROOT" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
      CHK_TRACKED_MODIFIED+=("$rel")
      chk_ok "versionado, modificado a propósito: $rel"
    else
      chk_bad "ignorado por git: $rel" "ignorado, o versionado a propósito" "ni ignorado ni versionado: un 'git add' lo subiría"
    fi
  done
}
