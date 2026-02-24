#!/bin/bash
set -euo pipefail
# Script: nginx_load_balancer.sh
# Description: Generates Nginx load balancer configurations with multiple algorithms and health checks
# Author: Aakash
# Date: 2026-02-23
# Usage: ./nginx_load_balancer.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/nginx_load_balancer.log"
VERBOSE=false
SITES_AVAILABLE="/etc/nginx/sites-available"
SITES_ENABLED="/etc/nginx/sites-enabled"
DOMAIN="lb.devops.local"
ALGORITHM="round_robin"
ENABLE_STICKY=false

# Logging functions
log_info()    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK]    $1" | tee -a "$LOG_FILE"; }
log_verbose() { [[ "$VERBOSE" == true ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" | tee -a "$LOG_FILE"; }

# Help function
show_usage() {
    cat << EOF
Usage: $(basename $0) [OPTIONS]

Generates Nginx load balancer configuration supporting:
  - Round-robin (default), least_conn, ip_hash algorithms
  - Health checks with max_fails and fail_timeout
  - Backup server configuration
  - Optional sticky sessions

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -d, --domain NAME       Load balancer domain (default: lb.devops.local)
    -a, --algorithm ALG     Algorithm: round_robin | least_conn | ip_hash (default: round_robin)
    -s, --sticky            Enable sticky sessions (ip_hash)

Examples:
    $(basename $0)
    $(basename $0) --algorithm least_conn
    $(basename $0) --domain lb.myapp.local --algorithm ip_hash
    $(basename $0) --sticky
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

# Get upstream servers from user
collect_upstream_servers() {
    echo ""
    echo "===== Upstream Server Configuration ====="
    read -rp "Enter number of primary upstream servers (2-5): " SERVER_COUNT

    if [[ "$SERVER_COUNT" -lt 2 || "$SERVER_COUNT" -gt 5 ]]; then
        log_error "Server count must be between 2 and 5"
        exit $EXIT_ERROR
    fi

    UPSTREAM_SERVERS=()
    for ((i=1; i<=SERVER_COUNT; i++)); do
        read -rp "Enter server #${i} IP:PORT (e.g. 192.168.1.10:3000): " server_entry
        UPSTREAM_SERVERS+=("$server_entry")
    done

    read -rp "Enter backup server IP:PORT (e.g. 192.168.1.20:3000): " BACKUP_SERVER
    echo ""
}

# Build upstream block based on algorithm
build_upstream_block() {
    local lb_directive=""
    case "$ALGORITHM" in
        least_conn)  lb_directive="    least_conn;" ;;
        ip_hash)     lb_directive="    ip_hash;" ;;
        round_robin) lb_directive="    # round-robin (default)" ;;
    esac

    # Override with ip_hash if sticky requested
    if [[ "$ENABLE_STICKY" == true ]]; then
        lb_directive="    ip_hash; # sticky sessions"
        ALGORITHM="ip_hash"
    fi

    local server_lines=""
    for srv in "${UPSTREAM_SERVERS[@]}"; do
        server_lines+="    server ${srv} max_fails=3 fail_timeout=30s;"$'\n'
    done

    cat << EOF
upstream app_cluster {
${lb_directive}

${server_lines}    server ${BACKUP_SERVER} backup;
}
EOF
}

# Generate load balancer config file
generate_lb_config() {
    log_info "Generating load balancer configuration..."
    local conf_file="${SITES_AVAILABLE}/load-balancer.conf"
    local upstream_block
    upstream_block=$(build_upstream_block)

    cat > "$conf_file" << EOF
# Nginx Load Balancer Configuration
# Algorithm: ${ALGORITHM}
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

${upstream_block}

server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass         http://app_cluster;
        proxy_http_version 1.1;

        # Failover on errors
        proxy_next_upstream error timeout http_500 http_502 http_503 http_504;

        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Timeouts
        proxy_connect_timeout 10s;
        proxy_send_timeout    60s;
        proxy_read_timeout    60s;

        # Buffering
        proxy_buffering    on;
        proxy_buffer_size  4k;
        proxy_buffers      8 16k;
    }

    # Health check endpoint (returns 200 from load balancer itself)
    location /lb-status {
        access_log off;
        return 200 "load-balancer-ok\n";
        add_header Content-Type text/plain;
    }

    access_log /var/log/nginx/lb.access.log;
    error_log  /var/log/nginx/lb.error.log;
}
EOF
    log_success "Load balancer config written: ${conf_file}"
}

# Enable site and test
enable_and_reload() {
    ln -sf "${SITES_AVAILABLE}/load-balancer.conf" "${SITES_ENABLED}/load-balancer.conf"
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

# Copy config to project folder
copy_to_configs() {
    local configs_dir="${SCRIPT_DIR}/../configs"
    mkdir -p "$configs_dir"
    cp "${SITES_AVAILABLE}/load-balancer.conf" "$configs_dir/" 2>/dev/null || true
    log_verbose "Load balancer config copied to ${configs_dir}"
}

# Print summary
print_summary() {
    echo ""
    echo "========== Nginx Load Balancer Setup =========="
    echo "  Domain:     ${DOMAIN}"
    echo "  Algorithm:  ${ALGORITHM}"
    echo "  Servers:    ${#UPSTREAM_SERVERS[@]} primary + 1 backup"
    echo "  Health:     max_fails=3, fail_timeout=30s"
    echo "  Sticky:     ${ENABLE_STICKY}"
    echo "  Config:     ${SITES_AVAILABLE}/load-balancer.conf"
    echo "  Status:     Ready"
    echo "==============================================="
}

# Main function
main() {
    init_logging
    log_info "=== nginx_load_balancer.sh started ==="
    check_root
    collect_upstream_servers
    generate_lb_config
    enable_and_reload
    copy_to_configs
    print_summary
    log_info "=== nginx_load_balancer.sh completed successfully ==="
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)       show_usage; exit $EXIT_SUCCESS ;;
        -v|--verbose)    VERBOSE=true ;;
        -d|--domain)     DOMAIN="$2"; shift ;;
        -a|--algorithm)  ALGORITHM="$2"; shift ;;
        -s|--sticky)     ENABLE_STICKY=true ;;
        *) echo "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
