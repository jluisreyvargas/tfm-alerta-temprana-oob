#!/usr/bin/env bash
# Verificación de estado de la Fase 6 (DFIR-IRIS).
# Uso: verify-fase6.sh [--check]   Salida: 0 todo OK, 1 alguna comprobación falla.
# Comprueba comportamiento observable, no ficheros de configuración.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CA_FP="AB:11:4F:F8:A6:08:F2:9F:FB:C5:59:5F:54:B3:AC:6C:4E:65:4D:FB:C4:9B:0F:0E:68:21:28:14:19:EC:82:5C"
FAIL=0

ok()   { printf '  OK    %s\n' "$1"; }
bad()  { printf '  FALLO %s\n' "$1"; FAIL=1; }

echo "== Fase 6 · DFIR-IRIS =="

# 1 · contenedores operativos (P1-11)
for c in app worker nginx db rabbitmq; do
  st=$(docker inspect "iriswebapp_$c" --format '{{.State.Status}}' 2>/dev/null || echo ausente)
  [ "$st" = running ] && ok "iriswebapp_$c running" || bad "iriswebapp_$c: $st"
done

# 2 · pertenencia a la red (causa raíz de P1-11)
net=$(docker network inspect iris_frontend --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null)
for c in app nginx; do
  case "$net" in *"iriswebapp_$c"*) ok "iriswebapp_$c en iris_frontend" ;;
                 *) bad "iriswebapp_$c NO esta en iris_frontend" ;; esac
done

# 3 · exposicion restringida al tailnet (P0-D)
if ss -tln | grep -q '100\.64\.0\.1:4833'; then ok "escucha en 100.64.0.1:4833"
else bad "no escucha en 100.64.0.1:4833"; fi
if ss -tln | grep -qE '(0\.0\.0\.0|\[::\]):4833'; then bad "expuesto en todas las interfaces"
else ok "sin exposicion en 0.0.0.0 ni IPv6"; fi

# 4 · ancla de confianza del enclave (P0-C)
fp=$(docker exec iriswebapp_app openssl x509 -in /etc/irisRootCACert.pem \
       -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
[ "$fp" = "$CA_FP" ] && ok "ancla = CA del enclave" || bad "ancla inesperada: ${fp:-vacio}"

# 5 · el ancla valida un certificado del enclave
docker exec iriswebapp_app openssl verify -CAfile /etc/irisRootCACert.pem \
  /home/iris/certificates/web_certificates/iris_oob_cert.pem >/dev/null 2>&1 \
  && ok "validacion funcional del ancla" || bad "el ancla no valida el cert del enclave"

# 6 · bundle TLS saliente (P1-6)
n=$(docker exec iriswebapp_app python3 -c \
     "import ssl;print(len(ssl.create_default_context().get_ca_certs()))" 2>/dev/null)
[ "${n:-0}" -ge 151 ] && ok "bundle con $n CAs" || bad "bundle con ${n:-0} CAs (esperado >=151)"

# 7 · claves no publicas (P0-E)
for v in IRIS_SECRET_KEY IRIS_SECURITY_PASSWORD_SALT; do
  a=$(grep "^$v=" "$REPO/fase6-iris/.env"       2>/dev/null | cut -d= -f2-)
  m=$(grep "^$v=" "$REPO/fase6-iris/.env.model" 2>/dev/null | cut -d= -f2-)
  if [ -z "$a" ]; then bad "$v ausente de .env"
  elif [ "$a" = "$m" ]; then bad "$v es la constante publica de upstream"
  else ok "$v propia"; fi
done

# 8 · MFA efectivo — la BD, no el log de arranque (P1-9)
mfa=$(docker exec iriswebapp_db psql -U postgres -d iris_db -tAc \
       'SELECT enforce_mfa FROM server_settings;' 2>/dev/null | tr -d ' ')
[ "$mfa" = t ] && ok "enforce_mfa activo" || bad "enforce_mfa = ${mfa:-?}"

# 9 · dos cuentas con MFA enrolado (P1-10)
n=$(docker exec iriswebapp_db psql -U postgres -d iris_db -tAc \
     'SELECT count(*) FROM "user" WHERE mfa_setup_complete;' 2>/dev/null | tr -d ' ')
[ "${n:-0}" -ge 2 ] && ok "$n cuentas con MFA enrolado" \
  || bad "solo ${n:-0} cuenta(s) con MFA: sin acceso de emergencia"

echo
[ $FAIL -eq 0 ] && echo "RESULTADO: OK" || echo "RESULTADO: FALLO"
exit $FAIL
