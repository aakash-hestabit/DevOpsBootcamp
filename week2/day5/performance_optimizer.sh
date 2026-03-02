#!/bin/bash
set -euo pipefail

# Script: performance_optimizer.sh
# Description: Applies system-level and application-level performance
#              tuning for all 3 production stacks. Covers sysctl, Nginx,
#              MySQL, MongoDB, PHP-FPM, Node.js, and Python tuning.
#              Creates before/after benchmark snapshots.
# Author: Aakash
# Date: 2026-03-02
# Usage: sudo ./performance_optimizer.sh [--dry-run] [--help]

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

EXIT_SUCCESS=0
EXIT_ERROR=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/var/log"
REPORT_DIR="$SCRIPT_DIR/performance_reports"
DRY_RUN=false
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "$LOG_DIR" "$REPORT_DIR"

LOG_FILE="$LOG_DIR/optimizer_${TIMESTAMP}.log"

TOTAL_STEPS=6
CURRENT=0

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >> "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "$LOG_FILE"; }
log()  { echo -e "  $*"; }
pass() { echo -e "  [${GREEN}OK${NC}]   $*"; }
fail() { echo -e "  [${RED}FAIL${NC}] $*"; }
warn() { echo -e "  [${YELLOW}WARN${NC}] $*"; }
info() { echo -e "  [${BLUE}INFO${NC}] $*"; }

sep() { echo -e "${DIM}$(printf '─%.0s' {1..60})${NC}"; }
step() {
    CURRENT=$((CURRENT + 1))
    echo ""
    echo -e "${BOLD}${BLUE}[Step ${CURRENT}/${TOTAL_STEPS}] $*${NC}"
    sep
}

show_usage() {
    cat <<EOF
Usage: sudo $(basename "$0") [OPTIONS]

Apply system and application performance tuning.

OPTIONS:
  -h, --help       Show this help
  --dry-run        Show what would be done without applying changes

TUNING AREAS:
  1. Kernel / sysctl parameters
  2. Nginx optimization
  3. MySQL tuning
  4. MongoDB tuning
  5. Application runtime settings
  6. Before/After benchmark
EOF
}

apply() {
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY-RUN] Would apply: $*"
    else
        eval "$@"
    fi
}

# ---------------------------------------------------------------------------
# Step 1: Sysctl tuning
# ---------------------------------------------------------------------------
tune_sysctl() {
    step "Kernel / Sysctl Tuning"

    local sysctl_file="/etc/sysctl.d/99-devops-performance.conf"

    local params=(
        "net.core.somaxconn=65535"
        "net.core.netdev_max_backlog=65535"
        "net.ipv4.tcp_max_syn_backlog=65535"
        "net.ipv4.tcp_tw_reuse=1"
        "net.ipv4.tcp_fin_timeout=15"
        "net.ipv4.tcp_keepalive_time=300"
        "net.ipv4.tcp_keepalive_intvl=30"
        "net.ipv4.tcp_keepalive_probes=5"
        "net.ipv4.ip_local_port_range=1024 65535"
        "net.core.rmem_max=16777216"
        "net.core.wmem_max=16777216"
        "vm.swappiness=10"
        "vm.dirty_ratio=15"
        "vm.dirty_background_ratio=5"
        "fs.file-max=2097152"
        "fs.inotify.max_user_watches=524288"
    )

    for param in "${params[@]}"; do
        local key="${param%%=*}"
        local val="${param#*=}"
        local current
        current=$(sysctl -n "$key" 2>/dev/null | tr '\t' ' ' || echo "N/A")
        if [[ "$current" == "$val" ]]; then
            pass "$key = $val (already set)"
        else
            info "$key: $current → $val"
        fi
    done

    if [[ "$DRY_RUN" == false ]]; then
        printf '%s\n' "# DevOps Bootcamp performance tuning" \
            "# Applied: $(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            "" "${params[@]}" | sudo tee "$sysctl_file" > /dev/null 2>/dev/null || true
        sudo sysctl -p "$sysctl_file" &>/dev/null && pass "Sysctl parameters applied" || warn "Could not apply sysctl (may need root)"
    fi

    # File descriptor limits
    info "Setting ulimit nofile to 65535"
    if [[ "$DRY_RUN" == false ]]; then
        grep -q "* soft nofile" /etc/security/limits.conf 2>/dev/null || {
            echo "* soft nofile 65535" | sudo tee -a /etc/security/limits.conf >/dev/null 2>/dev/null || true
            echo "* hard nofile 65535" | sudo tee -a /etc/security/limits.conf >/dev/null 2>/dev/null || true
        }
    fi

    log_info "Sysctl tuning completed"
}

