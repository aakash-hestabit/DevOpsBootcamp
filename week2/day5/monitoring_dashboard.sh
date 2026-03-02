#!/bin/bash
set -euo pipefail

# Script: monitoring_dashboard.sh
# Description: Real-time terminal monitoring dashboard for all 3 stacks.
#              Displays system resources, stack health, request rates,
#              response times, error rates, DB connections, queue status.
#              Auto-refreshes every 5 seconds. Color-coded status.
# Author: Aakash
# Date: 2026-03-02
# Usage: ./monitoring_dashboard.sh [--interval N] [--help]

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

INTERVAL=5
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Real-time monitoring dashboard for all 3 production stacks.

OPTIONS:
  -h, --help       Show this help
  --interval N     Refresh interval in seconds (default: 5)

CONTROLS:
  Ctrl+C           Quit
EOF
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
bar() {
    # Usage: bar <percentage> <width>
    local pct="$1" width="${2:-10}"
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local color="$GREEN"
    [[ $pct -ge 70 ]] && color="$YELLOW"
    [[ $pct -ge 90 ]] && color="$RED"

    printf "${color}"
    printf '█%.0s' $(seq 1 $filled 2>/dev/null) || true
    printf '░%.0s' $(seq 1 $empty 2>/dev/null) || true
    printf "${NC} %3d%%" "$pct"
}

check_port() {
    # Returns response time in ms or "DOWN"
    local port="$1" path="${2:-/}" pattern="${3:-}"
    local start end ms out

    start=$(date +%s%N)
    out=$(curl -sk --max-time 3 "http://127.0.0.1:$port$path" 2>/dev/null || echo "")
    end=$(date +%s%N)
    ms=$(( (end - start) / 1000000 ))

    if [[ -z "$out" ]]; then
        echo "DOWN"
        return
    fi
    if [[ -n "$pattern" && "$out" != *"$pattern"* ]]; then
        echo "DOWN"
        return
    fi
    echo "${ms}ms"
}

status_icon() {
    local result="$1"
    if [[ "$result" == "DOWN" ]]; then
        printf "${RED}✗ DOWN${NC}"
    else
        printf "${GREEN}✓ UP${NC} ${DIM}($result)${NC}"
    fi
}

