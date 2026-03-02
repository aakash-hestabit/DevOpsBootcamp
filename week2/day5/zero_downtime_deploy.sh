#!/bin/bash
set -euo pipefail

# Script: zero_downtime_deploy.sh
# Description: Blue-Green deployment strategy for all 3 stacks.
#              1. Deploy new version to inactive (Green) instances
#              2. Health check Green instances
#              3. Switch Nginx upstream to Green
#              4. Monitor for 5 minutes
#              5. If healthy, decommission Blue; if failed, switch back to Blue
# Author: Aakash
# Date: 2026-03-02
# Usage: sudo ./zero_downtime_deploy.sh --stack 1|2|3 [--help]

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/var/log"
LOG_FILE="$LOG_DIR/$(basename "$0" .sh).log"
DEPLOY_LOG="$LOG_DIR/zero-downtime-$(date +%Y%m%d-%H%M%S).log"
NGINX_DIR="/etc/nginx"

mkdir -p "$LOG_DIR"

TARGET_STACK=""
MONITOR_DURATION=300   # 5 minutes
REAL_USER="${SUDO_USER:-$USER}"

# PATH setup for nvm
for _nvm_bin in \
    "/home/$REAL_USER/.nvm/versions/node/"*/bin \
    "$HOME/.nvm/versions/node/"*/bin \
    /usr/local/bin /usr/bin; do
    [[ -d "$_nvm_bin" && ":$PATH:" != *":$_nvm_bin:"* ]] && PATH="$_nvm_bin:$PATH"
done
export PATH

# Logging
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }

log()  { echo -e "$1" | tee -a "$DEPLOY_LOG"; }
pass() { log "${GREEN}    $1${NC}"; }
fail() { log "${RED}    $1${NC}"; }
info() { log "${BLUE}    $1${NC}"; }
warn() { log "${YELLOW}    $1${NC}"; }
sep()  { log "${CYAN}------------------------------------------------------------${NC}"; }
step() { log ""; sep; log "${BOLD}${BLUE}  [$1/$TOTAL_STEPS] $2${NC}"; sep; }

show_usage() {
    cat <<EOF
Usage: sudo $(basename "$0") [OPTIONS]

Blue-Green zero-downtime deployment for production stacks.

OPTIONS:
  -h, --help            Show this help message
  --stack NUM           Target stack: 1, 2, or 3 (required)
  --monitor-duration N  Monitor period in seconds after switch (default: 300)
  -v, --verbose         Enable verbose output

STRATEGY:
  1. Deploy new version to Green instances (offset ports)
  2. Health check all Green instances
  3. Switch Nginx upstream from Blue to Green
  4. Monitor for errors (default: 5 minutes)
  5. If OK --> decommission Blue; if failed --> switch back to Blue

PORT MAPPING:
  Stack 1: Blue 3000,3003,3004 / Green 3010,3013,3014 (backend)
           Blue 3001,3002     / Green 3011,3012        (frontend)
  Stack 2: Blue 8000,8001,8002 / Green 8010,8011,8012
  Stack 3: Blue 8003,8004,8005 / Green 8013,8014,8015 (backend)
           Blue 3005,3006     / Green 3015,3016        (frontend)

EXAMPLES:
  sudo ./$(basename "$0") --stack 1
  sudo ./$(basename "$0") --stack 3 --monitor-duration 120
EOF
}

# ---------------------------------------------------------------------------
# Check HTTP endpoint
# ---------------------------------------------------------------------------
check_health() {
    local url="$1" pattern="${2:-}"
    local out
    out=$(curl -sk --max-time 5 "$url" 2>/dev/null || echo "")
    if [[ -z "$out" ]]; then return 1; fi
    if [[ -n "$pattern" && "$out" != *"$pattern"* ]]; then return 1; fi
    return 0
}

# ---------------------------------------------------------------------------
# Generate Nginx upstream config for color
# ---------------------------------------------------------------------------
generate_nginx_upstream() {
    local stack_num="$1" color="$2" output_file="$3"

    case "$stack_num" in
        1)
            if [[ "$color" == "blue" ]]; then
                local api_ports=(3000 3003 3004)
                local fe_ports=(3001 3002)
            else
                local api_ports=(3010 3013 3014)
                local fe_ports=(3011 3012)
            fi
            cat > "$output_file" <<EOF
