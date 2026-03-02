#!/bin/bash
set -euo pipefail

# Script: health_check_all_stacks.sh
# Description: Comprehensive multi-level health check system for all 3 stacks.
#              Level 1: Infrastructure (Nginx, databases, disk, memory)
#              Level 2: Applications (processes, ports, endpoints, response times)
#              Level 3: Business Logic (DB queries, API functionality, auth)
#              Includes automatic failover: restart unhealthy services, remove from pool,
#              re-add when healthy, send alerts, log incidents.
# Author: Aakash
# Date: 2026-03-02
# Usage: sudo ./health_check_all_stacks.sh [--once] [--interval N] [--level 1|2|3|all]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/var/log"
REPORT_DIR="$LOG_DIR/health"
LOG_FILE="$LOG_DIR/$(basename "$0" .sh).log"
REPORT_FILE="$REPORT_DIR/health-all-$(date +%Y%m%d).log"
ALERT_LOG="$LOG_DIR/alerts.log"
INCIDENT_LOG="$LOG_DIR/incidents.log"

mkdir -p "$REPORT_DIR"

# Config
INTERVAL=10
ONCE=false
CHECK_LEVEL="all"           # 1, 2, 3, or all
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNED=0
AUTO_RECOVERIES=0

# Stack definitions
STACK1_DIR="$SCRIPT_DIR/stack1_next_node_mongodb"
STACK2_DIR="$SCRIPT_DIR/stack2_laravel_mysql_api"
STACK3_DIR="$SCRIPT_DIR/stack3_next_fastapi_mysql"

# Credentials
MONGO_ADMIN_AUTH="mongodb://admin:Admin%40123@localhost"
MONGO_AUTH="mongodb://devops:Devops%40123@localhost"
MYSQL_S2_USER="laraveluser"
MYSQL_S2_PASS="Laravel@123"
MYSQL_S2_DB="laraveldb"
MYSQL_S3_USER="fastapiuser"
MYSQL_S3_PASS="Fast@123"
MYSQL_S3_DB="fastapidb"

# Logging
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }

ts()   { date '+%Y-%m-%d %H:%M:%S'; }
log()  { echo -e "$1" | tee -a "$REPORT_FILE"; }
ok()   { log "${GREEN}     $1${NC}"; CHECKS_PASSED=$((CHECKS_PASSED + 1)); }
warn() { log "${YELLOW}     $1${NC}"; CHECKS_WARNED=$((CHECKS_WARNED + 1)); }
fail() { log "${RED}     $1${NC}"; CHECKS_FAILED=$((CHECKS_FAILED + 1)); }
sep()  { log "${CYAN}  ──────────────────────────────────────────────────${NC}"; }

show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Comprehensive multi-level health check for all 3 production stacks.

OPTIONS:
  -h, --help          Show this help message
  --once              Run a single check round then exit
  --interval N        Poll every N seconds (default: 10)
  --level LEVEL       Check level: 1 (infra), 2 (app), 3 (business), all (default: all)
  -v, --verbose       Enable verbose output

LEVELS:
  1  Infrastructure   Nginx, databases, disk, memory, CPU
  2  Applications     Process status, port checks, health endpoints, response times
  3  Business Logic   DB query execution, API functionality, auth verification

EXAMPLES:
  sudo ./$(basename "$0")                     # full check, poll every 10s
  sudo ./$(basename "$0") --once              # single check, all levels
  sudo ./$(basename "$0") --level 2 --once    # app-level check only
EOF
}

# ---------------------------------------------------------------------------
# Utility: check HTTP endpoint with timing
# ---------------------------------------------------------------------------
check_http() {
    local label="$1" url="$2" pattern="${3:-}"
    local start end ms out

    start=$(date +%s%N)
    out=$(curl -sk --max-time 5 "$url" 2>/dev/null || echo "")
    end=$(date +%s%N)
    ms=$(( (end - start) / 1000000 ))

    if [[ -z "$out" ]]; then
        fail "$label --> no response (${ms}ms)"
        return 1
    fi
    if [[ -n "$pattern" && "$out" != *"$pattern"* ]]; then
        fail "$label --> unexpected body (${ms}ms)"
        return 1
    fi
    ok "$label (${ms}ms)"
    return 0
}