# ---------------------------------------------------------------------------
# Draw dashboard
# ---------------------------------------------------------------------------
draw_dashboard() {
    clear

    local NOW
    NOW=$(date '+%Y-%m-%d %H:%M:%S')

    # System resources
    local cpu_load mem_pct disk_pct
    cpu_load=$(awk '{print $1}' /proc/loadavg)
    mem_pct=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')
    disk_pct=$(df / --output=pcent | tail -1 | tr -d ' %')

    echo -e "${BOLD}${BLUE}┌────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${BLUE}│         DevOps Bootcamp Monitoring Dashboard               │${NC}"
    echo -e "${BOLD}${BLUE}│                  $NOW                       │${NC}"
    echo -e "${BOLD}${BLUE}└────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    echo -e "${BOLD}SYSTEM RESOURCES:${NC}"
    printf "  CPU:  "; bar "$( echo "$cpu_load" | awk -v c="$(nproc)" '{printf "%.0f", ($1/c)*100}' )" 10
    printf " ($cpu_load)"
    printf "  | RAM: "; bar "$mem_pct" 10
    printf "  | Disk: "; bar "$disk_pct" 10
    echo ""
    echo ""

    # --- Stack 1 ---
    echo -e "${BOLD}STACK 1 (Next.js + Node.js + MongoDB):${NC}"

    local s1_be_up=0 s1_be_total=3 s1_fe_up=0 s1_fe_total=2 s1_avg_ms=0
    local s1_times=()

    for port in 3000 3003 3004; do
        local r; r=$(check_port "$port" "/api/health" '"status"')
        if [[ "$r" != "DOWN" ]]; then
            s1_be_up=$((s1_be_up + 1))
            s1_times+=("${r%ms}")
        fi
    done
    for port in 3001 3002; do
        local r; r=$(check_port "$port" "/" "html")
        [[ "$r" != "DOWN" ]] && s1_fe_up=$((s1_fe_up + 1))
    done

    if [[ ${#s1_times[@]} -gt 0 ]]; then
        local sum=0
        for t in "${s1_times[@]}"; do sum=$((sum + t)); done
        s1_avg_ms=$((sum / ${#s1_times[@]}))
    fi

    local s1_status="${GREEN}✓ HEALTHY${NC}"
    [[ $s1_be_up -lt $s1_be_total || $s1_fe_up -lt $s1_fe_total ]] && s1_status="${YELLOW}⚠ WARNING${NC}"
    [[ $s1_be_up -eq 0 && $s1_fe_up -eq 0 ]] && s1_status="${RED}✗ DOWN${NC}"

    echo -e "  Status: $s1_status | Avg Response: ${s1_avg_ms}ms"
    echo -e "  Backend: ${s1_be_up}/${s1_be_total} instances UP | Frontend: ${s1_fe_up}/${s1_fe_total} instances UP"

    # MongoDB status
    if command -v mongosh &>/dev/null; then
        local mongo_ok=0
        for p in 27017 27018 27019; do
            mongosh "mongodb://localhost:$p/admin" --quiet --eval "db.runCommand({ping:1})" &>/dev/null && mongo_ok=$((mongo_ok + 1))
        done
        echo -e "  MongoDB: ${mongo_ok}/3 nodes UP"
    fi
    echo ""

    # --- Stack 2 ---
    echo -e "${BOLD}STACK 2 (Laravel + MySQL):${NC}"

    local s2_up=0 s2_total=3 s2_avg_ms=0
    local s2_times=()

    for port in 8000 8001 8002; do
        local r; r=$(check_port "$port" "/api/health" '"status"')
        if [[ "$r" != "DOWN" ]]; then
            s2_up=$((s2_up + 1))
            s2_times+=("${r%ms}")
        fi
    done

    if [[ ${#s2_times[@]} -gt 0 ]]; then
        local sum=0
        for t in "${s2_times[@]}"; do sum=$((sum + t)); done
        s2_avg_ms=$((sum / ${#s2_times[@]}))
    fi

    local s2_status="${GREEN}✓ HEALTHY${NC}"
    [[ $s2_up -lt $s2_total ]] && s2_status="${YELLOW}⚠ WARNING${NC}"
    [[ $s2_up -eq 0 ]] && s2_status="${RED}✗ DOWN${NC}"

    echo -e "  Status: $s2_status | Avg Response: ${s2_avg_ms}ms"
    echo -e "  Laravel: ${s2_up}/${s2_total} instances UP"

    # Queue workers
    local wk_up=0
    for wid in 1 2; do
        systemctl is-active --quiet "laravel-worker@$wid" 2>/dev/null && wk_up=$((wk_up + 1))
    done
    echo -e "  Queue Workers: ${wk_up}/2 active"

    # MySQL replication
    if command -v mysql &>/dev/null; then
        local repl_lag="N/A"
        local slave_status
        slave_status=$(mysql -h 127.0.0.1 -P 3307 -u root -p"${MYSQL_ROOT_PASSWORD:-Root@123}" \
            -e "SHOW SLAVE STATUS\G" 2>/dev/null || echo "")
        if [[ -n "$slave_status" ]]; then
            repl_lag=$(echo "$slave_status" | grep "Seconds_Behind_Master:" | awk '{print $2}')
            echo -e "  MySQL: REPLICATING | Lag: ${repl_lag}s"
        else
            echo -e "  MySQL: Master UP (slave status N/A)"
        fi

        local conns
        conns=$(mysql -u root -pRoot@123 -e "SHOW STATUS LIKE 'Threads_connected'" 2>/dev/null | tail -1 | awk '{print $2}' || echo "N/A")
        echo -e "  MySQL Connections: $conns"
    fi
    echo ""

    # --- Stack 3 ---
    echo -e "${BOLD}STACK 3 (Next.js + FastAPI + MySQL):${NC}"

    local s3_be_up=0 s3_be_total=3 s3_fe_up=0 s3_fe_total=2 s3_avg_ms=0
    local s3_times=()

    for port in 8003 8004 8005; do
        local r; r=$(check_port "$port" "/health" '"status"')
        if [[ "$r" != "DOWN" ]]; then
            s3_be_up=$((s3_be_up + 1))
            s3_times+=("${r%ms}")
        fi
    done
    for port in 3005 3006; do
        local r; r=$(check_port "$port" "/" "html")
        [[ "$r" != "DOWN" ]] && s3_fe_up=$((s3_fe_up + 1))
    done

    if [[ ${#s3_times[@]} -gt 0 ]]; then
        local sum=0
        for t in "${s3_times[@]}"; do sum=$((sum + t)); done
        s3_avg_ms=$((sum / ${#s3_times[@]}))
    fi

    local s3_status="${GREEN}✓ HEALTHY${NC}"
    [[ $s3_be_up -lt $s3_be_total || $s3_fe_up -lt $s3_fe_total ]] && s3_status="${YELLOW}⚠ WARNING${NC}"
    [[ $s3_be_up -eq 0 && $s3_fe_up -eq 0 ]] && s3_status="${RED}✗ DOWN${NC}"

    echo -e "  Status: $s3_status | Avg Response: ${s3_avg_ms}ms"
    echo -e "  Backend: ${s3_be_up}/${s3_be_total} instances UP | Frontend: ${s3_fe_up}/${s3_fe_total} instances UP"

    if command -v mysql &>/dev/null; then
        local s3_conns
        s3_conns=$(mysql -u fastapiuser -pFast@123 -e "SHOW STATUS LIKE 'Threads_connected'" fastapidb 2>/dev/null | tail -1 | awk '{print $2}' || echo "N/A")
        echo -e "  MySQL Connections: $s3_conns"
    fi
    echo ""

    # --- Nginx ---
    echo -e "${BOLD}NGINX LOAD BALANCER:${NC}"
    if systemctl is-active --quiet nginx 2>/dev/null || pgrep -x nginx &>/dev/null; then
        echo -e "  Status: ${GREEN}✓ RUNNING${NC}"
    else
        echo -e "  Status: ${RED}✗ DOWN${NC}"
    fi
    echo ""

    # --- Alerts ---
    echo -e "${BOLD}ALERTS:${NC}"
    local alert_file="$SCRIPT_DIR/var/log/alerts.log"
    if [[ -f "$alert_file" ]]; then
        tail -3 "$alert_file" 2>/dev/null | while read -r line; do
            echo -e "  ${YELLOW}$line${NC}"
        done
    else
        echo -e "  ${DIM}No recent alerts${NC}"
    fi
    echo ""

    echo -e "${DIM}[Refresh: ${INTERVAL}s | Ctrl+C to quit]${NC}"
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
main() {
    # Hide cursor
    tput civis 2>/dev/null || true
    trap 'tput cnorm 2>/dev/null; exit 0' INT TERM EXIT

    if [[ "${ONCE:-false}" == "true" ]]; then
        draw_dashboard
        tput cnorm 2>/dev/null || true
        return
    fi

    while true; do
        draw_dashboard
        sleep "$INTERVAL"
    done
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    show_usage; exit 0 ;;
        --interval)   INTERVAL="${2:-5}"; shift ;;
        --once)       ONCE=true ;;
        *)            echo "Unknown: $1"; exit 1 ;;
    esac
    shift
done

main "$@"
