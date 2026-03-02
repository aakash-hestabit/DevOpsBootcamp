#!/bin/bash
set -euo pipefail

# Script: deploy_stack2.sh
# Description: Full Stack 2 deployment -- MySQL master-slave --> composer install
#              --> migrations --> frontend build --> systemd services --> SSL --> Nginx.
#              Use --skip-* flags to re-run only the parts you need.
# Author: Aakash
# Date: 2026-03-01
# Usage: sudo ./deploy_stack2.sh [OPTIONS]

# Ensure nvm-installed node/npm are on the PATH (needed when running under sudo)
for _nvm_bin in \
    "/home/${SUDO_USER:-$USER}/.nvm/versions/node/"*/bin \
    "$HOME/.nvm/versions/node/"*/bin \
    /usr/local/bin \
    /usr/bin; do
    [[ -d "$_nvm_bin" && ":$PATH:" != *":$_nvm_bin:"* ]] && PATH="$_nvm_bin:$PATH"
done
export PATH

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
MYSQL_DIR="$SCRIPT_DIR/mysql"
NGINX_DIR="$SCRIPT_DIR/nginx"
SYSTEMD_DIR="$SCRIPT_DIR/systemd"
LOG_DIR="$SCRIPT_DIR/var/log/apps"
DEPLOY_LOG="$LOG_DIR/deploy-$(date +%Y%m%d-%H%M%S).log"
LOG_FILE="$LOG_DIR/$(basename "$0" .sh).log"

mkdir -p "$LOG_DIR"

# Flags
SKIP_MYSQL=false
SKIP_NGINX=false
SKIP_BUILD=false

# Detect the real (non-root) user when running under sudo
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo ~"$REAL_USER")

# MySQL settings (must match master-slave-setup.sh)
MASTER_PORT=3306
SLAVE_PORT=3307
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-Root@123}"
APP_USER="laraveluser"
APP_PASSWORD="Laravel@123"
APP_DB="laraveldb"

# Laravel app ports
APP_PORTS=(8000 8001 8002)

# Suppress composer self-update network checks
export COMPOSER_NO_INTERACTION=1
export COMPOSER_NO_AUDIT=1
export COMPOSER_DISABLE_XDEBUG_WARN=1

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }

log()  { echo -e "$1" | tee -a "$DEPLOY_LOG"; }
pass() { log "${GREEN}    $1${NC}"; }
fail() { log "${RED}    $1${NC}"; }
info() { log "${BLUE}    $1${NC}"; }
warn() { log "${YELLOW}    $1${NC}"; }
sep()  { log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
step() { log ""; sep; log "${BOLD}${BLUE}  [$1/$TOTAL_STEPS] $2${NC}"; sep; }


show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Full Stack 2 deployment -- MySQL master-slave + Laravel + Nginx.

OPTIONS:
  -h, --help          Show this help message
  --skip-mysql        Skip MySQL master-slave setup (assumes it is already running)
  --skip-nginx        Skip Nginx install and SSL config
  --skip-build        Skip composer install and frontend asset build
  -v, --verbose       Enable verbose output

EXAMPLES:
  sudo ./deploy_stack2.sh                            # fresh full deployment
  sudo ./deploy_stack2.sh --skip-mysql               # re-deploy app only
       ./deploy_stack2.sh --skip-mysql --skip-nginx  # no sudo needed
EOF
}


