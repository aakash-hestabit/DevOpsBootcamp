#!/bin/bash
set -euo pipefail

# Script: deploy_stack1.sh
# Description: Full Stack 1 deployment — MongoDB RS --> backend deps --> Next.js build
#              --> PM2 launch --> SSL certificate --> Nginx load balancer.
#              Use --skip-* flags to re-run only the parts you need.
# Author: Aakash
# Date: 2026-03-01
# Usage: sudo ./deploy_stack1.sh [OPTIONS]

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

for _nvm_bin in \
    "/home/$SUDO_USER/.nvm/versions/node/"*/bin \
    "$HOME/.nvm/versions/node/"*/bin \
    /usr/local/bin \
    /usr/bin; do
    [[ -d "$_nvm_bin" && ":$PATH:" != *":$_nvm_bin:"* ]] && PATH="$_nvm_bin:$PATH"
done
export PATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/backend"
FRONTEND_DIR="$SCRIPT_DIR/frontend"
MONGO_DIR="$SCRIPT_DIR/mongodb-replicaset"
NGINX_DIR="$SCRIPT_DIR/nginx"
PM2_CONFIG="$SCRIPT_DIR/pm2/ecosystem.config.js"
LOG_DIR="$SCRIPT_DIR/var/log/apps"
DEPLOY_LOG="$LOG_DIR/deploy-$(date +%Y%m%d-%H%M%S).log"

LOG_FILE="$LOG_DIR/$(basename "$0" .sh).log"

mkdir -p "$LOG_DIR"

SKIP_MONGO=false
SKIP_NGINX=false
SKIP_BUILD=false

# Detect the real (non-root) user when running under sudo
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo ~"$REAL_USER")

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }

log()  { echo -e "$1" | tee -a "$DEPLOY_LOG"; }
pass() { log "${GREEN}    $1${NC}"; }
fail() { log "${RED}    $1${NC}"; }
info() { log "${BLUE}    $1${NC}"; }
warn() { log "${YELLOW}    $1${NC}"; }
sep()  { log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
step() { log ""; sep; log "${BOLD}${BLUE}  [$1/$TOTAL_STEPS] $2${NC}"; sep; }

# Help function
show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Full Stack 1 deployment — MongoDB RS + Node.js API + Next.js + Nginx.

OPTIONS:
  -h, --help          Show this help message
  --skip-mongo        Skip MongoDB replica set setup (assumes it's already running)
  --skip-nginx        Skip Nginx install and SSL config
  --skip-build        Skip npm install and Next.js build steps
  -v, --verbose       Enable verbose output

EXAMPLES:
  sudo ./deploy_stack1.sh                            # fresh full deployment
  sudo ./deploy_stack1.sh --skip-mongo               # re-deploy app only
       ./deploy_stack1.sh --skip-mongo --skip-nginx  # no sudo needed
EOF
}

# Main function
main() {
    log_info "Deployment started"

    # Nginx and SSL operations require root — catch this early
    if [[ $SKIP_NGINX == false && $EUID -ne 0 ]]; then
        log_error "Nginx setup requires root. Run: sudo $0 $*"
        log_error "To skip Nginx: $0 --skip-nginx $*"
        exit $EXIT_ERROR
    fi

# Count total steps dynamically based on flags
TOTAL_STEPS=0
TOTAL_STEPS=$((TOTAL_STEPS + 1))   # git pull always runs
[[ $SKIP_MONGO  == false ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
TOTAL_STEPS=$((TOTAL_STEPS + 1))   # backend install always runs
TOTAL_STEPS=$((TOTAL_STEPS + 1))   # migrations always run
[[ $SKIP_BUILD  == false ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
TOTAL_STEPS=$((TOTAL_STEPS + 1))   # PM2 rolling restart always runs
[[ $SKIP_NGINX  == false ]] && TOTAL_STEPS=$((TOTAL_STEPS + 2))  # SSL + Nginx

CURRENT=0

log ""
log "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
log "${BOLD}${BLUE}║  Stack 1 Deployment — Next.js + Node.js + MongoDB        ║${NC}"
log "${BOLD}${BLUE}║  Started: $(date)                                        ║${NC}"
log "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
log ""

# Pre-flight: check required tools are installed
sep
log "${BOLD}Pre-flight checks${NC}"
for cmd in node npm pm2; do
    if command -v "$cmd" &>/dev/null; then
        # Run version check as the real user to avoid spawning a root PM2 daemon
        _ver=$(sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; '"$cmd"' --version 2>/dev/null | head -1' 2>/dev/null || echo "unknown")
        pass "$cmd $_ver"
    else
        fail "$cmd is not installed — install it and re-run."
        exit 1
    fi
done
if [[ $SKIP_MONGO == false ]]; then
    command -v mongod  &>/dev/null && pass "mongod  $(mongod --version | head -1)"  || { fail "mongod not installed";  exit 1; }
    command -v mongosh &>/dev/null && pass "mongosh $(mongosh --version | head -1)" || { fail "mongosh not installed"; exit 1; }
fi
# STEP: Git pull (DISABLED — pseudo pull to protect local code)
CURRENT=$((CURRENT + 1))
step "$CURRENT" "Git — pull latest code"

#   IMPORTANT: git stash + git pull are COMMENTED OUT to prevent      
#   overwriting local changes.                

# Pseudo pull: log what would happen, but don't actually touch git
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)

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

    # ── Original git pull code (COMMENTED OUT) ──
    # cd "$GIT_ROOT"
    # git stash --quiet 2>/dev/null || true
    # if git pull origin "$CURRENT_BRANCH" 2>&1 | tee -a "$DEPLOY_LOG"; then
    #     COMMIT=$(git log -1 --format="%h - %s (%ar)" 2>/dev/null || echo "unknown")
    #     pass "Updated to: $COMMIT"
    # else
    #     warn "Git pull failed — continuing with current local code"
    # fi
else
    warn "Not inside a Git repository — skipping pull"
fi

# STEP: MongoDB Replica Set 
if [[ $SKIP_MONGO == false ]]; then
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "MongoDB Replica Set  (ports 27017 · 27018 · 27019)"

    chmod +x "$MONGO_DIR/setup-replicaset.sh"
    bash "$MONGO_DIR/setup-replicaset.sh" | tee -a "$DEPLOY_LOG"
    pass "MongoDB replica set ready"
fi

# STEP: Backend dependencies 
CURRENT=$((CURRENT + 1))
step "$CURRENT" "Backend — dependencies + environment"

cd "$BACKEND_DIR"
if [[ $SKIP_BUILD == false ]]; then
    info "npm ci (production)..."
    npm ci --omit=dev 2>&1 | tail -5 | tee -a "$DEPLOY_LOG"
fi

# Copy production env file to the active .env
if [[ -f "$BACKEND_DIR/.env.production" ]]; then
    cp "$BACKEND_DIR/.env.production" "$BACKEND_DIR/.env"
    pass "Production .env applied"
else
    warn ".env.production not found — existing .env will be used"
fi

mkdir -p "$BACKEND_DIR/var/log/apps"
pass "Backend ready"

# STEP: Database migrations
CURRENT=$((CURRENT + 1))
step "$CURRENT" "Database — MongoDB migrations"

cd "$BACKEND_DIR"
if compgen -G "migrations/*.js" &>/dev/null; then

    # --- verify MongoDB is actually reachable before attempting migrations ---
    info "Checking MongoDB connectivity on port 27017..."
    _MONGO_UP=false
    for _i in $(seq 1 10); do
        if mongosh --port 27017 --quiet --eval "db.runCommand({ping:1})" &>/dev/null 2>&1; then
            _MONGO_UP=true
            break
        fi
        sleep 2
    done

    if [[ $_MONGO_UP == false ]]; then
        fail "MongoDB is not reachable on port 27017."
        fail "Either:"
        fail "  • Run the full deploy (without --skip-mongo) so the replica set is started first"
        fail "  • Or manually start MongoDB:  ./mongodb-replicaset/manage-replicaset.sh start"
        exit 1
    fi
    pass "MongoDB is reachable"

    _MIGRATION_URI=""
    if [[ -f "$BACKEND_DIR/.env" ]]; then
        _MIGRATION_URI=$(grep -E '^MONGODB_URI=' "$BACKEND_DIR/.env" | head -1 | cut -d'=' -f2- | tr -d '"'"'")
    fi

    if [[ -z "$_MIGRATION_URI" ]]; then
        warn "MONGODB_URI not found in backend/.env — migrations will use unauthenticated fallback"
    else
        info "Using authenticated MONGODB_URI for migrations"
    fi

    for MIGRATION_FILE in migrations/*.js; do
        info "  --> $(basename "$MIGRATION_FILE")"
        if MONGODB_URI="$_MIGRATION_URI" node "$MIGRATION_FILE" 2>&1 | tee -a "$DEPLOY_LOG"; then
            pass "  $(basename "$MIGRATION_FILE") applied"
        else
            fail "Migration failed: $(basename "$MIGRATION_FILE") — aborting deployment"
            exit 1
        fi
    done
    pass "All migrations applied"
else
    warn "No migration files found in backend/migrations — skipping"
fi

# STEP: Frontend build 
if [[ $SKIP_BUILD == false ]]; then
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "Frontend — npm install + Next.js production build"

    cd "$FRONTEND_DIR"
    info "npm ci..."
    npm ci 2>&1 | tail -5 | tee -a "$DEPLOY_LOG"

    info "next build..."
    npm run build 2>&1 | tail -20 | tee -a "$DEPLOY_LOG"

    mkdir -p "$FRONTEND_DIR/var/log"
    pass "Frontend build complete"
fi

# STEP: PM2 — rolling restart with health checks and rollback
CURRENT=$((CURRENT + 1))
step "$CURRENT" "PM2 — rolling restart with health checks"

cd "$SCRIPT_DIR"

# Ensure log directories exist and are writable by the real user
mkdir -p "$BACKEND_DIR/var/log/apps" "$FRONTEND_DIR/var/log"
chown -R "$REAL_USER:$REAL_USER" "$BACKEND_DIR/var" "$FRONTEND_DIR/var" 2>/dev/null || true

# Wait for MongoDB to be fully ready before starting backends
if [[ $SKIP_MONGO == false ]]; then
    info "Waiting for MongoDB replica set to accept connections..."
    MONGO_READY=false
    for i in $(seq 1 30); do
        if mongosh --port 27017 --quiet --eval "db.runCommand({ping:1})" &>/dev/null; then
            MONGO_READY=true
            break
        fi
        sleep 2
    done
    [[ $MONGO_READY == true ]] && pass "MongoDB is accepting connections" \
                                || warn "MongoDB may not be fully ready — backends will retry"
fi

# Detect fresh deploy vs re-deploy based on whether processes already exist
if ! sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; pm2 describe backend-3000 &>/dev/null'; then

    # Fresh deployment: clean start 
    info "Fresh deployment — starting all services from scratch..."

    # Kill only Stack 1 ports (do NOT touch Stack 3 ports 3005-3006)
    for port in 3000 3001 3002 3003 3004; do
        fuser -k "$port/tcp" 2>/dev/null || true
    done
    sleep 1

    # Delete only Stack 1 PM2 processes (preserve Stack 3)
    for proc in backend-3000 backend-3003 backend-3004 frontend-3001 frontend-3002; do
        sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; pm2 delete '"$proc"' 2>/dev/null || true'
    done
    sleep 2
    info "Starting via pm2/ecosystem.config.js..."
    sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; cd "'"$SCRIPT_DIR"'" && pm2 start "'"$PM2_CONFIG"'"' \
        2>&1 | tee -a "$DEPLOY_LOG"
    sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; pm2 save'
    pass "All services started (fresh deploy)"

else

    # Re-deployment: rolling restart one instance at a time 
    info "Re-deployment detected — performing zero-downtime rolling restart..."

    # Save current state so we can resurrect it on rollback
    info "Saving pre-restart state for rollback..."
    sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; pm2 save --force' 2>/dev/null || true

    # Rolling restart — backend instances (Express API)
    for PORT in 3000 3003 3004; do
        PROC_NAME="backend-$PORT"
        info "Restarting $PROC_NAME (port $PORT)..."
        sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; pm2 restart '"$PROC_NAME"' 2>/dev/null \
            || pm2 start "'"$PM2_CONFIG"'" --only '"$PROC_NAME"'' 2>&1 | tee -a "$DEPLOY_LOG" || true
        sleep 5

        # Health check with retries
        HEALTHY=false
        for i in $(seq 1 12); do
            if curl -sf --max-time 4 "http://localhost:$PORT/api/health" | grep -q '"status"' 2>/dev/null; then
                HEALTHY=true
                break
            fi
            sleep 3
        done

        if [[ $HEALTHY == true ]]; then
            pass "$PROC_NAME  healthy"
        else
            fail "$PROC_NAME health check failed — rolling back to previous state..."
            sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; pm2 resurrect' 2>&1 | tee -a "$DEPLOY_LOG" || true
            log_error "Rollback triggered: $PROC_NAME failed health check on port $PORT"
            exit 1
        fi
    done

    # Rolling restart — frontend instances (Next.js SSR)
    for PORT in 3001 3002; do
        PROC_NAME="frontend-$PORT"
        info "Restarting $PROC_NAME (port $PORT)..."
        sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; pm2 restart '"$PROC_NAME"' 2>/dev/null \
            || pm2 start "'"$PM2_CONFIG"'" --only '"$PROC_NAME"'' 2>&1 | tee -a "$DEPLOY_LOG" || true
        sleep 5

        # Health check with retries
        HEALTHY=false
        for i in $(seq 1 12); do
            if curl -sf --max-time 5 "http://localhost:$PORT" | grep -qi 'html' 2>/dev/null; then
                HEALTHY=true
                break
            fi
            sleep 3
        done

        if [[ $HEALTHY == true ]]; then
            pass "$PROC_NAME  healthy"
        else
            fail "$PROC_NAME health check failed — rolling back to previous state..."
            sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; pm2 resurrect' 2>&1 | tee -a "$DEPLOY_LOG" || true
            log_error "Rollback triggered: $PROC_NAME failed health check on port $PORT"
            exit 1
        fi
    done

    # Save the new healthy state
    sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; pm2 save'
    pass "Rolling restart complete — all 5 instances healthy"

fi

log ""
sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; pm2 list' 2>&1 | tee -a "$DEPLOY_LOG"
pass "All services launched"

# STEP: SSL certificate 
if [[ $SKIP_NGINX == false ]]; then
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "SSL certificate  (stack1.devops.local)"

    chmod +x "$NGINX_DIR/setup-ssl.sh"
    if [[ -f /etc/ssl/certs/stack1-ca.crt && -f /etc/ssl/certs/stack1.crt && -f /etc/ssl/private/stack1.key ]]; then
        pass "SSL certificate already exists (CA-signed) — skipping"
    else
        # Remove old self-signed cert if present, regenerate with local CA
        rm -f /etc/ssl/certs/stack1.crt /etc/ssl/private/stack1.key 2>/dev/null || true
        bash "$NGINX_DIR/setup-ssl.sh" 2>&1 | tee -a "$DEPLOY_LOG"
        pass "SSL certificate generated (CA-signed)"
    fi

    # STEP: Nginx load balancer 
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "Nginx - install + configure load balancer"

    chmod +x "$NGINX_DIR/install-nginx-config.sh"
    bash "$NGINX_DIR/install-nginx-config.sh" 2>&1 | tee -a "$DEPLOY_LOG"
    pass "Nginx configured and running"
fi

# Post-deploy smoke tests
sep
log "${BOLD}Health checks${NC}"
sleep 10

# Wait for backends to fully start (they need to connect to MongoDB)
info "Waiting for backend services to initialize..."
for port in 3000 3003 3004; do
    READY=false
    for i in $(seq 1 15); do
        if curl -sf --max-time 3 "http://localhost:$port/api/health" | grep -q '"status"' 2>/dev/null; then
            READY=true
            break
        fi
        sleep 2
    done
    if [[ $READY == true ]]; then
        pass "Backend  :$port  healthy"
    else
        warn "Backend  :$port  not responding — check: pm2 logs backend-$port"
    fi
done

for port in 3001 3002; do
    READY=false
    for i in $(seq 1 10); do
        if curl -sf --max-time 5 "http://localhost:$port" | grep -qi 'html' 2>/dev/null; then
            READY=true
            break
        fi
        sleep 2
    done
    if [[ $READY == true ]]; then
        pass "Frontend :$port  healthy"
    else
        warn "Frontend :$port  not responding — check: pm2 logs frontend-$port"
    fi
done

if [[ $SKIP_NGINX == false ]]; then
    curl -sk --max-time 5 "https://stack1.devops.local/health" | grep -q '"status"' 2>/dev/null \
        && pass "Nginx HTTPS  -->  https://stack1.devops.local  healthy" \
        || warn "Nginx HTTPS  -->  not reachable  (add 127.0.0.1 stack1.devops.local to /etc/hosts)"
fi

# Final summary
sep
log ""
log "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
log "${BOLD}${GREEN}║   Stack 1 deployed successfully!                         ║${NC}"
log "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
log ""
log "  ${CYAN}Frontend${NC}"
log "    https://stack1.devops.local         (Nginx)"
log "    http://localhost:3001               (direct)"
log "    http://localhost:3002               (direct)"
log ""
log "  ${CYAN}Backend API${NC}"
log "    https://stack1.devops.local/api/    (Nginx)"
log "    https://stack1.devops.local/api-docs"
log "    http://localhost:3000/api/health    (direct)"
log ""
log "  ${CYAN}MongoDB  rs0${NC}"
log "    localhost:27017  (primary)"
log "    localhost:27018  (secondary)"
log "    localhost:27019  (secondary)"
log ""
log "  ${CYAN}Useful commands${NC}"
log "    pm2 list                                    # process status"
log "    pm2 logs                                    # tail all logs"
log "    ./mongodb-replicaset/manage-replicaset.sh status"
log "    ./mongodb-replicaset/test-failover.sh       # failover test"
log "    ./health_check_stack1.sh                    # live health polling"
log ""
log "  Deploy log: $DEPLOY_LOG"
log ""

log_info "Deployment completed successfully"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)       show_usage; exit $EXIT_SUCCESS ;;
        --skip-mongo)    SKIP_MONGO=true ;;
        --skip-nginx)    SKIP_NGINX=true ;;
        --skip-build)    SKIP_BUILD=true ;;
        -v|--verbose)    set -x ;;
        *)               warn "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"