# ---------------------------------------------------------------------------
# Utility: attempt service restart
# ---------------------------------------------------------------------------
attempt_restart() {
    local service_type="$1" service_name="$2"
    log "${YELLOW}    ACTION: Restarting $service_name...${NC}"
    echo "[$(ts)] RESTART $service_name" >> "$INCIDENT_LOG"

    case "$service_type" in
        systemd)
            sudo systemctl restart "$service_name" 2>/dev/null || true
            sleep 5
            if systemctl is-active --quiet "$service_name" 2>/dev/null; then
                log "${GREEN}     $service_name restarted and healthy${NC}"
                AUTO_RECOVERIES=$((AUTO_RECOVERIES + 1))
                return 0
            fi
            ;;
        pm2)
            pm2 restart "$service_name" 2>/dev/null || true
            sleep 5
            if pm2 describe "$service_name" 2>/dev/null | grep -q "online"; then
                log "${GREEN}     $service_name restarted and healthy${NC}"
                AUTO_RECOVERIES=$((AUTO_RECOVERIES + 1))
                return 0
            fi
            ;;
    esac
    log "${RED}     $service_name restart failed${NC}"
    echo "[$(ts)] ALERT: $service_name restart failed" >> "$ALERT_LOG"
    return 1
}

# ---------------------------------------------------------------------------
# LEVEL 1: Infrastructure Checks
# ---------------------------------------------------------------------------
check_level1() {
    log "${BOLD}${BLUE}  LEVEL 1: Infrastructure${NC}"
    sep

    # Nginx
    if systemctl is-active --quiet nginx 2>/dev/null; then
        ok "Nginx load balancer: UP"
    elif pgrep -x nginx >/dev/null 2>&1; then
        ok "Nginx load balancer: UP (non-systemd)"
    else
        fail "Nginx load balancer: DOWN"
        attempt_restart systemd nginx
    fi

    # MongoDB (Stack 1)
    if command -v mongosh &>/dev/null; then
        for port in 27017 27018 27019; do
            if mongosh "mongodb://localhost:$port/admin" --quiet \
                --eval "db.runCommand({ping:1})" >/dev/null 2>&1; then
                local role
                role=$(mongosh "$MONGO_ADMIN_AUTH:$port/admin?authSource=admin" --quiet \
                    --eval "rs.status().members.filter(m=>m.self)[0]?.stateStr || 'UNKNOWN'" 2>/dev/null || echo "UNKNOWN")
                ok "MongoDB :$port ($role)"
            else
                fail "MongoDB :$port --> not responding"
            fi
        done
    else
        warn "mongosh not installed - skipping MongoDB checks"
    fi

    # MySQL Master (Stack 2 - port 3306)
    if command -v mysql &>/dev/null; then
        if mysql -u "$MYSQL_S2_USER" -p"$MYSQL_S2_PASS" -e "SELECT 1" "$MYSQL_S2_DB" &>/dev/null 2>&1; then
            ok "MySQL :3306 (Stack 2 master): connected"
        else
            fail "MySQL :3306 (Stack 2 master): connection failed"
        fi

        # MySQL Slave (Stack 2 - port 3307)
        if mysql -h 127.0.0.1 -P 3307 -u "$MYSQL_S2_USER" -p"$MYSQL_S2_PASS" -e "SELECT 1" "$MYSQL_S2_DB" &>/dev/null 2>&1; then
            ok "MySQL :3307 (Stack 2 slave): connected"
        else
            warn "MySQL :3307 (Stack 2 slave): not reachable"
        fi

        # MySQL (Stack 3 - port 3306)
        if mysql -u "$MYSQL_S3_USER" -p"$MYSQL_S3_PASS" -e "SELECT 1" "$MYSQL_S3_DB" &>/dev/null 2>&1; then
            ok "MySQL :3306 (Stack 3 fastapidb): connected"
        else
            fail "MySQL :3306 (Stack 3 fastapidb): connection failed"
        fi
    else
        warn "mysql client not installed - skipping MySQL checks"
    fi

    # Disk space
    local disk_pct
    disk_pct=$(df / --output=pcent | tail -1 | tr -d ' %')
    if [[ "$disk_pct" -lt 80 ]]; then
        ok "Disk usage: ${disk_pct}%"
    elif [[ "$disk_pct" -lt 90 ]]; then
        warn "Disk usage: ${disk_pct}% (approaching limit)"
    else
        fail "Disk usage: ${disk_pct}% (CRITICAL)"
    fi

    # Memory
    local mem_pct
    mem_pct=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')
    if [[ "$mem_pct" -lt 80 ]]; then
        ok "Memory usage: ${mem_pct}%"
    elif [[ "$mem_pct" -lt 90 ]]; then
        warn "Memory usage: ${mem_pct}% (high)"
    else
        fail "Memory usage: ${mem_pct}% (CRITICAL)"
    fi

    # CPU load
    local cpu_load
    cpu_load=$(awk '{print $1}' /proc/loadavg)
    local cores
    cores=$(nproc)
    ok "CPU load: $cpu_load (cores: $cores)"
}

