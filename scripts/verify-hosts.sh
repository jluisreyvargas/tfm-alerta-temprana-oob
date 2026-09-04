#!/usr/bin/env bash
# verify-hosts.sh — control de divergencia de la resolución de nombres del enclave.
#
# El enclave no despliega DNS propio: la resolución es por ficheros hosts en tres
# máquinas (ubuntu, w11, dc01). Nada detectaba que esas tres copias divergieran
# (defectos D1–D3, ver docs/README-resolucion-nombres.md). Este script compara
# cada hosts real contra el estado declarado y falla (exit 1) si no coinciden.
#
# Fuente de verdad: docs/resolucion-nombres.tsv  (una fila por par host,nombre).
# La tabla del README se deriva de ese fichero; `--check-doc` comprueba que no
# han divergido entre sí.
#
# Alcance: los nombres *.oob.local y los declarados explícitamente en el .tsv.
# Los alias .local que no pasan por Traefik, VelociraptorServer, localhost y la
# pila IPv6 se listan como informativos y no cuentan como divergencia.
#
# Uso:
#   verify-hosts.sh                     Verifica el /etc/hosts local (host ubuntu).
#   verify-hosts.sh --emit  w11|dc01    Imprime el comando PowerShell de recogida
#                                       para ejecutar en ese host.
#   verify-hosts.sh --check w11|dc01 FICHERO
#                                       Verifica la salida de --emit pegada en
#                                       FICHERO (líneas crudas del hosts remoto).
#   verify-hosts.sh --check-doc         Comprueba que el .tsv y la tabla del
#                                       README declaran los mismos (host,nombre,ip).
#   verify-hosts.sh --help
#
# Detecta: nombre declarado y ausente, nombre presente y no declarado (solo en el
# espacio vigilado), IP que no coincide, y entradas duplicadas (causa de D2).
#
# No modifica ningún fichero hosts. La corrección la hace el usuario.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV="${REPO_ROOT}/docs/resolucion-nombres.tsv"
DOC="${REPO_ROOT}/docs/README-resolucion-nombres.md"

die() { echo "ERROR: $*" >&2; exit 2; }

