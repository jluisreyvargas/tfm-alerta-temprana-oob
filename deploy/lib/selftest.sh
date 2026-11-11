# shellcheck shell=bash
# shellcheck disable=SC2016  # comillas simples a propósito: texto para awk, sed o sh
# selftest.sh — pruebas de las funciones puras del instalador.
#
# Sin sudo y sin Docker. Todo ocurre en un directorio temporal que se elimina
# al terminar; no se toca ni el repositorio ni el sistema. Lo que necesita un
# host real (paquetes, /etc/hosts, imágenes, almacén de confianza) NO se prueba
# aquí: queda para la VM.

ST_PASS=0
ST_FAIL=0
ST_TMP=''

st_ok()   { ST_PASS=$((ST_PASS + 1)); printf '  ok    %s\n' "$1"; }
st_fail() { ST_FAIL=$((ST_FAIL + 1)); printf '  FALLO %s\n' "$1"; }
# st_eq "descripción" ESPERADO OBTENIDO
st_eq() {
  if [ "$2" = "$3" ]; then st_ok "$1"
  else st_fail "$1 (esperado: '$2' · obtenido: '$3')"; fi
}
# st_true "descripción" orden…   /   st_false "descripción" orden…
st_true()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then st_ok "$d"; else st_fail "$d"; fi; }
st_false() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then st_fail "$d"; else st_ok "$d"; fi; }

ST_ITER=200

# ─── 1. Generadores, cada uno contra su restricción ──────────────────────────
st_generators() {
  printf '\n[1] Generadores (%d iteraciones cada uno)\n' "$ST_ITER"
  local i v bad

  bad=0
  for i in $(seq "$ST_ITER"); do
    v=$(gen_hex 32); { [ "${#v}" -eq 64 ] && is_hex "$v"; } || bad=$((bad + 1))
  done
  st_eq "gen_hex 32: 64 hexadecimales en minúscula" 0 "$bad"

  bad=0
  for i in $(seq "$ST_ITER"); do
    v=$(gen_b64 48)
    { [ "${#v}" -eq 64 ] && is_b64 "$v" && [[ "$v" != *$'\n'* ]]; } || bad=$((bad + 1))
  done
  st_eq "gen_b64 48: 64 caracteres base64, sin salto de línea" 0 "$bad"

  bad=0
  for i in $(seq "$ST_ITER"); do
    v=$(gen_b64 24); { [ "${#v}" -eq 32 ] && is_b64 "$v"; } || bad=$((bad + 1))
  done
  st_eq "gen_b64 24: 32 caracteres base64" 0 "$bad"

  bad=0
  for i in $(seq "$ST_ITER"); do
    v=$(gen_alnum 48)
    { [ "${#v}" -eq 48 ] && is_alnum "$v" && [[ "$v" =~ [A-Z] && "$v" =~ [a-z] && "$v" =~ [0-9] ]]; } || bad=$((bad + 1))
  done
  st_eq "gen_alnum 48 (Mongo): solo alfanumérico, con mayúscula, minúscula y dígito" 0 "$bad"

  bad=0
  for i in $(seq "$ST_ITER"); do
    v=$(gen_alnum 20); { [ "${#v}" -eq 20 ] && is_alnum "$v"; } || bad=$((bad + 1))
  done
  st_eq "gen_alnum 20: longitud exacta" 0 "$bad"

  bad=0
  for i in $(seq "$ST_ITER"); do
    v=$(gen_wazuh_api)
    { [ "${#v}" -eq 32 ] && wazuh_policy_ok "$v" && [[ "${v:0:1}" =~ [A-Za-z0-9] ]]; } || bad=$((bad + 1))
  done
  st_eq "gen_wazuh_api: cumple la política y empieza por alfanumérico" 0 "$bad"

  bad=0
  for i in $(seq "$ST_ITER"); do
    v=$(gen_urlsafe 64); { [ "${#v}" -eq 86 ] && is_urlsafe "$v"; } || bad=$((bad + 1))
  done
  st_eq "gen_urlsafe 64 (IRIS): 86 caracteres [A-Za-z0-9_-], como token_urlsafe(64)" 0 "$bad"

  local a b
  a=$(gen_hex 32); b=$(gen_hex 32)
  if [ "$a" != "$b" ]; then st_ok "dos llamadas seguidas dan valores distintos"; else st_fail "dos llamadas seguidas dan el mismo valor"; fi

  printf '\n[1b] El validador de la política de Wazuh discrimina\n'
  st_true  "acepta: mayúscula+minúscula+dígito+símbolo"       wazuh_policy_ok 'Abcdef1.'
  st_false "rechaza: sin símbolo"                             wazuh_policy_ok 'Abcdefg1'
  st_false "rechaza: sin mayúscula"                           wazuh_policy_ok 'abcdef1.'
  st_false "rechaza: sin minúscula"                           wazuh_policy_ok 'ABCDEF1.'
  st_false "rechaza: sin dígito"                              wazuh_policy_ok 'Abcdefg.'
  st_false "rechaza: 7 caracteres"                            wazuh_policy_ok 'Abcd1.x'
  st_false "rechaza: 65 caracteres"                           wazuh_policy_ok "Aa1.$(printf 'x%.0s' $(seq 61))"
  st_false "rechaza: símbolo fuera de .*+?-"                  wazuh_policy_ok 'Abcdef1!'
  st_false "is_alnum rechaza un carácter reservado de URI"    is_alnum 'abc@DEF123'
  st_false "is_alnum rechaza la cadena vacía"                 is_alnum ''
}

