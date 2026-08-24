#!/usr/bin/env bash
#
# Genera la autoridad certificadora interna del enclave OOB y el certificado
# de servidor para los servicios internos (*.oob.local).
#
# Motivacion
# ----------
# Un enclave out-of-band no puede apoyarse en la PKI corporativa: si el
# directorio activo esta comprometido, su autoridad certificadora tambien lo
# esta. La confianza criptografica del enclave debe originarse dentro del
# propio enclave, igual que su plano de red y su autenticacion.
#
# Antes de este cambio, Traefik servia el certificado de relleno
# "TRAEFIK DEFAULT CERT", cuyo CN no corresponde a ningun nombre de host y que
# se regenera en cada reinicio. Ningun cliente podia verificarlo, lo que
# obligaba a desactivar la verificacion TLS en cadena: CERT_NONE en la
# integracion de Wazuh, allowUnauthorizedCerts en el nodo MISP de n8n e
# insecureSkipVerify global en Traefik.
#
# Uso:  bash generate-oob-ca.sh
#
# La clave privada de la CA NO debe versionarse. El .gitignore del repositorio
# debe excluir certs/*-key.pem y certs/*.key.

set -euo pipefail

CERT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/certs"
DAYS_CA=3650
DAYS_LEAF=825   # Limite aceptado por navegadores modernos para hojas TLS.

mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

if [[ -f oob-rootCA.key ]]; then
  echo "Ya existe una CA en $CERT_DIR."
  echo "Para regenerarla, borra oob-rootCA.* y vuelve a ejecutar."
  echo "Aviso: al regenerar hay que redistribuir el CA a todos los clientes."
  exit 1
fi

umask 077

echo "==> Generando la CA raiz del enclave"
openssl genrsa -out oob-rootCA.key 4096
openssl req -x509 -new -nodes -key oob-rootCA.key -sha256 -days "$DAYS_CA" \
  -out oob-rootCA.crt \
  -subj "/C=ES/O=TFM Enclave OOB/OU=Seguridad/CN=OOB Enclave Root CA"

echo "==> Generando la clave y la peticion del certificado de servidor"
openssl genrsa -out oob-wildcard.key 2048

# Los navegadores ignoran el CN desde hace anos: la identidad valida es la
# lista de SAN. Se incluye el comodin y tambien oob.local a secas, porque un
# comodin no cubre el dominio base.
cat > san.cnf <<'EOF'
[req]
distinguished_name = dn
req_extensions     = ext
prompt             = no

[dn]
C  = ES
O  = TFM Enclave OOB
CN = *.oob.local

[ext]
basicConstraints = CA:FALSE
keyUsage         = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName   = @alt

[alt]
DNS.1 = *.oob.local
DNS.2 = oob.local
DNS.3 = n8n.oob.local
DNS.4 = misp.oob.local
DNS.5 = auth.oob.local
DNS.6 = chat.oob.local
DNS.7 = iris.oob.local
DNS.8 = localhost
IP.1  = 127.0.0.1
EOF

openssl req -new -key oob-wildcard.key -out oob-wildcard.csr -config san.cnf

echo "==> Firmando el certificado de servidor con la CA del enclave"
openssl x509 -req -in oob-wildcard.csr \
  -CA oob-rootCA.crt -CAkey oob-rootCA.key -CAcreateserial \
  -out oob-wildcard.crt -days "$DAYS_LEAF" -sha256 \
  -extfile san.cnf -extensions ext

rm -f oob-wildcard.csr san.cnf

# El certificado y el CA son publicos; solo las claves privadas son sensibles.
chmod 600 oob-rootCA.key oob-wildcard.key
chmod 644 oob-rootCA.crt oob-wildcard.crt

echo
echo "==> Verificacion"
openssl verify -CAfile oob-rootCA.crt oob-wildcard.crt
openssl x509 -in oob-wildcard.crt -noout -subject -dates
openssl x509 -in oob-wildcard.crt -noout -ext subjectAltName

cat <<'EOF'

Ficheros generados en certs/:

  oob-rootCA.crt      CA del enclave. Se distribuye a los clientes que deban
                      verificar los servicios internos. Publico.
  oob-rootCA.key      Clave privada de la CA. NO versionar. NO distribuir.
  oob-wildcard.crt    Certificado de servidor para Traefik. Publico.
  oob-wildcard.key    Clave privada del servidor. NO versionar.

Siguientes pasos:

  1. Declarar el certificado en la configuracion dinamica de Traefik
     (dynamic/tls.yml) y montar el directorio certs/ en el contenedor.
  2. Reiniciar Traefik y comprobar que el issuer ya no es TRAEFIK DEFAULT CERT.
  3. Distribuir oob-rootCA.crt a los clientes: manager de Wazuh (para la
     integracion custom-n8n) y contenedor de n8n (para el nodo MISP).
  4. Retirar CERT_NONE, allowUnauthorizedCerts e insecureSkipVerify.
EOF
