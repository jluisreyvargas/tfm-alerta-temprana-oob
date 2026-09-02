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
# En fase5-velociraptor/config-templates/ solo se admite el marcador literal
# <<GENERADO_EN_DESPLIEGUE>>; cualquier otro valor en una plantilla es un fallo.
#
# NUNCA imprime el valor detectado, solo ruta y número de línea.
#
# Salida: 0 si el árbol trabajado está limpio, 1 si detecta algo.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

MARKER='<<GENERADO_EN_DESPLIEGUE>>'
TEMPLATE_DIR='fase5-velociraptor/config-templates/'
SELF='scripts/verify-no-secrets.sh'
B64_PATH_RE='^fase5-velociraptor/.*\.(yaml|yml|env|conf|json)$'

tracked_count=$(git ls-files | wc -l | tr -d ' ')
findings=0

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
      if sed -n "${line}p" "$path" | grep -qF "$MARKER"; then
        continue
      fi
    fi

    echo "  HALLAZGO  ${path}:${line}  [${label}]"
    findings=$((findings + 1))
  done < <(git grep -I -n -E "$ere" -- . ":(exclude)${SELF}" 2>/dev/null | cut -d: -f1-2 || true)
}

scan "PEM PRIVATE KEY"   'BEGIN( [A-Z0-9]+)* PRIVATE KEY'
scan "private_key"       '(^|[^A-Za-z_])private_key:[[:space:]]*[^[:space:]#]'
scan "password_hash"     '(^|[^A-Za-z_])password_hash:[[:space:]]*[^[:space:]#]'
scan "password_salt"     '(^|[^A-Za-z_])password_salt:[[:space:]]*[^[:space:]#]'
scan "obfuscation_nonce" '(^|[^A-Za-z_])obfuscation_nonce:[[:space:]]*[^[:space:]#]'
scan "nonce"             "(^|[^A-Za-z_])nonce:[[:space:]]*[\"']?[A-Za-z0-9+/=_-]{16,}"
scan "base64>60"         '[A-Za-z0-9+/]{60,}={0,2}'   "$B64_PATH_RE"

echo
if [ "$findings" -eq 0 ]; then
  echo "OK: 0 hallazgos sobre ${tracked_count} ficheros trackeados."
  exit 0
else
  echo "FALLO: ${findings} hallazgos sobre ${tracked_count} ficheros trackeados."
  exit 1
fi