# ─── 2. Escritura idempotente de clave=valor ─────────────────────────────────
st_kv() {
  printf '\n[2] Escritura de clave=valor en un .env\n'
  local f="$ST_TMP/kv.env" before after raro

  printf '# comentario\nA=1\n\nB=dos\n# B=comentada\nC=\n' >"$f"
  chmod 600 "$f"

  kv_set "$f" B nuevo
  st_eq "sustituye el valor en su sitio" "nuevo" "$(kv_get "$f" B)"
  st_eq "no duplica la clave" 1 "$(kv_count "$f" B)"
  st_eq "no toca el resto de líneas" "$(printf '# comentario\nA=1\n\nB=nuevo\n# B=comentada\nC=')" "$(cat "$f")"
  st_eq "conserva el modo 600" 600 "$(stat -c %a "$f")"

  kv_set "$f" C lleno
  st_eq "rellena una clave vacía" "lleno" "$(kv_get "$f" C)"

  kv_set "$f" NUEVA valor
  st_eq "añade al final una clave que no existía" "NUEVA=valor" "$(tail -n1 "$f")"
  st_eq "la línea comentada '# B=' sigue intacta" 1 "$(grep -c '^# B=comentada$' "$f")"

  before=$(cat "$f"; stat -c %Y%i "$f")
  kv_set "$f" B nuevo; kv_set "$f" NUEVA valor
  after=$(cat "$f"; stat -c %Y%i "$f")
  st_eq "repetir la misma escritura no cambia el fichero (ni lo reescribe)" "$before" "$after"

  raro='a&b/c\d=e$f*g?h|i"j k'"'"'l'
  kv_set "$f" RARO "$raro"
  st_eq "valor con & / \\ = \$ * ? | comillas y espacio: se guarda literal" "$raro" "$(kv_get "$f" RARO)"

  printf 'D=1\nD=2\nD=3\n' >>"$f"
  kv_set "$f" D unico
  st_eq "una clave repetida queda en una sola línea" 1 "$(kv_count "$f" D)"
  st_eq "y con el valor nuevo" "unico" "$(kv_get "$f" D)"

  kv_set "$f" AB x
  st_eq "una clave que es prefijo de otra no la pisa (A frente a AB)" "1" "$(kv_get "$f" A)"

  st_eq "no quedan ficheros temporales" 0 "$(find "$ST_TMP" -maxdepth 1 -name 'kv.env.tmp.*' | wc -l)"

  printf '\n[2b] Almacén de secretos\n'
  SECRETS_FILE="$ST_TMP/secrets.env"; : >"$SECRETS_FILE"; chmod 600 "$SECRETS_FILE"
  secret_ensure UNO gen_hex 32
  before=$(secret_get UNO)
  secret_ensure UNO gen_hex 32
  st_eq "secret_ensure no regenera un secreto que ya existe" "$before" "$(secret_get UNO)"
  st_eq "el almacén tiene una sola línea para la clave" 1 "$(kv_count "$SECRETS_FILE" UNO)"

  printf 'X=\nOS_PASS=\n' >"$ST_TMP/a.env"; printf 'OS_PASS=\n' >"$ST_TMP/b.env"
  secret_ensure INDEXER_PASSWORD gen_b64 24
  env_put_secret "$ST_TMP/a.env" OS_PASS INDEXER_PASSWORD
  env_put_secret "$ST_TMP/b.env" OS_PASS INDEXER_PASSWORD
  st_eq "una entrada del almacén alimenta la misma clave en dos .env" \
    "$(kv_get "$ST_TMP/a.env" OS_PASS)" "$(kv_get "$ST_TMP/b.env" OS_PASS)"
  st_false "env_put_secret falla si el almacén no tiene la entrada" env_put_secret "$ST_TMP/a.env" X NO_EXISTE

  printf 'P=plantilla\n' >"$ST_TMP/tpl"
  env_from_template "$ST_TMP/tpl" "$ST_TMP/c.env"
  st_eq "env_from_template crea el .env en modo 600" 600 "$(stat -c %a "$ST_TMP/c.env")"
  kv_set "$ST_TMP/c.env" P cambiado
  env_from_template "$ST_TMP/tpl" "$ST_TMP/c.env"
  st_eq "env_from_template no pisa un .env que ya existe" "cambiado" "$(kv_get "$ST_TMP/c.env" P)"
}

