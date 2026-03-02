#!/bin/bash
set -euo pipefail

# Script: health_check_stack2.sh
# Description: Live health monitor for all Stack 2 services.
#              Polls every 5 seconds and reports status of:
#                - 3 Laravel application instances (ports 8000, 8001, 8002)
#                - MySQL master (port 3306) and slave (port 3307)
#                - MySQL replication status
#                - 2 Queue workers (laravel-worker@1, laravel-worker@2)
#                - Laravel scheduler timer
#                - Nginx load balancer (ports 80, 443)
#              Each check round is appended to a timestamped log file.
# Author: Aakash
# Date: 2026-03-01
# Usage: ./health_check_stack2.sh [--once] [--interval N] [--help]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/var/log/apps/$(basename "$0" .sh).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Config
INTERVAL=5
ONCE=false
REPORT_DIR="$SCRIPT_DIR/var/log/apps"
REPORT_FILE="$REPORT_DIR/health-$(date +%Y%m%d).log"

# MySQL credentials
MASTER_PORT=3306
SLAVE_PORT=3307
APP_USER="laraveluser"
APP_PASSWORD="Laravel@123"
APP_DB="laraveldb"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-Root@123}"

log_info()  { mkdir -p "$(dirname "$LOG_FILE")"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { mkdir -p "$(dirname "$LOG_FILE")"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }

# Help function
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Live health monitor for all Stack 2 services. Runs continuously
(Ctrl+C to stop) unless --once is provided.

OPTIONS:
    -h, --help          Show this help message
    --once              Run a single check then exit
    --interval N        Poll every N seconds (default: 5)
    -v, --verbose       Enable verbose output

EXAMPLES:
    $(basename "$0")                  # poll every 5 s
    $(basename "$0") --once           # one-shot check
    $(basename "$0") --interval 10    # poll every 10 s
EOF
}

ts()   { date '+%Y-%m-%d %H:%M:%S'; }
log()  { echo -e "$1" | tee -a "$REPORT_FILE"; }
ok()   { log "${GREEN}  [OK]   $1${NC}"; }
warn() { log "${YELLOW}  [WARN] $1${NC}"; }
fail() { log "${RED}  [FAIL] $1${NC}"; }

# -----------------------------------------------------------------------
# Check HTTP endpoint
# -----------------------------------------------------------------------
check_http() {
    local label="$1"
    local url="$2"
    local pattern="${3:-}"

    local start; start=$(date +%s%N)
    local out; out=$(curl -sk --max-time 4 "$url" 2>/dev/null || echo "")
    local end; end=$(date +%s%N)
    local ms=$(( (end - start) / 1000000 ))

    if [[ -z "$out" ]]; then
        fail "$label --> no response (${ms}ms)"
        return 1
    fi

    if [[ -n "$pattern" && "$out" != *"$pattern"* ]]; then
        fail "$label --> unexpected response: ${out:0:60}"
        return 1
    fi

    ok "$label --> ${ms}ms"
    return 0
}

# -----------------------------------------------------------------------
# Check MySQL instance
# -----------------------------------------------------------------------
check_mysql() {
    local port="$1"
    local label="MySQL :$port"
    local role="$2"

    if ! mysql -h 127.0.0.1 -P "$port" -u "$APP_USER" -p"$APP_PASSWORD" -e "SELECT 1" "$APP_DB" &>/dev/null 2>&1; then
        fail "$label ($role) --> not responding"
        return 1
    fi

    ok "$label ($role) --> connected"
    return 0
}

# -----------------------------------------------------------------------
# Check MySQL replication
# -----------------------------------------------------------------------
check_replication() {
    local slave_sock="/var/run/mysqld/mysqld-slave.sock"

    # Try socket first, fall back to TCP
    local SLAVE_STATUS=""
    if [[ -S "$slave_sock" ]]; then
        SLAVE_STATUS=$(mysql --socket="$slave_sock" -u root -p"$MYSQL_ROOT_PASSWORD" -e "SHOW SLAVE STATUS\G" 2>/dev/null || echo "")
    fi

    if [[ -z "$SLAVE_STATUS" ]]; then
        SLAVE_STATUS=$(mysql -h 127.0.0.1 -P "$SLAVE_PORT" -u root -p"$MYSQL_ROOT_PASSWORD" -e "SHOW SLAVE STATUS\G" 2>/dev/null || echo "")
    fi

    if [[ -z "$SLAVE_STATUS" ]]; then
        fail "Replication --> cannot query slave status"
        return 1
    fi

    local IO_RUNNING=$(echo "$SLAVE_STATUS" | grep "Slave_IO_Running:" | awk '{print $2}')
    local SQL_RUNNING=$(echo "$SLAVE_STATUS" | grep "Slave_SQL_Running:" | awk '{print $2}')
    local BEHIND=$(echo "$SLAVE_STATUS" | grep "Seconds_Behind_Master:" | awk '{print $2}')

    if [[ "$IO_RUNNING" == "Yes" && "$SQL_RUNNING" == "Yes" ]]; then
        ok "Replication --> IO: $IO_RUNNING, SQL: $SQL_RUNNING, lag: ${BEHIND}s"
        return 0
    else
        fail "Replication --> IO: $IO_RUNNING, SQL: $SQL_RUNNING"
        return 1
    fi
}

