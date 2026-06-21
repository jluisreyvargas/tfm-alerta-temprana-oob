#!/usr/bin/env bash
set -euo pipefail
mc alias set oob http://minio:9000 "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"
mc mb -p "oob/${MINIO_BUCKET}"
mc anonymous set none "oob/${MINIO_BUCKET}"