main() {
    log_info "Deployment started"

    # Nginx and SSL operations require root
    if [[ $SKIP_NGINX == false && $EUID -ne 0 ]]; then
        log_error "Nginx setup requires root. Run: sudo $0 $*"
        log_error "To skip Nginx: $0 --skip-nginx $*"
        exit $EXIT_ERROR
    fi

    # Count total steps dynamically based on flags
    TOTAL_STEPS=0
    TOTAL_STEPS=$((TOTAL_STEPS + 1))   # git pull always runs
    if [[ $SKIP_MYSQL  == false ]]; then TOTAL_STEPS=$((TOTAL_STEPS + 1)); fi
    TOTAL_STEPS=$((TOTAL_STEPS + 1))   # composer install always runs
    TOTAL_STEPS=$((TOTAL_STEPS + 1))   # migrations always run
    if [[ $SKIP_BUILD  == false ]]; then TOTAL_STEPS=$((TOTAL_STEPS + 1)); fi
    TOTAL_STEPS=$((TOTAL_STEPS + 1))   # systemd services always runs
    if [[ $SKIP_NGINX  == false ]]; then TOTAL_STEPS=$((TOTAL_STEPS + 2)); fi  # SSL + Nginx

    CURRENT=0

    log ""
    log "${BOLD}${BLUE}+===========================================================+${NC}"
    log "${BOLD}${BLUE}|  Stack 2 Deployment -- Laravel + MySQL                     |${NC}"
    log "${BOLD}${BLUE}|  Started: $(date)                                          |${NC}"
    log "${BOLD}${BLUE}+===========================================================+${NC}"
    log ""

    # -------------------------------------------------------------------
    # Pre-flight: check required tools
    # -------------------------------------------------------------------
    sep
    log "${BOLD}Pre-flight checks${NC}"

    for cmd in php composer; do
        if command -v "$cmd" &>/dev/null; then
            _ver=$(timeout 5 "$cmd" --version 2>/dev/null | head -1)
            pass "$cmd: $_ver"
        else
            fail "$cmd is not installed -- install it and re-run."
            exit $EXIT_ERROR
        fi
    done

    # Check PHP version (Laravel 11 requires PHP >= 8.2)
    PHP_VER=$(php -r 'echo PHP_VERSION;')
    PHP_MAJOR=$(echo "$PHP_VER" | cut -d. -f1)
    PHP_MINOR=$(echo "$PHP_VER" | cut -d. -f2)
    if [[ $PHP_MAJOR -lt 8 || ($PHP_MAJOR -eq 8 && $PHP_MINOR -lt 2) ]]; then
        fail "PHP $PHP_VER is too old. Laravel 11 requires PHP >= 8.2"
        exit $EXIT_ERROR
    fi
    pass "PHP version $PHP_VER meets requirements (>= 8.2)"

    # Check required PHP extensions (run php -m once, cache output)
    PHP_MODULES=$(php -m 2>/dev/null)
    for ext in pdo_mysql mbstring openssl tokenizer xml ctype json bcmath; do
        if echo "$PHP_MODULES" | grep -qi "^$ext$"; then
            pass "PHP extension: $ext"
        else
            warn "PHP extension $ext may not be installed -- Laravel may fail"
        fi
    done

    if [[ $SKIP_MYSQL == false ]]; then
        if command -v mysqld &>/dev/null; then
            pass "mysqld: $(timeout 5 mysqld --version 2>&1 | head -1)"
        else
            fail "mysqld is not installed"
            exit $EXIT_ERROR
        fi
        if command -v mysql &>/dev/null; then
            pass "mysql client found"
        else
            fail "mysql client is not installed"
            exit $EXIT_ERROR
        fi
    fi

    # Check npm (needed for frontend build)
    if [[ $SKIP_BUILD == false ]]; then
        if command -v npm &>/dev/null; then
            pass "npm: $(timeout 5 npm --version 2>/dev/null)"
        else
            warn "npm not found -- frontend asset build will be skipped"
        fi
    fi

    # ===================================================================
    # STEP: Git pull (DISABLED -- pseudo pull to protect local code)
    # ===================================================================
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "Git -- pull latest code"

    #   IMPORTANT: git stash + git pull are COMMENTED OUT to prevent
    #   overwriting local changes.

    GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

    if [[ -n "$GIT_ROOT" ]]; then
        REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "Unknown Remote")
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
        COMMIT=$(git log -1 --format="%h - %s (%ar)" 2>/dev/null || echo "unknown")

        info "Repository : $REMOTE_URL"
        info "Branch     : $CURRENT_BRANCH"
        info "Current    : $COMMIT"
        warn "[PSEUDO PULL] git stash + git pull are DISABLED in this script"
        warn "[PSEUDO PULL] Using current local code as-is"
        pass "Local code preserved (pseudo pull)"

        # -- Original git pull code (COMMENTED OUT) --
        # cd "$GIT_ROOT"
        # git stash --quiet 2>/dev/null || true
        # if git pull origin "$CURRENT_BRANCH" 2>&1 | tee -a "$DEPLOY_LOG"; then
        #     COMMIT=$(git log -1 --format="%h - %s (%ar)" 2>/dev/null || echo "unknown")
        #     pass "Updated to: $COMMIT"
        # else
        #     warn "Git pull failed -- continuing with current local code"
        # fi
    else
        warn "Not inside a Git repository -- skipping pull"
    fi

    # ===================================================================
    # STEP: MySQL Master-Slave Replication
    # ===================================================================
    if [[ $SKIP_MYSQL == false ]]; then
        CURRENT=$((CURRENT + 1))
        step "$CURRENT" "MySQL Master-Slave Replication (ports $MASTER_PORT / $SLAVE_PORT)"

        chmod +x "$MYSQL_DIR/master-slave-setup.sh"
        # Run MySQL setup and capture exit code properly (pipe to tee can mask failures)
        set +e
        bash "$MYSQL_DIR/master-slave-setup.sh" 2>&1 | tee -a "$DEPLOY_LOG"
        MYSQL_EXIT=${PIPESTATUS[0]}
        set -e
        if [[ $MYSQL_EXIT -ne 0 ]]; then
            fail "MySQL master-slave setup failed (exit code: $MYSQL_EXIT)"
            exit $EXIT_ERROR
        fi
        pass "MySQL master-slave replication ready"
    fi

    # ===================================================================
    # STEP: Composer install + environment config
    # ===================================================================
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "Laravel -- dependencies + environment"

    cd "$SCRIPT_DIR"
    if [[ $SKIP_BUILD == false ]]; then
        info "Running composer install (production)..."
        composer install --no-dev --optimize-autoloader --no-interaction 2>&1 | tee -a "$DEPLOY_LOG"
        pass "Composer dependencies installed"
    fi

    # Copy production env file
    if [[ -f "$SCRIPT_DIR/.env.production" ]]; then
        cp "$SCRIPT_DIR/.env.production" "$SCRIPT_DIR/.env"
        pass "Production .env applied"
    else
        warn ".env.production not found -- existing .env will be used"
    fi

    # Laravel optimization commands
    info "Running Laravel optimization..."
    php artisan config:cache 2>&1 | tee -a "$DEPLOY_LOG"
    php artisan route:cache 2>&1 | tee -a "$DEPLOY_LOG"
    php artisan view:cache 2>&1 | tee -a "$DEPLOY_LOG"
    pass "Laravel config/route/view cached"

    # Ensure storage directories exist with correct permissions
    mkdir -p storage/app/public storage/framework/{cache,sessions,views} storage/logs
    mkdir -p bootstrap/cache
    mkdir -p var/log/apps

    # Set permissions
    chmod -R 775 storage bootstrap/cache var/log/apps
    chown -R "$REAL_USER":"$REAL_USER" storage bootstrap/cache var/log/apps 2>/dev/null || true
    pass "Storage directories ready"

    # ===================================================================
    # STEP: Database migrations
    # ===================================================================
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "Database -- Laravel migrations"

    cd "$SCRIPT_DIR"

    # Verify MySQL master is reachable before attempting migrations
    info "Checking MySQL master connectivity on port $MASTER_PORT..."
    _MYSQL_UP=false
    for _i in $(seq 1 10); do
        if mysql -h 127.0.0.1 -P "$MASTER_PORT" -u "$APP_USER" -p"$APP_PASSWORD" -e "SELECT 1" "$APP_DB" &>/dev/null 2>&1; then
            _MYSQL_UP=true
            break
        fi
        sleep 2
    done

    if [[ $_MYSQL_UP == false ]]; then
        fail "MySQL master is not reachable on port $MASTER_PORT."
        fail "Either:"
        fail "  - Run the full deploy (without --skip-mysql) so MySQL is started first"
        fail "  - Or manually start MySQL master"
        exit $EXIT_ERROR
    fi
    pass "MySQL master is reachable"

    info "Running database migrations..."
    # Temporarily point read replica to master to avoid read/write split
    # race conditions during migrations (slave may be catching up)
    DB_READ_HOST=127.0.0.1 DB_READ_PORT=$MASTER_PORT php artisan config:clear --no-interaction 2>&1
    DB_READ_HOST=127.0.0.1 DB_READ_PORT=$MASTER_PORT php artisan migrate --force --no-interaction 2>&1 | tee -a "$DEPLOY_LOG"
    pass "All migrations applied"

    # Re-cache config with the real read/write split settings
    php artisan config:cache 2>&1 | tee -a "$DEPLOY_LOG"

    # Seed database if it is empty (first deploy only)
    TASK_COUNT=$(mysql -h 127.0.0.1 -P "$MASTER_PORT" -u "$APP_USER" -p"$APP_PASSWORD" -Nse "SELECT COUNT(*) FROM tasks" "$APP_DB" 2>/dev/null || echo "0")
    if [[ "$TASK_COUNT" == "0" ]]; then
        info "Database is empty -- running seeders..."
        php artisan db:seed --force --no-interaction 2>&1 | tee -a "$DEPLOY_LOG"
        pass "Database seeded"
    else
        info "Database already has $TASK_COUNT tasks -- skipping seeder"
    fi

    # ===================================================================
    # STEP: Frontend asset build
    # ===================================================================
    if [[ $SKIP_BUILD == false ]]; then
        CURRENT=$((CURRENT + 1))
        step "$CURRENT" "Frontend -- npm install + Vite production build"

        cd "$SCRIPT_DIR"
        if command -v npm &>/dev/null; then
            info "npm install..."
            npm install 2>&1 | tee -a "$DEPLOY_LOG"

            info "npm run build (Vite)..."
            npm run build 2>&1 | tee -a "$DEPLOY_LOG"
            pass "Frontend assets compiled"
        else
            warn "npm not available -- skipping frontend build"
            warn "Pre-built assets in public/build/ will be used if they exist"
        fi
    fi

    # ===================================================================
    # STEP: systemd services -- rolling restart with health checks
    # ===================================================================
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "systemd -- rolling restart with health checks"

    cd "$SCRIPT_DIR"

    # Ensure log directories are writable
    mkdir -p "$SCRIPT_DIR/var/log/apps"
    chmod -R 775 "$SCRIPT_DIR/var/log/apps"

    # Copy systemd unit files, substituting www-data with the real user
    info "Installing systemd service files (user=$REAL_USER)..."
    for SERVICE_FILE in "$SYSTEMD_DIR"/*.service "$SYSTEMD_DIR"/*.timer; do
        [[ -f "$SERVICE_FILE" ]] || continue
        DEST="/etc/systemd/system/$(basename "$SERVICE_FILE")"
        sed "s|User=www-data|User=$REAL_USER|g; s|Group=www-data|Group=$REAL_USER|g" \
            "$SERVICE_FILE" > "$DEST"
        info "  Installed: $(basename "$SERVICE_FILE")"
    done
    systemctl daemon-reload
    pass "systemd unit files installed"

    # Detect fresh deploy vs re-deploy
    FIRST_SERVICE="laravel-app-${APP_PORTS[0]}"
    if ! systemctl is-active --quiet "$FIRST_SERVICE" 2>/dev/null; then

        # -----------------------------------------------------------
        # Fresh deployment: start everything from scratch
        # -----------------------------------------------------------
        info "Fresh deployment -- starting all services..."

        # Kill any processes occupying our ports and wait for them to die
        for PORT in "${APP_PORTS[@]}"; do
            if fuser "$PORT/tcp" &>/dev/null 2>&1; then
                fuser -k "$PORT/tcp" 2>/dev/null || true
            fi
        done
        sleep 2
        # Force-kill anything still lingering
        for PORT in "${APP_PORTS[@]}"; do
            if fuser "$PORT/tcp" &>/dev/null 2>&1; then
                fuser -k -9 "$PORT/tcp" 2>/dev/null || true
            fi
        done
        sleep 1

        # Start all Laravel app instances
        for PORT in "${APP_PORTS[@]}"; do
            systemctl enable "laravel-app-$PORT" 2>/dev/null || true
            systemctl start "laravel-app-$PORT"
            info "  Started laravel-app-$PORT"
        done

        # Start queue workers
        for WORKER_ID in 1 2; do
            systemctl enable "laravel-worker@$WORKER_ID" 2>/dev/null || true
            systemctl start "laravel-worker@$WORKER_ID"
            info "  Started laravel-worker@$WORKER_ID"
        done

        # Start scheduler
        systemctl enable laravel-scheduler.timer 2>/dev/null || true
        systemctl start laravel-scheduler.timer
        info "  Started laravel-scheduler.timer"

        # Wait for services to initialize
        sleep 5

        # Health check all instances
        for PORT in "${APP_PORTS[@]}"; do
            HEALTHY=false
            for i in $(seq 1 12); do
                if curl -sf --max-time 4 "http://127.0.0.1:$PORT/api/health" | grep -q '"status"' 2>/dev/null; then
                    HEALTHY=true
                    break
                fi
                sleep 3
            done
            if [[ $HEALTHY == true ]]; then
                pass "laravel-app-$PORT healthy"
            else
                warn "laravel-app-$PORT not responding yet -- check: journalctl -u laravel-app-$PORT"
            fi
        done

        pass "All services started (fresh deploy)"

    else

        # -----------------------------------------------------------
        # Re-deployment: rolling restart one instance at a time
        # -----------------------------------------------------------
        info "Re-deployment detected -- performing zero-downtime rolling restart..."

        for PORT in "${APP_PORTS[@]}"; do
            SERVICE_NAME="laravel-app-$PORT"
            info "Restarting $SERVICE_NAME (port $PORT)..."
            systemctl restart "$SERVICE_NAME" 2>&1 | tee -a "$DEPLOY_LOG" || true
            sleep 5

            # Health check with retries
            HEALTHY=false
            for i in $(seq 1 12); do
                if curl -sf --max-time 4 "http://127.0.0.1:$PORT/api/health" | grep -q '"status"' 2>/dev/null; then
                    HEALTHY=true
                    break
                fi
                sleep 3
            done

            if [[ $HEALTHY == true ]]; then
                pass "$SERVICE_NAME healthy"
            else
                fail "$SERVICE_NAME health check failed -- rolling back..."
                # Rollback: restart the failed instance and abort
                systemctl restart "$SERVICE_NAME" 2>/dev/null || true
                log_error "Rollback triggered: $SERVICE_NAME failed health check on port $PORT"
                fail "Deployment aborted. Remaining instances were NOT restarted."
                fail "The instances that were already restarted should still be running."
                fail "Check: journalctl -u $SERVICE_NAME -n 50"
                exit $EXIT_ERROR
            fi
        done

        # Restart queue workers
        for WORKER_ID in 1 2; do
            systemctl restart "laravel-worker@$WORKER_ID" 2>&1 | tee -a "$DEPLOY_LOG" || true
            info "  Restarted laravel-worker@$WORKER_ID"
        done

        # Restart scheduler
        systemctl restart laravel-scheduler.timer 2>&1 | tee -a "$DEPLOY_LOG" || true
        info "  Restarted laravel-scheduler.timer"

        pass "Rolling restart complete -- all instances healthy"
    fi

    # Show systemd service status
    log ""
    for PORT in "${APP_PORTS[@]}"; do
        systemctl --no-pager status "laravel-app-$PORT" 2>&1 | head -5 | tee -a "$DEPLOY_LOG" || true
    done
    pass "All services running"

    # ===================================================================
    # STEP: SSL certificate
    # ===================================================================
    if [[ $SKIP_NGINX == false ]]; then
        CURRENT=$((CURRENT + 1))
        step "$CURRENT" "SSL certificate (stack2.devops.local)"

        chmod +x "$NGINX_DIR/setup-ssl.sh"
        if [[ -f /etc/ssl/certs/stack2-ca.crt && -f /etc/ssl/certs/stack2.crt && -f /etc/ssl/private/stack2.key ]]; then
            pass "SSL certificate already exists (CA-signed) -- skipping"
        else
            rm -f /etc/ssl/certs/stack2.crt /etc/ssl/private/stack2.key 2>/dev/null || true
            bash "$NGINX_DIR/setup-ssl.sh" 2>&1 | tee -a "$DEPLOY_LOG"
            pass "SSL certificate generated (CA-signed)"
        fi

        # ===============================================================
        # STEP: Nginx load balancer
        # ===============================================================
        CURRENT=$((CURRENT + 1))
        step "$CURRENT" "Nginx -- install + configure load balancer"

        chmod +x "$NGINX_DIR/install-nginx-config.sh"
        bash "$NGINX_DIR/install-nginx-config.sh" 2>&1 | tee -a "$DEPLOY_LOG"
        pass "Nginx configured and running"
    fi

    # ===================================================================
    # Post-deploy smoke tests
    # ===================================================================
    sep
    log "${BOLD}Health checks${NC}"
    sleep 5

    # Wait for Laravel instances to be fully ready
    info "Waiting for Laravel instances to initialize..."
    for PORT in "${APP_PORTS[@]}"; do
        READY=false
        for i in $(seq 1 15); do
            if curl -sf --max-time 3 "http://127.0.0.1:$PORT/api/health" | grep -q '"status"' 2>/dev/null; then
                READY=true
                break
            fi
            sleep 2
        done
        if [[ $READY == true ]]; then
            pass "Laravel :$PORT  healthy"
        else
            warn "Laravel :$PORT  not responding -- check: journalctl -u laravel-app-$PORT"
        fi
    done

    # Check MySQL
    if mysql -h 127.0.0.1 -P "$MASTER_PORT" -u "$APP_USER" -p"$APP_PASSWORD" -e "SELECT 1" "$APP_DB" &>/dev/null 2>&1; then
        pass "MySQL master :$MASTER_PORT  healthy"
    else
        warn "MySQL master :$MASTER_PORT  not responding"
    fi

    if mysql -h 127.0.0.1 -P "$SLAVE_PORT" -u "$APP_USER" -p"$APP_PASSWORD" -e "SELECT 1" "$APP_DB" &>/dev/null 2>&1; then
        pass "MySQL slave  :$SLAVE_PORT  healthy"
    else
        warn "MySQL slave  :$SLAVE_PORT  not responding"
    fi

    # Check queue workers
    for WORKER_ID in 1 2; do
        if systemctl is-active --quiet "laravel-worker@$WORKER_ID" 2>/dev/null; then
            pass "Queue worker @$WORKER_ID  active"
        else
            warn "Queue worker @$WORKER_ID  not active"
        fi
    done

    # Check scheduler
    if systemctl is-active --quiet laravel-scheduler.timer 2>/dev/null; then
        pass "Scheduler timer  active"
    else
        warn "Scheduler timer  not active"
    fi

    # Check Nginx
    if [[ $SKIP_NGINX == false ]]; then
        curl -sk --max-time 5 "https://stack2.devops.local/health" | grep -q '"status"' 2>/dev/null \
            && pass "Nginx HTTPS  -->  https://stack2.devops.local  healthy" \
            || warn "Nginx HTTPS  -->  not reachable  (add 127.0.0.1 stack2.devops.local to /etc/hosts)"
    fi

    # ===================================================================
    # Final summary
    # ===================================================================
    sep
    log ""
    log "${BOLD}${GREEN}+===========================================================+${NC}"
    log "${BOLD}${GREEN}|   Stack 2 deployed successfully!                           |${NC}"
    log "${BOLD}${GREEN}+===========================================================+${NC}"
    log ""
    log "  ${CYAN}Application${NC}"
    log "    https://stack2.devops.local             (Nginx LB)"
    log "    https://stack2.devops.local/api/health   (health check)"
    log "    https://stack2.devops.local/api/tasks    (tasks API)"
    log "    http://localhost:8000                    (direct, instance 1)"
    log "    http://localhost:8001                    (direct, instance 2)"
    log "    http://localhost:8002                    (direct, instance 3)"
    log ""
    log "  ${CYAN}MySQL${NC}"
    log "    Master (write): 127.0.0.1:${MASTER_PORT}  (${APP_DB})"
    log "    Slave  (read):  127.0.0.1:${SLAVE_PORT}  (${APP_DB})"
    log ""
    log "  ${CYAN}Queue & Scheduler${NC}"
    log "    Workers: laravel-worker@1, laravel-worker@2"
    log "    Scheduler: laravel-scheduler.timer (every minute)"
    log ""
    log "  ${CYAN}Useful commands${NC}"
    log "    systemctl status laravel-app-8000        # service status"
    log "    journalctl -u laravel-app-8000 -f        # follow logs"
    log "    ./health_check_stack2.sh                 # live health polling"
    log "    php artisan tinker                       # Laravel REPL"
    log ""
    log "  Deploy log: $DEPLOY_LOG"
    log ""

    log_info "Deployment completed successfully"
}

# -----------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)       show_usage; exit $EXIT_SUCCESS ;;
        --skip-mysql)    SKIP_MYSQL=true ;;
        --skip-nginx)    SKIP_NGINX=true ;;
        --skip-build)    SKIP_BUILD=true ;;
        -v|--verbose)    set -x ;;
        *)               warn "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
