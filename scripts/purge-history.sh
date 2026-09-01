#!/usr/bin/env bash
# DESTRUCTIVO E IRREVERSIBLE. Reescribe todo el historial y cambia todos los SHA.
# Ejecutar SOLO después de haber rotado la PKI de Velociraptor (Fase D del plan)
# y con el backup de ~/tfm-backups/ verificado.
set -euo pipefail

# ─── Rutas que se eliminan de TODO el historial ──────────────────────────────
PATHS=(
  "fase5-velociraptor/velociraptor-config/"
  "fase5-velociraptor/velociraptor/"
  "fase5-velociraptor/client.config.yaml"
  "fase5-velociraptor/installer-windows/"
  "fase6-iris/certificates/"
)

BACKUP_DIR="${HOME}/tfm-backups"
MIRROR="${BACKUP_DIR}/fase5-p0-1-20260901/repo-mirror-pre-purga.git"
REMOTOS_FILE="${BACKUP_DIR}/remotos-pre-purga.txt"

cd "$(git rev-parse --show-toplevel)"

# ─── 1. git filter-repo disponible ──────────────────────────────────────────
if ! command -v git-filter-repo >/dev/null 2>&1 && ! git filter-repo --help >/dev/null 2>&1; then
  echo "ERROR: git filter-repo no está instalado." >&2
  echo "Instalar con uno de:" >&2
  echo "  pipx install git-filter-repo" >&2
  echo "  pip install --user git-filter-repo" >&2
  echo "  apt install git-filter-repo        # Debian/Ubuntu" >&2
  exit 1
fi

# ─── 2. Backup mirror presente ─────────────────────────────────────────────
if [ ! -d "$MIRROR" ] || ! git -C "$MIRROR" rev-parse --git-dir >/dev/null 2>&1; then
  echo "ERROR: no se encuentra un mirror de backup válido en:" >&2
  echo "  $MIRROR" >&2
  echo >&2
  echo "Créalo antes de purgar:" >&2
  echo "  mkdir -p \"$BACKUP_DIR\"" >&2
  echo "  git clone --mirror \"$(pwd)\" \"$MIRROR\"" >&2
  exit 1
fi

# ─── 3. Árbol de trabajo limpio ────────────────────────────────────────────
if [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: el árbol de trabajo no está limpio. Haz commit o stash antes de purgar." >&2
  git status --short >&2
  exit 1
fi

# ─── Captura de remotos ANTES de purgar ───────────────────────────────────
mkdir -p "$BACKUP_DIR"
git remote -v > "$REMOTOS_FILE"
echo "Remotos guardados en: $REMOTOS_FILE"
echo

# ─── 4. Confirmación interactiva ──────────────────────────────────────────
echo "================================================================"
echo " PURGA DE HISTORIAL — se eliminan de TODOS los commits las rutas:"
for p in "${PATHS[@]}"; do echo "   - $p"; done
echo
echo " Remotos configurados AHORA (git filter-repo los elimina TODOS):"
sed 's/^/   /' "$REMOTOS_FILE"
echo
echo " Cada uno de esos remotos apunta a un repositorio distinto en"
echo " GitHub que contiene una copia del material expuesto. Tras la"
echo " purga habrá que re-añadir cada remoto y hacer 'git push --force'"
echo " contra cada uno por separado."
echo
echo " Esta operación es DESTRUCTIVA E IRREVERSIBLE: cambia todos los SHA."
echo "================================================================"
printf ' Escribe PURGAR para continuar: '
read -r CONFIRM
if [ "$CONFIRM" != "PURGAR" ]; then
  echo "Cancelado. No se ha modificado nada."
  exit 1
fi

# ─── 5. Purga ─────────────────────────────────────────────────────────────
FR_ARGS=(--force --invert-paths)
for p in "${PATHS[@]}"; do FR_ARGS+=(--path "$p"); done
git filter-repo "${FR_ARGS[@]}"

# ─── 6. Comandos de restauración de remotos (SE IMPRIMEN, no se ejecutan) ──
echo
echo "================================================================"
echo " git filter-repo ha eliminado todos los remotos. Restáuralos y"
echo " fuerza el push a mano tras revisar (uno por repositorio):"
echo "----------------------------------------------------------------"
TAGS_ARG=""
[ -n "$(git tag)" ] && TAGS_ARG=" --tags"
# remotos-pre-purga.txt tiene líneas 'name<TAB>url (fetch|push)'
awk '$3=="(push)" { print $1, $2 }' "$REMOTOS_FILE" | sort -u | while read -r NAME URL; do
  echo "git remote add $NAME $URL"
  echo "git push --force $NAME main${TAGS_ARG}"
  echo
done
echo "----------------------------------------------------------------"
echo " Recuerda: cada repositorio remoto conserva el historial expuesto"
echo " hasta que se le aplique el push --force de arriba. Si alguno"
echo " tiene protección de rama o PRs abiertos, resuélvelo antes."
echo "================================================================"

# ─── 7. Verificaciones de cierre ─────────────────────────────────────────
echo
echo "=== Verificación: el historial ya no contiene las rutas purgadas ==="
for p in "${PATHS[@]}"; do
  echo "--- git log --all --oneline -- $p"
  if git log --all --oneline -- "$p" | grep -q .; then
    echo "  ¡ATENCIÓN! todavía aparecen commits para esta ruta."
  else
    echo "  (sin resultados — purgada)"
  fi
done
echo
echo "=== git count-objects -vH ==="
git count-objects -vH
