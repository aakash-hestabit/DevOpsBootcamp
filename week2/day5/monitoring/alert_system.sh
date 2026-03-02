#!/bin/bash
set -euo pipefail

# Script: alert_system.sh
# Description: Alert notification system for production stacks.
#              Monitors thresholds, sends alert notifications via
#              log files and optional email. Supports escalation levels.
# Author: Aakash
# Date: 2026-03-02
# Usage: ./alert_system.sh [--once] [--interval 30] [--help]

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$BASE_DIR/var/log"
ALERT_LOG="$LOG_DIR/alerts.log"
INTERVAL=30
ONCE=false

mkdir -p "$LOG_DIR"

# ---------------------------------------------------------------------------
# Threshold configuration
# ---------------------------------------------------------------------------
CPU_WARNING=70
CPU_CRITICAL=90
MEM_WARNING=75
MEM_CRITICAL=90
DISK_WARNING=80
DISK_CRITICAL=95
RESPONSE_WARNING=500    # ms
RESPONSE_CRITICAL=2000  # ms

# ---------------------------------------------------------------------------
# Notification
# ---------------------------------------------------------------------------
send_alert() {
    local level="$1" component="$2" message="$3"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')

    local prefix=""
    case "$level" in
        INFO)     prefix="${GREEN}[INFO]${NC}" ;;
        WARNING)  prefix="${YELLOW}[WARNING]${NC}" ;;
        CRITICAL) prefix="${RED}[CRITICAL]${NC}" ;;
    esac

    echo -e "  $prefix $component — $message"
    echo "[$ts] $level: $component — $message" >> "$ALERT_LOG"

    # Email notification for CRITICAL (if mail is available)
    if [[ "$level" == "CRITICAL" ]] && command -v mail &>/dev/null; then
        echo "$message" | mail -s "CRITICAL: $component" root@localhost 2>/dev/null || true
    fi
}

show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Alert system for all 3 stacks. Monitors thresholds and logs alerts.

THRESHOLDS:
  CPU:       Warning ${CPU_WARNING}% / Critical ${CPU_CRITICAL}%
  Memory:    Warning ${MEM_WARNING}% / Critical ${MEM_CRITICAL}%
  Disk:      Warning ${DISK_WARNING}% / Critical ${DISK_CRITICAL}%
  Response:  Warning ${RESPONSE_WARNING}ms / Critical ${RESPONSE_CRITICAL}ms

OPTIONS:
  -h, --help      Show this help
  --once          Single check
  --interval N    Check interval in seconds (default: 30)
  --summary       Show alert summary for today
EOF
}

# ---------------------------------------------------------------------------
# System checks
# ---------------------------------------------------------------------------
check_system_resources() {
    echo -e "${BOLD}System Resources:${NC}"

    # CPU
    local cpu_pct
    cpu_pct=$(awk -v c="$(nproc)" '{printf "%.0f", ($1/c)*100}' /proc/loadavg)
    if [[ $cpu_pct -ge $CPU_CRITICAL ]]; then
        send_alert "CRITICAL" "CPU" "Usage at ${cpu_pct}% (threshold: ${CPU_CRITICAL}%)"
    elif [[ $cpu_pct -ge $CPU_WARNING ]]; then
        send_alert "WARNING" "CPU" "Usage at ${cpu_pct}% (threshold: ${CPU_WARNING}%)"
    else
        send_alert "INFO" "CPU" "Usage at ${cpu_pct}% — OK"
    fi

    # Memory
    local mem_pct
    mem_pct=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')
    if [[ $mem_pct -ge $MEM_CRITICAL ]]; then
        send_alert "CRITICAL" "Memory" "Usage at ${mem_pct}% (threshold: ${MEM_CRITICAL}%)"
    elif [[ $mem_pct -ge $MEM_WARNING ]]; then
        send_alert "WARNING" "Memory" "Usage at ${mem_pct}% (threshold: ${MEM_WARNING}%)"
    else
        send_alert "INFO" "Memory" "Usage at ${mem_pct}% — OK"
    fi

    # Disk
    local disk_pct
    disk_pct=$(df / --output=pcent | tail -1 | tr -d ' %')
    if [[ $disk_pct -ge $DISK_CRITICAL ]]; then
        send_alert "CRITICAL" "Disk" "Usage at ${disk_pct}% (threshold: ${DISK_CRITICAL}%)"
    elif [[ $disk_pct -ge $DISK_WARNING ]]; then
        send_alert "WARNING" "Disk" "Usage at ${disk_pct}% (threshold: ${DISK_WARNING}%)"
    else
        send_alert "INFO" "Disk" "Usage at ${disk_pct}% — OK"
    fi
}

