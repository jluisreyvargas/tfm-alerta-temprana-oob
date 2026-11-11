#!/usr/bin/env bash
# deploy.sh — despliegue del enclave OOB desde cero sobre un Ubuntu limpio.
#
# Fuente de verdad: docs/despliegue/INVENTARIO-despliegue.md.
# Uso: ver deploy/README.md o `deploy.sh --help`.
#
# Este instalador genera secretos nuevos, una CA nueva y reescribe ficheros
# versionados. Ejecutado sobre el laboratorio en uso lo destruiría: por eso
# las guardas de seguridad van antes que cualquier otra cosa y no admiten
# forzado.

set -euo pipefail
umask 077

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DEPLOY_DIR/.." && pwd)"

# shellcheck source=lib/ui.sh
. "$DEPLOY_DIR/lib/ui.sh"
# shellcheck source=lib/secrets.sh
. "$DEPLOY_DIR/lib/secrets.sh"
# shellcheck source=lib/state.sh
. "$DEPLOY_DIR/lib/state.sh"
# shellcheck source=lib/checks.sh
. "$DEPLOY_DIR/lib/checks.sh"

usage() {
  cat <<'EOF'
Uso:
  deploy.sh              Continúa desde la primera etapa no completada.
  deploy.sh --list       Lista las etapas y su estado.
  deploy.sh --only N     Ejecuta solo la etapa N, aunque ya esté completada.
  deploy.sh --from N     Ejecuta desde la etapa N en adelante.
  deploy.sh selftest     Pruebas de las funciones puras. Sin sudo y sin Docker.
  deploy.sh --help

Etapas: 0 a 10, según la sección 4.5 del inventario.
EOF
}

# ─── Guardas de seguridad ────────────────────────────────────────────────────
# Solo se evalúan mientras no exista deploy/.state/ creado por este script.
# No hay opción de forzar: si alguna se cumple, este no es un equipo limpio.

guard_not_the_lab() {
  local found n

  found=$(find "$REPO_ROOT" -path "$REPO_ROOT/.git" -prune -o -type f -name .env -print -quit)
  [ -z "$found" ] || die "hay un .env real en el árbol (${found#"$REPO_ROOT"/}).
       Este clon ya tiene un despliegue. El instalador solo se ejecuta sobre un
       clon recién hecho en una máquina limpia."

  [ ! -e "$REPO_ROOT/fase1-infraestructura/traefik/certs/oob-rootCA.key" ] \
    || die "existe la clave privada de la CA (fase1-infraestructura/traefik/certs/oob-rootCA.key).
       Este clon ya tiene una CA en uso. El instalador generaría otra."

  if command -v docker >/dev/null 2>&1; then
    if n=$(docker ps -aq 2>/dev/null | wc -l) && docker info >/dev/null 2>&1; then :
    elif n=$(sudo docker ps -aq 2>/dev/null | wc -l) && sudo docker info >/dev/null 2>&1; then :
    else
      die "Docker está instalado pero no se puede consultar.
       No se puede descartar que haya contenedores: arranca Docker o desinstálalo."
    fi
    [ "$n" -eq 0 ] || die "Docker tiene $n contenedor(es), en ejecución o parados.
       Este no es un equipo limpio. El instalador no continúa."
  fi
}

