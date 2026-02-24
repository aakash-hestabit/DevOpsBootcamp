#!/bin/bash
set -euo pipefail
# Script: apache_reverse_proxy.sh
# Description: Generates Apache2 reverse proxy virtual host configurations for multiple backends
# Author: Aakash
# Date: 2026-02-23
# Usage: ./apache_reverse_proxy.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/apache_reverse_proxy.log"
VERBOSE=false
SITES_AVAILABLE="/etc/apache2/sites-available"
CERT_DIR="/etc/ssl/certs"
KEY_DIR="/etc/ssl/private"
DOMAIN="devops.local"

# Logging functions
log_info()    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK]    $1" | tee -a "$LOG_FILE"; }
log_verbose() { [[ "$VERBOSE" == true ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" | tee -a "$LOG_FILE"; }

# Help function
show_usage() {
    cat << EOF
Usage: $(basename $0) [OPTIONS]

Generates Apache2 reverse proxy virtual host configuration files.
Supports Node.js, Python, and PHP backends with SSL termination.

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -d, --domain NAME   Base domain name (default: devops.local)

Examples:
    $(basename $0)
    $(basename $0) --domain myapp.local
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

# Ensure required modules are enabled
ensure_modules() {
    log_info "Enabling required Apache2 modules..."
    for mod in proxy proxy_http ssl rewrite headers; do
        a2enmod "$mod" 2>/dev/null || true
    done
    log_success "Modules verified"
}

# Ensure SSL cert exists
ensure_ssl() {
    if [[ ! -f "${CERT_DIR}/${DOMAIN}.crt" ]]; then
        log_info "SSL certificate not found, generating self-signed cert for ${DOMAIN}..."
        openssl genrsa -out "${KEY_DIR}/${DOMAIN}.key" 2048
        openssl req -new -x509 \
            -key "${KEY_DIR}/${DOMAIN}.key" \
            -out "${CERT_DIR}/${DOMAIN}.crt" \
            -days 365 \
            -subj "/C=US/ST=State/L=City/O=DevOps Bootcamp/CN=${DOMAIN}"
        chmod 600 "${KEY_DIR}/${DOMAIN}.key"
        log_success "Self-signed certificate created"
    fi
}

# Generate Node.js proxy virtual host
generate_nodejs_vhost() {
    log_info "Generating Apache Node.js reverse proxy virtual host..."
    cat > "${SITES_AVAILABLE}/nodejs-proxy.conf" << EOF
# Apache Node.js Reverse Proxy Virtual Host
<VirtualHost *:80>
    ServerName node.${DOMAIN}
    Redirect permanent / https://node.${DOMAIN}/
</VirtualHost>

<VirtualHost *:443>
    ServerName node.${DOMAIN}

    SSLEngine on
    SSLCertificateFile    ${CERT_DIR}/${DOMAIN}.crt
    SSLCertificateKeyFile ${KEY_DIR}/${DOMAIN}.key
    SSLProtocol           all -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite        HIGH:!aNULL:!MD5

    # Proxy settings
    ProxyPreserveHost On
    ProxyRequests Off

    ProxyPass        / http://127.0.0.1:3000/
    ProxyPassReverse / http://127.0.0.1:3000/

    # Proxy headers
    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Real-IP "%{REMOTE_ADDR}s"

    # Security headers
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"

    ErrorLog  \${APACHE_LOG_DIR}/nodejs-proxy.error.log
    CustomLog \${APACHE_LOG_DIR}/nodejs-proxy.access.log combined
</VirtualHost>
EOF
    a2ensite nodejs-proxy 2>/dev/null || true
    log_success "Node.js virtual host created and enabled"
}

# Generate Python proxy virtual host
generate_python_vhost() {
    log_info "Generating Apache Python reverse proxy virtual host..."
    cat > "${SITES_AVAILABLE}/python-proxy.conf" << EOF
# Apache Python Reverse Proxy Virtual Host
<VirtualHost *:80>
    ServerName python.${DOMAIN}
    Redirect permanent / https://python.${DOMAIN}/
</VirtualHost>

<VirtualHost *:443>
    ServerName python.${DOMAIN}

    SSLEngine on
    SSLCertificateFile    ${CERT_DIR}/${DOMAIN}.crt
    SSLCertificateKeyFile ${KEY_DIR}/${DOMAIN}.key
    SSLProtocol           all -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite        HIGH:!aNULL:!MD5

    ProxyPreserveHost On
    ProxyRequests Off

    ProxyPass        / http://127.0.0.1:8000/
    ProxyPassReverse / http://127.0.0.1:8000/

    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Real-IP "%{REMOTE_ADDR}s"

    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"

    ErrorLog  \${APACHE_LOG_DIR}/python-proxy.error.log
    CustomLog \${APACHE_LOG_DIR}/python-proxy.access.log combined
</VirtualHost>
EOF
    a2ensite python-proxy 2>/dev/null || true
    log_success "Python virtual host created and enabled"
}

# Test and reload Apache
test_and_reload() {
    log_info "Testing Apache configuration..."
    if apachectl configtest 2>&1 | grep -q "Syntax OK"; then
        log_success "Configuration test passed"
        systemctl reload apache2
        log_success "Apache2 reloaded"
    else
        apachectl configtest
        log_error "Apache configuration test failed"
        exit $EXIT_ERROR
    fi
}

# Copy configs to project configs folder
copy_to_configs() {
    local configs_dir="${SCRIPT_DIR}/../configs"
    mkdir -p "$configs_dir"
    cp "${SITES_AVAILABLE}/nodejs-proxy.conf"  "$configs_dir/" 2>/dev/null || true
    cp "${SITES_AVAILABLE}/python-proxy.conf"  "$configs_dir/" 2>/dev/null || true
    log_verbose "Apache config files copied to ${configs_dir}"
}

# Print summary
print_summary() {
    echo ""
    echo "========== Apache Reverse Proxy Setup =========="
    echo "   Node.js proxy:  https://node.${DOMAIN} → 127.0.0.1:3000"
    echo "   Python proxy:   https://python.${DOMAIN} → 127.0.0.1:8000"
    echo "   SSL configured with ${DOMAIN} certificate"
    echo "   HTTP → HTTPS redirect active"
    echo "   Proxy headers forwarded"
    echo "  Status: Ready"
    echo "================================================"
}

# Main function
main() {
    init_logging
    log_info "=== apache_reverse_proxy.sh started ==="
    check_root
    ensure_modules
    ensure_ssl
    generate_nodejs_vhost
    generate_python_vhost
    test_and_reload
    copy_to_configs
    print_summary
    log_info "=== apache_reverse_proxy.sh completed successfully ==="
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)    show_usage; exit $EXIT_SUCCESS ;;
        -v|--verbose) VERBOSE=true ;;
        -d|--domain)  DOMAIN="$2"; shift ;;
        *) echo "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
