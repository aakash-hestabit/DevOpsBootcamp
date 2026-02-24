#!/bin/bash
set -euo pipefail
# Script: nginx_setup.sh
# Description: Installs and configures Nginx with optimized production settings
# Author: Aakash
# Date: 2026-02-23
# Usage: ./nginx_setup.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../var/log/apps"
LOG_FILE="${LOG_DIR}/nginx_setup.log"
VERBOSE=false

# Logging functions
log_info()    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE" || true ;}
log_error()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2 || true; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK]    $1" | tee -a "$LOG_FILE" || true; }
log_verbose() { [[ "$VERBOSE" == true ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" | tee -a "$LOG_FILE" || true ; }

# Help function
show_usage() {
    cat << EOF
Usage: $(basename $0) [OPTIONS]

Installs and configures Nginx with optimized production settings.
Creates directory structure, default server block, log rotation,
and verifies service is running.

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
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit $EXIT_ERROR
    fi
}

# Install Nginx latest stable
install_nginx() {
    log_info "Installing Nginx..."
    apt-get update -qq
    apt-get install -y nginx curl
    NGINX_VERSION=$(nginx -v 2>&1 | grep -oP '[\d.]+')
    log_success "Nginx ${NGINX_VERSION} installed"
}

# Create optimized nginx.conf
configure_nginx() {
    log_info "Writing optimized nginx.conf..."
    local cpu_cores
    cpu_cores=$(nproc)

    cat > /etc/nginx/nginx.conf << EOF
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
    multi_accept on;
    use epoll;
}

http {
    ##
    # Basic Settings
    ##
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    client_body_buffer_size    128k;
    client_max_body_size       16m;
    client_header_buffer_size  1k;
    large_client_header_buffers 4 16k;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ##
    # Logging Settings
    ##
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    error_log  /var/log/nginx/error.log warn;   

    ##
    # Gzip Settings
    ##
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript
               application/json application/javascript application/xml
               application/rss+xml application/atom+xml image/svg+xml;
    gzip_min_length 256;

    ##
    # Virtual Host Configs
    ##
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
    log_success "nginx.conf written"
}

# Create directory structure
create_directories() {
    log_info "Creating directory structure..."
    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/sites-enabled
    mkdir -p /var/www/html
    log_verbose "Directories created: sites-available, sites-enabled, /var/www/html"
    log_success "Directory structure created"
}

# Create default server block
create_default_site() {
    log_info "Creating default server block..."
    cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html index.htm;

    server_name _;

    location / {
        try_files $uri $uri/ =404;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    # Deny access to hidden files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF

    # Enable default site
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

    # Create test page
    cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>Nginx - DevOps Bootcamp</title></head>
<body>
<h1>Nginx is running!</h1>
<p>Web Server Setup - DevOps Bootcamp</p>
</body>
</html>
EOF
    log_success "Default site configured"
}

# Configure log rotation
configure_logrotate() {
    log_info "Configuring log rotation..."
    cat > /etc/logrotate.d/nginx << 'EOF'
/var/log/nginx/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 www-data adm
    sharedscripts
    postrotate
        if [ -f /run/nginx.pid ]; then
            kill -USR1 $(cat /run/nginx.pid)
        fi
    endscript
}
EOF
    log_success "Log rotation configured"
}

# Start and enable Nginx
start_nginx() {
    log_info "Starting and enabling Nginx service..."
    nginx -t
    systemctl enable nginx
    systemctl restart nginx
    log_success "Service started and enabled"
}

# Verify installation
verify_nginx() {
    log_info "Verifying Nginx is responding..."
    sleep 1
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost)
    if [[ "$http_code" == "200" ]]; then
        log_success "Test page accessible"
    else
        log_error "Nginx did not respond with 200 (got $http_code)"
        exit $EXIT_ERROR
    fi
}

# Print summary
print_summary() {
    local nginx_version
    nginx_version=$(nginx -v 2>&1 | grep -oP '[\d.]+')
    echo ""
    echo "========== Nginx Setup =========="
    echo "   Nginx ${nginx_version} installed"
    echo "   Configuration optimized"
    echo "   Directory structure created"
    echo "   Default site configured"
    echo "   Service started and enabled"
    echo "   Test page accessible"
    echo "  Status: Ready"
    echo "================================="
}

# Main function
main() {
    init_logging
    log_info "=== nginx_setup.sh started ==="
    check_root
    install_nginx
    configure_nginx
    create_directories
    create_default_site
    configure_logrotate
    start_nginx
    verify_nginx
    print_summary
    log_info "=== nginx_setup.sh completed successfully ==="
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
