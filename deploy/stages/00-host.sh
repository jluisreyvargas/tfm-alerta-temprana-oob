# shellcheck shell=bash
# shellcheck disable=SC2016  # comillas simples a propósito: texto para awk, sed o sh
# TITULO: Host — paquetes, parámetros, red Docker, /etc/hosts e imágenes
#
# Etapa 0 de la sección 4.5 del inventario. No arranca ningún servicio del
# enclave. Las funciones de la parte superior son puras (no tocan el sistema) y
# las ejercita `deploy.sh selftest`.

# Umbrales de aviso. Son una ESTIMACIÓN SIN MEDIR: el repositorio no documenta
# el consumo del enclave completo. Solo producen un aviso, nunca un aborto.
MIN_RAM_GB=16
MIN_DISK_GB=80

# Puertos que el enclave publica en todas las interfaces
# (inventario, sección 4.2).
PORTS_TCP='80 443 1514 1515 55000 9200 8001 9000 8888'
PORTS_UDP='514 3478'

# Imágenes cuyo nombre va en el compose y cuya etiqueta va en una plantilla.
MISP_CORE_REPO='ghcr.io/misp/misp-docker/misp-core'
MISP_MODULES_REPO='ghcr.io/misp/misp-docker/misp-modules'
ROCKETCHAT_REPO='registry.rocket.chat/rocketchat/rocket.chat'

HOSTS_BEGIN='# >>> tfm-oob (gestionado por deploy/deploy.sh; no editar a mano) >>>'
HOSTS_END='# <<< tfm-oob <<<'

# ─── Funciones puras ─────────────────────────────────────────────────────────

# ifaces_parse  < salida de `ip -4 -o addr show scope global`
# -> "interfaz IP" por línea, sin las interfaces de Docker ni la del tailnet.
ifaces_parse() {
  awk '{
    ifc = $2; split($4, a, "/")
    if (ifc ~ /^(lo|docker[0-9]*|br-|veth|tailscale)/) next
    print ifc, a[1]
  }'
}

# ports_busy "PUERTOS"  < salida de `ss -H -ltn` o `ss -H -lun`
# -> los puertos de la lista que ya tienen un proceso escuchando.
ports_busy() {
  awk -v want="$1" '
    BEGIN { n = split(want, w, " "); for (i = 1; i <= n; i++) need[w[i]] = 1 }
    { m = split($4, a, ":"); p = a[m]; if (p in need) busy[p] = 1 }
    END { for (i = 1; i <= n; i++) if (w[i] in busy) printf "%s ", w[i] }
  '
}

# hosts_render_block TSV IP_ENCLAVE IP_TAILNET IP_LAN IP_GLRM1
# Filas `ubuntu` de docs/resolucion-nombres.tsv con las IP del laboratorio
# sustituidas por los parámetros. Una IP que no sea ninguna de las conocidas
# es un error: el .tsv ha cambiado y este script no sabe qué poner.
# La línea de iris comparte el alias iris.local (resolucion-nombres.tsv:29).
hosts_render_block() {
  awk -F'\t' -v enc="$2" -v tail="$3" -v lan="$4" -v kvm="$5" \
      -v d_enc="$DEF_ENCLAVE_IP" -v d_tail="$DEF_TAILNET_IP" \
      -v d_lan="$DEF_LAN_IP" -v d_kvm="$DEF_GLRM1_IP" '
    $1 != "ubuntu" { next }
    {
      ip = $3
      if (ip == "127.0.0.1")   out = ip
      else if (ip == d_enc)    out = enc
      else if (ip == d_tail)   out = tail
      else if (ip == d_lan)    out = lan
      else if (ip == d_kvm)    out = kvm
      else {
        printf "IP no reconocida en %s para %s: %s\n", FILENAME, $2, ip > "/dev/stderr"
        bad = 1; next
      }
      line = out "\t" $2
      if ($2 == "iris.oob.local") line = line " iris.local"
      print line
    }
    END { exit bad ? 3 : 0 }
  ' "$1"
}