# ─── 3. Bloque de /etc/hosts ─────────────────────────────────────────────────
st_hosts() {
  printf '\n[3] Bloque de hosts sobre un fichero de prueba\n'
  local tsv="$REPO_ROOT/docs/resolucion-nombres.tsv" h="$ST_TMP/hosts" b="$ST_TMP/block" n1 n2 n3

  hosts_render_block "$tsv" 10.0.0.5 100.64.0.9 10.1.1.7 10.1.1.8 >"$b"
  st_eq "13 filas 'ubuntu' del .tsv" 13 "$(wc -l <"$b" | tr -d ' ')"
  st_eq "hs.oob.local -> IP del enclave"        "10.0.0.5"   "$(awk -F'\t' '$2=="hs.oob.local"{print $1}' "$b")"
  st_eq "iris.oob.local -> IP del tailnet, con alias iris.local" "$(printf '100.64.0.9\tiris.oob.local iris.local')" "$(grep 'iris' "$b")"
  st_eq "auth.oob.local sigue en loopback"      "127.0.0.1"  "$(awk -F'\t' '$2=="auth.oob.local"{print $1}' "$b")"
  st_eq "ninguna IP del laboratorio sobrevive"  0 "$(grep -cE '192\.168\.127\.138|100\.64\.0\.1$|100\.64\.0\.1[^0-9]' "$b" || true)"
  st_eq "no entran filas de w11 ni dc01"        0 "$(grep -c 'velociraptor\.local' "$b" || true)"

  printf 'ubuntu\tx.oob.local\t10.99.99.99\ts\tj\n' >"$ST_TMP/bad.tsv"
  st_false "una IP desconocida en el .tsv es un error, no se copia tal cual" \
    hosts_render_block "$ST_TMP/bad.tsv" 1.1.1.1 2.2.2.2 3.3.3.3 4.4.4.4

  printf '127.0.0.1 localhost\n127.0.1.1 equipo\n\n# comentario del usuario\n::1 ip6-localhost\n' >"$h"
  hosts_apply_block "$h" "$b" >"$ST_TMP/h1"
  st_eq "conserva las líneas ajenas al bloque" \
    "$(printf '127.0.0.1 localhost\n127.0.1.1 equipo\n\n# comentario del usuario\n::1 ip6-localhost')" \
    "$(sed -n '1,5p' "$ST_TMP/h1")"
  st_eq "el bloque queda entre los dos marcadores" 2 "$(grep -cE '^# (>>>|<<<) tfm-oob' "$ST_TMP/h1")"

  hosts_apply_block "$ST_TMP/h1" "$b" >"$ST_TMP/h2"
  st_true "aplicar dos veces da el mismo fichero" cmp -s "$ST_TMP/h1" "$ST_TMP/h2"

  hosts_render_block "$tsv" 10.0.0.77 100.64.0.9 10.1.1.7 10.1.1.8 >"$ST_TMP/block2"
  hosts_apply_block "$ST_TMP/h2" "$ST_TMP/block2" >"$ST_TMP/h3"
  n1=$(grep -c 'hs.oob.local' "$ST_TMP/h3"); n2=$(grep -c '10.0.0.5' "$ST_TMP/h3" || true); n3=$(grep -c '10.0.0.77' "$ST_TMP/h3")
  st_eq "cambiar un parámetro reescribe el bloque: un solo hs.oob.local" 1 "$n1"
  st_eq "sin rastro de la IP anterior" 0 "$n2"
  st_eq "con la IP nueva" 1 "$n3"
  st_eq "y las líneas ajenas siguen ahí" 1 "$(grep -c '^# comentario del usuario$' "$ST_TMP/h3")"

  printf 'solo una linea sin salto final' >"$ST_TMP/hn"
  hosts_apply_block "$ST_TMP/hn" "$b" >"$ST_TMP/hn1"
  st_eq "fichero sin salto de línea final: la línea se conserva entera" "solo una linea sin salto final" "$(head -n1 "$ST_TMP/hn1")"
}

