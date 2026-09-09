#!/usr/bin/env bash
# verify-no-secrets.sh — control preventivo de la remediación P0-1.
#
# Recorre solo los ficheros TRACKEADOS por git y falla (exit 1) si encuentra
# material que no debe estar versionado.
#
# Reglas ancladas por nombre de campo — se aplican a TODO el repositorio:
#   - bloques PEM de clave privada  (BEGIN ... PRIVATE KEY)
#   - private_key: / password_hash: / password_salt: / obfuscation_nonce:
#     con valor no vacío
#   - nonce:  seguido de una cadena con aspecto de secreto (>= 16 caracteres
#     base64 o hexadecimales). Exigir esa forma, y no solo la palabra suelta,
#     evita falsos positivos sobre prosa ("... al nonce: ...") sin recurrir a
#     una lista de exclusión de ficheros, que enmascararía un secreto real que
#     apareciera en ellos más adelante.
#
# Regla de entropía — solo bajo fase5-velociraptor/ y en ficheros de config
#   (.yaml .yml .env .conf .json):
#   - cadenas base64 de más de 60 caracteres
#   Acotada aquí a propósito: aplicada a todo el árbol produce miles de falsos
#   positivos en assets vendorizados (JS minificado, yarn.lock, .db del
#   datastore). Las reglas ancladas cubren el material real de Velociraptor.
#
# Regla de credenciales conocidas (P0-3) — se aplica a TODO el árbol trackeado,
#   binarios incluidos (git grep -a):
#   - minioadmin, minioadmin123, SecretPassword, changeme, change_me,
#     admin:admin, password123
#   Las reglas ancladas por nombre de campo no cubren una contraseña literal
#   suelta como "minioadmin123": no va precedida de un campo reconocido ni tiene
#   forma de bloque PEM. El .pyc de metrics_client, trackeado, llevaba
#   "SecretPassword" en su tabla de constantes y el detector daba 0 hallazgos —
#   no por ser binario (grep -a lo encontraría), sino por no existir la regla.
#
#   Esta regla —y SOLO esta— lleva dos exclusiones acotadas. Las reglas de PEM,
#   private_key, password_hash, nonce y base64 largo NO se ven afectadas y
#   siguen recorriendo estos ficheros: si algún día aparece ahí una clave
#   privada real, el detector la ve.
#
#     1. fase1-infraestructura/wazuh/  — árbol vendorizado del proyecto oficial
#        wazuh-docker (no es código de este proyecto). Las cadenas que contiene
#        (admin / admin:admin / SecretPassword en workflows, docs y composes de
#        ejemplo del upstream) son las credenciales de demo que trae wazuh-docker
#        en claro. No se pueden reescribir sin divergir del upstream. El
#        despliegue real de la Fase 1 toma los secretos de
#        fase1-infraestructura/wazuh/single-node/.env (INDEXER_PASSWORD /
#        API_PASSWORD / DASHBOARD_PASSWORD), que está fuera del control de
#        versiones (**/.env en .gitignore).
#
#     2. *.env.example / env.example  — un marcador de posición como
#        "change_me" / "changeme" comunica al lector "sustituye esto" y es
#        legítimo en un fichero de ejemplo. Se descarta SOLO si en esa misma
#        línea no hay además una credencial real de la lista: un
#        MINIO_SECRET_KEY=minioadmin123 en un .env.example SÍ sigue saltando.
#
# En fase5-velociraptor/config-templates/ solo se admite el marcador literal
# <<GENERADO_EN_DESPLIEGUE>>; cualquier otro valor en una plantilla es un fallo.
#
# NUNCA imprime el valor detectado, solo ruta y número de línea.
#
# Reglas de cabecera/credencial de autenticación (P1-4) — TODO el árbol
# trackeado, solo texto (git grep -I, como el resto de reglas ancladas):
#   - Authorization: Bearer <valor> / Authorization: Basic <valor>
#   - X-Auth-Token / X-Api-Key / X-User-Id con valor literal
#   - Asignaciones *SECRET= / *TOKEN= / *PASSWORD= / *API_KEY= (incluye
#     HMAC_SECRET=, que termina en SECRET=) seguidas de un valor literal de
#     16+ caracteres
#   Motivo: un token con permisos de ejecución remota de PowerShell (agente
#   del DC, fase4-breakglass-dc) convivió con este detector en exit 0 porque
#   no había regla para cabeceras de autorización ni para asignaciones de
#   credencial — el fichero que lo llevaba no estaba trackeado, así que el
#   detector nunca llegó a evaluarlo, pero la cobertura faltaba igualmente.
#   Se excluyen deliberadamente: referencias a variables ($TOKEN, ${SECRET},
#   %TOKEN%), placeholders entre `<` y `>` (p.ej. <TOKEN>, usados en
#   fase4-breakglass-dc/dcagent/README-despliegue.md) y valores vacíos
#   (TOKEN=) — un placeholder o una variable no es el secreto, y penalizar
#   esa forma habría hecho ruidoso el propio README de despliegue.
#
# Modo --staged: revisa el CONTENIDO DEL ÍNDICE (git grep --cached / git show
#   ":<path>") en vez del árbol de trabajo. Pensado para ejecutarse justo
#   antes de `git commit`: si se corrigió un secreto en el árbol de trabajo
#   pero todavía no se ha vuelto a hacer `git add`, el modo normal (que lee
#   ficheros en disco) ya no lo vería, pero el índice — lo que de verdad se
#   va a commitear — seguiría llevándolo. No instala ningún hook; solo deja
#   el modo disponible. Para engancharlo como pre-commit:
#     printf '#!/bin/sh\nexec scripts/verify-no-secrets.sh --staged\n' \
#       > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
#
# Modo --selftest: prueba negativa de las reglas nuevas de este apartado
# (P1-4, 3.1) contra credenciales SINTÉTICAS generadas en memoria — nunca
# contra el árbol del repositorio ni con git add/commit. Comprueba que cada
# patrón nuevo detecta su caso positivo y que ninguno dispara sobre
# referencias a variables, valores vacíos o una línea de estilo .env.example.
#
# NUNCA imprime el valor detectado, solo ruta y número de línea.
#
# Salida: 0 si el árbol trabajado (o el índice, con --staged) está limpio,
# 1 si detecta algo. --selftest: 0 si las comprobaciones coinciden, 1 si no.