# hosts_apply_block FICHERO_HOSTS FICHERO_BLOQUE  -> contenido nuevo por stdout
# Sustituye el bloque delimitado por los marcadores (o lo añade al final) sin
# tocar el resto del fichero. Las líneas en blanco del final se normalizan a
# una sola separación para que aplicar dos veces dé el mismo resultado.
hosts_apply_block() {
  awk -v b="$HOSTS_BEGIN" -v e="$HOSTS_END" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    skip { next }
    { lines[++n] = $0 }
    END {
      while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
      for (i = 1; i <= n; i++) print lines[i]
    }
  ' "$1"
  printf '\n%s\n' "$HOSTS_BEGIN"
  cat "$2"
  printf '%s\n' "$HOSTS_END"
}

# image_by_digest REFERENCIA  -> nombre@sha256:… (sin la etiqueta)
image_by_digest() { printf '%s' "$1" | sed -E 's#:[^/@:]+@sha256:#@sha256:#'; }

# images_list RAIZ_DEL_REPO
# Todas las imágenes fijadas por digest: las líneas image: de los compose del
# despliegue y las que se componen con variables de las plantillas.
images_list() {
  local root="$1" f v name
  {
    for f in \
      fase1-infraestructura/docker-compose.yml \
      fase1-infraestructura/wazuh/single-node/docker-compose.yml \
      fase2-orquestador/n8n/docker-compose.yml \
      fase2-orquestador/ollama/docker-compose.yml \
      fase4-breakglass-dc/docker-compose.headscale-ui.yml \
      fase4-breakglass-dc/docker-compose.rustdesk.yml \
      fase4-breakglass-dc/headscale/config/docker-compose.headscale.yml \
      fase5-velociraptor/docker-compose.yml \
      fase6-iris/docker-compose.override.yml \
      fase8-kvm/glkvm-cloud/docker-compose/docker-compose.override.yml \
      misp/misp-docker/docker-compose.yml
    do
      # Solo referencias literales con digest: las que llevan ${…} se componen
      # más abajo a partir de su plantilla.
      sed -n -E 's/^[[:space:]]*image:[[:space:]]*//p' "$root/$f" \
        | sed -e 's/\${REGISTRY_MIRROR_URL:-}//' -e 's/[[:space:]]*$//' \
        | grep -E '@sha256:[0-9a-f]{64}$' | grep -v -F '${' || true
    done

    v=$(kv_get "$root/fase1-infraestructura/.env.example" ROCKETCHAT_VERSION)
    printf '%s:%s\n' "$ROCKETCHAT_REPO" "$v"

    for name in NGINX DB APP; do
      printf '%s:%s\n' \
        "$(kv_get "$root/fase6-iris/.env.example" "${name}_IMAGE_NAME")" \
        "$(kv_get "$root/fase6-iris/.env.example" "${name}_IMAGE_TAG")"
    done

    printf '%s:%s\n' "$MISP_CORE_REPO" \
      "$(kv_get "$root/misp/misp-docker/template.env" CORE_RUNNING_TAG)"
    printf '%s:%s\n' "$MISP_MODULES_REPO" \
      "$(kv_get "$root/misp/misp-docker/template.env" MODULES_RUNNING_TAG)"
  } | sort -u
}

# ─── Pasos ───────────────────────────────────────────────────────────────────