# Hook que rechaza cualquier commit en el clon de despliegue.
install_precommit_block() {
  local hook
  hook="$(git -C "$REPO_ROOT" rev-parse --git-path hooks/pre-commit)"
  case "$hook" in /*) ;; *) hook="$REPO_ROOT/$hook" ;; esac
  if [ -e "$hook" ] && ! grep -q 'tfm-oob-deploy' "$hook"; then
    die "ya existe un hook pre-commit que no es de este instalador ($hook).
       En un clon recién hecho no debería haberlo. Revísalo antes de continuar."
  fi
  mkdir -p "$(dirname "$hook")"
  cat >"$hook" <<'EOF'
#!/bin/sh
# tfm-oob-deploy: bloqueo de commits en el clon de despliegue.
cat >&2 <<'MSG'

COMMIT RECHAZADO: este clon es solo de despliegue.

deploy/deploy.sh ha sustituido ficheros versionados por los de esta
instalación: la CA del enclave y sus copias, el bundle de CAs de IRIS y, en
etapas posteriores, configuración con direcciones y credenciales propias de
este equipo. Un commit desde aquí subiría al repositorio el material de un
despliegue concreto y pisaría el del laboratorio.

Los cambios al proyecto se hacen en el clon de trabajo, no en este.
MSG
exit 1
EOF
  chmod 755 "$hook"
}

first_run_setup() {
  step "Guardas de seguridad"
  guard_not_the_lab
  info "sin .env, sin clave de CA y sin contenedores: el equipo parece limpio"

  cat >&2 <<EOF

    Este instalador va a generar secretos y una CA nuevos y a reescribir
    ficheros versionados del repositorio en:
      $REPO_ROOT
    El árbol de trabajo quedará modificado. Para que nada de eso llegue al
    repositorio, se instalará un hook pre-commit que rechaza los commits.

EOF
  confirm "¿Este clon es SOLO de despliegue y aceptas que quede bloqueado para commits?" \
    || die "cancelado: no se ha escrito nada"

  install_precommit_block
  state_init
  info "hook pre-commit instalado; estado en ${STATE_DIR#"$REPO_ROOT"/}"
}

# ─── Etapas ──────────────────────────────────────────────────────────────────

list_stages() {
  local n st
  for n in $(seq "$STAGE_MIN" "$STAGE_MAX"); do
    if stage_is_done "$n"; then st='hecha    '; else st='pendiente'; fi
    printf '  %2d  %s  %s\n' "$n" "$st" "$(stage_title "$n")"
  done
}

run_stage() {
  local n="$1" file
  file=$(stage_file "$n") || die "no existe el fichero de la etapa $n"
  step "Etapa $n · $(stage_title "$n")"
  # Cada etapa corre en un subshell: sus funciones y variables no se mezclan
  # con las de otra, y un fallo no deja el estado a medias en este proceso.
  # El subshell no puede ir como condición de un if: ahí bash desactiva
  # set -e dentro de él y un error intermedio pasaría inadvertido.
  local rc
  set +e
  # shellcheck disable=SC1090
  ( set -euo pipefail; . "$file"; stage_main )
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    stage_mark "$n"
    info "etapa $n completada"
  else
    die "la etapa $n no ha terminado correctamente y NO queda marcada como hecha.
       Corrige lo indicado arriba y vuelve a ejecutar deploy.sh."
  fi
}

valid_stage() {
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge "$STAGE_MIN" ] && [ "$1" -le "$STAGE_MAX" ]
}

main() {
  local mode='continue' arg=''
  case "${1:-}" in
    '')          mode='continue' ;;
    --list)      mode=list ;;
    --only)      mode=only; arg="${2:-}" ;;
    --from)      mode=from; arg="${2:-}" ;;
    selftest)    mode=selftest ;;
    -h|--help)   usage; exit 0 ;;
    *)           usage >&2; exit 2 ;;
  esac

  if [ "$mode" = selftest ]; then
    # shellcheck source=lib/selftest.sh
    . "$DEPLOY_DIR/lib/selftest.sh"
    selftest_main
    exit $?
  fi

  if [ "$mode" = list ]; then
    list_stages
    exit 0
  fi

  if [ "$mode" = only ] || [ "$mode" = from ]; then
    valid_stage "$arg" || die "número de etapa no válido: '${arg}' (de $STAGE_MIN a $STAGE_MAX)"
  fi

  [ "$(id -u)" -ne 0 ] || die "no ejecutes el instalador como root ni con sudo.
       Los ficheros deben pertenecer a tu usuario; el script pide sudo cuando lo necesita."
  git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
    || die "$REPO_ROOT no es un clon de git"

  if state_exists; then
    state_init
  else
    first_run_setup
  fi
  _log "---- deploy.sh ${*:-(sin argumentos)} ----"

  local n ran=0
  case "$mode" in
    only)
      run_stage "$arg" ;;
    from)
      for n in $(seq "$arg" "$STAGE_MAX"); do run_stage "$n"; done ;;
    continue)
      for n in $(seq "$STAGE_MIN" "$STAGE_MAX"); do
        stage_is_done "$n" && continue
        run_stage "$n"; ran=1
      done
      [ "$ran" -eq 1 ] || info "todas las etapas están completadas" ;;
  esac
}

main "$@"