set -euo pipefail

STAGED=0
case "${1:-}" in
  --staged)
    STAGED=1
    ;;
  --selftest)
    SELFTEST_MODE=1
    ;;
  -h|--help)
    cat <<'EOF'
Uso:
  verify-no-secrets.sh              Recorre el arbol de trabajo trackeado.
  verify-no-secrets.sh --staged     Recorre el indice (lo que se va a
                                     commitear), no el arbol de trabajo.
                                     Pensado para lanzarse justo antes de
                                     `git commit`. No instala ningun hook.
  verify-no-secrets.sh --selftest   Prueba negativa: verifica con
                                     credenciales sinteticas que las reglas
                                     nuevas (P1-4) detectan lo que deben y no
                                     disparan sobre falsos positivos. No toca
                                     el repositorio.
  verify-no-secrets.sh -h|--help    Esta ayuda.
EOF
    exit 0
    ;;
  "")
    ;;
  *)
    echo "ERROR: argumento desconocido: $1 (usa --help)" >&2
    exit 2
    ;;
esac

cd "$(git rev-parse --show-toplevel)"

MARKER='<<GENERADO_EN_DESPLIEGUE>>'
TEMPLATE_DIR='fase5-velociraptor/config-templates/'
SELF='scripts/verify-no-secrets.sh'
B64_PATH_RE='^fase5-velociraptor/.*\.(yaml|yml|env|conf|json)$'

# Reglas nuevas (P1-4, 3.1). Solo caracteres ["] dentro de las clases de
# corchete: sin comillas simples embebidas, para poder escribirlas como
# cadena bash entre comillas simples sin escapes.
AUTH_HEADER_RE='Authorization:[[:space:]]*(Bearer|Basic)[[:space:]]+[^[:space:]$%<]{8,}'
XHEADER_RE='(X-Auth-Token|X-Api-Key|X-User-Id)["]?[[:space:]]*[:=][[:space:]]*["]?[^[:space:]"$%<]{3,}'
ASSIGN_RE='(^|[^A-Za-z0-9_])[A-Za-z0-9_]*(SECRET|TOKEN|PASSWORD|API_KEY)=["]?[^[:space:]"$%<]{16,}'

