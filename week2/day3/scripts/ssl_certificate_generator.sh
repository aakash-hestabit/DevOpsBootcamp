#!/bin/bash
set -euo pipefail
# Script: ssl_certificate_generator.sh
# Description: Interactive SSL certificate generator for self-signed and Let's Encrypt certificates
# Author: Aakash
# Date: 2026-02-23
# Usage: ./ssl_certificate_generator.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/ssl_certificate_generator.log"
VERBOSE=false
CERT_DIR="/etc/ssl/certs"
KEY_DIR="/etc/ssl/private"

# Logging functions
log_info()    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK]    $1" | tee -a "$LOG_FILE"; }
log_verbose() { [[ "$VERBOSE" == true ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" | tee -a "$LOG_FILE"; }

# Help function
show_usage() {
    cat << EOF
Usage: $(basename $0) [OPTIONS]

Interactive SSL certificate management tool.
Supports self-signed certificates, Let's Encrypt, renewal, and listing.

OPTIONS:
    -h, --help      Show this help message
    -v, --verbose   Enable verbose output

Examples:
    $(basename $0)
    $(basename $0) --verbose
EOF
}

# Ensure log directory exists
init_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
}

# Check root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit $EXIT_ERROR
    fi
}

# Generate self-signed certificate
generate_self_signed() {
    echo ""
    read -rp "Enter domain name: " DOMAIN
    read -rp "Enter organization: " ORG
    read -rp "Enter country code (2 letters): " COUNTRY
    read -rp "Enter state: " STATE
    read -rp "Enter city: " CITY

    log_info "Generating self-signed certificate for ${DOMAIN}..."

    # Generate private key
    openssl genrsa -out "${KEY_DIR}/${DOMAIN}.key" 2048
    log_success "Private key generated"

    # Generate certificate
    openssl req -new -x509 \
        -key "${KEY_DIR}/${DOMAIN}.key" \
        -out "${CERT_DIR}/${DOMAIN}.crt" \
        -days 365 \
        -subj "/C=${COUNTRY}/ST=${STATE}/L=${CITY}/O=${ORG}/CN=${DOMAIN}" \
        -extensions v3_req \
        -addext "subjectAltName=DNS:${DOMAIN},DNS:www.${DOMAIN}"

    chmod 600 "${KEY_DIR}/${DOMAIN}.key"
    chmod 644 "${CERT_DIR}/${DOMAIN}.crt"

    log_success "Certificate generated (valid 365 days)"
    echo ""
    echo "   Private key generated"
    echo "   Certificate generated (valid 365 days)"
    echo "   Files saved:"
    echo "      - ${KEY_DIR}/${DOMAIN}.key"
    echo "      - ${CERT_DIR}/${DOMAIN}.crt"
    echo ""

    log_info "Self-signed cert created: ${CERT_DIR}/${DOMAIN}.crt"
}

# Generate Let's Encrypt certificate
generate_letsencrypt() {
    echo ""
    read -rp "Enter domain name: " DOMAIN
    read -rp "Enter email address: " EMAIL

    log_info "Installing certbot..."
    apt-get update -qq
    apt-get install -y certbot python3-certbot-nginx

    log_info "Requesting Let's Encrypt certificate for ${DOMAIN}..."
    certbot --nginx -d "${DOMAIN}" -d "www.${DOMAIN}" \
        --non-interactive --agree-tos --email "${EMAIL}"

    # Set up auto-renewal cron
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null; echo "0 3 * * 1 certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -
        log_success "Auto-renewal cron job configured (every Monday at 3:00 AM)"
    fi

    log_success "Let's Encrypt certificate obtained for ${DOMAIN}"
    echo ""
    echo "   Certificate installed for ${DOMAIN}"
    echo "   Auto-renewal cron configured"
}

# Renew existing certificates
renew_certificates() {
    log_info "Renewing Let's Encrypt certificates..."
    if command -v certbot &>/dev/null; then
        certbot renew --quiet --post-hook "systemctl reload nginx"
        log_success "Certificates renewed"
        echo "   Renewal complete"
    else
        log_error "certbot not installed. No Let's Encrypt certificates to renew."
        echo "  ✗ certbot not installed"
    fi
}

# List all certificates
list_certificates() {
    echo ""
    echo "===== SSL Certificates ====="
    echo ""
    echo "-- Self-signed Certificates --"
    if ls "${CERT_DIR}"/*.crt 2>/dev/null | grep -v "ca-certificates" | head -20; then
        for cert in "${CERT_DIR}"/*.crt; do
            [[ -f "$cert" ]] || continue
            expiry=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2 || echo "unknown")
            domain=$(openssl x509 -subject -noout -in "$cert" 2>/dev/null | grep -oP 'CN\s*=\s*\K[^,/]+' || echo "unknown")
            echo "  Domain: ${domain} | Expires: ${expiry} | File: $(basename "$cert")"
        done
    else
        echo "  No self-signed certificates found."
    fi

    echo ""
    echo "-- Let's Encrypt Certificates --"
    if command -v certbot &>/dev/null; then
        certbot certificates 2>/dev/null || echo "  No Let's Encrypt certificates found."
    else
        echo "  certbot not installed"
    fi
    echo "============================="
}

# Main menu
main_menu() {
    echo ""
    echo "SSL Certificate Generator"
    echo "========================================"
    echo "1) Generate self-signed certificate"
    echo "2) Generate Let's Encrypt certificate"
    echo "3) Renew certificate"
    echo "4) List certificates"
    echo "5) Exit"
    echo ""
    read -rp "Choice: " CHOICE

    case $CHOICE in
        1) generate_self_signed ;;
        2) generate_letsencrypt ;;
        3) renew_certificates ;;
        4) list_certificates ;;
        5) log_info "Exiting."; exit $EXIT_SUCCESS ;;
        *) echo "Invalid choice. Please select 1-5."; main_menu ;;
    esac
}

# Main function
main() {
    init_logging
    log_info "=== ssl_certificate_generator.sh started ==="
    check_root
    main_menu
    log_info "=== ssl_certificate_generator.sh completed ==="
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)    show_usage; exit $EXIT_SUCCESS ;;
        -v|--verbose) VERBOSE=true ;;
        *) echo "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