# ─── 4. PKI: sustitución de IP en los .cnf y emisión real en temporal ────────
st_pki() {
  printf '\n[4] .cnf con las IP sustituidas (copia temporal) y emisión de prueba\n'
  local src="$REPO_ROOT/fase1-infraestructura/traefik/certs" w="$ST_TMP/pki" before
  mkdir -p "$w"
  before=$(cat "$src/iris.cnf" "$src/glkvm-cloud.cnf" "$src/glkvm-device.cnf" | sha256sum)

  cnf_set_san_ip "$src/iris.cnf"         "$w/iris.cnf"         IP.2 10.0.0.5
  cnf_set_san_ip "$src/glkvm-cloud.cnf"  "$w/glkvm-cloud.cnf"  IP.1 10.1.1.7
  cnf_set_san_ip "$src/glkvm-device.cnf" "$w/glkvm-device.cnf" IP.1 10.1.1.8
  st_eq "iris.cnf: IP.2 sustituida"          "IP.2  = 10.0.0.5" "$(grep '^IP\.2' "$w/iris.cnf")"
  st_eq "iris.cnf: IP.1 (127.0.0.1) intacta" "IP.1  = 127.0.0.1" "$(grep '^IP\.1' "$w/iris.cnf")"
  st_eq "glkvm-cloud.cnf: IP.1 sustituida"   "IP.1  = 10.1.1.7" "$(grep '^IP\.1' "$w/glkvm-cloud.cnf")"
  st_eq "glkvm-device.cnf: IP.1 sustituida"  "IP.1  = 10.1.1.8" "$(grep '^IP\.1' "$w/glkvm-device.cnf")"
  st_eq "solo cambia esa línea (diff de 1 línea por fichero)" "1 1 1" \
    "$(for n in iris glkvm-cloud glkvm-device; do diff "$src/$n.cnf" "$w/$n.cnf" | grep -c '^>' ; done | tr '\n' ' ' | sed 's/ $//')"
  st_eq "los .cnf versionados no se han tocado" "$before" \
    "$(cat "$src/iris.cnf" "$src/glkvm-cloud.cnf" "$src/glkvm-device.cnf" | sha256sum)"
  st_false "una entrada que no existe (IP.9) es un error" cnf_set_san_ip "$src/iris.cnf" "$w/x.cnf" IP.9 1.2.3.4

  # CA de prueba, solo para este directorio temporal.
  openssl genrsa -out "$w/ca.key" 2048 2>/dev/null
  openssl req -x509 -new -nodes -key "$w/ca.key" -sha256 -days 2 -out "$w/ca.crt" -subj "/CN=CA de prueba selftest" 2>/dev/null

  pki_issue_leaf "$w/ca.crt" "$w/ca.key" "$w/iris.cnf"         "$w/iris.key"   "$w/iris.crt"   rsa
  pki_issue_leaf "$w/ca.crt" "$w/ca.key" "$w/glkvm-cloud.cnf"  "$w/cloud.key"  "$w/cloud.crt"  rsa
  pki_issue_leaf "$w/ca.crt" "$w/ca.key" "$w/glkvm-device.cnf" "$w/device.key" "$w/device.crt" ec

  st_true "iris: openssl verify contra la CA"          openssl verify -CAfile "$w/ca.crt" "$w/iris.crt"
  st_true "glkvm-cloud: openssl verify contra la CA"   openssl verify -CAfile "$w/ca.crt" "$w/cloud.crt"
  st_true "glkvm-device: openssl verify contra la CA"  openssl verify -CAfile "$w/ca.crt" "$w/device.crt"
  st_true "iris: SAN con los nombres y la IP del parámetro" pki_leaf_ok "$w/ca.crt" "$w/iris.key" "$w/iris.crt" \
    "DNS:iris.oob.local" "DNS:iris.local" "DNS:localhost" "IP Address:127.0.0.1" "IP Address:10.0.0.5"
  st_true "glkvm-cloud: SAN con los nombres y la IP del parámetro" pki_leaf_ok "$w/ca.crt" "$w/cloud.key" "$w/cloud.crt" \
    "DNS:glkvm-cloud.oob.local" "DNS:kvm.oob.local" "DNS:glkvm_cloud" "DNS:localhost" "IP Address:10.1.1.7" "IP Address:127.0.0.1"
  st_true "glkvm-device: SAN con los nombres y la IP del parámetro" pki_leaf_ok "$w/ca.crt" "$w/device.key" "$w/device.crt" \
    "DNS:glkvm-device.oob.local" "DNS:localhost" "IP Address:10.1.1.8" "IP Address:127.0.0.1"
  st_false "pki_leaf_ok rechaza la hoja si el parámetro ha cambiado (IP antigua del laboratorio)" \
    pki_leaf_ok "$w/ca.crt" "$w/iris.key" "$w/iris.crt" "IP Address:192.168.127.138"
  st_false "pki_leaf_ok rechaza una clave que no es la del certificado" \
    pki_leaf_ok "$w/ca.crt" "$w/cloud.key" "$w/iris.crt" "DNS:iris.oob.local"
  st_eq "glkvm-device: clave EC prime256v1" 1 "$(openssl pkey -in "$w/device.key" -noout -text 2>/dev/null | grep -c 'prime256v1')"
  st_eq "claves privadas en modo 600" "600 600 600" "$(stat -c %a "$w/iris.key" "$w/cloud.key" "$w/device.key" | tr '\n' ' ' | sed 's/ $//')"
  st_eq "extendedKeyUsage serverAuth en la hoja" 1 "$(openssl x509 -in "$w/cloud.crt" -noout -ext extendedKeyUsage 2>/dev/null | grep -c 'TLS Web Server Authentication')"

  printf '\n[4b] La comprobación «glkvm.key no es la clave de la CA» discrimina\n'
  local out
  checks_begin
  out=$(chk_key_differs "$w/cloud.key" "$w/ca.key" "prueba" 2>&1; echo "fallos=$CHECK_FAILS")
  st_eq "clave propia: pasa" "fallos=0" "$(printf '%s' "$out" | tail -n1)"
  checks_begin
  cp "$w/ca.key" "$w/copia-de-la-ca.key"
  out=$(chk_key_differs "$w/copia-de-la-ca.key" "$w/ca.key" "prueba" 2>&1; echo "fallos=$CHECK_FAILS")
  st_eq "copia de la clave de la CA: falla" "fallos=1" "$(printf '%s' "$out" | tail -n1)"
  checks_begin
  mkdir "$w/un-directorio"
  out=$(chk_regular_file "$w/un-directorio" 2>&1; echo "fallos=$CHECK_FAILS")
  st_eq "chk_regular_file: un directorio donde debía haber un fichero falla" "fallos=1" "$(printf '%s' "$out" | tail -n1)"
  checks_begin
  out=$(chk_cert_san "$w/iris.crt" iris "IP Address:192.168.127.138" 2>&1; echo "fallos=$CHECK_FAILS")
  st_eq "chk_cert_san: un SAN que falta se detecta" "fallos=1" "$(printf '%s' "$out" | tail -n1)"
  checks_begin

  printf '\n[4c] Bundle de CAs\n'
  mkdir "$w/pub"; cp "$w/ca.crt" "$w/pub/una.crt"
  openssl req -x509 -new -nodes -newkey rsa:2048 -keyout /dev/null -days 2 -out "$w/pub/otra.crt" -subj "/CN=Otra" 2>/dev/null
  printf '%s' "$(cat "$w/pub/otra.crt")" >"$w/pub/otra.crt"     # sin salto de línea final
  ca_bundle_build "$w/pub" "$w/ca.crt" >"$w/bundle.crt"
  st_eq "bundle = CAs públicas + CA del enclave (2 + 1)" 3 "$(grep -c 'BEGIN CERTIFICATE' "$w/bundle.crt")"
  st_eq "un certificado sin salto final no se pega al siguiente" 3 "$(grep -c '^-----BEGIN CERTIFICATE-----$' "$w/bundle.crt")"
  st_true "el bundle valida un certificado del enclave" openssl verify -CAfile "$w/bundle.crt" "$w/iris.crt"

  printf '\n[4d] users_database.yml\n'
  printf 'ana\tAna - IR Lead\tana@oob.local\t$argon2id$v=19$m=65536,t=3,p=4$SALPRUEBA$HASHPRUEBA\n' >"$w/rows"
  users_db_render <"$w/rows" >"$w/users.yml"
  st_eq "estructura del fichero de usuarios" \
    "$(printf 'users:\n  ana:\n    displayname: "Ana - IR Lead"\n    password: "$argon2id$v=19$m=65536,t=3,p=4$SALPRUEBA$HASHPRUEBA"\n    email: ana@oob.local\n    groups:\n      - ir_lead\n      - ir_team')" \
    "$(cat "$w/users.yml")"
  st_true  "nombre de usuario válido"            valid_username 'ir_lead2'
  st_false "nombre de usuario con mayúsculas"    valid_username 'Jose'
  st_false "nombre visible con comillas"         valid_displayname 'a"b'
  st_true  "correo válido"                       valid_email 'jose@oob.local'
  st_false "correo sin dominio"                  valid_email 'jose@'
}

