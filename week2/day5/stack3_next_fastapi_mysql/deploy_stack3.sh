#!/bin/bash
set -euo pipefail

# Script: deploy_stack3.sh
# Description: Full Stack 3 deployment - MySQL setup, FastAPI backend (3 instances via systemd),
#              Next.js frontend (2 instances via PM2), SSL certificate, Nginx load balancer.
#              Use --skip-* flags to re-run only the parts you need.
# Author: Aakash
# Date: 2026-03-02
# Usage: sudo ./deploy_stack3.sh [OPTIONS]

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

# Path setup for nvm/node
for _nvm_bin in \
    "/home/$SUDO_USER/.nvm/versions/node/"*/bin \
    "$HOME/.nvm/versions/node/"*/bin \
    /usr/local/bin \
    /usr/bin; do
    [[ -d "$_nvm_bin" && ":$PATH:" != *":$_nvm_bin:"* ]] && PATH="$_nvm_bin:$PATH"
done
export PATH

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/backend"
FRONTEND_DIR="$SCRIPT_DIR/frontend"
MYSQL_DIR="$SCRIPT_DIR/mysql"
NGINX_DIR="$SCRIPT_DIR/nginx"
SYSTEMD_DIR="$SCRIPT_DIR/systemd"
PM2_CONFIG="$SCRIPT_DIR/pm2/nextjs-ecosystem.config.js"
LOG_DIR="$SCRIPT_DIR/var/log/apps"
DEPLOY_LOG="$LOG_DIR/deploy-$(date +%Y%m%d-%H%M%S).log"
LOG_FILE="$LOG_DIR/$(basename "$0" .sh).log"

mkdir -p "$LOG_DIR"

# Flags
SKIP_MYSQL=false
SKIP_NGINX=false
SKIP_BUILD=false

# Detect real user when running under sudo
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo ~"$REAL_USER")

# Logging functions
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }

log()  { echo -e "$1" | tee -a "$DEPLOY_LOG"; }
pass() { log "${GREEN}    $1${NC}"; }
fail() { log "${RED}    $1${NC}"; }
info() { log "${BLUE}    $1${NC}"; }
warn() { log "${YELLOW}    $1${NC}"; }
sep()  { log "${CYAN}------------------------------------------------------------${NC}"; }
step() { log ""; sep; log "${BOLD}${BLUE}  [$1/$TOTAL_STEPS] $2${NC}"; sep; }

# Help function
show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Full Stack 3 deployment - FastAPI + Next.js + MySQL with Nginx load balancer.

OPTIONS:
  -h, --help          Show this help message
  --skip-mysql        Skip MySQL database setup (assumes it's already configured)
  --skip-nginx        Skip Nginx install and SSL config
  --skip-build        Skip pip install and Next.js build steps
  -v, --verbose       Enable verbose output

EXAMPLES:
  sudo ./deploy_stack3.sh                            # fresh full deployment
  sudo ./deploy_stack3.sh --skip-mysql               # re-deploy app only
       ./deploy_stack3.sh --skip-mysql --skip-nginx  # no sudo needed
EOF
}

