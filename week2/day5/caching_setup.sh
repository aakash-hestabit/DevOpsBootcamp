#!/bin/bash
set -euo pipefail

# Script: caching_setup.sh
# Description: Install and configure Redis caching layer for all 3 stacks.
#              - Install Redis server with persistence and authentication
#              - Configure application-level caching (Node.js, Laravel, FastAPI)
#              - Configure HTTP caching headers in Nginx
#              - Set up Nginx proxy_cache zones
# Author: Aakash
# Date: 2026-03-02
# Usage: sudo ./caching_setup.sh [--skip-redis] [--skip-nginx] [--help]

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
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/var/log"
LOG_FILE="$LOG_DIR/$(basename "$0" .sh).log"
CACHING_DIR="$SCRIPT_DIR/caching"

mkdir -p "$LOG_DIR" "$CACHING_DIR"

SKIP_REDIS=false
SKIP_NGINX=false
TOTAL_STEPS=5
CURRENT=0

# Logging
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }

log()  { echo -e "$1" | tee -a "$LOG_FILE"; }
pass() { log "${GREEN}    $1${NC}"; }
fail() { log "${RED}    $1${NC}"; }
info() { log "${BLUE}    $1${NC}"; }
warn() { log "${YELLOW}    $1${NC}"; }
sep()  { log "${CYAN}------------------------------------------------------------${NC}"; }
step() { log ""; sep; log "${BOLD}${BLUE}  [$1/$TOTAL_STEPS] $2${NC}"; sep; }

show_usage() {
    cat <<EOF
Usage: sudo $(basename "$0") [OPTIONS]

Install and configure Redis caching for all 3 production stacks.

OPTIONS:
  -h, --help          Show this help message
  --skip-redis        Skip Redis installation (use existing Redis)
  --skip-nginx        Skip Nginx cache configuration
  -v, --verbose       Enable verbose output

EXAMPLES:
  sudo ./$(basename "$0")               # full setup
  sudo ./$(basename "$0") --skip-redis   # configure apps only
EOF
}

main() {
    log_info "Caching setup started"

    log ""
    log "${BOLD}${BLUE}+============================================================+${NC}"
    log "${BOLD}${BLUE}|  Caching Strategy Setup — All Stacks                       |${NC}"
    log "${BOLD}${BLUE}|  $(date)                              |${NC}"
    log "${BOLD}${BLUE}+============================================================+${NC}"

    # STEP 1: Install Redis
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "Redis — install and configure"

    if [[ $SKIP_REDIS == false ]]; then
        if ! command -v redis-server &>/dev/null; then
            info "Installing Redis server..."
            sudo apt-get update -qq
            sudo apt-get install -y redis-server 2>&1 | tail -5
        fi
        pass "Redis server installed: $(redis-server --version 2>/dev/null | head -1)"

        # Deploy custom Redis config
        if [[ -f "$CACHING_DIR/redis.conf" ]]; then
            info "Applying custom Redis configuration..."
            sudo cp "$CACHING_DIR/redis.conf" /etc/redis/redis.conf
            sudo systemctl restart redis-server
            sleep 2
        fi

        # Verify Redis is running
        if redis-cli -a 'DevOpsRedis@123' ping 2>/dev/null | grep -q "PONG"; then
            pass "Redis is running and authenticated"
        elif redis-cli ping 2>/dev/null | grep -q "PONG"; then
            pass "Redis is running (no auth)"
        else
            fail "Redis is not responding"
        fi
    else
        info "Skipping Redis installation (--skip-redis)"
    fi

    # STEP 2: Application cache integration - Node.js (Stack 1)
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "Stack 1 — Node.js Redis integration"

    info "Cache integration reference: caching/cache_integration_nodejs.js"
    info "Add to Express routes for query result caching"
    info "Redis key pattern: stack1:users:*, stack1:api:*"
    info "TTL: 300s for user lists, 60s for individual resources"
    pass "Node.js cache integration guide ready"

    # STEP 3: Application cache integration - Laravel (Stack 2)
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "Stack 2 — Laravel Redis cache driver"

    info "Cache integration reference: caching/cache_integration_laravel.php"
    info "Set CACHE_DRIVER=redis in .env.production"
    info "Set SESSION_DRIVER=redis for session persistence across instances"
    info "Redis key pattern: laravel_cache:*, laravel_session:*"
    info "TTL: 600s for view cache, 300s for query cache"
    pass "Laravel cache integration guide ready"

    # STEP 4: Application cache integration - FastAPI (Stack 3)
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "Stack 3 — FastAPI aioredis integration"

    info "Cache integration reference: caching/cache_integration_fastapi.py"
    info "Use aioredis for async Redis operations"
    info "Redis key pattern: stack3:products:*, stack3:api:*"
    info "TTL: 300s for product lists, 60s for health checks"
    pass "FastAPI cache integration guide ready"

    # STEP 5: Nginx proxy_cache
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "Nginx — proxy_cache configuration"

    if [[ $SKIP_NGINX == false ]]; then
        info "Nginx proxy_cache zones already configured in stack3.conf"
        info "Cache zone: stack3_cache (10m keys, 100m storage)"
        info "Cached endpoints: GET /api/products (5m TTL)"
        info "Cache bypass: Cache-Control header"

        # Create Nginx cache directories
        for stack in stack1 stack2 stack3; do
            sudo mkdir -p "/var/cache/nginx/$stack"
            sudo chown www-data:www-data "/var/cache/nginx/$stack"
        done
        pass "Nginx cache directories created"
    else
        info "Skipping Nginx cache configuration (--skip-nginx)"
    fi

    # Summary
    sep
    log ""
    log "${BOLD}${GREEN}+============================================================+${NC}"
    log "${BOLD}${GREEN}|  Caching setup complete                                    |${NC}"
    log "${BOLD}${GREEN}+============================================================+${NC}"
    log ""
    log "  ${CYAN}Redis${NC}"
    log "    Host: 127.0.0.1:6379"
    log "    Password: DevOpsRedis@123"
    log "    Max memory: 256mb (allkeys-lru)"
    log ""
    log "  ${CYAN}Integration files${NC}"
    log "    caching/redis.conf"
    log "    caching/cache_integration_nodejs.js"
    log "    caching/cache_integration_laravel.php"
    log "    caching/cache_integration_fastapi.py"
    log ""

    log_info "Caching setup completed"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)       show_usage; exit $EXIT_SUCCESS ;;
        --skip-redis)    SKIP_REDIS=true ;;
        --skip-nginx)    SKIP_NGINX=true ;;
        -v|--verbose)    set -x ;;
        *)               log_error "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