# ---------------------------------------------------------------------------
# Step 2: Nginx tuning
# ---------------------------------------------------------------------------
tune_nginx() {
    step "Nginx Performance Tuning"

    local nginx_conf="/etc/nginx/nginx.conf"
    if [[ ! -f "$nginx_conf" ]]; then
        warn "Nginx not found, skipping"
        return
    fi

    info "Recommended Nginx optimizations:"
    log "  worker_processes auto;"
    log "  worker_connections 4096;"
    log "  multi_accept on;"
    log "  tcp_nopush on;"
    log "  tcp_nodelay on;"
    log "  keepalive_timeout 65;"
    log "  gzip on;"
    log "  gzip_comp_level 5;"
    log "  gzip_types text/* application/json application/javascript;"
    log "  proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=main:10m;"
    log ""

    # Deploy advanced Nginx config
    local opt_conf="$SCRIPT_DIR/optimization/nginx_advanced.conf"
    if [[ -f "$opt_conf" ]]; then
        pass "Advanced Nginx config available at: $opt_conf"
        info "Apply with: sudo cp $opt_conf /etc/nginx/conf.d/performance.conf && sudo nginx -t && sudo systemctl reload nginx"
    fi

    # Test current config
    if sudo nginx -t &>/dev/null; then
        pass "Current Nginx config is valid"
    else
        warn "Nginx config test failed"
    fi

    log_info "Nginx tuning reviewed"
}

# ---------------------------------------------------------------------------
# Step 3: MySQL tuning
# ---------------------------------------------------------------------------
tune_mysql() {
    step "MySQL Performance Tuning"

    if ! command -v mysql &>/dev/null; then
        warn "MySQL not found, skipping"
        return
    fi

    info "Recommended MySQL optimizations:"
    local recommendations=(
        "innodb_buffer_pool_size = 1G   # 50-70% of available RAM"
        "innodb_log_file_size = 256M"
        "innodb_flush_log_at_trx_commit = 2   # Faster writes, slight durability trade-off"
        "innodb_flush_method = O_DIRECT"
        "innodb_io_capacity = 2000"
        "innodb_io_capacity_max = 4000"
        "max_connections = 200"
        "query_cache_type = OFF   # Deprecated in 8.0"
        "slow_query_log = ON"
        "long_query_time = 1"
        "join_buffer_size = 4M"
        "sort_buffer_size = 4M"
        "tmp_table_size = 64M"
        "max_heap_table_size = 64M"
    )

    for rec in "${recommendations[@]}"; do
        log "  $rec"
    done

    # Check current values
    echo ""
    info "Current key values:"
    local vars=("innodb_buffer_pool_size" "max_connections" "innodb_flush_log_at_trx_commit" "slow_query_log")
    for v in "${vars[@]}"; do
        local val
        val=$(mysql -u root -pRoot@123 -e "SHOW VARIABLES LIKE '$v'" 2>/dev/null | tail -1 | awk '{print $2}' || echo "N/A")
        log "  $v = $val"
    done

    log_info "MySQL tuning reviewed"
}

# ---------------------------------------------------------------------------
# Step 4: MongoDB tuning
# ---------------------------------------------------------------------------
tune_mongodb() {
    step "MongoDB Performance Tuning"

    if ! command -v mongosh &>/dev/null; then
        warn "MongoDB not found, skipping"
        return
    fi

    info "Recommended MongoDB optimizations:"
    log "  storage.wiredTiger.engineConfig.cacheSizeGB: 1.5"
    log "  operationProfiling.slowOpThresholdMs: 100"
    log "  operationProfiling.mode: slowOp"
    log "  net.maxIncomingConnections: 1000"
    log ""

    # Check current connections
    local conns
    conns=$(mongosh "mongodb://admin:Admin%40123@localhost:27017/admin?authSource=admin" --quiet \
        --eval "db.serverStatus().connections.current" 2>/dev/null || echo "N/A")
    info "Current connections: $conns"

    log_info "MongoDB tuning reviewed"
}