usage() { sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

[[ -f "$TSV" ]] || die "no existe $TSV"

# --- filas declaradas para un host: "nombre<TAB>ip", nombre en minúsculas ------
declared_for() {
  awk -F'\t' -v h="$1" '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    $1 == "host" { next }
    tolower($1) == h { print tolower($2) "\t" $3 }
  ' "$TSV"
}

# --- fichero hosts -> "nombre<TAB>ip", una línea por aparición de cada nombre ---
parse_hosts() {
  awk '
    { sub(/#.*/, ""); gsub(/\r/, "") }
    /^[[:space:]]*$/ { next }
    {
      ip = $1
      for (i = 2; i <= NF; i++) print tolower($i) "\t" ip
    }
  ' "$1"
}

# --- comparación declarado vs. real; imprime hallazgos y devuelve nº problemas -
compare() {
  local host="$1" hosts_file="$2"
  local decl_file parsed_file
  decl_file="$(mktemp)"; parsed_file="$(mktemp)"
  trap 'rm -f "$decl_file" "$parsed_file"' RETURN

  declared_for "$host" > "$decl_file"
  parse_hosts "$hosts_file" > "$parsed_file"

  [[ -s "$decl_file" ]] || die "el .tsv no declara ningún nombre para el host '$host'"

  awk -F'\t' '
    FNR == NR { decl_ip[$1] = $2; order[++nd] = $1; next }
    {
      cnt[$1]++
      if (cnt[$1] == 1) first_ip[$1] = $2
      else all_ip[$1] = (all_ip[$1] == "" ? first_ip[$1] : all_ip[$1]) "," $2
      present[$1] = 1
    }
    END {
      problems = 0
      for (i = 1; i <= nd; i++) {
        n = order[i]
        if (!present[n]) {
          printf "  FALTA          %-26s  esperado %s\n", n, decl_ip[n]; problems++; continue
        }
        if (cnt[n] > 1) {
          printf "  DUPLICADO      %-26s  %d veces: %s\n", n, cnt[n], all_ip[n]; problems++
        }
        if (first_ip[n] != decl_ip[n]) {
          printf "  IP DISTINTA    %-26s  esperado %s  encontrado %s\n", n, decl_ip[n], first_ip[n]; problems++
        } else if (cnt[n] == 1) {
          printf "  OK             %-26s  %s\n", n, decl_ip[n]
        }
      }
      for (n in present) {
        if (n in decl_ip) continue
        if (n ~ /\.oob\.local$/) {
          printf "  NO DECLARADO   %-26s  -> %s%s\n", n, first_ip[n], \
                 (cnt[n] > 1 ? "  (" cnt[n] " veces)" : ""); problems++
        } else if (n ~ /\./ && n != "localhost") {
          printf "  (fuera de alcance) %-22s  -> %s\n", n, first_ip[n]
        }
      }
      exit (problems > 0 ? 1 : 0)
    }
  ' "$decl_file" "$parsed_file"
}

emit_ps() {
  local host="$1"
  cat <<EOF
# ---------------------------------------------------------------------------
# Ejecutar en PowerShell en el host '${host}' (no requiere administrador: solo lee).
# Guardar la salida en un fichero y traerlo al Ubuntu.
# ---------------------------------------------------------------------------
Get-Content "\$env:SystemRoot\System32\drivers\etc\hosts" |
  Where-Object { \$_ -notmatch '^\s*#' -and \$_ -match '\S' }

# Luego, en el Ubuntu:
#   scripts/verify-hosts.sh --check ${host} <fichero-con-la-salida>
EOF
}

check_doc() {
  local a b
  a="$(mktemp)"; b="$(mktemp)"
  trap 'rm -f "$a" "$b"' RETURN
  awk -F'\t' '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    $1 == "host" { next }
    { print tolower($1) "\t" tolower($2) "\t" $3 }
  ' "$TSV" | sort > "$a"
  # filas de la tabla del README:  | host | nombre | ip | servicio | ... |
  grep -E '^\|[[:space:]]*(ubuntu|w11|dc01)[[:space:]]*\|' "$DOC" | awk -F'|' '
    {
      for (i = 2; i <= 4; i++) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i) }
      print tolower($2) "\t" tolower($3) "\t" $4
    }
  ' | sort > "$b"

  if diff -u "$a" "$b" > /dev/null; then
    echo "check-doc: el .tsv y la tabla del README declaran los mismos (host,nombre,ip)."
    return 0
  fi
  echo "check-doc: DIVERGENCIA entre docs/resolucion-nombres.tsv y la tabla del README" >&2
  echo "  (< solo en .tsv    > solo en la tabla del README)" >&2
  diff "$a" "$b" | grep -E '^[<>]' >&2 || true
  return 1
}

# --------------------------------------------------------------------------
main() {
  case "${1:-}" in
    -h|--help)  usage; exit 0 ;;
    --check-doc) check_doc; exit $? ;;
    --emit)
      host="${2:-}"
      [[ "$host" == "w11" || "$host" == "dc01" ]] || die "--emit requiere 'w11' o 'dc01'"
      emit_ps "$host"; exit 0 ;;
    --check)
      host="${2:-}"; file="${3:-}"
      [[ "$host" == "w11" || "$host" == "dc01" || "$host" == "ubuntu" ]] \
        || die "--check requiere 'w11', 'dc01' o 'ubuntu'"
      [[ -n "$file" ]] || die "--check requiere un fichero con la salida de --emit"
      [[ -r "$file" ]] || die "no se puede leer el fichero '$file'"
      target_host="$host"; hosts_path="$file" ;;
    "")
      target_host="ubuntu"; hosts_path="/etc/hosts"
      [[ -f "$hosts_path" ]] || die "no existe $hosts_path" ;;
    *) usage; exit 2 ;;
  esac

  echo "== verificación de resolución de nombres =="
  echo "host declarado : ${target_host}"
  echo "hosts real     : ${hosts_path}"
  echo "declaración    : docs/resolucion-nombres.tsv"
  echo

  rc=0
  compare "$target_host" "$hosts_path" || rc=1
  echo
  if [[ "$rc" -eq 0 ]]; then
    echo "RESULTADO ${target_host}: sin divergencias."
  else
    echo "RESULTADO ${target_host}: divergencia(s) detectada(s) — corregir el hosts (no lo hace este script)."
  fi
  exit "$rc"
}

main "$@"
