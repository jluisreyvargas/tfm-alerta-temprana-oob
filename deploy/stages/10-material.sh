# shellcheck shell=bash
# shellcheck disable=SC2016  # comillas simples a propósito: texto para awk, sed o sh
# TITULO: Material previo — secretos, .env, PKI, ficheros y usuarios de Authelia
#
# Etapa 1 de la sección 4.5 del inventario. Todo lo que se puede crear antes de
# arrancar el primer servicio. No arranca nada: solo usa Docker para calcular
# los hashes de Authelia con la imagen ya descargada en la etapa 0.
#
# Idempotente: lo que ya existe y es válido no se regenera. En particular,
# ningún secreto del almacén ni ninguna clave privada se vuelve a crear.

F1="$REPO_ROOT/fase1-infraestructura"
CERTS="$F1/traefik/certs"
WAZUH="$F1/wazuh/single-node"
N8N="$REPO_ROOT/fase2-orquestador/n8n"
F3="$REPO_ROOT/fase3-agentic"
F4="$REPO_ROOT/fase4-breakglass-dc"
F5V="$REPO_ROOT/fase5-velociraptor"
F5A="$REPO_ROOT/fase5-orchestrator-api"
F6="$REPO_ROOT/fase6-iris"
F8="$REPO_ROOT/fase8-kvm/glkvm-cloud/docker-compose"
MISP="$REPO_ROOT/misp/misp-docker"

CA_CRT="$CERTS/oob-rootCA.crt"
CA_KEY="$CERTS/oob-rootCA.key"

# Validez de las hojas: la misma que usa generate-oob-ca.sh para el comodín
# (fase1-infraestructura/traefik/generate-oob-ca.sh:29, DAYS_LEAF).
LEAF_DAYS=825

# Certificados públicos de la distribución (paquete ca-certificates). Se usan
# para rehacer el bundle de IRIS: CAs públicas + CA del enclave
# (fase6-iris/README.md:254; docs/INFORME-AUDITORIA-FASE6.md, P1-6).
MOZILLA_CA_DIR=/usr/share/ca-certificates/mozilla

# El nginx de IRIS no corre como root sino como www-data
# (fase6-iris/docker/nginx/Dockerfile:45), uid 33 en la imagen base. Su clave
# privada queda en modo 600 pero con ese propietario, o no podría leerla.
IRIS_NGINX_UID=33

# Valores públicos que traen el compose de fase 8 y el de MISP como defecto o
# como ejemplo. Ninguno puede acabar en un .env (inventario, 1.8 y 1.9).
PUBLIC_EXAMPLES='DeviceTokenYouCanChangeMe StrongP@ssw0rd AnotherS3cret example password redispassword admin'

# ─── Funciones puras (las ejercita `deploy.sh selftest`) ─────────────────────

# cnf_set_san_ip ORIGEN DESTINO CLAVE IP
# Copia un .cnf de OpenSSL sustituyendo la IP de una entrada del SAN
# (CLAVE = IP.1, IP.2…). Falla si la entrada no existe: el .cnf ha cambiado.
cnf_set_san_ip() {
  awk -v key="$3" -v ip="$4" '
    $1 == key && $2 == "=" { print key "  = " ip; found = 1; next }
    { print }
    END { exit found ? 0 : 4 }
  ' "$1" >"$2"
}

# pki_issue_leaf CA_CRT CA_KEY CNF CLAVE_SALIDA CERT_SALIDA rsa|ec
# Emite una hoja firmada por la CA. Mismo procedimiento que
# generate-oob-ca.sh:84-90 para el comodín (petición con -config, firma con
# -CAcreateserial -sha256 -extfile -extensions ext); los .cnf versionados
# declaran la sección [ext] que se pasa a -extensions.
#   rsa: 2048 bits, como el comodín (generate-oob-ca.sh:50).
#   ec : prime256v1, la curva del firmware del GL-RM1 (fase8-kvm/README.md:254-256).
pki_issue_leaf() {
  local ca_crt="$1" ca_key="$2" cnf="$3" key="$4" crt="$5" kind="$6" csr
  case "$kind" in
    rsa) openssl genrsa -out "$key" 2048 2>/dev/null ;;
    ec)  openssl ecparam -name prime256v1 -genkey -noout -out "$key" ;;
    *)   printf 'tipo de clave desconocido: %s\n' "$kind" >&2; return 2 ;;
  esac
  chmod 600 "$key"
  csr=$(mktemp)
  openssl req -new -key "$key" -out "$csr" -config "$cnf"
  openssl x509 -req -in "$csr" \
    -CA "$ca_crt" -CAkey "$ca_key" -CAcreateserial \
    -out "$crt" -days "$LEAF_DAYS" -sha256 \
    -extfile "$cnf" -extensions ext 2>/dev/null
  rm -f "$csr"
  chmod 644 "$crt"
}

# pki_leaf_ok CA_CRT CLAVE CERT SAN…
# 0 si la hoja existe, la firma la CA, su clave es la suya y lleva esos SAN.
pki_leaf_ok() {
  local ca="$1" key="$2" crt="$3" want have
  shift 3
  [ -f "$key" ] && [ -f "$crt" ] || return 1
  openssl verify -CAfile "$ca" "$crt" >/dev/null 2>&1 || return 1
  [ "$(pubkey_fp_of_key "$key")" = "$(pubkey_fp_of_cert "$crt")" ] || return 1
  have=$(cert_sans "$crt")
  for want in "$@"; do
    printf '%s\n' "$have" | grep -qxF "$want" || return 1
  done
}