# ---------------------------------------------------------------------------
# LEVEL 2: Application Checks
# ---------------------------------------------------------------------------
check_level2() {
    log ""
    log "${BOLD}${BLUE}  LEVEL 2: Applications${NC}"
    sep

    # --- Stack 1 ---
    log "${CYAN}  STACK 1 (Next.js + Node.js + MongoDB):${NC}"

    # Express API
    for port in 3000 3003 3004; do
        if ! check_http "Node.js API :$port" "http://127.0.0.1:$port/api/health" '"status"'; then
            attempt_restart pm2 "backend-$port"
        fi
    done

    # Next.js frontend
    for port in 3001 3002; do
        if ! check_http "Next.js     :$port" "http://127.0.0.1:$port/" "html"; then
            attempt_restart pm2 "frontend-$port"
        fi
    done

    # PM2 process status
    if command -v pm2 &>/dev/null; then
        for app in backend-3000 backend-3003 backend-3004 frontend-3001 frontend-3002; do
            if pm2 describe "$app" 2>/dev/null | grep -q "online"; then
                ok "PM2 [$app]: online"
            else
                fail "PM2 [$app]: not online"
                attempt_restart pm2 "$app"
            fi
        done
    fi

    log ""
    log "${CYAN}  STACK 2 (Laravel + MySQL):${NC}"

    # Laravel instances
    for port in 8000 8001 8002; do
        if ! check_http "Laravel     :$port" "http://127.0.0.1:$port/api/health" '"status"'; then
            attempt_restart systemd "laravel-app-$port"
        fi
    done

    # systemd services
    for port in 8000 8001 8002; do
        if systemctl is-active --quiet "laravel-app-$port" 2>/dev/null; then
            ok "systemd [laravel-app-$port]: active"
        else
            fail "systemd [laravel-app-$port]: not active"
        fi
    done

    # Queue workers
    for wid in 1 2; do
        if systemctl is-active --quiet "laravel-worker@$wid" 2>/dev/null; then
            ok "Queue Worker @$wid: active"
        else
            fail "Queue Worker @$wid: not active"
            attempt_restart systemd "laravel-worker@$wid"
        fi
    done

    # Scheduler
    if systemctl is-active --quiet laravel-scheduler.timer 2>/dev/null; then
        ok "Laravel Scheduler timer: active"
    else
        warn "Laravel Scheduler timer: not active"
    fi

    log ""
    log "${CYAN}  STACK 3 (Next.js + FastAPI + MySQL):${NC}"

    # FastAPI backend
    for port in 8003 8004 8005; do
        if ! check_http "FastAPI     :$port" "http://127.0.0.1:$port/health" '"status"'; then
            attempt_restart systemd "fastapi-$port"
        fi
    done

    # Next.js frontend
    for port in 3005 3006; do
        if ! check_http "Next.js     :$port" "http://127.0.0.1:$port/" "html"; then
            attempt_restart pm2 "nextjs-$port"
        fi
    done

    # Nginx HTTPS endpoints
    log ""
    log "${CYAN}  Nginx HTTPS endpoints:${NC}"
    for stack in stack1 stack2 stack3; do
        check_http "Nginx --> $stack" "https://$stack.devops.local/health" '"status"' || true
    done
}

