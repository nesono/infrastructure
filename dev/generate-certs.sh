#!/usr/bin/env bash
set -o errexit -o pipefail -o nounset

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/certs"

mkdir -p "${CERTS_DIR}"

if [[ -f "${CERTS_DIR}/fullchain.pem" && -f "${CERTS_DIR}/key.pem" ]]; then
  echo "Certs already exist in ${CERTS_DIR}"
  exit 0
fi

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "${CERTS_DIR}/key.pem" \
  -out "${CERTS_DIR}/fullchain.pem" \
  -days 365 \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,DNS:smtp.nesono.com,DNS:mail.nesono.com,DNS:imap.nesono.com" \
  2>/dev/null

echo "Self-signed certs created in ${CERTS_DIR}"
