#!/bin/bash
set -euo pipefail

# Script: metrics_collector.sh
# Description: Collects system and application metrics at regular intervals.
#              Outputs structured CSV data for analysis and trending.
# Author: Aakash
# Date: 2026-03-02
# Usage: ./metrics_collector.sh [--once] [--interval 60] [--help]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
METRICS_DIR="$BASE_DIR/var/log/metrics"
INTERVAL=60
ONCE=false

mkdir -p "$METRICS_DIR"

show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Collect system and application metrics for trending and analysis.

OPTIONS:
  -h, --help       Show this help
  --once           Single collection
  --interval N     Collection interval in seconds (default: 60)
  --export [day]   Export metrics as JSON for the given day (YYYYMMDD)
EOF
}

# ---------------------------------------------------------------------------
# System metrics
# ---------------------------------------------------------------------------
collect_system_metrics() {
    local ts cpu_load mem_total mem_used mem_pct disk_pct swap_used net_rx net_tx procs
    ts=$(date -u +%s)

    cpu_load=$(awk '{print $1}' /proc/loadavg)
    read -r mem_total mem_used <<< "$(free -m | awk '/Mem:/ {print $2, $3}')"
    mem_pct=$(free | awk '/Mem:/ {printf "%.1f", $3/$2*100}')
    disk_pct=$(df / --output=pcent | tail -1 | tr -d ' %')
    swap_used=$(free -m | awk '/Swap:/ {print $3}')
    procs=$(ps aux --no-headers | wc -l)

    # Network (total bytes since boot on primary interface)
    local iface
    iface=$(ip route show default 2>/dev/null | awk '{print $5; exit}' || echo "eth0")
    net_rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo "0")
    net_tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo "0")

    echo "$ts,system,$cpu_load,$mem_total,$mem_used,$mem_pct,$disk_pct,$swap_used,$net_rx,$net_tx,$procs" \
        >> "$METRICS_DIR/system_$(date +%Y%m%d).csv"
}

# ---------------------------------------------------------------------------
# Application metrics
# ---------------------------------------------------------------------------
collect_app_metric() {
    local name="$1" url="$2"
    local ts code ms

    ts=$(date -u +%s)
    local start end
    start=$(date +%s%N)
    code=$(curl -sk --max-time 5 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    end=$(date +%s%N)
    ms=$(( (end - start) / 1000000 ))

    local status="UP"
    [[ "$code" =~ ^(2[0-9]{2}|3[0-9]{2})$ ]] || status="DOWN"

    echo "$ts,$name,$status,$code,$ms" >> "$METRICS_DIR/app_$(date +%Y%m%d).csv"
}

collect_app_metrics() {
    # Stack 1
    collect_app_metric "stack1-express-1" "http://127.0.0.1:3000/api/health"
    collect_app_metric "stack1-express-2" "http://127.0.0.1:3003/api/health"
    collect_app_metric "stack1-express-3" "http://127.0.0.1:3004/api/health"
    collect_app_metric "stack1-nextjs-1"  "http://127.0.0.1:3001/"
    collect_app_metric "stack1-nextjs-2"  "http://127.0.0.1:3002/"

    # Stack 2
    collect_app_metric "stack2-laravel-1" "http://127.0.0.1:8000/api/health"
    collect_app_metric "stack2-laravel-2" "http://127.0.0.1:8001/api/health"
    collect_app_metric "stack2-laravel-3" "http://127.0.0.1:8002/api/health"

    # Stack 3
    collect_app_metric "stack3-fastapi-1" "http://127.0.0.1:8003/health"
    collect_app_metric "stack3-fastapi-2" "http://127.0.0.1:8004/health"
    collect_app_metric "stack3-fastapi-3" "http://127.0.0.1:8005/health"
    collect_app_metric "stack3-nextjs-1"  "http://127.0.0.1:3005/"
    collect_app_metric "stack3-nextjs-2"  "http://127.0.0.1:3006/"
}

# ---------------------------------------------------------------------------
# Database metrics
# ---------------------------------------------------------------------------
collect_db_metrics() {
    local ts
    ts=$(date -u +%s)

    # MongoDB connections
    if command -v mongosh &>/dev/null; then
        local mongo_conns
        mongo_conns=$(mongosh "mongodb://admin:Admin%40123@localhost:27017/admin?authSource=admin" --quiet \
            --eval "db.serverStatus().connections.current" 2>/dev/null || echo "0")
        echo "$ts,mongodb,connections,$mongo_conns" >> "$METRICS_DIR/db_$(date +%Y%m%d).csv"
    fi

    # MySQL connections and queries
    if command -v mysql &>/dev/null; then
        local threads queries
        threads=$(mysql -u root -pRoot@123 -e "SHOW STATUS LIKE 'Threads_connected'" 2>/dev/null | tail -1 | awk '{print $2}' || echo "0")
        queries=$(mysql -u root -pRoot@123 -e "SHOW STATUS LIKE 'Queries'" 2>/dev/null | tail -1 | awk '{print $2}' || echo "0")
        echo "$ts,mysql,threads_connected,$threads" >> "$METRICS_DIR/db_$(date +%Y%m%d).csv"
        echo "$ts,mysql,queries_total,$queries" >> "$METRICS_DIR/db_$(date +%Y%m%d).csv"
    fi
}

# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------
export_metrics() {
    local day="${1:-$(date +%Y%m%d)}"
    echo "{"
    echo "  \"date\": \"$day\","
    echo "  \"system\": ["
    if [[ -f "$METRICS_DIR/system_${day}.csv" ]]; then
        awk -F, '{printf "    {\"ts\":%s,\"cpu_load\":\"%s\",\"mem_total\":%s,\"mem_used\":%s,\"mem_pct\":\"%s\",\"disk_pct\":%s,\"procs\":%s},\n", $1,$3,$4,$5,$6,$7,$11}' \
            "$METRICS_DIR/system_${day}.csv"
    fi
    echo "  ],"
    echo "  \"apps\": ["
    if [[ -f "$METRICS_DIR/app_${day}.csv" ]]; then
        awk -F, '{printf "    {\"ts\":%s,\"name\":\"%s\",\"status\":\"%s\",\"http\":%s,\"ms\":%s},\n", $1,$2,$3,$4,$5}' \
            "$METRICS_DIR/app_${day}.csv"
    fi
    echo "  ]"
    echo "}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
run_collection() {
    collect_system_metrics
    collect_app_metrics
    collect_db_metrics
    echo "[$(date '+%H:%M:%S')] Metrics collected → $METRICS_DIR/"
}

main() {
    if [[ "$ONCE" == true ]]; then
        run_collection
        return
    fi

    echo "Starting metrics collector (interval: ${INTERVAL}s)..."
    while true; do
        run_collection
        sleep "$INTERVAL"
    done
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    show_usage; exit 0 ;;
        --once)       ONCE=true ;;
        --interval)   INTERVAL="${2:-60}"; shift ;;
        --export)     export_metrics "${2:-}"; exit 0 ;;
        *)            echo "Unknown: $1"; exit 1 ;;
    esac
    shift
done

main