# ─── 5. Lista de imágenes ────────────────────────────────────────────────────
st_images() {
  printf '\n[5] Imágenes fijadas por digest\n'
  local list n
  list=$(images_list "$REPO_ROOT")
  n=$(printf '%s\n' "$list" | wc -l | tr -d ' ')
  st_eq "24 imágenes distintas" 24 "$n"
  st_eq "todas llevan @sha256: y 64 hexadecimales" "$n" "$(printf '%s\n' "$list" | grep -cE '@sha256:[0-9a-f]{64}$')"
  st_eq "ninguna conserva una variable sin resolver" 0 "$(printf '%s\n' "$list" | grep -c '\$' || true)"
  st_eq "Rocket.Chat sale de la plantilla de fase 1" 1 "$(printf '%s\n' "$list" | grep -c '^registry.rocket.chat/rocketchat/rocket.chat:8\.4\.3@sha256:')"
  st_eq "las tres de IRIS salen de su plantilla" 3 "$(printf '%s\n' "$list" | grep -c '^ghcr.io/dfir-iris/iriswebapp_.*:v2\.4\.27@sha256:')"
  st_eq "misp-core y misp-modules salen de template.env" 2 "$(printf '%s\n' "$list" | grep -cE '^ghcr.io/misp/misp-docker/misp-(core|modules):latest@sha256:')"
  st_eq "no entra ninguna flotante (minio/mc, misp-guard, coturn)" 0 "$(printf '%s\n' "$list" | grep -cE 'minio/mc|misp-guard|coturn' || true)"
  st_eq "image_by_digest quita la etiqueta" "traefik@sha256:abc" "$(image_by_digest 'traefik:v3.3@sha256:abc')"
  st_eq "image_by_digest respeta un registro con ruta" "ghcr.io/a/b@sha256:abc" "$(image_by_digest 'ghcr.io/a/b:latest@sha256:abc')"
  st_eq "image_by_digest deja igual una referencia sin etiqueta" "glzhitong/glkvm-cloud@sha256:abc" "$(image_by_digest 'glzhitong/glkvm-cloud@sha256:abc')"
}

