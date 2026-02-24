#!/bin/bash
set -euo pipefail
# Script: nginx_reverse_proxy.sh
# Description: Generates Nginx reverse proxy configurations for Node.js, Python, and PHP backends
# Author: Aakash
# Date: 2026-02-23
# Usage: ./nginx_reverse_proxy.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/nginx_reverse_proxy.log"
VERBOSE=false
SITES_AVAILABLE="/etc/nginx/sites-available"
SITES_ENABLED="/etc/nginx/sites-enabled"
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

Generates Nginx reverse proxy configuration files for:
  - Node.js application (port 3000) with WebSocket support
  - Python application (port 8000)
  - PHP application (port 9000)

Includes SSL termination and HTTP-->HTTPS redirect for each backend.

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

# Ensure directories exist
check_directories() {
    mkdir -p "$SITES_AVAILABLE" "$SITES_ENABLED"
    log_verbose "Sites directories verified"
}

# Check SSL cert exists, create self-signed if missing
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
        log_success "Self-signed certificate created for ${DOMAIN}"
    fi
}

# Generate Node.js reverse proxy config
generate_nodejs_config() {
    log_info "Generating Node.js reverse proxy config..."
    local conf_file="${SITES_AVAILABLE}/nodejs-app.conf"

    cat > "$conf_file" << EOF
# Node.js Reverse Proxy Configuration
upstream nodejs_backend {
    server 127.0.0.1:3000;
    keepalive 32;
}

server {
    listen 80;
    server_name node.${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name node.${DOMAIN};

    ssl_certificate     ${CERT_DIR}/${DOMAIN}.crt;
    ssl_certificate_key ${KEY_DIR}/${DOMAIN}.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    # Proxy buffering
    proxy_buffering on;
    proxy_buffer_size 4k;
    proxy_buffers 8 16k;

    location / {
        proxy_pass         http://nodejs_backend;
        proxy_http_version 1.1;

        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket support
        proxy_set_header Upgrade    \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 60s;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
    }

    access_log /var/log/nginx/nodejs-app.access.log;
    error_log  /var/log/nginx/nodejs-app.error.log;
}
EOF
    log_success "Node.js config written: ${conf_file}"
}

# Generate Python reverse proxy config
generate_python_config() {
    log_info "Generating Python reverse proxy config..."
    local conf_file="${SITES_AVAILABLE}/python-app.conf"

    cat > "$conf_file" << EOF
# Python Application Reverse Proxy Configuration
upstream python_backend {
    server 127.0.0.1:8000;
    keepalive 16;
}

server {
    listen 80;
    server_name python.${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name python.${DOMAIN};

    ssl_certificate     ${CERT_DIR}/${DOMAIN}.crt;
    ssl_certificate_key ${KEY_DIR}/${DOMAIN}.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    # Proxy settings
    proxy_buffering on;
    proxy_buffer_size 4k;
    proxy_buffers 8 16k;

    location / {
        proxy_pass         http://python_backend;
        proxy_http_version 1.1;

        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_read_timeout 60s;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
    }

    access_log /var/log/nginx/python-app.access.log;
    error_log  /var/log/nginx/python-app.error.log;
}
EOF
    log_success "Python config written: ${conf_file}"
}

# Generate PHP reverse proxy config
generate_php_config() {
    log_info "Generating PHP reverse proxy config..."
    local conf_file="${SITES_AVAILABLE}/php-app.conf"

    cat > "$conf_file" << EOF
# PHP Application Reverse Proxy Configuration
upstream php_backend {
    server 127.0.0.1:9000;
}

server {
    listen 80;
    server_name php.${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name php.${DOMAIN};

    ssl_certificate     ${CERT_DIR}/${DOMAIN}.crt;
    ssl_certificate_key ${KEY_DIR}/${DOMAIN}.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;

    root /var/www/php-app;
    index index.php;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass    127.0.0.1:9000;
        fastcgi_index   index.php;
        fastcgi_param   SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param   HTTPS on;
    }

    location ~ /\. {
        deny all;
    }

    access_log /var/log/nginx/php-app.access.log;
    error_log  /var/log/nginx/php-app.error.log;
}
EOF
    log_success "PHP config written: ${conf_file}"
}

# Enable sites
enable_sites() {
    log_info "Creating symbolic links to sites-enabled..."
    for conf in nodejs-app.conf python-app.conf php-app.conf; do
        if [[ -f "${SITES_AVAILABLE}/${conf}" ]]; then
            ln -sf "${SITES_AVAILABLE}/${conf}" "${SITES_ENABLED}/${conf}"
            log_verbose "Enabled: ${conf}"
        fi
    done
    log_success "All sites enabled"
}

# Test and reload Nginx
test_and_reload() {
    log_info "Testing Nginx configuration..."
    if nginx -t; then
        log_success "Configuration test passed"
        systemctl reload nginx
        log_success "Nginx reloaded"
    else
        log_error "Nginx configuration test failed"
        exit $EXIT_ERROR
    fi
}

# Copy configs to project configs folder
copy_to_configs() {
    local configs_dir="${SCRIPT_DIR}/../configs"
    mkdir -p "$configs_dir"
    cp "${SITES_AVAILABLE}/nodejs-app.conf" "$configs_dir/" 2>/dev/null || true
    cp "${SITES_AVAILABLE}/python-app.conf" "$configs_dir/" 2>/dev/null || true
    cp "${SITES_AVAILABLE}/php-app.conf"    "$configs_dir/" 2>/dev/null || true
    log_verbose "Config files copied to ${configs_dir}"
}

# Print summary
print_summary() {
    echo ""
    echo "========== Nginx Reverse Proxy Setup =========="
    echo "   Node.js proxy: https://node.${DOMAIN} --> 127.0.0.1:3000"
    echo "   Python proxy:  https://python.${DOMAIN} --> 127.0.0.1:8000"
    echo "   PHP proxy:     https://php.${DOMAIN} --> 127.0.0.1:9000"
    echo "   SSL certificates configured"
    echo "   HTTP --> HTTPS redirects active"
    echo "   WebSocket support enabled (Node.js)"
    echo "  Status: Ready"
    echo "==============================================="
}

# Main function
main() {
    init_logging
    log_info "=== nginx_reverse_proxy.sh started ==="
    check_root
    check_directories
    ensure_ssl
    generate_nodejs_config
    generate_python_config
    generate_php_config
    enable_sites
    test_and_reload
    copy_to_configs
    print_summary
    log_info "=== nginx_reverse_proxy.sh completed successfully ==="
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
