#!/bin/bash
set -euo pipefail

# Script: setup-ssl.sh
# Description: Generate a local CA and use it to sign an SSL certificate for
#              stack1.devops.local. The CA is added to the system trust store
#              so browsers and curl trust it without warnings.
#              For production environments replace with a Let's Encrypt cert;
#              certbot instructions are included at the bottom of this script.
# Author: Aakash
# Date: 2026-03-01
# Usage: sudo ./setup-ssl.sh [--help]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/../var/log/apps/$(basename "$0" .sh).log"

# SSL paths and target domain
DOMAIN="stack1.devops.local"
CERT_DIR="/etc/ssl/certs"
KEY_DIR="/etc/ssl/private"
CA_KEY="$KEY_DIR/stack1-ca.key"
CA_CERT="$CERT_DIR/stack1-ca.crt"
CERT_FILE="$CERT_DIR/stack1.crt"
KEY_FILE="$KEY_DIR/stack1.key"
CSR_FILE="/tmp/stack1.csr"
EXT_FILE="/tmp/stack1-ext.cnf"
DAYS=3650   

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info()  { mkdir -p "$(dirname "$LOG_FILE")"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { mkdir -p "$(dirname "$LOG_FILE")"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }

# Help function
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Generate a local CA + signed SSL certificate for $DOMAIN.
Certificate is valid for $DAYS days (10 years). Requires sudo.
The CA certificate is installed into the system trust store so
browsers and CLI tools (curl, wget) trust the certificate.

OPTIONS:
    -h, --help    Show this help message

EXAMPLES:
    sudo $(basename "$0")

NOTE:
    For production use Let's Encrypt instead:
        sudo apt install certbot python3-certbot-nginx
        sudo certbot --nginx -d $DOMAIN
EOF
}

# Main function
main() {
    log_info "SSL certificate setup started for $DOMAIN"

    echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║    SSL Certificate Setup — stack1.devops.local       ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Must run as root to write certificates to /etc/ssl/
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root. Use: sudo $0"
        exit $EXIT_ERROR
    fi

    # Make sure OpenSSL is available before we do anything
    if ! command -v openssl &>/dev/null; then
        log_info "OpenSSL not found — installing..."
        apt-get update -q && apt-get install -y openssl
    fi

    # Ensure the certificate and key directories exist
    mkdir -p "$CERT_DIR" "$KEY_DIR"

    # Step 1: Generate a local Certificate Authority (CA)
    echo -e "${YELLOW}[1/5] Generating local CA private key...${NC}"
    openssl genrsa -out "$CA_KEY" 4096
    chmod 600 "$CA_KEY"
    log_info "CA private key written to $CA_KEY"
    echo -e "${GREEN}-->  CA Key: $CA_KEY${NC}"

    echo -e "${YELLOW}[2/5] Generating CA certificate (10 year validity)...${NC}"
    openssl req -x509 -new -nodes \
        -key  "$CA_KEY" \
        -sha256 \
        -days "$DAYS" \
        -out  "$CA_CERT" \
        -subj "/C=US/ST=DevOps/L=Lab/O=DevOpsBootcamp/OU=CA/CN=DevOpsBootcamp Local CA"
    chmod 644 "$CA_CERT"
    log_info "CA certificate written to $CA_CERT"
    echo -e "${GREEN}-->  CA Cert: $CA_CERT${NC}"

    # Step 2: Generate server private key
    echo -e "${YELLOW}[3/5] Generating server private key (2048-bit RSA)...${NC}"
    openssl genrsa -out "$KEY_FILE" 2048
    chmod 600 "$KEY_FILE"
    log_info "Server private key written to $KEY_FILE"
    echo -e "${GREEN}-->  Server Key: $KEY_FILE${NC}"

    # Step 3: Create CSR + SAN extension file
    echo -e "${YELLOW}[4/5] Generating CSR and signing with local CA...${NC}"
    openssl req -new \
        -key  "$KEY_FILE" \
        -out  "$CSR_FILE" \
        -subj "/C=US/ST=DevOps/L=Lab/O=DevOpsBootcamp/OU=Stack1/CN=$DOMAIN"

    # Create extension file with SAN entries
    cat > "$EXT_FILE" <<-EXTEOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = localhost
IP.1 = 127.0.0.1
EXTEOF

    # Step 4: Sign the server certificate with the CA
    openssl x509 -req \
        -in      "$CSR_FILE" \
        -CA      "$CA_CERT" \
        -CAkey   "$CA_KEY" \
        -CAcreateserial \
        -out     "$CERT_FILE" \
        -days    "$DAYS" \
        -sha256 \
        -extfile "$EXT_FILE"

    chmod 644 "$CERT_FILE"
    rm -f "$CSR_FILE" "$EXT_FILE"
    log_info "Server certificate signed and written to $CERT_FILE"

    # Step 5: Install the CA cert into the system trust store
    echo -e "${YELLOW}[5/5] Installing CA into system trust store...${NC}"
    if [[ -d /usr/local/share/ca-certificates ]]; then
        cp "$CA_CERT" /usr/local/share/ca-certificates/my_local_ca/stack1-ca.crt
        update-ca-certificates 2>/dev/null || true
        log_info "CA installed in system trust store"
        echo -e "${GREEN}-->  CA added to system trust store${NC}"
    fi

    echo ""
    echo -e "${GREEN}-->  Certificate: $CERT_FILE  (signed by local CA)${NC}"
    echo -e "${GREEN}-->  Private key: $KEY_FILE${NC}"
    echo -e "${GREEN}-->  CA cert:     $CA_CERT${NC}"

    # Print the certificate details so we can verify what was generated
    echo ""
    echo -e "${BLUE}Certificate Details:${NC}"
    openssl x509 -in "$CERT_FILE" -noout -subject -issuer -dates

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   SSL Certificate Generated Successfully!            ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Remind the user to update /etc/hosts if the domain isn't resolved yet
    if ! grep -q "stack1.devops.local" /etc/hosts; then
        echo -e "${YELLOW}[TIP] Add the following line to /etc/hosts on client machines:${NC}"
        echo "      127.0.0.1  stack1.devops.local"
        echo ""
        echo -e "      Run: echo '127.0.0.1  stack1.devops.local' | sudo tee -a /etc/hosts"
    fi

    echo ""
    echo -e "${YELLOW}[BROWSER TRUST]${NC}"
    echo "  The local CA has been added to the system trust store."
    echo "  For Chrome/Chromium, this is usually enough after a restart."
    echo "  For Firefox, you may need to import the CA manually:"
    echo "    Settings → Privacy & Security → Certificates → View Certificates"
    echo "    → Authorities → Import → select $CA_CERT"
    echo ""

    echo -e "${BLUE}━━━━━  Production (Let's Encrypt) Alternative  ━━━━━${NC}"
    echo ""
    echo "  # Install certbot:"
    echo "  sudo apt install certbot python3-certbot-nginx"
    echo ""
    echo "  # Obtain certificate (requires public DNS pointing to this server):"
    echo "  sudo certbot --nginx -d $DOMAIN"
    echo ""
    echo "  # Auto-renewal cron (add to /etc/cron.d/certbot):"
    echo "  0 3 * * * root certbot renew --quiet --post-hook 'nginx -s reload'"
    echo ""

    log_info "SSL certificate setup completed successfully"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_usage; exit $EXIT_SUCCESS ;;
        *) log_error "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