# ─── 6. Analizadores de la etapa 0 ───────────────────────────────────────────
st_parsers() {
  printf '\n[6] Analizadores de interfaces y puertos (sobre texto de muestra)\n'
  local ip_out ss_t ss_u
  ip_out='1: lo    inet 127.0.0.1/8 scope host lo\       valid_lft forever preferred_lft forever
2: ens33    inet 192.168.0.70/24 brd 192.168.0.255 scope global ens33\       valid_lft forever
3: ens34    inet 192.168.127.138/24 brd 192.168.127.255 scope global ens34\       valid_lft forever
4: docker0    inet 172.17.0.1/16 brd 172.17.255.255 scope global docker0\       valid_lft forever
5: br-1a2b3c    inet 172.18.0.1/16 scope global br-1a2b3c\       valid_lft forever
6: tailscale0    inet 100.64.0.1/32 scope global tailscale0\       valid_lft forever'
  st_eq "interfaces: quedan las físicas, sin lo, docker, bridges ni tailscale" \
    "$(printf 'ens33 192.168.0.70\nens34 192.168.127.138')" "$(printf '%s\n' "$ip_out" | ifaces_parse)"

  ss_t='LISTEN 0      4096   127.0.0.53%lo:53        0.0.0.0:*
LISTEN 0      511          0.0.0.0:80        0.0.0.0:*
LISTEN 0      128          0.0.0.0:22        0.0.0.0:*
LISTEN 0      4096            [::]:9200         [::]:*
LISTEN 0      4096       127.0.0.1:8001      0.0.0.0:*'
  st_eq "puertos TCP ocupados de la lista: 80, 9200 y 8001" "80 9200 8001 " \
    "$(printf '%s\n' "$ss_t" | ports_busy '80 443 1514 1515 55000 9200 8001 9000 8888')"
  st_eq "el 22 no está en la lista y no se informa" 0 \
    "$(printf '%s\n' "$ss_t" | ports_busy '80 443' | grep -c 22 || true)"
  st_eq "8080 no se confunde con 80" "" "$(printf 'LISTEN 0 1 0.0.0.0:8080 0.0.0.0:*\n' | ports_busy '80 443')"
  ss_u='UNCONN 0      0      127.0.0.53%lo:53        0.0.0.0:*
UNCONN 0      0            0.0.0.0:3478      0.0.0.0:*'
  st_eq "puertos UDP ocupados de la lista: 3478" "3478 " "$(printf '%s\n' "$ss_u" | ports_busy '514 3478')"
  st_eq "sin nada escuchando no se informa ninguno" "" "$(printf '' | ports_busy '80 443')"

  st_true  "is_ipv4 acepta 192.168.0.70"   is_ipv4 192.168.0.70
  st_true  "is_ipv4 acepta 010.1.1.8 (ceros a la izquierda, no octal)" is_ipv4 010.1.1.8
  st_false "is_ipv4 rechaza 256.1.1.1"     is_ipv4 256.1.1.1
  st_false "is_ipv4 rechaza tres octetos"  is_ipv4 10.1.1
  st_false "is_ipv4 rechaza un nombre"     is_ipv4 kvm.oob.local
  st_false "is_ipv4 rechaza vacío"         is_ipv4 ''
}