# -----------------------------------------------------------------------
# Check systemd service
# -----------------------------------------------------------------------
check_systemd() {
    local name="$1"
    local label="${2:-$name}"

    if systemctl is-active --quiet "$name" 2>/dev/null; then
        ok "$label --> active"
        return 0
    fi
    fail "$label --> not active"
    return 1
}

# -----------------------------------------------------------------------
# Check Nginx
# -----------------------------------------------------------------------
check_nginx() {
    if systemctl is-active --quiet nginx 2>/dev/null; then
        ok "Nginx --> active"
    elif pgrep -x nginx >/dev/null 2>&1; then
        ok "Nginx --> running (non-systemd)"
    else
        fail "Nginx --> not running"
        return 1
    fi

    # Test HTTP --> HTTPS redirect
    local redir; redir=$(curl -sk --max-time 4 -o /dev/null -w "%{http_code}" \
        -H "Host: stack2.devops.local" http://127.0.0.1/ 2>/dev/null || echo "000")
    if [[ "$redir" == "301" || "$redir" == "302" ]]; then
        ok "Nginx HTTP redirect --> ${redir}"
    else
        warn "Nginx HTTP-->HTTPS redirect --> code ${redir} (expected 301)"
    fi
}

# -----------------------------------------------------------------------
# Run one complete health check
# -----------------------------------------------------------------------
run_check() {
    local PASS=0 FAIL=0

    log ""
    log "${BOLD}${BLUE}+===========================================================+${NC}"
    log "${BOLD}${BLUE}|  Stack 2 Health Check  |  $(ts)                            |${NC}"
    log "${BOLD}${BLUE}+===========================================================+${NC}"

    # Laravel Application Instances
    log "${CYAN}${BOLD}  [ Laravel Application (3 instances) ]${NC}"
    for port in 8000 8001 8002; do
        if check_http "Laravel   :$port" "http://127.0.0.1:$port/api/health" '"status"'; then
            PASS=$((PASS + 1))
        else
            FAIL=$((FAIL + 1))
        fi
    done

    # MySQL Master & Slave
    log "${CYAN}${BOLD}  [ MySQL -- Master-Slave Replication ]${NC}"
    if check_mysql "$MASTER_PORT" "master"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi

    if check_mysql "$SLAVE_PORT" "slave"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi

    # Replication status
    if check_replication; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi

    # Queue Workers
    log "${CYAN}${BOLD}  [ Queue Workers (2 workers) ]${NC}"
    for WORKER_ID in 1 2; do
        if check_systemd "laravel-worker@$WORKER_ID" "Worker @$WORKER_ID"; then
            PASS=$((PASS + 1))
        else
            FAIL=$((FAIL + 1))
        fi
    done

    # Scheduler
    log "${CYAN}${BOLD}  [ Laravel Scheduler ]${NC}"
    if check_systemd "laravel-scheduler.timer" "Scheduler timer"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi

    # Nginx
    log "${CYAN}${BOLD}  [ Load Balancer -- Nginx ]${NC}"
    if check_nginx; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi

    # Nginx HTTPS health endpoint
    if check_http "Nginx LB  :443" \
        "https://stack2.devops.local/health" '"status"'; then
        PASS=$((PASS + 1))
    else
        warn "Nginx HTTPS health endpoint not reachable (check /etc/hosts or DNS)"
    fi

    # systemd service status overview
    log "${CYAN}${BOLD}  [ systemd Service Status ]${NC}"
    for PORT in 8000 8001 8002; do
        if check_systemd "laravel-app-$PORT" "laravel-app-$PORT"; then
            PASS=$((PASS + 1))
        else
            FAIL=$((FAIL + 1))
        fi
    done

    # Summary
    local TOTAL=$((PASS + FAIL))
    log ""
    if [[ $FAIL -eq 0 ]]; then
        log "${BOLD}${GREEN}  All $TOTAL checks passed${NC}"
    else
        log "${BOLD}${RED}  $FAIL/$TOTAL checks failed${NC}"
    fi
    log "${DIM}  Report: $REPORT_FILE${NC}"
    log ""

    return $FAIL
}

# -----------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------
main() {
    log_info "Script started"
    mkdir -p "$REPORT_DIR"

    if [[ $ONCE == true ]]; then
        run_check
        log_info "Script completed successfully"
        exit $?
    fi

    log "${BOLD}${BLUE}Stack 2 health monitor started -- interval: ${INTERVAL}s  (Ctrl+C to stop)${NC}"
    log ""

    while true; do
        run_check || true
        sleep "$INTERVAL"
    done
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --once)             ONCE=true ;;
        --interval)         INTERVAL="${2:-5}"; shift ;;
        -h|--help)          show_usage; exit $EXIT_SUCCESS ;;
        -v|--verbose)       set -x ;;
        *)                  log_error "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
