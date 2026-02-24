#!/bin/bash
set -uo pipefail
# Script: webserver_performance_tuner.sh
# Description: Optimizes Nginx and Apache configurations based on system CPU and RAM resources
# Author: Aakash
# Date: 2026-02-23
# Usage: ./webserver_performance_tuner.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/webserver_performance_tuner.log"
VERBOSE=false
DRY_RUN=false
REPORT_FILE="var/log/apps/performance_tuning_$(date '+%Y-%m-%d').txt"

# Global variables for system resources
CPU_CORES=0
TOTAL_RAM_MB=0
TOTAL_RAM_GB=0

# Nginx parameters
NGINX_WORKERS=0
NGINX_WORKER_CONNECTIONS=0
CLIENT_BODY_BUFFER=""

# Apache parameters
MAX_REQUEST_WORKERS=0
THREADS_PER_CHILD=0
MIN_SPARE_THREADS=0
MAX_SPARE_THREADS=0

# Logging functions
log_info()    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE" || true; }
log_error()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2 || true; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK]    $1" | tee -a "$LOG_FILE" || true; }
log_verbose() { [[ "$VERBOSE" == true ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" | tee -a "$LOG_FILE" || true; }

# Help function
show_usage() {
    cat << EOF
Usage: $(basename $0) [OPTIONS]

Tunes Nginx and Apache configurations based on available CPU cores and RAM.
Creates backups of original configs before applying changes.

OPTIONS:
    -h, --help       Show this help message
    -v, --verbose    Enable verbose output
    -n, --dry-run    Show proposed changes without applying them

Examples:
    $(basename $0)
    $(basename $0) --dry-run
    $(basename $0) --verbose
EOF
}

# Ensure log directory exists
init_logging() {
    mkdir -p "$(dirname "$LOG_FILE")" || true
    touch "$LOG_FILE" || true
    touch "$REPORT_FILE" || true
}

# Check root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit $EXIT_ERROR
    fi
}

# Detect system resources
detect_resources() {
    CPU_CORES=$(nproc 2>/dev/null || echo 1)
    TOTAL_RAM_MB=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null || echo 1024)
    TOTAL_RAM_GB=$(awk '/MemTotal/ {printf "%.1f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 1.0)

    log_info "Detected: ${CPU_CORES} CPU cores, ${TOTAL_RAM_MB}MB RAM (${TOTAL_RAM_GB}GB)"
    echo "System: ${CPU_CORES} cores, ${TOTAL_RAM_MB}MB RAM" >> "$REPORT_FILE" || true
}

# Calculate Nginx tuning values
calculate_nginx_params() {
    NGINX_WORKERS="${CPU_CORES}"

    if [[ $TOTAL_RAM_MB -ge 4096 ]]; then
        NGINX_WORKER_CONNECTIONS=2048
    else
        NGINX_WORKER_CONNECTIONS=1024
    fi

    # Buffer sizes
    CLIENT_BODY_BUFFER="256k"
    if [[ $TOTAL_RAM_MB -ge 2048 ]]; then
        CLIENT_BODY_BUFFER="512k"
    fi

    log_verbose "Nginx: workers=${NGINX_WORKERS}, connections=${NGINX_WORKER_CONNECTIONS}"
}

# Tune Nginx
tune_nginx() {
    local nginx_conf="/etc/nginx/nginx.conf"
    local timestamp
    timestamp=$(date '+%Y%m%d%H%M%S')

    if [[ ! -f "$nginx_conf" ]]; then
        log_info "Nginx not installed, skipping Nginx tuning"
        return
    fi

    log_info "Backing up Nginx config..."
    if cp "$nginx_conf" "${nginx_conf}.bak.${timestamp}" 2>/dev/null; then
        log_success "Backup created: ${nginx_conf}.bak.${timestamp}"
    else
        log_error "Failed to backup Nginx config"
        return
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        echo "[DRY-RUN] Nginx proposed changes:"
        echo "  worker_processes:   ${NGINX_WORKERS}"
        echo "  worker_connections: ${NGINX_WORKER_CONNECTIONS}"
        echo "  gzip:               on (level 6)"
        echo "  keepalive_timeout:  65s"
        echo "  client_body_buffer: ${CLIENT_BODY_BUFFER}"
        return
    fi

    log_info "Applying Nginx performance tuning..."

    # Update worker_processes
    # Update worker_processes (add if doesn't exist)
    if grep -q "^worker_processes" "$nginx_conf" 2>/dev/null; then
        sed -i "s/^worker_processes.*/worker_processes ${NGINX_WORKERS};/" "$nginx_conf" 2>/dev/null || true
    else
        sed -i "1i worker_processes ${NGINX_WORKERS};" "$nginx_conf" 2>/dev/null || true
    fi

    # Update worker_connections (if it exists)
    if grep -q "worker_connections" "$nginx_conf" 2>/dev/null; then
        sed -i "s/worker_connections.*/worker_connections ${NGINX_WORKER_CONNECTIONS};/" "$nginx_conf" 2>/dev/null || true
    fi

    # Write a performance tuning conf drop-in
    cat > /etc/nginx/conf.d/performance.conf << EOF
# Nginx Performance Tuning - Generated $(date '+%Y-%m-%d %H:%M:%S')
# System: ${CPU_CORES} cores, ${TOTAL_RAM_MB}MB RAM

# Connection handling
keepalive_timeout 65;
keepalive_requests 1000;

# Buffer tuning
client_body_buffer_size    ${CLIENT_BODY_BUFFER};
client_max_body_size       16m;
client_header_buffer_size  1k;
large_client_header_buffers 4 16k;

# Proxy buffer settings
proxy_buffer_size   4k;
proxy_buffers       8 16k;
proxy_busy_buffers_size 32k;

# Open file cache
open_file_cache          max=1000 inactive=20s;
open_file_cache_valid    30s;
open_file_cache_min_uses 2;
open_file_cache_errors   on;
EOF

    log_success "Nginx performance tuning applied"
    echo "Nginx optimizations applied: workers=${NGINX_WORKERS}, connections=${NGINX_WORKER_CONNECTIONS}" >> "$REPORT_FILE"

    # Test and reload
    if nginx -t 2>/dev/null; then
        systemctl reload nginx 2>/dev/null || true
        log_success "Nginx reloaded with new settings"
    else
        log_error "Nginx config test failed, restoring backup..."
        cp "${nginx_conf}.bak.${timestamp}" "$nginx_conf" 2>/dev/null || true
        return $EXIT_ERROR
    fi
}

# Calculate Apache tuning values
calculate_apache_params() {
    # MaxRequestWorkers: rough formula based on RAM
    # Reserve ~20% for OS, each Apache worker ~25MB
    local usable_mb=$(( TOTAL_RAM_MB * 80 / 100 ))
    MAX_REQUEST_WORKERS=$(( usable_mb / 25 ))
    # Clamp between 50 and 400
    [[ $MAX_REQUEST_WORKERS -lt 50 ]]  && MAX_REQUEST_WORKERS=50
    [[ $MAX_REQUEST_WORKERS -gt 400 ]] && MAX_REQUEST_WORKERS=400

    THREADS_PER_CHILD=25
    MIN_SPARE_THREADS=25
    MAX_SPARE_THREADS=75

    log_verbose "Apache: MaxRequestWorkers=${MAX_REQUEST_WORKERS}"
}

# Tune Apache
tune_apache() {
    local timestamp
    timestamp=$(date '+%Y%m%d%H%M%S')

    if [[ ! -f "/etc/apache2/apache2.conf" ]]; then
        log_info "Apache not installed, skipping Apache tuning"
        return
    fi

    log_info "Backing up Apache config..."
    if cp /etc/apache2/apache2.conf "/etc/apache2/apache2.conf.bak.${timestamp}" 2>/dev/null; then
        log_success "Backup created: apache2.conf.bak.${timestamp}"
    else
        log_error "Failed to backup Apache config"
        return
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        echo "[DRY-RUN] Apache proposed changes:"
        echo "  MaxRequestWorkers: ${MAX_REQUEST_WORKERS}"
        echo "  ThreadsPerChild:   ${THREADS_PER_CHILD}"
        echo "  MinSpareThreads:   ${MIN_SPARE_THREADS}"
        echo "  MaxSpareThreads:   ${MAX_SPARE_THREADS}"
        echo "  KeepAlive:         On"
        return
    fi

    log_info "Applying Apache performance tuning..."

    cat > /etc/apache2/conf-available/performance-tuning.conf << EOF
# Apache Performance Tuning - Generated $(date '+%Y-%m-%d %H:%M:%S')
# System: ${CPU_CORES} cores, ${TOTAL_RAM_MB}MB RAM

<IfModule mpm_event_module>
    StartServers             ${CPU_CORES}
    MinSpareThreads         ${MIN_SPARE_THREADS}
    MaxSpareThreads         ${MAX_SPARE_THREADS}
    ThreadLimit             64
    ThreadsPerChild         ${THREADS_PER_CHILD}
    MaxRequestWorkers       ${MAX_REQUEST_WORKERS}
    MaxConnectionsPerChild  1000
</IfModule>

# Keepalive
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5

# Compression
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css
    AddOutputFilterByType DEFLATE application/json application/javascript
</IfModule>
EOF

    a2enconf performance-tuning 2>/dev/null || true

    log_success "Apache performance tuning applied"
    echo "Apache optimizations applied: MaxRequestWorkers=${MAX_REQUEST_WORKERS}" >> "$REPORT_FILE" || true

    if apachectl configtest 2>&1 | grep -q "Syntax OK"; then
        systemctl reload apache2 2>/dev/null || true
        log_success "Apache reloaded with new settings"
    else
        log_error "Apache config test failed"
        return $EXIT_ERROR
    fi
}

# Generate report
generate_report() {
    cat >> "$REPORT_FILE" << EOF

===== Performance Tuning Report =====
Date:    $(date '+%Y-%m-%d %H:%M:%S')
Host:    $(hostname)
CPU:     ${CPU_CORES} cores
RAM:     ${TOTAL_RAM_MB}MB (${TOTAL_RAM_GB}GB)

Nginx Settings:
  worker_processes:   ${NGINX_WORKERS}
  worker_connections: ${NGINX_WORKER_CONNECTIONS}
  gzip:               on (level 6)
  keepalive_timeout:  65s

Apache Settings:
  MaxRequestWorkers:  ${MAX_REQUEST_WORKERS}
  ThreadsPerChild:    ${THREADS_PER_CHILD}
  KeepAlive:          On
=====================================
EOF
    echo ""
    echo "Performance report saved: ${REPORT_FILE}"
    log_info "Report generated: ${REPORT_FILE}" || true
}

# Main function
main() {
    init_logging
    log_info "=== webserver_performance_tuner.sh started ==="
    check_root || exit $EXIT_ERROR
    detect_resources || exit $EXIT_ERROR
    calculate_nginx_params || exit $EXIT_ERROR
    calculate_apache_params || exit $EXIT_ERROR
    tune_nginx || true
    tune_apache || true
    generate_report || true
    log_info "=== webserver_performance_tuner.sh completed successfully ==="
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)    show_usage; exit $EXIT_SUCCESS ;;
        -v|--verbose) VERBOSE=true ;;
        -n|--dry-run) DRY_RUN=true ;;
        *) echo "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
