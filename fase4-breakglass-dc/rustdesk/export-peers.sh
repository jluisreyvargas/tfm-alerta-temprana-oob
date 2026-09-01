#!/bin/bash
# Vuelca el inventario de peers de RustDesk a JSON para consumo por n8n.
#
# Se ejecuta en el host y no dentro del contenedor por dos razones:
#   1. La imagen de n8n no incluye sqlite3 ni gestor de paquetes.
#   2. db_v2.sqlite3 usa WAL: montar solo el fichero principal en un
#      contenedor daría un estado desactualizado.
#
# Programado por cron cada 30 minutos.

set -euo pipefail

BASE="$(dirname "$(readlink -f "$0")")"

sqlite3 -readonly -json "$BASE/data/db_v2.sqlite3" \
  "SELECT id, note FROM peer;" > "$BASE/peers.json"
