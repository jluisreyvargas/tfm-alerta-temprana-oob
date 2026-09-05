#!/bin/bash
# Sonda de CAPACIDAD del KVM OOB.
#
# Mide la conexion TCP real del dispositivo contra rttys, no un campo de la BD.
#
# Historia de este control (relevante para la memoria del TFM):
#  - El campo 'status' tiene retraso demostrado: entre el ultimo contacto real
#    (12 jul 18:36) y su marcado como offline (12 jul 20:55) pasaron 2h26m.
#  - Se sustituyo por 'last_seen_at', que resulto ser peor: NO es un heartbeat,
#    sino el instante del ultimo REGISTRO. Con el dispositivo conectado y
#    funcionando, el valor crece indefinidamente y la sonda habria disparado
#    una falsa alarma a los 900 s.
#  - La tabla device_event_logs tampoco registro una desconexion provocada.
#  - Criterio actual: conexion ESTABLISHED al puerto 5912 dentro del namespace
#    de red del contenedor. La conexion no es visible con `ss` en el host:
#    termina dentro del contenedor, detras del docker-proxy.

set -uo pipefail

CONTENEDOR="${KVM_CONTAINER:-glkvm_cloud}"
PUERTO="${KVM_PORT:-5912}"
WEBHOOK="${ROCKETCHAT_WEBHOOK:-}"

alerta() {
  echo "[$(date -Is)] ALERTA: $1" >&2
  [ -n "$WEBHOOK" ] && curl -sS --max-time 10 -X POST "$WEBHOOK" \
    -H 'Content-Type: application/json' \
    -d "$(printf '{"text":"KVM OOB: %s. Via de recuperacion fisica NO disponible."}' "$1")" >/dev/null
}

if ! docker inspect -f '{{.State.Running}}' "$CONTENEDOR" 2>/dev/null | grep -q true; then
  alerta "el contenedor $CONTENEDOR no esta en ejecucion"
  exit 2
fi

N=$(docker exec "$CONTENEDOR" sh -c \
      "netstat -tn 2>/dev/null | grep -c ':${PUERTO}.*ESTABLISHED'" 2>/dev/null)

case "$N" in
  ''|*[!0-9]*) alerta "no se pudo consultar el estado de la conexion"; exit 2 ;;
esac

if [ "$N" -lt 1 ]; then
  alerta "sin conexion establecida al puerto ${PUERTO}"
  exit 1
fi

echo "[$(date -Is)] OK: ${N} conexion(es) establecida(s) al puerto ${PUERTO}"
exit 0