_default_or() { if [ -n "$1" ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }

s0_prechecks() {
  info "comprobaciones previas"
  [ -r /etc/os-release ] || die "no existe /etc/os-release: este instalador es para Ubuntu"
  local os_id
  # shellcheck disable=SC1091
  os_id=$(. /etc/os-release && printf '%s' "${ID:-}")
  [ "$os_id" = ubuntu ] || die "el sistema no es Ubuntu (ID=${os_id:-desconocido})"
  sudo -v || die "hace falta sudo"
  local tool
  for tool in ss ip getent awk sed; do
    command -v "$tool" >/dev/null 2>&1 || die "falta la utilidad '$tool' (en Ubuntu viene de serie: iproute2, libc-bin)"
  done

  # curl puede no estar todavía en un Ubuntu recién instalado; wget sí suele.
  curl -fsS --max-time 15 -o /dev/null https://download.docker.com/linux/ubuntu/gpg 2>/dev/null \
    || wget -q -T 15 -O /dev/null https://download.docker.com/linux/ubuntu/gpg 2>/dev/null \
    || die "sin salida a Internet (no se alcanza download.docker.com).
       La etapa 0 descarga paquetes e imágenes."

  local busy_t busy_u
  busy_t=$(ss -H -ltn | ports_busy "$PORTS_TCP")
  busy_u=$(ss -H -lun | ports_busy "$PORTS_UDP")
  if [ -n "$busy_t$busy_u" ]; then
    if stage_is_done 2; then
      info "puertos en uso (tcp: ${busy_t:-ninguno}· udp: ${busy_u:-ninguno}): esperado, el enclave ya está arrancado"
    else
      die "puertos que el enclave necesita y ya están ocupados.
       tcp: ${busy_t:-ninguno}
       udp: ${busy_u:-ninguno}
       'sudo ss -ltnp' y 'sudo ss -lunp' dicen qué proceso los tiene. Libéralos y repite."
    fi
  fi

  local ram_gb disk_gb
  ram_gb=$(awk '/^MemTotal:/ {printf "%d", $2/1024/1024 + 0.5}' /proc/meminfo)
  disk_gb=$(df -BG --output=avail "$REPO_ROOT" | tail -n1 | tr -dc '0-9')
  [ "$ram_gb" -ge "$MIN_RAM_GB" ] \
    || warn "memoria: ${ram_gb} GB; umbral orientativo ${MIN_RAM_GB} GB (estimación sin medir)"
  [ "$disk_gb" -ge "$MIN_DISK_GB" ] \
    || warn "disco libre: ${disk_gb} GB; umbral orientativo ${MIN_DISK_GB} GB (estimación sin medir)"
}

s0_ask_params() {
  if [ -n "$(param_get PARAMS_CONFIRMADOS)" ]; then
    info "parámetros ya confirmados (${PARAMS_FILE#"$REPO_ROOT"/}); para volver a preguntar, quita ahí la línea PARAMS_CONFIRMADOS"
    return 0
  fi

  local ifaces ips lan enclave tailnet glrm1 user repo problems
  ifaces=$(ip -4 -o addr show scope global | ifaces_parse)
  [ -n "$ifaces" ] || die "no se ha detectado ninguna interfaz con IPv4"
  ips=$(printf '%s\n' "$ifaces" | awk '{print $2}')

  while :; do
    printf '\n    Interfaces detectadas en este host:\n' >&2
    printf '%s\n' "$ifaces" | awk '{printf "      %-14s %s\n", $1, $2}' >&2
    printf '\n' >&2

    ask_ipv4 "IP de LAN del KVM (por donde llega el GL-RM1)" \
      "$(_default_or "$(param_get LAN_IP)" "$DEF_LAN_IP")"
    lan="$ASK_VALUE"
    ask_ipv4 "IP del enclave (donde escucha Traefik)" \
      "$(_default_or "$(param_get ENCLAVE_IP)" "$DEF_ENCLAVE_IP")"
    enclave="$ASK_VALUE"
    ask_ipv4 "IP esperada del tailnet para este host" \
      "$(_default_or "$(param_get TAILNET_IP)" "$DEF_TAILNET_IP")"
    tailnet="$ASK_VALUE"
    ask_ipv4 "IP del GL-RM1" \
      "$(_default_or "$(param_get GLRM1_IP)" "$DEF_GLRM1_IP")"
    glrm1="$ASK_VALUE"
    ask "Usuario del sistema que ejecutará el enclave" \
      "$(_default_or "$(param_get SYS_USER)" "$(id -un)")"
    user="$ASK_VALUE"
    ask "Ruta del repositorio" \
      "$(_default_or "$(param_get REPO_DIR)" "$REPO_ROOT")"
    repo="$ASK_VALUE"

    problems=''
    printf '%s\n' "$ips" | grep -qxF "$lan" \
      || problems+="la IP de LAN $lan no está en ninguna interfaz de este host; "
    printf '%s\n' "$ips" | grep -qxF "$enclave" \
      || problems+="la IP del enclave $enclave no está en ninguna interfaz de este host; "
    id "$user" >/dev/null 2>&1 || problems+="el usuario $user no existe; "
    [ "$user" = "$(id -un)" ] || problems+="el usuario debe ser el que ejecuta el instalador ($(id -un)); "
    [ "$repo" = "$REPO_ROOT" ] || problems+="la ruta $repo no es la de este clon ($REPO_ROOT); "

    {
      printf '\n'
      printf '    Dominio                  %s (fijo)\n' "$ENCLAVE_DOMAIN"
      printf '    IP de LAN (KVM)          %s\n' "$lan"
      printf '    IP del enclave           %s\n' "$enclave"
      printf '    IP esperada del tailnet  %s\n' "$tailnet"
      printf '    IP del GL-RM1            %s\n' "$glrm1"
      printf '    Usuario                  %s\n' "$user"
      printf '    Ruta del repositorio     %s\n' "$repo"
    } >&2

    if [ -n "$problems" ]; then
      warn "no se puede aceptar: $problems"
      continue
    fi
    if confirm "¿Son correctos? Con la confirmación se guardan"; then break; fi
  done

  param_set LAN_IP "$lan"
  param_set ENCLAVE_IP "$enclave"
  param_set TAILNET_IP "$tailnet"
  param_set GLRM1_IP "$glrm1"
  param_set SYS_USER "$user"
  param_set REPO_DIR "$repo"
  param_set PARAMS_CONFIRMADOS "$(date -Is)"
}

s0_packages() {
  local codename arch user
  # shellcheck disable=SC1091
  codename=$(. /etc/os-release && printf '%s' "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
  arch=$(dpkg --print-architecture)
  user=$(param_require SYS_USER)

  info "utilidades: ca-certificates, curl, gnupg, jq, sqlite3, openssl"
  sudo apt-get update -q
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
    ca-certificates curl gnupg jq sqlite3 openssl

  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    info "Docker y el plugin de Compose ya están instalados"
  else
    # Repositorio oficial de Docker (docs/README-fase1a-traefik-portainer.md:93-96).
    info "Docker y el plugin de Compose, desde el repositorio oficial de Docker"
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
      "$arch" "$codename" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update -q
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
      docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi

  if command -v tailscale >/dev/null 2>&1; then
    info "Tailscale ya está instalado"
  else
    # Repositorio oficial de Tailscale. Solo se instala: `tailscale up` es de
    # la etapa 4, cuando Headscale ya existe.
    info "Tailscale, desde su repositorio (sin 'tailscale up')"
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${codename}.noarmor.gpg" \
      | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${codename}.tailscale-keyring.list" \
      | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null
    sudo apt-get update -q
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q tailscale
  fi

  sudo systemctl enable --now docker >/dev/null

  # Grupo docker. La sesión en curso no ve la pertenencia nueva: dk() (state.sh)
  # usa `sudo -g docker` mientras tanto, así que no hace falta cerrar sesión.
  if id -nG "$user" | tr ' ' '\n' | grep -qx docker; then
    info "$user ya pertenece al grupo docker"
  else
    sudo usermod -aG docker "$user"
    info "$user añadido al grupo docker (tu shell lo verá al volver a iniciar sesión; el instalador no lo necesita)"
  fi
}

s0_sysctl() {
  # docs/README-fase1d-wazuh.md:53-56. Se escribe el fichero entero en vez de
  # añadir una línea, para que repetir la etapa no la duplique.
  info "vm.max_map_count=262144 (requisito del indexador de Wazuh)"
  printf 'vm.max_map_count=262144\n' | sudo tee /etc/sysctl.d/99-wazuh.conf >/dev/null
  sudo sysctl -q -w vm.max_map_count=262144
}

s0_network() {
  if dk network inspect oob-network >/dev/null 2>&1; then
    info "la red oob-network ya existe"
  else
    dk network create oob-network >/dev/null
    info "red oob-network creada"
  fi
}

_hosts_block() {
  hosts_render_block "$REPO_ROOT/docs/resolucion-nombres.tsv" \
    "$(param_require ENCLAVE_IP)" "$(param_require TAILNET_IP)" \
    "$(param_require LAN_IP)" "$(param_require GLRM1_IP)"
}

s0_hosts() {
  local block new
  block=$(mktemp); new=$(mktemp)
  _hosts_block >"$block" \
    || die "no se ha podido generar el bloque de hosts a partir de docs/resolucion-nombres.tsv"
  hosts_apply_block /etc/hosts "$block" >"$new"
  if cmp -s "$new" /etc/hosts; then
    info "/etc/hosts ya tiene el bloque del enclave al día"
  else
    [ -e /etc/hosts.antes-de-tfm-oob ] || sudo cp -p /etc/hosts /etc/hosts.antes-de-tfm-oob
    sudo install -m 644 -o root -g root "$new" /etc/hosts
    info "/etc/hosts: bloque del enclave escrito ($(wc -l <"$block") nombres); copia previa en /etc/hosts.antes-de-tfm-oob"
  fi
  rm -f "$block" "$new"
}

s0_pull_images() {
  local ref failed=() total=0
  info "descarga de las imágenes fijadas por digest (puede tardar)"
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    total=$((total + 1))
    if dk image inspect "$(image_by_digest "$ref")" >/dev/null 2>&1; then
      continue
    fi
    info "  $ref"
    dk pull -q "$ref" >/dev/null 2>&1 || failed+=("$ref")
  done < <(images_list "$REPO_ROOT")
  if [ "${#failed[@]}" -gt 0 ]; then
    warn "no se han podido descargar ${#failed[@]} de $total imágenes:"
    printf '      %s\n' "${failed[@]}" >&2
    die "faltan imágenes: sin ellas el enclave no sería el validado en el laboratorio"
  fi
  info "$total imágenes presentes"
}

s0_checks() {
  local ref name ip got out missing=0 total=0
  checks_begin

  # Equivalente a hello-world con una imagen ya fijada por digest: no descarga
  # nada flotante. Prueba que el demonio crea y ejecuta un contenedor.
  ref=$(images_list "$REPO_ROOT" | grep -E '^mongo:' | head -n1)
  if out=$(dk run --rm --network none --entrypoint true "$(image_by_digest "$ref")" 2>&1); then
    chk_ok "Docker ejecuta un contenedor"
  else
    chk_bad "Docker ejecuta un contenedor" "salida 0 de un contenedor de prueba" "$(printf '%s' "$out" | tail -n1)"
  fi

  if out=$(dk compose version 2>&1); then chk_ok "plugin de Compose: $out"
  else chk_bad "plugin de Compose" "docker compose version" "$out"; fi

  if command -v tailscale >/dev/null 2>&1; then chk_ok "Tailscale instalado"
  else chk_bad "Tailscale instalado" "el binario tailscale" "no está"; fi

  for name in sqlite3 jq openssl curl; do
    if command -v "$name" >/dev/null 2>&1; then chk_ok "utilidad: $name"
    else chk_bad "utilidad: $name" "instalada" "no está"; fi
  done

  got=$(sysctl -n vm.max_map_count)
  if [ "$got" -ge 262144 ]; then chk_ok "vm.max_map_count = $got"
  else chk_bad "vm.max_map_count" ">= 262144" "$got"; fi

  if dk network inspect oob-network >/dev/null 2>&1; then chk_ok "red Docker oob-network"
  else chk_bad "red Docker oob-network" "que exista" "no existe"; fi

  # Resolución real, no lectura del fichero: getent devuelve la primera
  # coincidencia, así que una línea antigua fuera del bloque también se detecta.
  while IFS=$'\t' read -r ip name; do
    name="${name%% *}"
    got=$(getent hosts "$name" | awk '{print $1; exit}') || true
    if [ "$got" = "$ip" ]; then chk_ok "resuelve $name -> $ip"
    else chk_bad "resuelve $name" "$ip" "${got:-no resuelve} (¿una línea antigua fuera del bloque de /etc/hosts?)"; fi
  done < <(_hosts_block)

  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    total=$((total + 1))
    if ! dk image inspect "$(image_by_digest "$ref")" >/dev/null 2>&1; then
      missing=$((missing + 1)); warn "falta $ref"
    fi
  done < <(images_list "$REPO_ROOT")
  if [ "$missing" -eq 0 ]; then chk_ok "imágenes presentes por digest: $total"
  else chk_bad "imágenes presentes por digest" "$total" "faltan $missing"; fi

  checks_end
}

stage_main() {
  s0_prechecks
  s0_ask_params
  s0_packages
  s0_sysctl
  s0_network
  s0_hosts
  s0_pull_images
  s0_checks
}