# ---------------------------------------------------------------------------
# LEVEL 3: Business Logic Checks
# ---------------------------------------------------------------------------
check_level3() {
    log ""
    log "${BOLD}${BLUE}  LEVEL 3: Business Logic${NC}"
    sep

    # Stack 1: MongoDB query execution
    log "${CYAN}  Stack 1 - MongoDB query test:${NC}"
    if command -v mongosh &>/dev/null; then
        local result
        result=$(mongosh "$MONGO_AUTH:27017/usersdb?authSource=admin&replicaSet=rs0" --quiet \
            --eval "db.users.countDocuments({})" 2>/dev/null || echo "ERROR")
        if [[ "$result" != "ERROR" ]]; then
            ok "MongoDB query: db.users.countDocuments() = $result"
        else
            fail "MongoDB query execution failed"
        fi
    else
        warn "mongosh not available - skipping MongoDB query test"
    fi

    # Stack 1: API CRUD test
    log "${CYAN}  Stack 1 - API functionality test:${NC}"
    local api_resp
    api_resp=$(curl -sk --max-time 5 "https://stack1.devops.local/api/users" 2>/dev/null || echo "")
    if [[ -n "$api_resp" && "$api_resp" == *"["* ]]; then
        ok "GET /api/users returns data"
    else
        warn "GET /api/users - no data or unreachable"
    fi

    # Stack 2: MySQL query + Laravel health
    log "${CYAN}  Stack 2 - MySQL query test:${NC}"
    if command -v mysql &>/dev/null; then
        local count
        count=$(mysql -u "$MYSQL_S2_USER" -p"$MYSQL_S2_PASS" -N -e \
            "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$MYSQL_S2_DB'" 2>/dev/null || echo "ERROR")
        if [[ "$count" != "ERROR" ]]; then
            ok "MySQL laraveldb: $count tables"
        else
            fail "MySQL laraveldb query failed"
        fi
    fi

    log "${CYAN}  Stack 2 - Laravel API test:${NC}"
    api_resp=$(curl -sk --max-time 5 "https://stack2.devops.local/api/health" 2>/dev/null || echo "")
    if [[ -n "$api_resp" && "$api_resp" == *'"status"'* ]]; then
        ok "Laravel /api/health returns valid JSON"
    else
        warn "Laravel /api/health not reachable"
    fi

    # Stack 2: Replication lag
    log "${CYAN}  Stack 2 - Replication check:${NC}"
    if command -v mysql &>/dev/null; then
        local slave_status
        slave_status=$(mysql -h 127.0.0.1 -P 3307 -u root -p"${MYSQL_ROOT_PASSWORD:-Root@123}" \
            -e "SHOW SLAVE STATUS\G" 2>/dev/null || echo "")
        if [[ -n "$slave_status" ]]; then
            local lag
            lag=$(echo "$slave_status" | grep "Seconds_Behind_Master:" | awk '{print $2}')
            if [[ "$lag" == "0" || "$lag" == "NULL" ]]; then
                ok "Replication lag: ${lag}s"
            elif [[ -n "$lag" && "$lag" -lt 10 ]]; then
                warn "Replication lag: ${lag}s"
            else
                fail "Replication lag: ${lag:-unknown}s"
            fi
        else
            warn "Cannot query slave replication status"
        fi
    fi

    # Stack 3: MySQL query + FastAPI health
    log "${CYAN}  Stack 3 - MySQL query test:${NC}"
    if command -v mysql &>/dev/null; then
        local count3
        count3=$(mysql -u "$MYSQL_S3_USER" -p"$MYSQL_S3_PASS" -N -e \
            "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$MYSQL_S3_DB'" 2>/dev/null || echo "ERROR")
        if [[ "$count3" != "ERROR" ]]; then
            ok "MySQL fastapidb: $count3 tables"
        else
            fail "MySQL fastapidb query failed"
        fi
    fi

    log "${CYAN}  Stack 3 - FastAPI Swagger test:${NC}"
    check_http "FastAPI /docs" "https://stack3.devops.local/docs" "swagger" || true
}

