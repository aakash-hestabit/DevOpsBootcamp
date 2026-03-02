#!/bin/bash
set -euo pipefail

# Script: uptime_monitor.sh
# Description: Tracks uptime for all 3 stacks. Records availability
#              metrics, detects outages, and logs uptime statistics.
# Author: Aakash
# Date: 2026-03-02
# Usage: ./uptime_monitor.sh [--once] [--interval N] [--help]

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
DATA_DIR="$BASE_DIR/var/log/uptime"
INTERVAL=60
ONCE=false

mkdir -p "$DATA_DIR"

show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Uptime tracking for all 3 production stacks.

OPTIONS:
  -h, --help       Show this help
  --once           Single check and exit
  --interval N     Check interval in seconds (default: 60)
  --report         Print daily uptime summary
EOF
}

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >> "$DATA_DIR/uptime_monitor.log"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "$DATA_DIR/uptime_monitor.log"; }

pass() { echo -e "  [${GREEN}OK${NC}]   $*"; }
fail() { echo -e "  [${RED}FAIL${NC}] $*"; }
warn() { echo -e "  [${YELLOW}WARN${NC}] $*"; }

# ---------------------------------------------------------------------------
# Endpoint definition
# ---------------------------------------------------------------------------
declare -A ENDPOINTS=(
    ["stack1_nextjs_1"]="http://127.0.0.1:3001/"
    ["stack1_nextjs_2"]="http://127.0.0.1:3002/"
    ["stack1_express_1"]="http://127.0.0.1:3000/api/health"
    ["stack1_express_2"]="http://127.0.0.1:3003/api/health"
    ["stack1_express_3"]="http://127.0.0.1:3004/api/health"
    ["stack2_laravel_1"]="http://127.0.0.1:8000/api/health"
    ["stack2_laravel_2"]="http://127.0.0.1:8001/api/health"
    ["stack2_laravel_3"]="http://127.0.0.1:8002/api/health"
    ["stack3_nextjs_1"]="http://127.0.0.1:3005/"
    ["stack3_nextjs_2"]="http://127.0.0.1:3006/"
    ["stack3_fastapi_1"]="http://127.0.0.1:8003/health"
    ["stack3_fastapi_2"]="http://127.0.0.1:8004/health"
    ["stack3_fastapi_3"]="http://127.0.0.1:8005/health"
)

# ---------------------------------------------------------------------------
# Check single endpoint
# ---------------------------------------------------------------------------
check_endpoint() {
    local name="$1" url="$2"
    local start end ms code

    start=$(date +%s%N)
    code=$(curl -sk --max-time 5 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    end=$(date +%s%N)
    ms=$(( (end - start) / 1000000 ))

    local status="UP"
    [[ "$code" =~ ^(2[0-9]{2}|3[0-9]{2})$ ]] || status="DOWN"

    # Record result (timestamp, name, status, http_code, response_ms)
    echo "$(date -u +%s),$name,$status,$code,$ms" >> "$DATA_DIR/uptime_$(date +%Y%m%d).csv"

    if [[ "$status" == "UP" ]]; then
        pass "$name → ${code} (${ms}ms)"
    else
        fail "$name → ${code} (${ms}ms)"
        log_error "$name is DOWN (HTTP $code, ${ms}ms)"
    fi
}

# ---------------------------------------------------------------------------
# Run all checks
# ---------------------------------------------------------------------------
run_checks() {
    echo -e "${BOLD}${BLUE}═══ Uptime Check — $(date '+%Y-%m-%d %H:%M:%S') ═══${NC}"

    for name in $(echo "${!ENDPOINTS[@]}" | tr ' ' '\n' | sort); do
        check_endpoint "$name" "${ENDPOINTS[$name]}"
    done

    log_info "Uptime check cycle completed"
    echo ""
}

# ---------------------------------------------------------------------------
# Daily report
# ---------------------------------------------------------------------------
generate_report() {
    local today
    today=$(date +%Y%m%d)
    local csv="$DATA_DIR/uptime_${today}.csv"

    if [[ ! -f "$csv" ]]; then
        echo "No data for today."
        return
    fi

    echo -e "${BOLD}${BLUE}═══ Uptime Report — $(date +%Y-%m-%d) ═══${NC}"
    echo ""
    printf "  %-25s %8s %8s %8s %7s\n" "Endpoint" "Total" "Up" "Down" "Uptime%"
    echo "  $(printf '─%.0s' {1..60})"

    for name in $(echo "${!ENDPOINTS[@]}" | tr ' ' '\n' | sort); do
        local total up down pct
        total=$(grep -c ",$name," "$csv" 2>/dev/null || echo "0")
        up=$(grep ",$name,UP," "$csv" 2>/dev/null | wc -l || echo "0")
        down=$((total - up))

        if [[ $total -gt 0 ]]; then
            pct=$(awk "BEGIN {printf \"%.2f\", ($up/$total)*100}")
        else
            pct="N/A"
        fi

        local color="$GREEN"
        if [[ "$pct" != "N/A" ]]; then
            (( $(echo "$pct < 99.5" | bc -l 2>/dev/null || echo 0) )) && color="$YELLOW"
            (( $(echo "$pct < 95.0" | bc -l 2>/dev/null || echo 0) )) && color="$RED"
        fi

        printf "  %-25s %8s %8s %8s ${color}%6s%%${NC}\n" "$name" "$total" "$up" "$down" "$pct"
    done
    echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    if [[ "$ONCE" == true ]]; then
        run_checks
        return
    fi

    echo -e "${CYAN}Starting uptime monitor (interval: ${INTERVAL}s)...${NC}"
    while true; do
        run_checks
        sleep "$INTERVAL"
    done
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    show_usage; exit 0 ;;
        --once)       ONCE=true ;;
        --interval)   INTERVAL="${2:-60}"; shift ;;
        --report)     generate_report; exit 0 ;;
        *)            echo "Unknown: $1"; exit 1 ;;
    esac
    shift
done

main