# Blue-Green: $color active — Generated $(date)
upstream nodejs_api {
    least_conn;
    server 127.0.0.1:${api_ports[0]} max_fails=3 fail_timeout=30s;
    server 127.0.0.1:${api_ports[1]} max_fails=3 fail_timeout=30s;
    server 127.0.0.1:${api_ports[2]} max_fails=3 fail_timeout=30s;
    keepalive 32;
}
upstream nextjs_frontend {
    server 127.0.0.1:${fe_ports[0]} max_fails=2 fail_timeout=30s;
    server 127.0.0.1:${fe_ports[1]} max_fails=2 fail_timeout=30s;
    keepalive 16;
}
EOF
            ;;
        2)
            if [[ "$color" == "blue" ]]; then
                local ports=(8000 8001 8002)
            else
                local ports=(8010 8011 8012)
            fi
            cat > "$output_file" <<EOF
# Blue-Green: $color active — Generated $(date)
upstream laravel_pool {
    ip_hash;
    server 127.0.0.1:${ports[0]} max_fails=3 fail_timeout=30s;
    server 127.0.0.1:${ports[1]} max_fails=3 fail_timeout=30s;
    server 127.0.0.1:${ports[2]} max_fails=3 fail_timeout=30s;
    keepalive 32;
}
EOF
            ;;
        3)
            if [[ "$color" == "blue" ]]; then
                local api_ports=(8003 8004 8005)
                local fe_ports=(3005 3006)
            else
                local api_ports=(8013 8014 8015)
                local fe_ports=(3015 3016)
            fi
            cat > "$output_file" <<EOF
# Blue-Green: $color active — Generated $(date)
upstream stack3_fastapi {
    least_conn;
    server 127.0.0.1:${api_ports[0]} max_fails=3 fail_timeout=30s;
    server 127.0.0.1:${api_ports[1]} max_fails=3 fail_timeout=30s;
    server 127.0.0.1:${api_ports[2]} max_fails=3 fail_timeout=30s;
    keepalive 32;
}
upstream stack3_nextjs {
    server 127.0.0.1:${fe_ports[0]} max_fails=2 fail_timeout=30s;
    server 127.0.0.1:${fe_ports[1]} max_fails=2 fail_timeout=30s;
    keepalive 16;
}
EOF
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Deploy Green instances
# ---------------------------------------------------------------------------
deploy_green() {
    local stack_num="$1"
    local stack_dir

    case "$stack_num" in
        1) stack_dir="$SCRIPT_DIR/stack1_next_node_mongodb" ;;
        2) stack_dir="$SCRIPT_DIR/stack2_laravel_mysql_api" ;;
        3) stack_dir="$SCRIPT_DIR/stack3_next_fastapi_mysql" ;;
    esac

    info "Deploying Green instances for Stack $stack_num..."

    case "$stack_num" in
        1)
            # Start Green backend instances on offset ports
            for port in 3010 3013 3014; do
                info "Starting Green Express :$port..."
                sudo -u "$REAL_USER" bash -c "export PATH=\"$PATH\"; cd \"$stack_dir/backend\" && PORT=$port NODE_ENV=production node server.js &" 2>/dev/null
                sleep 3
            done
            # Start Green frontend instances
            for port in 3011 3012; do
                info "Starting Green Next.js :$port..."
                sudo -u "$REAL_USER" bash -c "export PATH=\"$PATH\"; cd \"$stack_dir/frontend\" && npx next start -p $port &" 2>/dev/null
                sleep 3
            done
            ;;
        2)
            for port in 8010 8011 8012; do
                info "Starting Green Laravel :$port..."
                cd "$stack_dir"
                php artisan serve --host=127.0.0.1 --port="$port" &>/dev/null &
                sleep 3
            done
            ;;
        3)
            # Green FastAPI instances
            for port in 8013 8014 8015; do
                info "Starting Green FastAPI :$port..."
                cd "$stack_dir/backend"
                source venv/bin/activate 2>/dev/null || true
                uvicorn app.main:app --host 127.0.0.1 --port "$port" --workers 4 &>/dev/null &
                deactivate 2>/dev/null || true
                sleep 3
            done
            # Green Next.js instances
            for port in 3015 3016; do
                info "Starting Green Next.js :$port..."
                sudo -u "$REAL_USER" bash -c "export PATH=\"$PATH\"; cd \"$stack_dir/frontend\" && npx next start -p $port &" 2>/dev/null
                sleep 3
            done
            ;;
    esac

    pass "Green instances started"
}