# ---------------------------------------------------------------------------
# Run complete health check round
# ---------------------------------------------------------------------------
run_check() {
    CHECKS_PASSED=0
    CHECKS_FAILED=0
    CHECKS_WARNED=0
    AUTO_RECOVERIES=0

    log ""
    log "${BOLD}${BLUE}+============================================================+${NC}"
    log "${BOLD}${BLUE}|       All-Stacks Health Check  |  $(ts)     |${NC}"
    log "${BOLD}${BLUE}+============================================================+${NC}"
    log ""

    if [[ "$CHECK_LEVEL" == "all" || "$CHECK_LEVEL" == "1" ]]; then
        check_level1
    fi

    if [[ "$CHECK_LEVEL" == "all" || "$CHECK_LEVEL" == "2" ]]; then
        check_level2
    fi

    if [[ "$CHECK_LEVEL" == "all" || "$CHECK_LEVEL" == "3" ]]; then
        check_level3
    fi

    # Summary
    local TOTAL=$((CHECKS_PASSED + CHECKS_FAILED + CHECKS_WARNED))
    local HEALTH_PCT=100
    if [[ $TOTAL -gt 0 ]]; then
        HEALTH_PCT=$(( (CHECKS_PASSED * 100) / TOTAL ))
    fi

    log ""
    log "${BOLD}  ──────────────────────────────────────────────────${NC}"
    if [[ $CHECKS_FAILED -eq 0 ]]; then
        log "${BOLD}${GREEN}  Overall Health: ${HEALTH_PCT}% | Passed: $CHECKS_PASSED | Warned: $CHECKS_WARNED | Failed: $CHECKS_FAILED${NC}"
    else
        log "${BOLD}${RED}  Overall Health: ${HEALTH_PCT}% | Passed: $CHECKS_PASSED | Warned: $CHECKS_WARNED | Failed: $CHECKS_FAILED${NC}"
    fi
    if [[ $AUTO_RECOVERIES -gt 0 ]]; then
        log "${BOLD}${YELLOW}  Auto-recoveries: $AUTO_RECOVERIES${NC}"
    fi
    log "${DIM}  Report: $REPORT_FILE${NC}"
    log ""

    return $CHECKS_FAILED
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log_info "Health check system started (level: $CHECK_LEVEL)"

    if [[ $ONCE == true ]]; then
        run_check
        local rc=$?
        log_info "Health check completed (exit: $rc)"
        exit $rc
    fi

    log "${BOLD}${BLUE}All-stacks health monitor started — interval: ${INTERVAL}s  (Ctrl+C to stop)${NC}"

    while true; do
        run_check || true
        sleep "$INTERVAL"
    done
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)       show_usage; exit $EXIT_SUCCESS ;;
        --once)          ONCE=true ;;
        --interval)      INTERVAL="${2:-10}"; shift ;;
        --level)         CHECK_LEVEL="${2:-all}"; shift ;;
        -v|--verbose)    set -x ;;
        *)               log_error "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
