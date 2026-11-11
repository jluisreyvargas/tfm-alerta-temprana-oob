# shellcheck shell=bash
# secrets.sh — ficheros clave=valor, generadores y almacén de secretos.
#
# Reglas:
#   - Ningún valor pasa por la línea de argumentos de un proceso externo (sería
#     visible en la lista de procesos): awk los recibe por entorno.
#   - Ningún fichero clave=valor se carga con "source": los valores pueden
#     llevar caracteres que el shell interpretaría. Se leen con kv_get.
#   - Nada de este fichero imprime un valor salvo por la salida estándar de un
#     generador o de kv_get, que quien llama captura en una variable.

# ─── Ficheros clave=valor ────────────────────────────────────────────────────

# kv_has FICHERO CLAVE
kv_has() {
  [ -f "$1" ] || return 1
  KV_KEY="$2" awk 'BEGIN{k=ENVIRON["KV_KEY"]"="} index($0,k)==1{f=1; exit} END{exit f?0:1}' "$1"
}

# kv_get FICHERO CLAVE  -> valor de la primera aparición (vacío si no existe)
kv_get() {
  [ -f "$1" ] || return 0
  KV_KEY="$2" awk 'BEGIN{k=ENVIRON["KV_KEY"]"="} index($0,k)==1{print substr($0,length(k)+1); exit}' "$1"
}

# kv_count FICHERO CLAVE  -> número de líneas que definen la clave
kv_count() {
  [ -f "$1" ] || { echo 0; return 0; }
  KV_KEY="$2" awk 'BEGIN{k=ENVIRON["KV_KEY"]"="} index($0,k)==1{n++} END{print n+0}' "$1"
}

# kv_set FICHERO CLAVE VALOR
# Escribe clave=valor sin tocar el resto de líneas y sin duplicar la clave:
# sustituye la primera aparición en su sitio, elimina las repetidas y, si no
# existía, la añade al final. Conserva el modo del fichero. Si el fichero ya
# tiene exactamente ese valor una sola vez, no lo reescribe.
kv_set() {
  local file="$1" key="$2" val="$3" tmp mode
  if [ ! -e "$file" ]; then
    ( umask 077; : >"$file" )
  fi
  if [ "$(kv_count "$file" "$key")" = "1" ] && [ "$(kv_get "$file" "$key")" = "$val" ]; then
    return 0
  fi
  mode=$(stat -c %a "$file")
  tmp=$(mktemp "${file}.tmp.XXXXXX")
  KV_KEY="$key" KV_VAL="$val" awk '
    BEGIN { k = ENVIRON["KV_KEY"] "="; v = ENVIRON["KV_VAL"]; done = 0 }
    index($0, k) == 1 { if (!done) { print k v; done = 1 } ; next }
    { print }
    END { if (!done) print k v }
  ' "$file" >"$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$file"
}

# ─── Generadores (uno por tipo de restricción) ───────────────────────────────
# Restricciones: docs/despliegue/INVENTARIO-despliegue.md, sección 1, columna
# «Restricciones».

ALPHA_ALNUM='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
# Símbolos que admite la política de la API de Wazuh
# (fase2-orquestador/README.md:546).
WAZUH_SYMBOLS='.*+?-'

# _gen_from_alphabet LONGITUD ALFABETO
# Muestreo por rechazo sobre bytes aleatorios: sin sesgo de módulo.
_gen_from_alphabet() {
  local len="$1" alpha="$2" n="${#2}" out='' b limit
  limit=$(( 256 - 256 % n ))
  while [ "${#out}" -lt "$len" ]; do
    for b in $(openssl rand 64 | od -An -v -tu1); do
      [ "$b" -lt "$limit" ] || continue
      out+="${alpha:$(( b % n )):1}"
      [ "${#out}" -lt "$len" ] || break
    done
  done
  printf '%s' "$out"
}

# gen_hex BYTES  -> 2*BYTES hexadecimales (openssl rand -hex)
gen_hex() { openssl rand -hex "$1"; }

# gen_b64 BYTES  -> base64 sin salto de línea
gen_b64() { openssl rand -base64 "$1" | tr -d '\n'; }