# --------------------------------------------------------------------------
# --selftest: prueba negativa de las 3 reglas nuevas contra credenciales
# SINTETICAS en ficheros temporales propios. No toca el repositorio ni usa
# git de ningun modo.
# --------------------------------------------------------------------------
_selftest() {
  local tmp_pos tmp_neg fail=0
  tmp_pos="$(mktemp)"
  tmp_neg="$(mktemp)"

  # Positivos: una linea por regla nueva, con prefijo SYNTHETIC_ reconocible.
  cat > "$tmp_pos" <<'EOF'
Authorization: Bearer SYNTHETIC_bearer_token_1234567890
Authorization: Basic SYNTHETIC_basic_credential_1234567890==
X-Auth-Token: SYNTHETIC_xauthtoken_abc123
X-Api-Key: SYNTHETIC_xapikey_abc123
X-User-Id: SYNTHETIC_xuserid_42
AGENT_TOKEN=SYNTHETIC_TOKEN_1234567890abcdef
SOME_PASSWORD=SYNTHETIC_PASSWORD_1234567890
MY_SERVICE_API_KEY=SYNTHETIC_APIKEY_1234567890ab
ORCH_HMAC_SECRET=SYNTHETIC_HMACSECRET_1234567890
EOF

  # Negativos: referencias a variables, valores vacios, estilo .env.example.
  # Ninguna de estas lineas debe disparar ninguna de las 3 reglas nuevas.
  cat > "$tmp_neg" <<'EOF'
AGENT_TOKEN=$AGENT_TOKEN
AGENT_HMAC_SECRET=${AGENT_HMAC_SECRET}
set AGENT_TOKEN=%AGENT_TOKEN%
AGENT_TOKEN=<TOKEN>
AGENT_HMAC_SECRET=<SECRETO>
TOKEN=
SECRET=
ORCH_HMAC_SECRET=
Authorization: Bearer $TOKEN
Authorization: Bearer ${TOKEN}
X-User-Id: ${USER_ID}
X-Api-Key:
EOF

  echo "== Selftest verify-no-secrets.sh: reglas nuevas (P1-4, 3.1) =="
  echo

  local labels=(auth-header x-token-header credencial-literal)
  local eres=("$AUTH_HEADER_RE" "$XHEADER_RE" "$ASSIGN_RE")

  echo "-- Positivos: cada regla debe detectar su linea sintetica --"
  local i label ere
  for i in "${!labels[@]}"; do
    label="${labels[$i]}"; ere="${eres[$i]}"
    if grep -qE "$ere" "$tmp_pos"; then
      echo "  [OK]    positivo ${label}"
    else
      echo "  [FALLO] positivo ${label}: no detecto ninguna linea sintetica"
      fail=1
    fi
  done

  echo
  echo "-- Negativos: ninguna regla debe disparar sobre variables/vacios/placeholders --"
  for i in "${!labels[@]}"; do
    label="${labels[$i]}"; ere="${eres[$i]}"
    if grep -qE "$ere" "$tmp_neg"; then
      echo "  [FALLO] negativo ${label}: disparo sobre un caso que no debia"
      fail=1
    else
      echo "  [OK]    negativo ${label}"
    fi
  done

  rm -f "$tmp_pos" "$tmp_neg"

  echo
  if [[ "$fail" -eq 0 ]]; then
    echo "OK: selftest completo."
    return 0
  else
    echo "FALLO: selftest con discrepancias (ver arriba)."
    return 1
  fi
}

if [[ "${SELFTEST_MODE:-0}" -eq 1 ]]; then
  _selftest
  exit $?
fi

# Exclusiones acotadas de la regla 'credencial-conocida' (ver cabecera).
VENDOR_WAZUH='fase1-infraestructura/wazuh/'          # árbol vendorizado upstream
EXAMPLE_PATH_RE='(^|/)(\.env\.example|env\.example)$' # ficheros de ejemplo
# Credenciales "duras": la lista sin los marcadores change_me / changeme. Sirve
# para re-examinar una línea de un fichero de ejemplo y decidir si el hallazgo
# era solo un placeholder legítimo o además una credencial real.
HARD_CRED_RE='(minioadmin|SecretPassword|admin:admin|password123)'

tracked_count=$(git ls-files | wc -l | tr -d ' ')
findings=0

# -I git grep flag NO va aqui: con --cached, git grep sigue aceptando -I para
# saltar binarios igual que sobre el arbol de trabajo.
GIT_GREP_SCOPE=()
[ "$STAGED" -eq 1 ] && GIT_GREP_SCOPE=(--cached)

# Contenido de una linea: del arbol de trabajo en modo normal, del INDICE
# (git show ":<path>") en modo --staged — es lo que de verdad se commitearia,
# que puede diferir del arbol de trabajo si hay cambios sin volver a stagear.
_line_content() {   # $1 = ruta   $2 = numero de linea
  if [ "$STAGED" -eq 1 ]; then
    git show ":$1" 2>/dev/null | sed -n "${2}p"
  else
    sed -n "${2}p" "$1"
  fi
}

