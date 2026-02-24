#!/bin/bash
set -euo pipefail
# Script: apache_setup.sh
# Description: Installs and configures Apache2 with required modules and optimized settings
# Author: Aakash
# Date: 2026-02-23
# Usage: ./apache_setup.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/apache_setup.log"
VERBOSE=false

# Logging functions
log_info()    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE" || true ; }
log_error()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2 || true ; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK]    $1" | tee -a "$LOG_FILE" || true ; }
log_verbose() { [[ "$VERBOSE" == true ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" | tee -a "$LOG_FILE" || true ; }

# Help function
show_usage() {
    cat << EOF
Usage: $(basename $0) [OPTIONS]

Installs Apache2 and enables required proxy/SSL/rewrite modules.
Creates optimized configuration with MPM event, virtual host structure,
and verifies service on port 8080.

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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit $EXIT_ERROR
    fi
}

# Install Apache2
install_apache() {
    log_info "Installing Apache2..."
    apt-get update -qq
    apt-get install -y apache2 curl
    APACHE_VERSION=$(apache2 -v 2>&1 | grep "Server version" | grep -oP '[\d.]+' | head -1)
    log_success "Apache2 ${APACHE_VERSION} installed"
}

# Disable PHP modules that conflict with mpm_event
disable_conflicting_modules() {
    log_info "Checking for conflicting modules..."
    if apache2ctl -M 2>/dev/null | grep -q "php"; then
        log_info "Disabling PHP modules (incompatible with mpm_event)..."
        find /etc/apache2/mods-enabled -name "php*.load" -exec basename {} .load \; | while read mod; do
            a2dismod "$mod" 2>/dev/null || true
            log_verbose "Disabled module: $mod"
        done
    fi
}

# Enable required modules
enable_modules() {
    log_info "Enabling Apache2 modules..."
    local modules=(proxy proxy_http ssl rewrite headers)
    for mod in "${modules[@]}"; do
        a2enmod "$mod" 2>/dev/null || true
        log_verbose "Enabled module: $mod"
    done

    # Switch to MPM event (disable prefork first if loaded)
    if apache2ctl -M 2>/dev/null | grep -q "mpm_prefork"; then
        log_info "Disabling mpm_prefork to enable mpm_event..."
        a2dismod mpm_prefork 2>/dev/null || log_error "Could not disable mpm_prefork"
    fi
    a2enmod mpm_event 2>/dev/null || log_error "Could not enable mpm_event"

    log_success "Module configuration updated"
}

# Create optimized apache2.conf additions
configure_apache() {
    log_info "Writing optimized MPM event configuration..."

    cat > /etc/apache2/conf-available/mpm-event-tuning.conf << 'EOF'
# MPM Event Tuning
<IfModule mpm_event_module>
    StartServers             2
    MinSpareThreads         25
    MaxSpareThreads         75
    ThreadLimit             64
    ThreadsPerChild         25
    MaxRequestWorkers      150
    MaxConnectionsPerChild 1000
</IfModule>

# Keepalive settings
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5

# Security
ServerTokens Prod
ServerSignature Off

# Log format
LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combined
LogFormat "%h %l %u %t \"%r\" %>s %b" common
EOF

    a2enconf mpm-event-tuning
    log_success "Apache configuration optimized"
}

# Configure ports - ensure only 8080 is listened on
configure_ports() {
    log_info "Configuring Apache to listen only on port 8080..."
    
    # Remove all Listen directives from ports.conf and set only 8080
    > /etc/apache2/ports.conf
    echo "Listen 8080" > /etc/apache2/ports.conf
    log_verbose "Set ports.conf to listen only on 8080"
    
    # Remove Listen 80 from main apache2.conf if it exists
    sed -i '/^Listen 80$/d' /etc/apache2/apache2.conf || true
    
    log_success "Port configuration set to 8080"
}

# Create directory structure
create_directories() {
    log_info "Creating virtual host directory structure..."
    mkdir -p /etc/apache2/sites-available
    mkdir -p /etc/apache2/sites-enabled
    mkdir -p /var/www/html
    log_success "Directory structure created"
}

# Create default virtual host on port 8080
create_default_vhost() {
    log_info "Creating default virtual host on port 8080..."

    cat > /etc/apache2/sites-available/000-default.conf << 'EOF'
<VirtualHost *:8080>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined

    <Directory /var/www/html>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    # Security headers
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
</VirtualHost>
EOF

    # Create test page
    cat > /var/www/html/apache-test.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>Apache2 - DevOps Bootcamp</title></head>
<body>
<h1>Apache2 is running!</h1>
<p>Web Server Setup - DevOps Bootcamp</p>
</body>
</html>
EOF

    a2ensite 000-default
    log_success "Default virtual host configured on port 8080"
}

# Start and enable Apache
start_apache() {
    log_info "Starting and enabling Apache2 service..."
    apache2ctl configtest
    systemctl enable apache2
    systemctl restart apache2
    log_success "Service started and enabled"
}

# Verify installation
verify_apache() {
    log_info "Verifying Apache2 is responding on port 8080..."
    sleep 1
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 | grep -q "200\|403"; then
        log_success "Apache2 responding on port 8080"
    else
        log_error "Apache2 did not respond on port 8080"
        exit $EXIT_ERROR
    fi
}

# Print summary
print_summary() {
    local apache_version
    apache_version=$(apache2 -v 2>&1 | grep "Server version" | grep -oP '[\d.]+' | head -1)
    echo ""
    echo "========== Apache Setup =========="
    echo "   Apache2 ${apache_version} installed"
    echo "   Modules enabled: proxy, proxy_http, ssl, rewrite, headers"
    echo "   MPM event configured"
    echo "   Directory structure created"
    echo "   Default virtual host on port 8080"
    echo "   Service started and enabled"
    echo "  Status: Ready"
    echo "=================================="
}

# Main function
main() {
    init_logging
    log_info "=== apache_setup.sh started ==="
    check_root
    install_apache
    disable_conflicting_modules
    enable_modules
    configure_apache
    configure_ports
    create_directories
    create_default_vhost
    start_apache
    verify_apache
    print_summary
    log_info "=== apache_setup.sh completed successfully ==="
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