# gen_alnum LONGITUD  -> solo [A-Za-z0-9], con al menos una mayúscula, una
# minúscula y un dígito. Para valores que viajan dentro de una URI (Mongo,
# PostgreSQL de IRIS) o que no deben necesitar comillas.
gen_alnum() {
  local v
  while :; do
    v=$(_gen_from_alphabet "$1" "$ALPHA_ALNUM")
    [[ "$v" =~ [A-Z] && "$v" =~ [a-z] && "$v" =~ [0-9] ]] && break
  done
  printf '%s' "$v"
}

# gen_wazuh_api  -> 32 caracteres conformes a la política de la API de Wazuh:
# 8-64, con mayúscula, minúscula, número y símbolo de .*+?-
# El primer carácter es alfanumérico para que ninguna herramienta lo tome por
# una opción.
gen_wazuh_api() {
  local v
  while :; do
    v="$(_gen_from_alphabet 1 "$ALPHA_ALNUM")$(_gen_from_alphabet 31 "${ALPHA_ALNUM}${WAZUH_SYMBOLS}")"
    wazuh_policy_ok "$v" && break
  done
  printf '%s' "$v"
}

# gen_urlsafe BYTES  -> base64url sin relleno, como secrets.token_urlsafe de
# Python. IRIS genera así su clave de API con 64 bytes
# (fase6-iris/source/app/post_init.py:1058; models/authorization.py:229).
gen_urlsafe() { openssl rand -base64 "$1" | tr -d '\n=' | tr '+/' '-_'; }

# ─── Validadores ─────────────────────────────────────────────────────────────

is_hex()     { [[ "$1" =~ ^[0-9a-f]+$ ]]; }
is_alnum()   { [[ "$1" =~ ^[A-Za-z0-9]+$ ]]; }
is_b64()     { [[ "$1" =~ ^[A-Za-z0-9+/]+={0,2}$ ]]; }
is_urlsafe() { [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]; }

wazuh_policy_ok() {
  local v="$1"
  [ "${#v}" -ge 8 ] && [ "${#v}" -le 64 ] || return 1
  [[ "$v" =~ ^[A-Za-z0-9.*+?-]+$ ]] || return 1
  [[ "$v" =~ [A-Z] ]] || return 1
  [[ "$v" =~ [a-z] ]] || return 1
  [[ "$v" =~ [0-9] ]] || return 1
  [[ "$v" =~ [.*+?-] ]] || return 1
}

# ─── Almacén de secretos ─────────────────────────────────────────────────────
# Un único fichero, modo 600. Cada secreto se genera una sola vez.

SECRETS_FILE="${SECRETS_FILE:-}"

secret_has() { kv_has "$SECRETS_FILE" "$1" && [ -n "$(kv_get "$SECRETS_FILE" "$1")" ]; }
secret_get() { kv_get "$SECRETS_FILE" "$1"; }
secret_put() { kv_set "$SECRETS_FILE" "$1" "$2"; }

# secret_ensure CLAVE GENERADOR [ARGS…]
# Genera y guarda solo si la clave no existe todavía.
secret_ensure() {
  local key="$1" v; shift
  secret_has "$key" && return 0
  v=$("$@")
  [ -n "$v" ] || { printf 'ERROR: el generador de %s no ha producido valor\n' "$key" >&2; return 1; }
  secret_put "$key" "$v"
}

# env_from_template PLANTILLA DESTINO
# Crea el .env a partir de su plantilla si todavía no existe. Modo 600.
env_from_template() {
  [ -f "$2" ] && { chmod 600 "$2"; return 0; }
  [ -f "$1" ] || { printf 'ERROR: no existe la plantilla %s\n' "$1" >&2; return 1; }
  install -m 600 "$1" "$2"
}

# env_put_secret FICHERO_ENV CLAVE_ENV [CLAVE_ALMACEN]
# Copia un secreto del almacén a un .env. Una sola entrada del almacén puede
# alimentar claves de nombre distinto en varios ficheros.
env_put_secret() {
  local v
  v=$(secret_get "${3:-$2}")
  [ -n "$v" ] || { printf 'ERROR: el almacén no tiene %s\n' "${3:-$2}" >&2; return 1; }
  kv_set "$1" "$2" "$v"
}