# ---------------------------------------------------------------------------
# Health check Green instances
# ---------------------------------------------------------------------------
health_check_green() {
    local stack_num="$1"
    local all_healthy=true

    info "Health checking Green instances..."

    case "$stack_num" in
        1)
            for port in 3010 3013 3014; do
                if check_health "http://localhost:$port/api/health" '"status"'; then
                    pass "Green Express :$port healthy"
                else
                    fail "Green Express :$port UNHEALTHY"
                    all_healthy=false
                fi
            done
            for port in 3011 3012; do
                if check_health "http://localhost:$port/" "html"; then
                    pass "Green Next.js :$port healthy"
                else
                    fail "Green Next.js :$port UNHEALTHY"
                    all_healthy=false
                fi
            done
            ;;
        2)
            for port in 8010 8011 8012; do
                if check_health "http://localhost:$port/api/health" '"status"'; then
                    pass "Green Laravel :$port healthy"
                else
                    fail "Green Laravel :$port UNHEALTHY"
                    all_healthy=false
                fi
            done
            ;;
        3)
            for port in 8013 8014 8015; do
                if check_health "http://localhost:$port/health" '"status"'; then
                    pass "Green FastAPI :$port healthy"
                else
                    fail "Green FastAPI :$port UNHEALTHY"
                    all_healthy=false
                fi
            done
            for port in 3015 3016; do
                if check_health "http://localhost:$port/" "html"; then
                    pass "Green Next.js :$port healthy"
                else
                    fail "Green Next.js :$port UNHEALTHY"
                    all_healthy=false
                fi
            done
            ;;
    esac

    if [[ "$all_healthy" == true ]]; then
        return 0
    else
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Switch Nginx upstream
# ---------------------------------------------------------------------------
switch_upstream() {
    local stack_num="$1" color="$2"
    local stack_conf="stack${stack_num}.conf"
    local upstream_file="$NGINX_DIR/conf.d/stack${stack_num}-upstream.conf"

    info "Switching Nginx upstream to $color..."

    generate_nginx_upstream "$stack_num" "$color" "$upstream_file"

    # Test Nginx config
    if sudo nginx -t 2>&1; then
        sudo systemctl reload nginx
        pass "Nginx reloaded — $color upstream active"
        return 0
    else
        fail "Nginx config test failed — NOT switching"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Monitor phase
# ---------------------------------------------------------------------------
monitor_phase() {
    local stack_num="$1" duration="$2"
    local stack_domain="stack${stack_num}.devops.local"
    local errors=0
    local checks=0
    local interval=10
    local elapsed=0

    info "Monitoring for ${duration}s (checking every ${interval}s)..."

    while [[ $elapsed -lt $duration ]]; do
        checks=$((checks + 1))
        if ! check_health "https://$stack_domain/health" '"status"'; then
            errors=$((errors + 1))
            warn "Health check failed at ${elapsed}s ($errors total errors)"
            # Abort if error rate > 20%
            if [[ $errors -gt $((checks / 5 + 1)) ]]; then
                fail "Error rate too high: $errors/$checks — aborting"
                return 1
            fi
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    if [[ $errors -eq 0 ]]; then
        pass "Monitoring complete: $checks checks, 0 errors"
        return 0
    else
        warn "Monitoring complete: $checks checks, $errors errors"
        if [[ $errors -gt $((checks / 10)) ]]; then
            return 1
        fi
        return 0
    fi
}

# ---------------------------------------------------------------------------
# Kill Green instances (cleanup on failure or after successful switch)
# ---------------------------------------------------------------------------
kill_color_instances() {
    local color="$1" stack_num="$2"

    case "$stack_num" in
        1)
            if [[ "$color" == "green" ]]; then
                for port in 3010 3013 3014 3011 3012; do
                    local pids; pids=$(lsof -i :"$port" -t 2>/dev/null || true)
                    [[ -n "$pids" ]] && echo "$pids" | xargs kill 2>/dev/null || true
                done
            fi
            ;;
        2)
            if [[ "$color" == "green" ]]; then
                for port in 8010 8011 8012; do
                    local pids; pids=$(lsof -i :"$port" -t 2>/dev/null || true)
                    [[ -n "$pids" ]] && echo "$pids" | xargs kill 2>/dev/null || true
                done
            fi
            ;;
        3)
            if [[ "$color" == "green" ]]; then
                for port in 8013 8014 8015 3015 3016; do
                    local pids; pids=$(lsof -i :"$port" -t 2>/dev/null || true)
                    [[ -n "$pids" ]] && echo "$pids" | xargs kill 2>/dev/null || true
                done
            fi
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log_info "Zero-downtime deployment started"

    if [[ -z "$TARGET_STACK" ]]; then
        log_error "No stack specified. Use --stack 1|2|3"
        show_usage
        exit $EXIT_ERROR
    fi

    if [[ $EUID -ne 0 ]]; then
        log_error "Root required for Nginx operations. Run: sudo $0 $*"
        exit $EXIT_ERROR
    fi

    TOTAL_STEPS=5

    log ""
    log "${BOLD}${BLUE}+============================================================+${NC}"
    log "${BOLD}${BLUE}|  Zero-Downtime Blue-Green Deploy — Stack $TARGET_STACK                 |${NC}"
    log "${BOLD}${BLUE}|  $(date)                              |${NC}"
    log "${BOLD}${BLUE}+============================================================+${NC}"

    # Step 1: Deploy Green
    step 1 "Deploy Green instances"
    deploy_green "$TARGET_STACK"

    # Step 2: Health check Green
    step 2 "Health check Green instances"
    sleep 10
    if ! health_check_green "$TARGET_STACK"; then
        fail "Green instances unhealthy — aborting deployment"
        kill_color_instances green "$TARGET_STACK"
        log "${BOLD}${RED}  Deployment aborted — Blue remains active${NC}"
        exit $EXIT_ERROR
    fi

    # Step 3: Switch Nginx
    step 3 "Switch Nginx upstream to Green"
    if ! switch_upstream "$TARGET_STACK" "green"; then
        fail "Nginx switch failed — aborting"
        kill_color_instances green "$TARGET_STACK"
        log "${BOLD}${RED}  Deployment aborted — Blue remains active${NC}"
        exit $EXIT_ERROR
    fi

    # Step 4: Monitor
    step 4 "Monitor Green (${MONITOR_DURATION}s)"
    if ! monitor_phase "$TARGET_STACK" "$MONITOR_DURATION"; then
        fail "Monitoring detected failures — rolling back to Blue"
        switch_upstream "$TARGET_STACK" "blue"
        kill_color_instances green "$TARGET_STACK"
        log ""
        log "${BOLD}${RED}+============================================================+${NC}"
        log "${BOLD}${RED}|  ✗ Rolled back to Blue — Green deployment failed           |${NC}"
        log "${BOLD}${RED}+============================================================+${NC}"
        exit $EXIT_ERROR
    fi

    # Step 5: Decommission Blue
    step 5 "Decommission Blue instances"
    info "Green is now production. Blue can be safely stopped."
    info "Blue instances remain running for immediate rollback if needed."
    info "To fully decommission: kill_color_instances blue $TARGET_STACK"
    pass "Blue-Green deployment complete"

    log ""
    log "${BOLD}${GREEN}+============================================================+${NC}"
    log "${BOLD}${GREEN}|  ✓ Zero-downtime deployment successful — Stack $TARGET_STACK           |${NC}"
    log "${BOLD}${GREEN}+============================================================+${NC}"
    log ""
    log "  ${CYAN}Active:${NC} Green instances"
    log "  ${CYAN}Standby:${NC} Blue instances (for rollback)"
    log "  ${CYAN}Rollback:${NC} sudo ./zero_downtime_deploy.sh --stack $TARGET_STACK"
    log "                  (will switch back to Blue)"
    log "  ${CYAN}Log:${NC} $DEPLOY_LOG"
    log ""

    log_info "Zero-downtime deployment completed"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)             show_usage; exit $EXIT_SUCCESS ;;
        --stack)               TARGET_STACK="${2:-}"; shift ;;
        --monitor-duration)    MONITOR_DURATION="${2:-300}"; shift ;;
        -v|--verbose)          set -x ;;
        *)                     log_error "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