# Main function
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
    [[ $SKIP_MYSQL  == false ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    TOTAL_STEPS=$((TOTAL_STEPS + 1))   # backend dependencies
    TOTAL_STEPS=$((TOTAL_STEPS + 1))   # migrations
    [[ $SKIP_BUILD  == false ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
    TOTAL_STEPS=$((TOTAL_STEPS + 1))   # FastAPI systemd services
    TOTAL_STEPS=$((TOTAL_STEPS + 1))   # PM2 Next.js
    [[ $SKIP_NGINX  == false ]] && TOTAL_STEPS=$((TOTAL_STEPS + 2))  # SSL + Nginx

    CURRENT=0

    log ""
    log "${BOLD}${BLUE}+============================================================+${NC}"
    log "${BOLD}${BLUE}|  Stack 3 Deployment - Next.js + FastAPI + MySQL            |${NC}"
    log "${BOLD}${BLUE}|  Started: $(date)                    |${NC}"
    log "${BOLD}${BLUE}+============================================================+${NC}"
    log ""

    # Pre-flight checks
    sep
    log "${BOLD}Pre-flight checks${NC}"
    
    for cmd in python3 pip3 node npm pm2; do
        if command -v "$cmd" &>/dev/null; then
            _ver=$("$cmd" --version 2>/dev/null | head -1 || echo "unknown")
            pass "$cmd $_ver"
        else
            fail "$cmd is not installed - install it and re-run."
            exit 1
        fi
    done
    
    if [[ $SKIP_MYSQL == false ]]; then
        command -v mysql &>/dev/null && pass "mysql $(mysql --version 2>/dev/null | head -1)" || { fail "mysql client not installed"; exit 1; }
    fi

    # STEP: Git pull (DISABLED - pseudo pull to protect local code)
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "Git - pull latest code"

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

        # Original git pull code (COMMENTED OUT)
        # cd "$GIT_ROOT"
        # git stash --quiet 2>/dev/null || true
        # if git pull origin "$CURRENT_BRANCH" 2>&1 | tee -a "$DEPLOY_LOG"; then
        #     COMMIT=$(git log -1 --format="%h - %s (%ar)" 2>/dev/null || echo "unknown")
        #     pass "Updated to: $COMMIT"
        # else
        #     warn "Git pull failed - continuing with current local code"
        # fi
    else
        warn "Not inside a Git repository - skipping pull"
    fi

    # STEP: MySQL Setup
    if [[ $SKIP_MYSQL == false ]]; then
        CURRENT=$((CURRENT + 1))
        step "$CURRENT" "MySQL - database setup and optimization"

        # Check if MySQL is running
        if ! systemctl is-active --quiet mysql 2>/dev/null && ! pgrep -x mysqld >/dev/null 2>&1; then
            info "Starting MySQL service..."
            sudo systemctl start mysql 2>/dev/null || sudo service mysql start 2>/dev/null || true
            sleep 3
        fi

        # Test MySQL connection
        if mysql -u root -pRoot@123 -e "SELECT 1" &>/dev/null 2>&1; then
            pass "MySQL root access verified"
        else
            warn "MySQL root access requires password - attempting with authentication"
        fi

        # Create database and user
        info "Creating database and user..."
        SQL_SETUP="CREATE DATABASE IF NOT EXISTS fastapidb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'fastapiuser'@'localhost' IDENTIFIED BY 'Fast@123';
GRANT ALL PRIVILEGES ON fastapidb.* TO 'fastapiuser'@'localhost';
FLUSH PRIVILEGES;"
        echo "$SQL_SETUP" | sudo mysql 2>/dev/null || echo "$SQL_SETUP" | mysql -u root -pRoot@123 2>/dev/null || true
        pass "Database 'fastapidb' and user 'fastapiuser' ready"

        # Apply optimization config if not already present
        if [[ -f "$MYSQL_DIR/optimization.cnf" ]]; then
            info "MySQL optimization config available at: $MYSQL_DIR/optimization.cnf"
            info "To apply: sudo cp $MYSQL_DIR/optimization.cnf /etc/mysql/mysql.conf.d/"
            info "Then: sudo systemctl restart mysql"
        fi

        pass "MySQL setup complete"
    fi

    # STEP: Backend dependencies
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "Backend - Python dependencies + environment"

    cd "$BACKEND_DIR"

    # Create virtual environment if not exists
    if [[ ! -d "venv" ]]; then
        info "Creating Python virtual environment..."
        python3 -m venv venv
    fi

    # Activate and install dependencies
    if [[ $SKIP_BUILD == false ]]; then
        info "Installing Python dependencies..."
        source venv/bin/activate
        pip install --upgrade pip 2>&1 | tail -3 | tee -a "$DEPLOY_LOG"
        pip install -r requirements.txt 2>&1 | tail -5 | tee -a "$DEPLOY_LOG"
        deactivate
    fi

    # Copy production env file
    if [[ -f "$SCRIPT_DIR/.env.production" ]]; then
        cp "$SCRIPT_DIR/.env.production" "$BACKEND_DIR/.env"
        pass "Production .env applied to backend"
    else
        warn ".env.production not found - using existing .env"
    fi

    mkdir -p "$BACKEND_DIR/var/log/apps"
    pass "Backend ready"

    # STEP: Database migrations
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "Database - MySQL migrations"

    cd "$BACKEND_DIR"

    # Check MySQL connectivity
    info "Checking MySQL connectivity..."
    if mysql -u fastapiuser -pFast@123 -e "SELECT 1" fastapidb &>/dev/null 2>&1; then
        pass "MySQL connection verified"
    else
        fail "Cannot connect to MySQL as fastapiuser"
        fail "Please ensure MySQL is running and user is created"
        exit 1
    fi

    # Run SQL migrations
    if compgen -G "migrations/*.sql" &>/dev/null; then
        for MIGRATION_FILE in migrations/*.sql; do
            info "  --> $(basename "$MIGRATION_FILE")"
            if mysql -u fastapiuser -pFast@123 fastapidb < "$MIGRATION_FILE" 2>&1 | tee -a "$DEPLOY_LOG"; then
                pass "  $(basename "$MIGRATION_FILE") applied"
            else
                warn "  Migration may have already been applied: $(basename "$MIGRATION_FILE")"
            fi
        done
        pass "All migrations processed"
    else
        warn "No migration files found in backend/migrations - skipping"
    fi

    # STEP: Frontend build
    if [[ $SKIP_BUILD == false ]]; then
        CURRENT=$((CURRENT + 1))
        step "$CURRENT" "Frontend - npm install + Next.js production build"

        cd "$FRONTEND_DIR"
        info "npm ci..."
        npm ci 2>&1 | tail -5 | tee -a "$DEPLOY_LOG"

        info "next build..."
        npm run build 2>&1 | tail -20 | tee -a "$DEPLOY_LOG"

        mkdir -p "$FRONTEND_DIR/var/log"
        pass "Frontend build complete"
    fi

    # STEP: FastAPI systemd services
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "FastAPI - systemd services (ports 8003, 8004, 8005)"

    cd "$SCRIPT_DIR"

    # Ensure log directory exists and is writable
    mkdir -p "$LOG_DIR"
    chown -R "$REAL_USER:$REAL_USER" "$LOG_DIR" 2>/dev/null || true

    # Install systemd service files
    for port in 8003 8004 8005; do
        SERVICE_FILE="$SYSTEMD_DIR/fastapi-$port.service"
        if [[ -f "$SERVICE_FILE" ]]; then
            info "Installing fastapi-$port.service..."
            sudo cp "$SERVICE_FILE" /etc/systemd/system/
        fi
    done

    # Reload systemd
    sudo systemctl daemon-reload

    # Stop existing services and kill any stale processes holding the ports
    for port in 8003 8004 8005; do
        sudo systemctl stop "fastapi-$port" 2>/dev/null || true
        # Kill any non-systemd uvicorn processes occupying the port
        local pids
        pids=$(sudo lsof -i :"$port" -t 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            info "Killing stale processes on port $port"
            echo "$pids" | xargs sudo kill 2>/dev/null || true
            sleep 1
        fi
    done

    # Rolling restart with health checks
    info "Starting FastAPI instances with health checks..."
    
    for port in 8003 8004 8005; do
        info "Starting fastapi-$port..."
        sudo systemctl enable "fastapi-$port" 2>/dev/null || true
        sudo systemctl start "fastapi-$port"
        
        # Wait and health check
        sleep 5
        HEALTHY=false
        for i in $(seq 1 12); do
            if curl -sf --max-time 4 "http://localhost:$port/health" | grep -q '"status"' 2>/dev/null; then
                HEALTHY=true
                break
            fi
            sleep 3
        done

        if [[ $HEALTHY == true ]]; then
            pass "FastAPI :$port healthy"
        else
            fail "FastAPI :$port health check failed"
            warn "Check logs: journalctl -u fastapi-$port -f"
            # Continue with other instances instead of exiting
        fi
    done

    pass "FastAPI services deployed"

    # STEP: PM2 - Next.js frontend
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "PM2 - Next.js frontend (ports 3005, 3006)"

    cd "$SCRIPT_DIR"

    # Ensure log directories exist
    mkdir -p "$LOG_DIR"
    chown -R "$REAL_USER:$REAL_USER" "$SCRIPT_DIR/var" 2>/dev/null || true

    # Check if PM2 processes exist
    if ! sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; pm2 describe nextjs-3005 &>/dev/null'; then
        # Fresh deployment
        info "Fresh deployment - starting Next.js instances..."
        # Delete only Stack 3 PM2 processes (preserve Stack 1)
        for proc in nextjs-3005 nextjs-3006; do
            sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; pm2 delete '"$proc"' 2>/dev/null || true'
        done
        sleep 2
        sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; cd "'"$SCRIPT_DIR"'" && pm2 start "'"$PM2_CONFIG"'"' \
            2>&1 | tee -a "$DEPLOY_LOG"
        sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; pm2 save'
        pass "Next.js instances started (fresh deploy)"
    else
        # Re-deployment with rolling restart
        info "Re-deployment - performing rolling restart..."

        # Save current state for rollback
        sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; pm2 save --force' 2>/dev/null || true

        for port in 3005 3006; do
            PROC_NAME="nextjs-$port"
            info "Restarting $PROC_NAME (port $port)..."
            sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; pm2 restart '"$PROC_NAME"' 2>/dev/null \
                || pm2 start "'"$PM2_CONFIG"'" --only '"$PROC_NAME"'' 2>&1 | tee -a "$DEPLOY_LOG" || true
            sleep 5

            # Health check
            HEALTHY=false
            for i in $(seq 1 12); do
                if curl -sf --max-time 5 "http://localhost:$port" | grep -qi 'html' 2>/dev/null; then
                    HEALTHY=true
                    break
                fi
                sleep 3
            done

            if [[ $HEALTHY == true ]]; then
                pass "$PROC_NAME healthy"
            else
                fail "$PROC_NAME health check failed - rolling back..."
                sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; pm2 resurrect' 2>&1 | tee -a "$DEPLOY_LOG" || true
                log_error "Rollback triggered: $PROC_NAME failed health check"
                exit 1
            fi
        done

        sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; pm2 save'
        pass "Rolling restart complete - all instances healthy"
    fi

    log ""
    sudo -u "$REAL_USER" bash -c 'export PATH="'"$PATH"'"; pm2 list' 2>&1 | tee -a "$DEPLOY_LOG"
    pass "All Next.js services launched"

    # STEP: SSL certificate
    if [[ $SKIP_NGINX == false ]]; then
        CURRENT=$((CURRENT + 1))
        step "$CURRENT" "SSL certificate (stack3.devops.local)"

        if [[ -f /etc/ssl/certs/stack3.crt && -f /etc/ssl/private/stack3.key ]]; then
            pass "SSL certificate already exists - skipping"
        else
            info "Generating self-signed SSL certificate..."
            
            # Generate private key
            sudo openssl genrsa -out /etc/ssl/private/stack3.key 2048 2>/dev/null
            
            # Generate certificate
            sudo openssl req -new -x509 \
                -key /etc/ssl/private/stack3.key \
                -out /etc/ssl/certs/stack3.crt \
                -days 365 \
                -subj "/C=US/ST=DevOps/L=Local/O=Stack3/CN=stack3.devops.local" \
                2>/dev/null
            
            sudo chmod 600 /etc/ssl/private/stack3.key
            sudo chmod 644 /etc/ssl/certs/stack3.crt
            
            pass "SSL certificate generated"
        fi

        # STEP: Nginx load balancer
        CURRENT=$((CURRENT + 1))
        step "$CURRENT" "Nginx - install + configure load balancer"

        # Install Nginx if not present
        if ! command -v nginx &>/dev/null; then
            info "Installing Nginx..."
            sudo apt-get update -qq
            sudo apt-get install -y nginx 2>&1 | tail -5 | tee -a "$DEPLOY_LOG"
        fi

        # Create cache directory
        sudo mkdir -p /var/cache/nginx/stack3
        sudo chown www-data:www-data /var/cache/nginx/stack3

        # Install configuration
        info "Installing Nginx configuration..."
        sudo cp "$NGINX_DIR/stack3.conf" /etc/nginx/sites-available/
        
        # Enable site
        sudo ln -sf /etc/nginx/sites-available/stack3.conf /etc/nginx/sites-enabled/
        
        # Remove default site if exists
        sudo rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

        # Test configuration
        if sudo nginx -t 2>&1 | tee -a "$DEPLOY_LOG"; then
            pass "Nginx configuration valid"
        else
            fail "Nginx configuration test failed"
            exit 1
        fi

        # Reload Nginx
        sudo systemctl reload nginx 2>/dev/null || sudo systemctl restart nginx
        pass "Nginx configured and running"

        # Add to /etc/hosts if not present
        if ! grep -q "stack3.devops.local" /etc/hosts 2>/dev/null; then
            echo "127.0.0.1  stack3.devops.local" | sudo tee -a /etc/hosts >/dev/null
            pass "Added stack3.devops.local to /etc/hosts"
        fi
    fi

    # Post-deploy smoke tests
    sep
    log "${BOLD}Health checks${NC}"
    sleep 10

    # FastAPI backends
    info "Checking FastAPI backends..."
    for port in 8003 8004 8005; do
        READY=false
        for i in $(seq 1 15); do
            if curl -sf --max-time 3 "http://localhost:$port/health" | grep -q '"status"' 2>/dev/null; then
                READY=true
                break
            fi
            sleep 2
        done
        if [[ $READY == true ]]; then
            pass "FastAPI :$port healthy"
        else
            warn "FastAPI :$port not responding - check: journalctl -u fastapi-$port"
        fi
    done

    # Next.js frontends
    for port in 3005 3006; do
        READY=false
        for i in $(seq 1 10); do
            if curl -sf --max-time 5 "http://localhost:$port" | grep -qi 'html' 2>/dev/null; then
                READY=true
                break
            fi
            sleep 2
        done
        if [[ $READY == true ]]; then
            pass "Next.js :$port healthy"
        else
            warn "Next.js :$port not responding - check: pm2 logs nextjs-$port"
        fi
    done

    # Nginx HTTPS
    if [[ $SKIP_NGINX == false ]]; then
        curl -sk --max-time 5 "https://stack3.devops.local/health" | grep -q '"status"' 2>/dev/null \
            && pass "Nginx HTTPS --> https://stack3.devops.local healthy" \
            || warn "Nginx HTTPS --> not reachable (check /etc/hosts)"
    fi

    # Final summary
    sep
    log ""
    log "${BOLD}${GREEN}+============================================================+${NC}"
    log "${BOLD}${GREEN}|   Stack 3 deployed successfully!                           |${NC}"
    log "${BOLD}${GREEN}+============================================================+${NC}"
    log ""
    log "  ${CYAN}Frontend${NC}"
    log "    https://stack3.devops.local         (Nginx)"
    log "    http://localhost:3005               (direct)"
    log "    http://localhost:3006               (direct)"
    log ""
    log "  ${CYAN}Backend API${NC}"
    log "    https://stack3.devops.local/api/    (Nginx)"
    log "    https://stack3.devops.local/docs    (Swagger)"
    log "    http://localhost:8003/health        (direct)"
    log "    http://localhost:8004/health        (direct)"
    log "    http://localhost:8005/health        (direct)"
    log ""
    log "  ${CYAN}MySQL${NC}"
    log "    localhost:3306 (database: fastapidb)"
    log ""
    log "  ${CYAN}Useful commands${NC}"
    log "    pm2 list                                    # Next.js process status"
    log "    pm2 logs                                    # tail all PM2 logs"
    log "    sudo systemctl status fastapi-8003          # FastAPI status"
    log "    journalctl -u fastapi-8003 -f               # FastAPI logs"
    log "    ./health_check_stack3.sh                    # live health polling"
    log ""
    log "  Deploy log: $DEPLOY_LOG"
    log ""

    log_info "Deployment completed successfully"
}

# Parse arguments
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