# ─── 7. Estructura del instalador ────────────────────────────────────────────
st_structure() {
  printf '\n[7] Etapas y stubs\n'
  local n f rc missing=0 titles=0 bad=0
  for n in $(seq "$STAGE_MIN" "$STAGE_MAX"); do
    if f=$(stage_file "$n"); then
      [ -n "$(stage_title "$n")" ] && titles=$((titles + 1))
    else
      missing=$((missing + 1))
    fi
  done
  st_eq "hay un fichero por etapa, de la 0 a la 10" 0 "$missing"
  st_eq "todas declaran su título" 11 "$titles"
  st_eq "etapa 10 -> stages/100-*.sh" "100-paquete.sh" "$(basename "$(stage_file 10)")"

  for n in $(seq 2 "$STAGE_MAX"); do
    f=$(stage_file "$n")
    set +e
    # shellcheck disable=SC1090
    ( set -euo pipefail; . "$f"; stage_main ) >/dev/null 2>&1
    rc=$?
    set -e
    [ "$rc" -ne 0 ] || bad=$((bad + 1))
  done
  st_eq "los stubs de las etapas 2 a 10 salen con error" 0 "$bad"
  st_eq "los stubs no llaman a docker, curl, sudo ni a ninguna API" 0 \
    "$(cat "$DEPLOY_DIR"/stages/[2-9]0-*.sh "$DEPLOY_DIR"/stages/100-*.sh | grep -vE '^[[:space:]]*#' | grep -cE 'docker|curl|sudo|wget|https?://' || true)"

  st_eq "ningún fichero del instalador activa la traza del shell" 0 \
    "$(find "$DEPLOY_DIR" -name '*.sh' ! -name selftest.sh -exec cat {} + | grep -vE '^[[:space:]]*#' | grep -cE 'set -[a-z]*x|set -o xtrace|bash -x' || true)"
}

selftest_main() {
  ST_TMP=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$ST_TMP'" EXIT
  LOG_FILE=''

  # Las funciones puras de las etapas. Cargar los ficheros solo define
  # funciones y variables; no ejecuta ningún paso.
  # shellcheck source=stages/00-host.sh
  . "$DEPLOY_DIR/stages/00-host.sh"
  # shellcheck source=stages/10-material.sh
  . "$DEPLOY_DIR/stages/10-material.sh"

  printf 'selftest de deploy.sh — sin sudo, sin Docker, en %s\n' "$ST_TMP"
  st_generators
  st_kv
  st_hosts
  st_pki
  st_images
  st_parsers
  st_structure

  printf '\n──────────────────────────────────────────\n'
  printf 'correctas: %d   fallidas: %d\n' "$ST_PASS" "$ST_FAIL"
  if [ "$ST_FAIL" -eq 0 ]; then printf 'SELFTEST: OK\n'; return 0; fi
  printf 'SELFTEST: FALLO\n'
  return 1
}