# ca_bundle_build DIRECTORIO_CAS_PUBLICAS CA_DEL_ENCLAVE  -> bundle por stdout
ca_bundle_build() {
  local f
  for f in "$1"/*.crt; do
    [ -f "$f" ] || continue
    cat "$f"
    # Algún certificado podría no terminar en salto de línea.
    [ -z "$(tail -c1 "$f")" ] || printf '\n'
  done
  cat "$2"
}

# users_db_render  < líneas "usuario<TAB>nombre<TAB>correo<TAB>hash"
# Formato de docs/README-fase1b-authelia.md:102-110.
users_db_render() {
  printf 'users:\n'
  awk -F'\t' '{
    printf "  %s:\n", $1
    printf "    displayname: \"%s\"\n", $2
    printf "    password: \"%s\"\n", $4
    printf "    email: %s\n", $3
    printf "    groups:\n      - ir_lead\n      - ir_team\n"
  }'
}

valid_username()    { [[ "$1" =~ ^[a-z][a-z0-9_-]{1,31}$ ]]; }
valid_email()       { [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; }
valid_displayname() { [[ "$1" =~ ^[^\"\\]{1,64}$ ]] && [[ "$1" != *$'\t'* ]]; }

# ─── Utilidades de la etapa ──────────────────────────────────────────────────

# put_file ORIGEN DESTINO MODO — copia solo si el contenido difiere.
put_file() {
  if [ -f "$2" ] && cmp -s "$1" "$2"; then chmod "$3" "$2"; return 0; fi
  install -m "$3" "$1" "$2"
}

ensure_dir() { mkdir -p "$1"; chmod "$2" "$1"; }

# ─── Pasos ───────────────────────────────────────────────────────────────────

s1_secrets() {
  info "secretos generables (los que ya están en el almacén no se tocan)"
  # Fase 1 — openssl rand -hex 32 (fase1-infraestructura/.env.example:11).
  secret_ensure AUTHELIA_JWT_SECRET             gen_hex 32
  secret_ensure AUTHELIA_SESSION_SECRET         gen_hex 32
  secret_ensure AUTHELIA_STORAGE_ENCRYPTION_KEY gen_hex 32
  # Mongo: solo alfanumérica, va dentro de una URI
  # (docs/HALLAZGO-credencial-mongodb-2026-09-23.md:102-105).
  secret_ensure MONGO_INITDB_ROOT_PASSWORD      gen_alnum 48
  # Wazuh — openssl rand -base64 24 (wazuh/single-node/.env.example:9-10);
  # la de la API, con su política (fase2-orquestador/README.md:546).
  secret_ensure INDEXER_PASSWORD                gen_b64 24
  secret_ensure DASHBOARD_PASSWORD              gen_b64 24
  secret_ensure API_PASSWORD                    gen_wazuh_api
  # n8n y los valores que comparte con otros ficheros.
  secret_ensure N8N_ENCRYPTION_KEY              gen_hex 32
  secret_ensure OOB_WEBHOOK_SECRET              gen_hex 32
  secret_ensure ORCH_HMAC_SECRET                gen_hex 32
  secret_ensure AGENT_TOKEN                     gen_hex 32
  secret_ensure AGENT_HMAC_SECRET               gen_hex 32
  # MinIO: raíz y usuario dedicado del orchestrator.
  secret_ensure MINIO_ROOT_USER                 gen_alnum 20
  secret_ensure MINIO_ROOT_PASSWORD             gen_alnum 40
  secret_ensure MINIO_ACCESS_KEY                gen_alnum 20
  secret_ensure MINIO_SECRET_KEY                gen_alnum 40
  # IRIS. Las de PostgreSQL van dentro de una URI sin escapar
  # (fase6-iris/source/app/configuration.py:181-190): alfanuméricas.
  secret_ensure POSTGRES_PASSWORD               gen_alnum 40
  secret_ensure POSTGRES_ADMIN_PASSWORD         gen_alnum 40
  secret_ensure IRIS_SECRET_KEY                 gen_b64 48    # fase6-iris/.env.example:33
  secret_ensure IRIS_SECURITY_PASSWORD_SALT     gen_b64 32    # fase6-iris/.env.example:35
  secret_ensure IRIS_ADM_PASSWORD               gen_alnum 32
  # Mismo formato que genera IRIS: secrets.token_urlsafe(64)
  # (fase6-iris/source/app/post_init.py:1056-1058).
  secret_ensure IRIS_ADM_API_KEY                gen_urlsafe 64
  # KVM.
  secret_ensure RTTYS_TOKEN                     gen_hex 32
  secret_ensure RTTYS_PASS                      gen_alnum 32
  secret_ensure TURN_PASS                       gen_alnum 32
  # MISP. ADMIN_KEY: 40 alfanuméricos. El código vendorizado (misp-docker) no
  # declara el formato: solo pasa el valor a `cake User change_authkey`
  # (core/files/configure_misp.sh:460-466). 40 alfanuméricos es la forma de
  # las claves que emite MISP; pendiente de confirmar en la VM.
  secret_ensure MISP_ADMIN_KEY                  gen_alnum 40
  secret_ensure MISP_ADMIN_PASSWORD             gen_alnum 32
  secret_ensure MISP_ENCRYPTION_KEY             gen_alnum 40
  secret_ensure MISP_GPG_PASSPHRASE             gen_alnum 40
  secret_ensure MISP_MYSQL_PASSWORD             gen_alnum 40
  secret_ensure MISP_MYSQL_ROOT_PASSWORD        gen_alnum 40
  secret_ensure MISP_REDIS_PASSWORD             gen_alnum 40
}

s1_external_keys() {
  local key label
  for key in VIRUSTOTAL_API_KEY ABUSEIPDB_API_KEY; do
    if kv_has "$SECRETS_FILE" "$key"; then
      if [ -n "$(secret_get "$key")" ]; then info "$key: ya está en el almacén"
      else info "$key: omitida en una ejecución anterior (para aportarla, borra su línea del almacén)"; fi
      continue
    fi
    case "$key" in
      VIRUSTOTAL_API_KEY) label="Clave de API de VirusTotal" ;;
      *)                  label="Clave de API de AbuseIPDB" ;;
    esac
    ask_secret "$label (Intro sin escribir nada = omitir)"
    secret_put "$key" "$SECRET_VALUE"
    if [ -n "$SECRET_VALUE" ]; then info "$key: guardada"
    else warn "$key: omitida; el enriquecimiento con ese servicio no funcionará"; fi
    SECRET_VALUE=''
  done
}

s1_env_files() {
  info "ficheros .env de cada fase (el de fase 4 depende de la IP del tailnet: etapa 5)"
  local e

  e="$F1/.env"; env_from_template "$F1/.env.example" "$e"
  env_put_secret "$e" AUTHELIA_JWT_SECRET
  env_put_secret "$e" AUTHELIA_SESSION_SECRET
  env_put_secret "$e" AUTHELIA_STORAGE_ENCRYPTION_KEY
  env_put_secret "$e" MONGO_INITDB_ROOT_PASSWORD

  e="$WAZUH/.env"; env_from_template "$WAZUH/.env.example" "$e"
  env_put_secret "$e" INDEXER_PASSWORD
  env_put_secret "$e" API_PASSWORD
  env_put_secret "$e" DASHBOARD_PASSWORD

  # Los cuatro valores que dependen de Rocket.Chat quedan vacíos: etapa 2.
  e="$N8N/.env"; env_from_template "$N8N/.env.example" "$e"
  env_put_secret "$e" N8N_ENCRYPTION_KEY
  env_put_secret "$e" OOB_WEBHOOK_SECRET
  env_put_secret "$e" ORCH_HMAC_SECRET
  env_put_secret "$e" AGENT_TOKEN
  env_put_secret "$e" AGENT_HMAC_SECRET

  e="$F3/.env"; env_from_template "$F3/.env.example" "$e"
  env_put_secret "$e" OS_PASS INDEXER_PASSWORD

  e="$F5V/.env"; env_from_template "$F5V/.env.example" "$e"
  env_put_secret "$e" MINIO_ROOT_USER
  env_put_secret "$e" MINIO_ROOT_PASSWORD
  # Variable inerte (ningún compose la lee) que la plantilla trae con un
  # marcador de relleno: se vacía en vez de dejar el marcador o de copiar
  # aquí una clave real que nadie consumiría.
  kv_set "$e" IRIS_API_KEY ''

  e="$F5A/.env"; env_from_template "$F5A/.env.example" "$e"
  env_put_secret "$e" OS_PASS INDEXER_PASSWORD
  env_put_secret "$e" MINIO_ACCESS_KEY
  env_put_secret "$e" MINIO_SECRET_KEY
  env_put_secret "$e" ORCH_HMAC_SECRET

  e="$F6/.env"; env_from_template "$F6/.env.example" "$e"
  env_put_secret "$e" POSTGRES_PASSWORD
  env_put_secret "$e" POSTGRES_ADMIN_PASSWORD
  env_put_secret "$e" IRIS_SECRET_KEY
  env_put_secret "$e" IRIS_SECURITY_PASSWORD_SALT
  env_put_secret "$e" IRIS_ADM_PASSWORD
  env_put_secret "$e" IRIS_ADM_API_KEY

  e="$F8/.env"; env_from_template "$F8/.env.example" "$e"
  kv_set "$e" GLKVM_ACCESS_IP "$(param_require LAN_IP)"
  env_put_secret "$e" RTTYS_TOKEN
  env_put_secret "$e" RTTYS_PASS
  env_put_secret "$e" TURN_PASS

  e="$MISP/.env"; env_from_template "$MISP/template.env" "$e"
  kv_set "$e" BASE_URL "https://misp.${ENCLAVE_DOMAIN}"
  env_put_secret "$e" ADMIN_KEY           MISP_ADMIN_KEY
  env_put_secret "$e" ADMIN_PASSWORD      MISP_ADMIN_PASSWORD
  env_put_secret "$e" ENCRYPTION_KEY      MISP_ENCRYPTION_KEY
  env_put_secret "$e" GPG_PASSPHRASE      MISP_GPG_PASSPHRASE
  # Comentadas en la plantilla: sin ellas el compose cae a valores públicos
  # (misp/misp-docker/docker-compose.yml:41,67,68).
  env_put_secret "$e" MYSQL_PASSWORD      MISP_MYSQL_PASSWORD
  env_put_secret "$e" MYSQL_ROOT_PASSWORD MISP_MYSQL_ROOT_PASSWORD
  env_put_secret "$e" REDIS_PASSWORD      MISP_REDIS_PASSWORD
  # Evita que la inicialización de MISP escriba ADMIN_KEY y ADMIN_PASSWORD en
  # claro en el log del contenedor (misp/misp-docker/template.env, comentario
  # de DISABLE_PRINTING_PLAINTEXT_CREDENTIALS).
  kv_set "$e" DISABLE_PRINTING_PLAINTEXT_CREDENTIALS true
}

# Listas de SAN esperados; las usan la emisión (para decidir si la hoja que hay
# sigue valiendo) y las comprobaciones de cierre.
_san_wildcard() { printf '%s\n' "DNS:*.${ENCLAVE_DOMAIN}" "DNS:${ENCLAVE_DOMAIN}"; }
_san_iris() {
  printf '%s\n' "DNS:iris.${ENCLAVE_DOMAIN}" "DNS:iris.local" "DNS:localhost" \
    "IP Address:127.0.0.1" "IP Address:$(param_require ENCLAVE_IP)"
}
_san_glkvm_cloud() {
  printf '%s\n' "DNS:glkvm-cloud.${ENCLAVE_DOMAIN}" "DNS:kvm.${ENCLAVE_DOMAIN}" "DNS:glkvm_cloud" \
    "DNS:localhost" "IP Address:$(param_require LAN_IP)" "IP Address:127.0.0.1"
}
_san_glkvm_device() {
  printf '%s\n' "DNS:glkvm-device.${ENCLAVE_DOMAIN}" "DNS:localhost" \
    "IP Address:$(param_require GLRM1_IP)" "IP Address:127.0.0.1"
}

# _issue NOMBRE CLAVE_SAN IP rsa|ec FUNCION_SAN
_issue() {
  local name="$1" san_key="$2" ip="$3" kind="$4" san_fn="$5" work sans=()
  mapfile -t sans < <("$san_fn")
  if pki_leaf_ok "$CA_CRT" "$CERTS/$name.key" "$CERTS/$name.crt" "${sans[@]}"; then
    info "certificado $name: ya existe y es válido para los parámetros actuales"
    return 0
  fi
  work="$STATE_DIR/pki"
  ensure_dir "$work" 700
  # El .cnf versionado no se modifica: se trabaja sobre una copia con la IP
  # del SAN sustituida por el parámetro.
  cnf_set_san_ip "$CERTS/$name.cnf" "$work/$name.cnf" "$san_key" "$ip" \
    || die "el fichero $name.cnf no tiene la entrada $san_key: ha cambiado respecto al inventario (sección 3.1)"
  pki_issue_leaf "$CA_CRT" "$CA_KEY" "$work/$name.cnf" "$CERTS/$name.key" "$CERTS/$name.crt" "$kind"
  info "certificado $name: emitido"
}

s1_pki() {
  local sans=()

  # CA y comodín: con el script existente, sin reimplementarlo.
  if [ -f "$CA_KEY" ]; then
    mapfile -t sans < <(_san_wildcard)
    pki_leaf_ok "$CA_CRT" "$CERTS/oob-wildcard.key" "$CERTS/oob-wildcard.crt" "${sans[@]}" \
      || die "existe la clave de la CA pero el comodín falta o no valida contra ella.
       generate-oob-ca.sh se niega a ejecutarse si la CA ya existe. Si esta CA
       es de un intento fallido de esta misma instalación, retira a mano
       $CERTS/oob-rootCA.key, oob-wildcard.key y oob-wildcard.crt y repite la etapa."
    info "CA y comodín: ya existen y son coherentes"
  else
    info "CA y comodín: fase1-infraestructura/traefik/generate-oob-ca.sh"
    bash "$F1/traefik/generate-oob-ca.sh" >>"$LOG_FILE" 2>&1 \
      || die "generate-oob-ca.sh ha fallado; el detalle está en ${LOG_FILE#"$REPO_ROOT"/}"
  fi

  # Hojas a partir de los .cnf versionados (inventario, sección 2.1).
  _issue iris         IP.2 "$(param_require ENCLAVE_IP)" rsa _san_iris
  _issue glkvm-cloud  IP.1 "$(param_require LAN_IP)"     rsa _san_glkvm_cloud
  _issue glkvm-device IP.1 "$(param_require GLRM1_IP)"   ec  _san_glkvm_device

  # Copias (inventario, sección 2.1).
  info "copias de la CA y de los certificados"
  put_file "$CA_CRT" "$N8N/certs/oob-rootCA.crt" 644
  ensure_dir "$F6/certificates/rootCA" 755
  put_file "$CA_CRT" "$F6/certificates/rootCA/irisRootCACert.pem" 644

  [ -d "$MOZILLA_CA_DIR" ] || die "no existe $MOZILLA_CA_DIR (paquete ca-certificates): no se puede rehacer el bundle de IRIS"
  local bundle; bundle=$(mktemp)
  ca_bundle_build "$MOZILLA_CA_DIR" "$CA_CRT" >"$bundle"
  put_file "$bundle" "$F6/certificates/rootCA/ca-bundle-oob.crt" 644
  rm -f "$bundle"

  # Certificado web de IRIS, con los nombres que declara su plantilla.
  local cert_name key_name
  cert_name=$(kv_get "$F6/.env" CERT_FILENAME)
  key_name=$(kv_get "$F6/.env" KEY_FILENAME)
  [ -n "$cert_name" ] && [ -n "$key_name" ] || die "fase6-iris/.env no define CERT_FILENAME o KEY_FILENAME"
  ensure_dir "$F6/certificates/web_certificates" 755
  put_file "$CERTS/iris.crt" "$F6/certificates/web_certificates/$cert_name" 644
  # La clave: modo 600 y propietario el usuario del nginx del contenedor.
  local kdst="$F6/certificates/web_certificates/$key_name"
  if ! sudo cmp -s "$CERTS/iris.key" "$kdst" 2>/dev/null \
     || [ "$(stat -c '%u:%a' "$kdst")" != "${IRIS_NGINX_UID}:600" ]; then
    sudo install -m 600 -o "$IRIS_NGINX_UID" -g "$IRIS_NGINX_UID" "$CERTS/iris.key" "$kdst"
  fi

  # KVM: el par de glkvm-cloud con los nombres que monta el compose
  # (docker-compose.yml:58-59). NUNCA la clave de la CA: ya ocurrió
  # (docs/credenciales-de-arranque.md, sección 2).
  ensure_dir "$F8/certificate" 700
  put_file "$CERTS/glkvm-cloud.crt" "$F8/certificate/glkvm.cer" 644
  put_file "$CERTS/glkvm-cloud.key" "$F8/certificate/glkvm.key" 600
}

s1_files() {
  info "ficheros y directorios que no dependen de ningún servicio"

  # Keyfile de Mongo: openssl rand -base64 756 (fase1-infraestructura/README.md:151).
  if [ ! -s "$F1/mongodb/mongo-keyfile" ]; then
    ( umask 077; openssl rand -base64 756 >"$F1/mongodb/mongo-keyfile" )
  fi
  chmod 600 "$F1/mongodb/mongo-keyfile"

  # Traefik monta acme.json como fichero aunque no use ACME
  # (docs/README-fase1a-traefik-portainer.md:288-289).
  [ -e "$F1/traefik/acme.json" ] || : >"$F1/traefik/acme.json"
  chmod 600 "$F1/traefik/acme.json"

  # n8n monta peers.json como fichero. Si no existe, Docker crea un directorio.
  # Lo lee el usuario del contenedor, que no es root: 644. No es un secreto.
  ensure_dir "$F4/rustdesk" 755
  [ -s "$F4/rustdesk/peers.json" ] || printf '[]\n' >"$F4/rustdesk/peers.json"
  chmod 644 "$F4/rustdesk/peers.json"

  # Deben existir antes de arrancar o Docker los crea de root
  # (fase6-iris/README.md:255-262).
  ensure_dir "$F6/certificates/ldap" 755
  ensure_dir "$F5V/velociraptor-config" 700
}

# _authelia_hash IMAGEN  (la contraseña llega en la variable AUTHELIA_PW_IN)
# -> hash argon2id por stdout.
# La ayuda documentada en el repositorio solo recoge el paso por argumento
# (docs/README-fase1b-authelia.md:222-223). Para que la contraseña no aparezca
# en la línea de órdenes de docker se entrega por --env-file y el argumento se
# forma dentro del contenedor; sigue siendo visible, mientras dura el cálculo,
# en los argumentos del proceso authelia.
_authelia_hash() {
  local img="$1" envf out
  envf=$(mktemp "$STATE_DIR/authelia-env.XXXXXX")
  chmod 600 "$envf"
  printf 'AUTHELIA_PW=%s\n' "$AUTHELIA_PW_IN" >"$envf"
  out=$(dk run --rm --network none --env-file "$envf" --entrypoint sh "$img" \
          -c 'authelia crypto hash generate argon2 --password "$AUTHELIA_PW"' 2>/dev/null) || true
  rm -f "$envf"
  printf '%s' "$out" | grep -oE '\$argon2id\$[^[:space:]"]+' | head -n1 || true
}

s1_authelia_users() {
  local db="$F1/authelia/users_database.yml"
  if [ -f "$db" ] && grep -qE '^[[:space:]]+password: "\$argon2' "$db"; then
    chmod 600 "$db"
    info "usuarios de Authelia: users_database.yml ya existe; no se modifica"
    return 0
  fi

  local img names=() disps=() mails=() pws=() origins=() i u d m p p2
  img=$(image_by_digest "$(images_list "$REPO_ROOT" | grep -E '^authelia/authelia:' | head -n1)")
  [ -n "$img" ] || die "no se encuentra la imagen de Authelia en la lista de imágenes fijadas"

  printf '\n    Usuarios de Authelia (grupo ir_lead). Hace falta al menos uno;\n' >&2
  printf '    el flujo de aprobación de dos personas necesita dos.\n\n' >&2
  while :; do
    names=(); disps=(); mails=(); pws=(); origins=()
    while :; do
      while :; do
        ask "Nombre de usuario (minúsculas, dígitos, - y _)" ""
        u="$ASK_VALUE"
        if ! valid_username "$u"; then warn "nombre de usuario no válido"; continue; fi
        if printf '%s\n' "${names[@]:-}" | grep -qxF "$u"; then warn "usuario repetido"; continue; fi
        break
      done
      while :; do
        ask "Nombre visible" "$u"; d="$ASK_VALUE"
        valid_displayname "$d" && break
        warn "el nombre visible no puede llevar comillas, barras invertidas ni tabuladores"
      done
      while :; do
        ask "Correo" "${u}@${ENCLAVE_DOMAIN}"; m="$ASK_VALUE"
        valid_email "$m" && break
        warn "correo no válido"
      done
      while :; do
        ask_secret "Contraseña (Intro sin escribir nada = generar una)"; p="$SECRET_VALUE"
        if [ -z "$p" ]; then
          p=$(gen_alnum 24); origins+=("generada"); break
        fi
        if [ "${#p}" -lt 12 ]; then warn "mínimo 12 caracteres"; continue; fi
        case "$p" in *$'\n'*|*$'\r'*) warn "sin saltos de línea"; continue ;; esac
        ask_secret "Repite la contraseña"; p2="$SECRET_VALUE"
        if [ "$p" != "$p2" ]; then warn "no coinciden"; continue; fi
        origins+=("introducida"); break
      done
      names+=("$u"); disps+=("$d"); mails+=("$m"); pws+=("$p")
      confirm "¿Añadir otro usuario?" || break
    done

    printf '\n' >&2
    for i in "${!names[@]}"; do
      printf '      %-16s %-28s %-30s contraseña %s\n' \
        "${names[$i]}" "${disps[$i]}" "${mails[$i]}" "${origins[$i]}" >&2
    done
    confirm "¿Crear estos usuarios?" && break
    info "se vuelve a preguntar"
  done

  info "cálculo de los hashes con la imagen de Authelia"
  local rows hash
  rows=$(mktemp "$STATE_DIR/authelia-rows.XXXXXX")
  for i in "${!names[@]}"; do
    AUTHELIA_PW_IN="${pws[$i]}"
    hash=$(_authelia_hash "$img")
    AUTHELIA_PW_IN=''
    if [ -z "$hash" ]; then
      rm -f "$rows"
      die "la imagen de Authelia no ha devuelto un hash argon2id para ${names[$i]}.
       Orden usada: authelia crypto hash generate argon2 --password …
       (docs/README-fase1b-authelia.md:222-223), con sh como punto de entrada."
    fi
    printf '%s\t%s\t%s\t%s\n' "${names[$i]}" "${disps[$i]}" "${mails[$i]}" "$hash" >>"$rows"
    if [ "${origins[$i]}" = generada ]; then
      secret_put "AUTHELIA_PASSWORD_${names[$i]}" "${pws[$i]}"
      info "${names[$i]}: contraseña generada; está en el almacén como AUTHELIA_PASSWORD_${names[$i]}"
    fi
  done
  ( umask 077; users_db_render <"$rows" >"$db" )
  chmod 600 "$db"
  rm -f "$rows"
  pws=()
  info "usuarios de Authelia: ${#names[@]} escritos. El alta de TOTP es personal y se hace tras arrancar Authelia."
}

s1_host_ca() {
  # Almacén de confianza de Ubuntu: fichero .crt en
  # /usr/local/share/ca-certificates y update-ca-certificates. Sin la CA,
  # `tailscale up` falla con x509; y tailscaled no recarga el almacén, hay que
  # reiniciarlo (docs/README-fase4b-tailnet.md:179-183).
  local dst=/usr/local/share/ca-certificates/oob-rootCA.crt
  if [ -f "$dst" ] && cmp -s "$CA_CRT" "$dst"; then
    info "CA del enclave: ya está en el almacén de confianza del host"
  else
    sudo install -m 644 -o root -g root "$CA_CRT" "$dst"
    sudo update-ca-certificates >/dev/null
    info "CA del enclave instalada en el almacén de confianza del host"
    if systemctl list-unit-files tailscaled.service >/dev/null 2>&1; then
      sudo systemctl restart tailscaled
      info "tailscaled reiniciado para que cargue la CA"
    fi
  fi
}

s1_checks() {
  local f v a b sans=()
  checks_begin

  # ── Certificados: firma, SAN y correspondencia de clave ────────────────────
  chk_cert_verify "$CA_CRT" "$CERTS/oob-wildcard.crt" "comodín"
  mapfile -t sans < <(_san_wildcard);     chk_cert_san "$CERTS/oob-wildcard.crt" "comodín" "${sans[@]}"
  chk_key_matches_cert "$CERTS/oob-wildcard.key" "$CERTS/oob-wildcard.crt" "comodín"

  chk_cert_verify "$CA_CRT" "$CERTS/iris.crt" "iris"
  mapfile -t sans < <(_san_iris);         chk_cert_san "$CERTS/iris.crt" "iris" "${sans[@]}"
  chk_key_matches_cert "$CERTS/iris.key" "$CERTS/iris.crt" "iris"

  chk_cert_verify "$CA_CRT" "$CERTS/glkvm-cloud.crt" "glkvm-cloud"
  mapfile -t sans < <(_san_glkvm_cloud);  chk_cert_san "$CERTS/glkvm-cloud.crt" "glkvm-cloud" "${sans[@]}"
  chk_key_matches_cert "$CERTS/glkvm-cloud.key" "$CERTS/glkvm-cloud.crt" "glkvm-cloud"

  chk_cert_verify "$CA_CRT" "$CERTS/glkvm-device.crt" "glkvm-device"
  mapfile -t sans < <(_san_glkvm_device); chk_cert_san "$CERTS/glkvm-device.crt" "glkvm-device" "${sans[@]}"
  chk_key_matches_cert "$CERTS/glkvm-device.key" "$CERTS/glkvm-device.crt" "glkvm-device"
  if openssl pkey -in "$CERTS/glkvm-device.key" -noout -text 2>/dev/null | grep -q 'prime256v1'; then
    chk_ok "glkvm-device: clave EC prime256v1"
  else
    chk_bad "glkvm-device: tipo de clave" "EC prime256v1" "otro tipo"
  fi

  # Copias montadas en contenedores.
  chk_cert_verify "$CA_CRT" "$F8/certificate/glkvm.cer" "KVM: glkvm.cer"
  chk_key_matches_cert "$F8/certificate/glkvm.key" "$F8/certificate/glkvm.cer" "KVM: glkvm.key"
  chk_key_differs "$F8/certificate/glkvm.key" "$CA_KEY" "KVM: glkvm.key NO es la clave de la CA"

  chk_cert_verify "$CA_CRT" "$F6/certificates/web_certificates/$(kv_get "$F6/.env" CERT_FILENAME)" "IRIS: certificado web"
  f="$F6/certificates/web_certificates/$(kv_get "$F6/.env" KEY_FILENAME)"
  if sudo cmp -s "$CERTS/iris.key" "$f"; then chk_ok "IRIS: la clave web es la de iris.crt"
  else chk_bad "IRIS: clave web" "copia idéntica de iris.key" "difiere o no existe"; fi
  v=$(stat -c '%u' "$f" 2>/dev/null || echo '?')
  if [ "$v" = "$IRIS_NGINX_UID" ]; then chk_ok "IRIS: la clave web pertenece al uid $IRIS_NGINX_UID (nginx del contenedor)"
  else chk_bad "IRIS: propietario de la clave web" "uid $IRIS_NGINX_UID" "uid $v"; fi

  for f in "$N8N/certs/oob-rootCA.crt" "$F6/certificates/rootCA/irisRootCACert.pem"; do
    if cmp -s "$CA_CRT" "$f"; then chk_ok "copia de la CA: ${f#"$REPO_ROOT"/}"
    else chk_bad "copia de la CA: ${f#"$REPO_ROOT"/}" "idéntica a la CA nueva" "difiere o no existe"; fi
  done

  f="$F6/certificates/rootCA/ca-bundle-oob.crt"
  if openssl verify -CAfile "$f" "$CERTS/iris.crt" >/dev/null 2>&1; then chk_ok "bundle de IRIS: contiene la CA nueva"
  else chk_bad "bundle de IRIS" "que valide un certificado del enclave" "no lo valida"; fi
  v=$(grep -c 'BEGIN CERTIFICATE' "$f" 2>/dev/null) || v=0
  if [ "$v" -ge 100 ]; then
    chk_ok "bundle de IRIS: $v certificados (CAs públicas + CA del enclave)"
    [ "$v" -ge 151 ] || warn "scripts/verify-fase6.sh exige >=151 CAs y este bundle tiene $v: depende de la versión de ca-certificates de este Ubuntu"
  else
    chk_bad "bundle de IRIS: CAs públicas" "al menos 100 certificados" "$v"
  fi

  if openssl verify -CApath /etc/ssl/certs "$CERTS/oob-wildcard.crt" >/dev/null 2>&1; then
    chk_ok "el host confía en la CA del enclave"
  else
    chk_bad "el host confía en la CA del enclave" "openssl verify OK con el almacén del sistema" "no valida"
  fi

  # ── Rutas que un compose monta como fichero (inventario, 2.1 y 2.2) ────────
  for f in \
    "$F1/traefik/acme.json" \
    "$F1/mongodb/mongo-keyfile" \
    "$F1/mongodb/docker-entrypoint-keyfile.sh" \
    "$N8N/certs/oob-rootCA.crt" \
    "$F4/rustdesk/peers.json" \
    "$F6/certificates/rootCA/irisRootCACert.pem" \
    "$F6/certificates/rootCA/ca-bundle-oob.crt" \
    "$F8/certificate/glkvm.cer" \
    "$F8/certificate/glkvm.key"
  do
    chk_regular_file "$f" "${f#"$REPO_ROOT"/}"
  done
  chk_nonempty_file "$F1/mongodb/mongo-keyfile"
  for f in "$F6/certificates/ldap" "$F6/certificates/web_certificates" "$F5V/velociraptor-config" "$F1/authelia"; do
    chk_dir "$f"
  done

  # ── Modo 600 en claves privadas y .env ─────────────────────────────────────
  local envs=("$F1/.env" "$WAZUH/.env" "$N8N/.env" "$F3/.env" "$F5V/.env" "$F5A/.env" "$F6/.env" "$F8/.env" "$MISP/.env")
  local keys=("$CA_KEY" "$CERTS/oob-wildcard.key" "$CERTS/iris.key" "$CERTS/glkvm-cloud.key" "$CERTS/glkvm-device.key"
              "$F8/certificate/glkvm.key" "$F6/certificates/web_certificates/$(kv_get "$F6/.env" KEY_FILENAME)")
  for f in "${envs[@]}" "${keys[@]}" "$SECRETS_FILE" "$F1/mongodb/mongo-keyfile" "$F1/authelia/users_database.yml"; do
    chk_mode "$f" 600
  done

  # ── Restricciones de formato ───────────────────────────────────────────────
  if wazuh_policy_ok "$(kv_get "$WAZUH/.env" API_PASSWORD)"; then chk_ok "API_PASSWORD cumple la política de la API de Wazuh"
  else chk_bad "API_PASSWORD" "8-64 con mayúscula, minúscula, número y símbolo de .*+?-" "no la cumple"; fi
  if is_alnum "$(kv_get "$F1/.env" MONGO_INITDB_ROOT_PASSWORD)"; then chk_ok "la contraseña de Mongo es alfanumérica"
  else chk_bad "contraseña de Mongo" "solo alfanumérica (va en una URI)" "lleva otros caracteres o está vacía"; fi
  for v in POSTGRES_PASSWORD POSTGRES_ADMIN_PASSWORD; do
    if is_alnum "$(kv_get "$F6/.env" "$v")"; then chk_ok "$v de IRIS es alfanumérica"
    else chk_bad "$v de IRIS" "solo alfanumérica (va en una URI)" "lleva otros caracteres o está vacía"; fi
  done

  # ── Igualdades entre ficheros, leídas de los .env escritos ─────────────────
  a=$(kv_get "$N8N/.env" ORCH_HMAC_SECRET); b=$(kv_get "$F5A/.env" ORCH_HMAC_SECRET)
  if [ -n "$a" ] && [ "$a" = "$b" ]; then chk_ok "ORCH_HMAC_SECRET: n8n = orchestrator"
  else chk_bad "ORCH_HMAC_SECRET" "igual en n8n/.env y fase5-orchestrator-api/.env" "distinto o vacío"; fi

  a=$(kv_get "$WAZUH/.env" INDEXER_PASSWORD)
  if [ -n "$a" ] && [ "$a" = "$(kv_get "$F3/.env" OS_PASS)" ] && [ "$a" = "$(kv_get "$F5A/.env" OS_PASS)" ]; then
    chk_ok "OS_PASS (fase 3 y orchestrator) = INDEXER_PASSWORD (Wazuh)"
  else
    chk_bad "OS_PASS = INDEXER_PASSWORD" "igual en fase3-agentic/.env, fase5-orchestrator-api/.env y wazuh/.env" "distinto o vacío"
  fi

  # Los otros extremos de estas igualdades aún no existen como fichero:
  # n8n-integration.conf vive dentro del manager (etapa 9) y el entorno del
  # agente va en el paquete de DC01 (etapa 10). Aquí se comprueba que el lado
  # de n8n está escrito y coincide con la entrada única del almacén.
  for v in OOB_WEBHOOK_SECRET AGENT_TOKEN AGENT_HMAC_SECRET; do
    a=$(kv_get "$N8N/.env" "$v")
    if [ -n "$a" ] && [ "$a" = "$(secret_get "$v")" ]; then chk_ok "$v: escrito en n8n/.env desde la entrada única"
    else chk_bad "$v" "presente en n8n/.env e igual a la entrada del almacén" "distinto o vacío"; fi
  done

  # ── Ningún valor público de ejemplo en fase 8 ni en MISP ───────────────────
  local pub
  for v in RTTYS_TOKEN RTTYS_PASS TURN_PASS GLKVM_ACCESS_IP; do
    a=$(kv_get "$F8/.env" "$v"); b=ok
    [ -n "$a" ] || b=vacío
    for pub in $PUBLIC_EXAMPLES; do [ "$a" != "$pub" ] || b="valor público de ejemplo"; done
    if [ "$b" = ok ]; then chk_ok "fase 8: $v propio"
    else chk_bad "fase 8: $v" "un valor propio" "$b (el compose caería a una constante pública)"; fi
  done
  for v in ADMIN_KEY ADMIN_PASSWORD ENCRYPTION_KEY MYSQL_PASSWORD MYSQL_ROOT_PASSWORD REDIS_PASSWORD; do
    a=$(kv_get "$MISP/.env" "$v"); b=ok
    [ -n "$a" ] || b=vacío
    for pub in $PUBLIC_EXAMPLES; do [ "$a" != "$pub" ] || b="valor público de ejemplo"; done
    if [ "$b" = ok ]; then chk_ok "MISP: $v propio"
    else chk_bad "MISP: $v" "un valor propio" "$b (el compose caería a una constante pública)"; fi
  done

  # ── Usuarios de Authelia ───────────────────────────────────────────────────
  v=$(grep -cE '^[[:space:]]+password: "\$argon2id\$' "$F1/authelia/users_database.yml" 2>/dev/null) || v=0
  if [ "$v" -ge 1 ]; then chk_ok "Authelia: $v usuario(s) con hash argon2id"
  else chk_bad "Authelia: users_database.yml" "al menos un usuario con hash argon2id" "ninguno"; fi

  # ── Git: lo sensible está ignorado ─────────────────────────────────────────
  CHK_TRACKED_MODIFIED=()
  chk_ignored_or_tracked "${envs[@]}" "${keys[@]}" \
    "$SECRETS_FILE" "$PARAMS_FILE" \
    "$F1/mongodb/mongo-keyfile" "$F1/traefik/acme.json" "$F1/authelia/users_database.yml" \
    "$CERTS/iris.crt" "$CERTS/glkvm-cloud.crt" "$CERTS/glkvm-device.crt" "$CERTS/oob-wildcard.crt" \
    "$F8/certificate/glkvm.cer" "$F4/rustdesk/peers.json" \
    "$F6/certificates/web_certificates/$(kv_get "$F6/.env" CERT_FILENAME)" \
    "$CA_CRT" "$N8N/certs/oob-rootCA.crt" \
    "$F6/certificates/rootCA/irisRootCACert.pem" "$F6/certificates/rootCA/ca-bundle-oob.crt"
  if [ "${#CHK_TRACKED_MODIFIED[@]}" -gt 0 ]; then
    info "ficheros versionados modificados a propósito (públicos; el hook pre-commit impide subirlos):"
    printf '      %s\n' "${CHK_TRACKED_MODIFIED[@]}" >&2
  fi

  checks_end
}

stage_main() {
  [ -n "$(param_get PARAMS_CONFIRMADOS)" ] || die "faltan los parámetros: ejecuta antes la etapa 0"
  command -v openssl >/dev/null 2>&1 || die "falta openssl: ejecuta antes la etapa 0"
  s1_secrets
  s1_external_keys
  s1_env_files
  s1_pki
  s1_files
  s1_authelia_users
  s1_host_ca
  s1_checks
}