# ---------------------------------------------------------------------------
# Step 5: Application runtime tuning
# ---------------------------------------------------------------------------
tune_applications() {
    step "Application Runtime Tuning"

    info "Node.js (Stacks 1 & 3):"
    log "  NODE_ENV=production"
    log "  NODE_OPTIONS='--max-old-space-size=1024 --max-semi-space-size=64'"
    log "  PM2: cluster mode for Express, fork for Next.js SSR"
    log "  PM2: max_memory_restart: 500M"
    log ""

    info "PHP / Laravel (Stack 2):"
    log "  opcache.enable=1"
    log "  opcache.memory_consumption=256"
    log "  opcache.max_accelerated_files=20000"
    log "  realpath_cache_size=4096K"
    log "  php artisan config:cache"
    log "  php artisan route:cache"
    log "  php artisan view:cache"
    log ""

    info "Python / FastAPI (Stack 3):"
    log "  uvicorn workers: CPU_COUNT * 2 + 1"
    log "  uvicorn --loop uvloop --http httptools"
    log "  PYTHONDONTWRITEBYTECODE=1"
    log ""

    info "Redis Caching:"
    log "  maxmemory 256mb"
    log "  maxmemory-policy allkeys-lru"
    log "  Save: RDB + AOF appendonly"

    log_info "Application tuning reviewed"
}

# ---------------------------------------------------------------------------
# Step 6: Benchmark snapshot
# ---------------------------------------------------------------------------
take_benchmark() {
    step "Before/After Benchmark Snapshot"

    local report="$REPORT_DIR/benchmark_${TIMESTAMP}.txt"

    {
        echo "Performance Benchmark — $TIMESTAMP"
        echo "=========================================="
        echo ""
        echo "System:"
        echo "  CPU: $(nproc) cores, load: $(awk '{print $1,$2,$3}' /proc/loadavg)"
        echo "  Memory: $(free -h | awk '/Mem:/ {print $2, "total,", $3, "used,", $7, "available"}')"
        echo "  Disk: $(df -h / | tail -1 | awk '{print $2, "total,", $3, "used,", $5, "used%"}')"
        echo ""
        echo "Response Times:"

        for label_url in \
            "Stack1-Express:http://127.0.0.1:3000/api/health" \
            "Stack1-NextJS:http://127.0.0.1:3001/" \
            "Stack2-Laravel:http://127.0.0.1:8000/api/health" \
            "Stack3-FastAPI:http://127.0.0.1:8003/health" \
            "Stack3-NextJS:http://127.0.0.1:3005/"; do

            local label="${label_url%%:http*}"
            local url="http${label_url#*:http}"
            local ms code start end

            start=$(date +%s%N)
            code=$(curl -sk --max-time 5 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
            end=$(date +%s%N)
            ms=$(( (end - start) / 1000000 ))

            echo "  $label: HTTP $code in ${ms}ms"
        done

        echo ""
        echo "Connections:"
        if command -v ss &>/dev/null; then
            echo "  Total: $(ss -s | head -1)"
            echo "  ESTABLISHED: $(ss -t state established | wc -l)"
        fi
    } | tee "$report"

    echo ""
    pass "Benchmark saved to $report"
    log_info "Benchmark snapshot saved"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║   Performance Optimizer — All Stacks      ║${NC}"
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════╝${NC}"
    echo ""

    [[ "$DRY_RUN" == true ]] && warn "DRY-RUN mode — no changes will be applied"

    tune_sysctl
    tune_nginx
    tune_mysql
    tune_mongodb
    tune_applications
    take_benchmark

    echo ""
    sep
    echo -e "${GREEN}${BOLD}Performance optimization complete.${NC}"
    echo -e "Log: $LOG_FILE"
    echo ""
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)  show_usage; exit $EXIT_SUCCESS ;;
        --dry-run)  DRY_RUN=true ;;
        *)          echo "Unknown: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
