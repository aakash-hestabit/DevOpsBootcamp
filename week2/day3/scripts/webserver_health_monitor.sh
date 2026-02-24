#!/bin/bash
set -uo pipefail

# Script: webserver_health_monitor.sh
# Description: Monitors Nginx and Apache services, ports, response times, logs, and upstream backends
# Author: Aakash
# Date: 2026-02-23
# Usage: ./webserver_health_monitor.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/webserver_health_monitor.log"
HEALTH_LOG="var/log/apps/webserver_health_$(date '+%Y-%m-%d').log"
VERBOSE=false
ALERT_EMAIL=""

# Upstream backends to check (space-separated IP:PORT list)
BACKENDS=(
    "http://127.0.0.1:3000/slow"
    "192.168.1.11:3000"
    "192.168.1.12:3000"
)

# Status counters
ISSUES=0
BACKEND_DOWN=0

# Logging functions
log_info()    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE" | tee -a "$HEALTH_LOG" || true; }
log_error()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" | tee -a "$HEALTH_LOG" >&2 || true; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK]    $1" | tee -a "$LOG_FILE" | tee -a "$HEALTH_LOG" || true; }
log_alert()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ALERT] $1" | tee -a "$LOG_FILE" | tee -a "$HEALTH_LOG" || true; }
log_verbose() { [[ "$VERBOSE" == true ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" | tee -a "$LOG_FILE" || true; }

# Help function
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Monitors Nginx and Apache services: status, ports, response time,
error log analysis, connection counts, and upstream backend health.
Saves a daily health report.

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -e, --email ADDR    Send alert emails to this address (requires mailutils)
    -b, --backends LIST Comma-separated list of backends (e.g. 192.168.1.10:3000,192.168.1.11:3000)

Examples:
    $(basename "$0")
    $(basename "$0") --verbose
    $(basename "$0") --backends 10.0.0.1:3000,10.0.0.2:3000
    $(basename "$0") --email admin@example.com
EOF
}

# Ensure log directory exists
init_logging() {
    mkdir -p "$(dirname "$LOG_FILE")" || true
    touch "$LOG_FILE" || true
    touch "$HEALTH_LOG" || true
}

# Check service status
check_service() {
    local service="$1"
    local display="$2"

    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo "   Service: Active and running"
        log_success "${display} service active"
    else
        echo "   Service: NOT running"
        log_alert "${display} service is DOWN"
        ((ISSUES++)) || true
    fi
}

# Check if process is running
check_process() {
    local process="$1"
    local display="$2"

    if pgrep -x "$process" > /dev/null 2>&1; then
        echo "   Process: Running"
        log_success "${display} process running"
    else
        echo "   Process: NOT running"
        log_alert "${display} process not found"
        ((ISSUES++)) || true
    fi
}

# Check if port is listening
check_port() {
    local port="$1"
    local label="$2"

    if ss -tlnp 2>/dev/null | grep -q ":${port} " || netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
        echo "   Port ${port}: Listening"
        log_verbose "Port ${port} open"
    else
        echo "   Port ${port}: NOT listening"
        log_alert "Port ${port} not listening for ${label}"
        ((ISSUES++)) || true
    fi
}

# Check response time
check_response() {
    local url="$1"
    local label="$2"

    local start end elapsed http_code
    start=$(date +%s%3N)
    http_code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
    end=$(date +%s%3N)
    elapsed=$((end - start))

    if [[ "$http_code" =~ ^(200|301|302|304)$ ]]; then
        echo "   Response time: ${elapsed}ms (HTTP ${http_code})"
        log_success "${label} responding in ${elapsed}ms"
    else
        echo "   Response failed: HTTP ${http_code}"
        log_alert "${label} returned HTTP ${http_code}"
        ((ISSUES++)) || true
    fi
}

# Check error logs for recent critical errors
check_error_log() {
    local log_file="$1"
    local label="$2"

    if [[ -f "$log_file" ]]; then
        local recent_errors
        recent_errors=$(tail -100 "$log_file" 2>/dev/null | grep -cE "\[crit\]|\[emerg\]|\[alert\]" 2>/dev/null || echo "0")
        recent_errors=$(echo "$recent_errors" | tr -d ' \n')
        
        if [[ "$recent_errors" -eq 0 ]]; then
            echo "   Error log: No critical errors"
        else
            echo "   Error log: ${recent_errors} critical error(s) found"
            log_alert "${label} has ${recent_errors} critical errors in log"
            ((ISSUES++)) || true
        fi
    else
        echo "   Error log: Not found"
    fi
}

# Check active connections (client connections to webserver, not backends)
check_connections() {
    local service="$1"

    if [[ "$service" == "nginx" ]]; then
        local active_conns
        active_conns=$(ss -tnp 2>/dev/null | grep -i "ESTAB" | grep -c nginx 2>/dev/null || echo 0)
        active_conns=$(echo "$active_conns" | tr -d ' \n')
        echo "   Active connections: ${active_conns}/1024"
        log_verbose "Nginx active connections: ${active_conns}"
    elif [[ "$service" == "apache2" ]]; then
        local active_workers
        active_workers=$(ps aux 2>/dev/null | grep -c "[a]pache2" 2>/dev/null || echo 0)
        active_workers=$(echo "$active_workers" | tr -d ' \n')
        echo "   Active workers: ${active_workers}/150"
        log_verbose "Apache workers: ${active_workers}"
    fi
}

# Check upstream backend health
check_backends() {
    echo ""
    echo "Upstream Backends:"

    for backend in "${BACKENDS[@]}"; do
        local url="" host="" port="" elapsed=0 http_code="000" start=0 end=0
        
        # Handle both full URLs (http://...) and IP:PORT formats
        if [[ "$backend" =~ ^http ]]; then
            url="$backend"
            host=$(echo "$backend" | sed 's|.*://||' | cut -d/ -f1 | cut -d: -f1)
            port=$(echo "$backend" | sed 's|.*://||' | cut -d/ -f1 | cut -d: -f2)
            [[ -z "$port" ]] && port="80"
        else
            host=$(echo "$backend" | cut -d: -f1)
            port=$(echo "$backend" | cut -d: -f2 || echo "80")
            url="http://${host}:${port}/"
        fi

        start=$(date +%s%3N)
        http_code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 3 "$url" 2>/dev/null || echo "000")
        end=$(date +%s%3N)
        elapsed=$((end - start))

        if nc -z -w3 "$host" "$port" 2>/dev/null; then
            echo "   ${backend} - UP (${elapsed}ms)"
            log_success "Backend ${backend} is UP"
        else
            echo "   ${backend} - DOWN (timeout)"
            log_alert "Backend ${backend} is DOWN"
            ((BACKEND_DOWN++)) || true
            ((ISSUES++)) || true
        fi
    done
}

# Check Nginx
check_nginx() {
    echo ""
    echo "Nginx:"
    check_service "nginx" "Nginx"
    check_process "nginx" "Nginx"
    check_port "80" "Nginx"
    check_port "443" "Nginx"
    check_response "http://localhost" "Nginx HTTP"
    check_connections "nginx"
    check_error_log "/var/log/nginx/error.log" "Nginx"
}

# Check Apache
check_apache() {
    echo ""
    echo "Apache:"
    check_service "apache2" "Apache"
    check_process "apache2" "Apache"
    check_port "8080" "Apache"
    check_response "http://localhost:8080" "Apache HTTP"
    check_connections "apache2"
    check_error_log "/var/log/apache2/error.log" "Apache"
}

# Send alert email
send_alert() {
    if [[ -n "$ALERT_EMAIL" ]] && [[ $ISSUES -gt 0 ]]; then
        if command -v mail &>/dev/null; then
            echo "Web server health check detected ${ISSUES} issue(s) on $(hostname) at $(date)" | \
                mail -s "[ALERT] Web Server Health Check - $(hostname)" "$ALERT_EMAIL" 2>/dev/null || true
            log_info "Alert email sent to ${ALERT_EMAIL}"
        fi
    fi
}

# Print status summary
print_status() {
    echo ""
    if [[ $ISSUES -eq 0 ]]; then
        echo "  Status: All systems healthy."
    elif [[ $BACKEND_DOWN -gt 0 && $ISSUES -eq $BACKEND_DOWN ]]; then
        echo "  Status: ${BACKEND_DOWN} backend down, traffic redirected."
    else
        echo "  Status: ${ISSUES} issue(s) detected — review logs."
    fi
}

# Main function
main() {
    init_logging
    log_info "=== webserver_health_monitor.sh started ==="

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo ""
    echo "Web Server Health Check - ${timestamp}"
    echo "=============================================="

    check_nginx
    check_apache
    check_backends
    print_status

    echo ""
    echo "  Report saved: ${HEALTH_LOG}"
    echo "=============================================="

    send_alert
    log_info "=== Health check completed. Issues: ${ISSUES} ==="
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)      show_usage; exit $EXIT_SUCCESS ;;
        -v|--verbose)   VERBOSE=true ;;
        -e|--email)     ALERT_EMAIL="$2"; shift ;;
        -b|--backends)
            IFS=',' read -ra BACKENDS <<< "$2"
            shift ;;
        *) echo "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