# Asume que las rutas trackeadas no contienen ':' (cierto en este repo).
# git grep -I salta binarios; -n da número de línea; el contenido de la
# línea se descarta con cut para no exponer nunca el valor.
scan() {   # $1 = etiqueta   $2 = ERE   $3 = (opcional) filtro de ruta ERE
  local label="$1" ere="$2" path_filter="${3:-}" hit path line
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    path=${hit%%:*}
    line=${hit#*:}; line=${line%%:*}

    [ "$path" = "$SELF" ] && continue
    if [ -n "$path_filter" ] && ! printf '%s' "$path" | grep -qE "$path_filter"; then
      continue
    fi

    # Plantillas: se admite únicamente el marcador en esa línea.
    if [ "${path#"$TEMPLATE_DIR"}" != "$path" ]; then
      if _line_content "$path" "$line" | grep -qF "$MARKER"; then
        continue
      fi
    fi

    echo "  HALLAZGO  ${path}:${line}  [${label}]"
    findings=$((findings + 1))
  done < <(git grep "${GIT_GREP_SCOPE[@]}" -I -n -E "$ere" -- . ":(exclude)${SELF}" 2>/dev/null | cut -d: -f1-2 || true)
}

# Como scan(), pero incluye binarios (git grep -a). Nunca imprime el valor
# detectado. Lleva las dos exclusiones acotadas descritas en la cabecera; el
# árbol vendorizado de Wazuh se excluye ya en el pathspec de git grep para que
# ni aparezca en el bucle.
scan_all() {   # $1 = etiqueta   $2 = ERE
  local label="$1" ere="$2" hit path line
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    path=${hit%%:*}
    line=${hit#*:}; line=${line%%:*}

    [ "$path" = "$SELF" ] && continue

    # Ficheros de ejemplo: un placeholder (change_me / changeme) es legítimo.
    # Se descarta el hallazgo solo si en esa línea no hay además una credencial
    # real de la lista.
    if printf '%s\n' "$path" | grep -qE "$EXAMPLE_PATH_RE"; then
      if ! _line_content "$path" "$line" | grep -qE "$HARD_CRED_RE"; then
        continue
      fi
    fi

    echo "  HALLAZGO  ${path}:${line}  [${label}]"
    findings=$((findings + 1))
  done < <(git grep "${GIT_GREP_SCOPE[@]}" -a -n -E "$ere" \
             -- . ":(exclude)${SELF}" ":(exclude)${VENDOR_WAZUH}" \
             2>/dev/null | cut -d: -f1-2 || true)
}

scan "PEM PRIVATE KEY"   'BEGIN( [A-Z0-9]+)* PRIVATE KEY'
scan "private_key"       '(^|[^A-Za-z_])private_key:[[:space:]]*[^[:space:]#]'
scan "password_hash"     '(^|[^A-Za-z_])password_hash:[[:space:]]*[^[:space:]#]'
scan "password_salt"     '(^|[^A-Za-z_])password_salt:[[:space:]]*[^[:space:]#]'
scan "obfuscation_nonce" '(^|[^A-Za-z_])obfuscation_nonce:[[:space:]]*[^[:space:]#]'
scan "nonce"             "(^|[^A-Za-z_])nonce:[[:space:]]*[\"']?[A-Za-z0-9+/=_-]{16,}"
scan "base64>60"         '[A-Za-z0-9+/]{60,}={0,2}'   "$B64_PATH_RE"
# Anclada por límites no alfabéticos: evita el falso positivo de "changeme"
# como subcadena de "changement" (prosa francesa en fase8-kvm) sin excluir
# ficheros. Un dígito o signo tras la credencial (minioadmin123) sí cuenta.
scan_all "credencial-conocida" '(^|[^A-Za-z])(minioadmin123|minioadmin|SecretPassword|changeme|change_me|admin:admin|password123)([^A-Za-z]|$)'

# Reglas nuevas P1-4 (3.1) — ver cabecera y definicion de *_RE mas arriba.
scan "auth-header"        "$AUTH_HEADER_RE"
scan "x-token-header"     "$XHEADER_RE"
scan "credencial-literal" "$ASSIGN_RE"

echo
scope_desc="ficheros trackeados"
[ "$STAGED" -eq 1 ] && scope_desc="ficheros trackeados (indice, --staged)"
if [ "$findings" -eq 0 ]; then
  echo "OK: 0 hallazgos sobre ${tracked_count} ${scope_desc}."
  exit 0
else
  echo "FALLO: ${findings} hallazgos sobre ${tracked_count} ${scope_desc}."
  exit 1
fi
