#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Generate wildcard self-signed cert for *.gasket-dev.local if not present
CERT_DIR="${SCRIPT_DIR}/certs"
CERT_FILE="${CERT_DIR}/local.crt"
KEY_FILE="${CERT_DIR}/local.key"

if [[ ! -f "${CERT_FILE}" || ! -f "${KEY_FILE}" ]]; then
  echo "[traefik] Generating self-signed wildcard cert for *.gasket-dev.local ..."
  mkdir -p "${CERT_DIR}"
  openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
    -keyout "${KEY_FILE}" \
    -out "${CERT_FILE}" \
    -subj "/CN=gasket-dev.local" \
    -addext "subjectAltName=DNS:gasket-dev.local,DNS:*.gasket-dev.local"
  echo "[traefik] Certificate written to ${CERT_DIR}"
else
  echo "[traefik] Certificates already exist, skipping generation."
fi

echo "[traefik] Starting Traefik ..."
docker compose -f "${SCRIPT_DIR}/docker-compose.yaml" up -d
