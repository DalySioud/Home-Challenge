#!/usr/bin/env bash
#
# generate-certs.sh — Generate self-signed SSL certificates for testing
#
# Usage: sudo bash generate-certs.sh
#

set -euo pipefail

CERT_DIR="/etc/nginx/ssl"
mkdir -p "$CERT_DIR"

echo "Generating self-signed SSL certificate..."

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "${CERT_DIR}/server.key" \
    -out "${CERT_DIR}/server.crt" \
    -subj "/C=US/ST=State/L=City/O=SSLProxy/OU=Monitoring/CN=ssl-proxy.local"

chmod 600 "${CERT_DIR}/server.key"
chmod 644 "${CERT_DIR}/server.crt"

echo "Certificate generated:"
echo "  Key:  ${CERT_DIR}/server.key"
echo "  Cert: ${CERT_DIR}/server.crt"
echo ""
echo "Certificate details:"
openssl x509 -in "${CERT_DIR}/server.crt" -noout -subject -dates
