#!/bin/bash
set -euo pipefail

# Script: setup-ssl.sh
# Description: Generate a local CA-signed SSL certificate for stack3.devops.local.
#              Creates a Certificate Authority, then signs a server certificate
#              with Subject Alternative Names (SAN).
# Author: Aakash
# Date: 2026-03-02
# Usage: sudo bash nginx/setup-ssl.sh

DOMAIN="stack3.devops.local"
SSL_DIR="/etc/ssl"
CERT_DIR="$SSL_DIR/certs"
KEY_DIR="$SSL_DIR/private"
CA_KEY="$KEY_DIR/stack3-ca.key"
CA_CERT="$CERT_DIR/stack3-ca.crt"
SERVER_KEY="$KEY_DIR/stack3.key"
SERVER_CSR="/tmp/stack3.csr"
SERVER_CERT="$CERT_DIR/stack3.crt"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "$1"; }
pass() { log "${GREEN}  [OK]   $1${NC}"; }
info() { log "${BLUE}  [INFO] $1${NC}"; }

# Check root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (sudo)."
    exit 1
fi

mkdir -p "$CERT_DIR" "$KEY_DIR"

log ""
log "${BOLD}${CYAN}Generating SSL certificate for ${DOMAIN}${NC}"
log ""

# ── Step 1: CA private key ──────────────────────────────────────────
info "Step 1/6: Generating CA private key..."
openssl genrsa -out "$CA_KEY" 4096 2>/dev/null
chmod 600 "$CA_KEY"
pass "CA private key created"

# ── Step 2: CA certificate (self-signed, valid 10 years) ───────────
info "Step 2/6: Generating CA certificate..."
openssl req -new -x509 -key "$CA_KEY" -sha256 -days 3650 \
    -out "$CA_CERT" \
    -subj "/C=IN/ST=DevOps/L=Lab/O=DevOps Bootcamp/OU=Stack3 CA/CN=Stack3 Local CA" \
    2>/dev/null
pass "CA certificate created (10 year validity)"

# ── Step 3: Server private key ─────────────────────────────────────
info "Step 3/6: Generating server private key..."
openssl genrsa -out "$SERVER_KEY" 2048 2>/dev/null
chmod 600 "$SERVER_KEY"
pass "Server private key created"

# ── Step 4: CSR + sign with CA (SAN support) ───────────────────────
info "Step 4/6: Creating CSR and signing with CA..."
cat > /tmp/stack3-san.cnf <<EOF
[req]
default_bits       = 2048
prompt             = no
distinguished_name = dn
req_extensions     = san

[dn]
C  = IN
ST = DevOps
L  = Lab
O  = DevOps Bootcamp
OU = Stack 3
CN = ${DOMAIN}

[san]
subjectAltName = DNS:${DOMAIN},DNS:localhost,IP:127.0.0.1

[v3_ext]
subjectAltName         = DNS:${DOMAIN},DNS:localhost,IP:127.0.0.1
authorityKeyIdentifier = keyid,issuer
basicConstraints       = CA:FALSE
keyUsage               = digitalSignature, keyEncipherment
extendedKeyUsage       = serverAuth
EOF

openssl req -new -key "$SERVER_KEY" \
    -out "$SERVER_CSR" \
    -config /tmp/stack3-san.cnf 2>/dev/null

openssl x509 -req -in "$SERVER_CSR" \
    -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
    -out "$SERVER_CERT" -days 825 -sha256 \
    -extfile /tmp/stack3-san.cnf -extensions v3_ext 2>/dev/null

rm -f "$SERVER_CSR" /tmp/stack3-san.cnf
pass "Server certificate signed by local CA (825 days)"

# ── Step 5: Install CA cert to system trust store ──────────────────
info "Step 5/6: Installing CA to system trust store..."
if [[ -d /usr/local/share/ca-certificates ]]; then
    cp "$CA_CERT" /usr/local/share/ca-certificates/stack3-ca.crt
    update-ca-certificates 2>/dev/null || true
    pass "CA installed to system trust store"
elif [[ -d /etc/pki/ca-trust/source/anchors ]]; then
    cp "$CA_CERT" /etc/pki/ca-trust/source/anchors/stack3-ca.crt
    update-ca-trust 2>/dev/null || true
    pass "CA installed to system trust store"
else
    info "Could not auto-install CA — manually trust: $CA_CERT"
fi

# ── Step 6: Install CA into Chrome / Chromium NSS database ────────
info "Step 6/6: Installing CA into Chrome NSS database..."
NSSDB_DIR="$HOME/.pki/nssdb"
if [[ -z "${SUDO_USER:-}" ]]; then
    NSSDB_DIR="$HOME/.pki/nssdb"
else
    NSSDB_DIR="$(getent passwd "$SUDO_USER" | cut -d: -f6)/.pki/nssdb"
fi
if command -v certutil &>/dev/null && [[ -d "$NSSDB_DIR" ]]; then
    certutil -d "sql:$NSSDB_DIR" -D -n "Stack3 Local CA" 2>/dev/null || true
    certutil -d "sql:$NSSDB_DIR" -A -t "C,," -n "Stack3 Local CA" -i "$CA_CERT"
    pass "CA installed to Chrome NSS database"
else
    info "certutil not found or NSS DB missing — install libnss3-tools"
fi

log ""
log "${GREEN}SSL certificate ready:${NC}"
log "  Certificate: $SERVER_CERT"
log "  Private key: $SERVER_KEY"
log "  CA cert:     $CA_CERT"
log ""
log "Certificate details:"
openssl x509 -in "$SERVER_CERT" -noout -subject -dates -issuer
log ""
log "${CYAN}After regenerating, reload Nginx:${NC}"
log "  sudo systemctl reload nginx"
