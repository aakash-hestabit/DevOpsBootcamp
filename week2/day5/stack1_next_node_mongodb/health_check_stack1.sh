#!/bin/bash
set -euo pipefail

# Script: health_check_stack1.sh
# Description: Live health monitor for all Stack 1 services.
#              Polls every 5 seconds and reports status of:
#                - 3 Express API instances (ports 3000, 3003, 3004)
#                - 2 Next.js frontend instances  (ports 3001, 3002)
#                - 3 MongoDB replica set nodes   (ports 27017, 27018, 27019)
#                - Nginx load balancer           (ports 80, 443)
#              Each check round is appended to a timestamped log file.
# Author: Aakash
# Date: 2026-03-01
# Usage: ./health_check_stack1.sh [--once] [--interval N] [--help]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/var/log/apps/$(basename "$0" .sh).log"

#  Colors 
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
MONGO_ADMIN_AUTH="mongodb://admin:Admin%40123@localhost"
MONGO_AUTH="mongodb://devops:Devops%40123@localhost"

log_info()  { mkdir -p "$(dirname "$LOG_FILE")"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { mkdir -p "$(dirname "$LOG_FILE")"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }

# Help function
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Live health monitor for all Stack 1 services. Runs continuously
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

# Check HTTP endpoint 
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

# Check MongoDB node 
check_mongo() {
    local port="$1"
    local label="MongoDB :$port"

    if ! mongosh "mongodb://localhost:$port/admin" \
        --quiet --eval "db.runCommand({ping:1})" >/dev/null 2>&1; then
        fail "$label --> not responding"
        return 1
    fi

    # Get role (PRIMARY / SECONDARY / etc)
    local role
    role=$(mongosh "$MONGO_ADMIN_AUTH:$port/admin?authSource=admin" \
        --quiet --eval "rs.status().members.filter(m=>m.self)[0]?.stateStr || 'UNKNOWN'" \
        2>/dev/null || echo "UNKNOWN")

    ok "$label --> $role"
    return 0
}

# Check PM2 process 
check_pm2() {
    local name="$1"
    if pm2 describe "$name" 2>/dev/null | grep -q "online"; then
        ok "PM2 [$name] --> online"
        return 0
    fi
    fail "PM2 [$name] --> not online"
    return 1
}

# Check Nginx 
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
        -H "Host: stack1.devops.local" http://127.0.0.1/ 2>/dev/null || echo "000")
    if [[ "$redir" == "301" || "$redir" == "302" ]]; then
        ok "Nginx HTTP redirect --> ${redir}"
    else
        warn "Nginx HTTP-->HTTPS redirect --> code ${redir} (expected 301)"
    fi
}

# Run one complete health check 
run_check() {
    local PASS=0 FAIL=0

    log ""
    log "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
    log "${BOLD}${BLUE}║  Stack 1 Health Check  │  $(ts)                          ║${NC}"
    log "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"

    # Backend API 
    log "${CYAN}${BOLD}  [ Backend — Express API ]${NC}"
    for port in 3000 3003 3004; do
        if check_http "Express   :$port" "http://127.0.0.1:$port/api/health" '"status"'; then
            PASS=$((PASS + 1))
        else
            FAIL=$((FAIL + 1))
        fi
    done

    # Frontend 
    log "${CYAN}${BOLD}  [ Frontend - Next.js SSR ]${NC}"
    for port in 3001 3002; do
        if check_http "Next.js   :$port" "http://127.0.0.1:$port/" "html"; then
            PASS=$((PASS + 1))
        else
            FAIL=$((FAIL + 1))
        fi
    done

    # MongoDB Replica Set 
    log "${CYAN}${BOLD}  [ MongoDB — Replica Set rs0 ]${NC}"
    for port in 27017 27018 27019; do
        if check_mongo "$port"; then
            PASS=$((PASS + 1))
        else
            FAIL=$((FAIL + 1))
        fi
    done

    #  Nginx 
    log "${CYAN}${BOLD}  [ Load Balancer — Nginx ]${NC}"
    if check_nginx; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi

    # Nginx HTTPS health endpoint
    if check_http "Nginx LB  :443" \
        "https://stack1.devops.local/health" '"status"'; then
        PASS=$((PASS + 1))
    else
        warn "Nginx HTTPS health endpoint not reachable (check /etc/hosts or DNS)"
    fi

    # PM2 Process Status 
    if command -v pm2 &>/dev/null; then
        log "${CYAN}${BOLD}  [ PM2 — Process Manager ]${NC}"
        for app in backend-3000 backend-3003 backend-3004 frontend-3001 frontend-3002; do
            if check_pm2 "$app"; then
                PASS=$((PASS + 1))
            else
                FAIL=$((FAIL + 1))
            fi
        done
    fi

    # Summary 
    local TOTAL=$((PASS + FAIL))
    log ""
    if [[ $FAIL -eq 0 ]]; then
        log "${BOLD}${GREEN}  ✓ All $TOTAL checks passed${NC}"
    else
        log "${BOLD}${RED}  ✗ $FAIL/$TOTAL checks failed${NC}"
    fi
    log "${DIM}  Report: $REPORT_FILE${NC}"
    log ""

    return $FAIL
}

main() {
    log_info "Script started"
    mkdir -p "$REPORT_DIR"

    if [[ $ONCE == true ]]; then
        run_check
        log_info "Script completed successfully"
        exit $?
    fi

    log "${BOLD}${BLUE}Stack 1 health monitor started — interval: ${INTERVAL}s  (Ctrl+C to stop)${NC}"
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
        -v|--verbose)       set -x ;;   # turn on bash trace for debug
        *)                  log_error "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