# ---------------------------------------------------------------------------
# Application checks
# ---------------------------------------------------------------------------
check_endpoint_alert() {
    local name="$1" url="$2"
    local start end ms code

    start=$(date +%s%N)
    code=$(curl -sk --max-time 5 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    end=$(date +%s%N)
    ms=$(( (end - start) / 1000000 ))

    if [[ "$code" == "000" ]]; then
        send_alert "CRITICAL" "$name" "UNREACHABLE (timeout after 5s)"
        return
    fi

    if [[ ! "$code" =~ ^(2[0-9]{2}|3[0-9]{2})$ ]]; then
        send_alert "CRITICAL" "$name" "HTTP $code returned"
        return
    fi

    if [[ $ms -ge $RESPONSE_CRITICAL ]]; then
        send_alert "CRITICAL" "$name" "Response time ${ms}ms (threshold: ${RESPONSE_CRITICAL}ms)"
    elif [[ $ms -ge $RESPONSE_WARNING ]]; then
        send_alert "WARNING" "$name" "Response time ${ms}ms (threshold: ${RESPONSE_WARNING}ms)"
    else
        send_alert "INFO" "$name" "HTTP $code in ${ms}ms — OK"
    fi
}

check_applications() {
    echo -e "${BOLD}Stack 1 (Next.js + Express + MongoDB):${NC}"
    check_endpoint_alert "stack1-express-1" "http://127.0.0.1:3000/api/health"
    check_endpoint_alert "stack1-express-2" "http://127.0.0.1:3003/api/health"
    check_endpoint_alert "stack1-express-3" "http://127.0.0.1:3004/api/health"
    check_endpoint_alert "stack1-nextjs-1"  "http://127.0.0.1:3001/"
    check_endpoint_alert "stack1-nextjs-2"  "http://127.0.0.1:3002/"

    echo -e "${BOLD}Stack 2 (Laravel + MySQL):${NC}"
    check_endpoint_alert "stack2-laravel-1" "http://127.0.0.1:8000/api/health"
    check_endpoint_alert "stack2-laravel-2" "http://127.0.0.1:8001/api/health"
    check_endpoint_alert "stack2-laravel-3" "http://127.0.0.1:8002/api/health"

    echo -e "${BOLD}Stack 3 (Next.js + FastAPI + MySQL):${NC}"
    check_endpoint_alert "stack3-fastapi-1" "http://127.0.0.1:8003/health"
    check_endpoint_alert "stack3-fastapi-2" "http://127.0.0.1:8004/health"
    check_endpoint_alert "stack3-fastapi-3" "http://127.0.0.1:8005/health"
    check_endpoint_alert "stack3-nextjs-1"  "http://127.0.0.1:3005/"
    check_endpoint_alert "stack3-nextjs-2"  "http://127.0.0.1:3006/"
}

# ---------------------------------------------------------------------------
# Database checks
# ---------------------------------------------------------------------------
check_databases() {
    echo -e "${BOLD}Databases:${NC}"

    # MongoDB
    if command -v mongosh &>/dev/null; then
        if mongosh "mongodb://admin:Admin%40123@localhost:27017/admin?authSource=admin" --quiet --eval "db.runCommand({ping:1})" &>/dev/null; then
            send_alert "INFO" "MongoDB-Primary" "Reachable — OK"
        else
            send_alert "CRITICAL" "MongoDB-Primary" "Primary node unreachable"
        fi
    fi

    # MySQL replication
    if command -v mysql &>/dev/null; then
        local slave_io slave_sql
        slave_io=$(mysql -h 127.0.0.1 -P 3307 -u root -pRoot@123 -e "SHOW SLAVE STATUS\G" 2>/dev/null | grep "Slave_IO_Running:" | awk '{print $2}' || echo "")
        slave_sql=$(mysql -h 127.0.0.1 -P 3307 -u root -pRoot@123 -e "SHOW SLAVE STATUS\G" 2>/dev/null | grep "Slave_SQL_Running:" | awk '{print $2}' || echo "")

        if [[ "$slave_io" == "Yes" && "$slave_sql" == "Yes" ]]; then
            send_alert "INFO" "MySQL-Replication" "IO=$slave_io SQL=$slave_sql — OK"
        elif [[ -n "$slave_io" ]]; then
            send_alert "CRITICAL" "MySQL-Replication" "IO=$slave_io SQL=$slave_sql — BROKEN"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
show_summary() {
    local today
    today=$(date +%Y-%m-%d)

    echo -e "${BOLD}${BLUE}═══ Alert Summary — $today ═══${NC}"

    if [[ ! -f "$ALERT_LOG" ]]; then
        echo "  No alerts logged."
        return
    fi

    local critical warning info
    critical=$(grep -c "CRITICAL" "$ALERT_LOG" 2>/dev/null || echo "0")
    warning=$(grep -c "WARNING" "$ALERT_LOG" 2>/dev/null || echo "0")
    info=$(grep -c "INFO" "$ALERT_LOG" 2>/dev/null || echo "0")

    echo -e "  ${RED}CRITICAL: $critical${NC}"
    echo -e "  ${YELLOW}WARNING:  $warning${NC}"
    echo -e "  ${GREEN}INFO:     $info${NC}"
    echo ""

    if [[ $critical -gt 0 ]]; then
        echo -e "${BOLD}Recent Critical Alerts:${NC}"
        grep "CRITICAL" "$ALERT_LOG" | tail -10
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
run_all_checks() {
    echo -e "${BOLD}${BLUE}═══ Alert Check — $(date '+%Y-%m-%d %H:%M:%S') ═══${NC}"
    echo ""
    check_system_resources
    echo ""
    check_applications
    echo ""
    check_databases
    echo ""
}

main() {
    if [[ "$ONCE" == true ]]; then
        run_all_checks
        return
    fi

    echo -e "${CYAN}Starting alert system (interval: ${INTERVAL}s)...${NC}"
    while true; do
        run_all_checks
        sleep "$INTERVAL"
    done
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    show_usage; exit 0 ;;
        --once)       ONCE=true ;;
        --interval)   INTERVAL="${2:-30}"; shift ;;
        --summary)    show_summary; exit 0 ;;
        *)            echo "Unknown: $1"; exit 1 ;;
    esac
    shift
done

main
