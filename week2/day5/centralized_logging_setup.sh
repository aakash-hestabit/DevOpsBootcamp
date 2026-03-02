#!/bin/bash
set -euo pipefail

# Script: centralized_logging_setup.sh
# Description: Configure centralized logging for all 3 stacks.
#              - Set up directory structure under /var/log/centralized/
#              - Configure rsyslog forwarding rules
#              - Configure logrotate for all log sources
#              - Aggregate Nginx, application, database, PM2, and system logs
# Author: Aakash
# Date: 2026-03-02
# Usage: sudo ./centralized_logging_setup.sh [--help]

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
CENTRAL_LOG="/var/log/centralized"
LOGGING_DIR="$SCRIPT_DIR/logging"

mkdir -p "$LOG_DIR" "$LOGGING_DIR"

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

Configure centralized logging for all 3 production stacks.

OPTIONS:
  -h, --help      Show this help message
  -v, --verbose   Enable verbose output

CREATES:
  /var/log/centralized/
  ├── nginx/           (access.log, error.log)
  ├── stack1/
  │   ├── nodejs-api/  (express logs)
  │   ├── nextjs-app/  (SSR logs)
  │   └── mongodb/     (mongod logs)
  ├── stack2/
  │   ├── laravel/     (application logs)
  │   └── mysql/       (query + slow logs)
  └── stack3/
      ├── fastapi/     (uvicorn logs)
      ├── nextjs/      (SSR logs)
      └── mysql/       (query + slow logs)
EOF
}

main() {
    log_info "Centralized logging setup started"

    if [[ $EUID -ne 0 ]]; then
        log_error "Root required. Run: sudo $0"
        exit $EXIT_ERROR
    fi

    log ""
    log "${BOLD}${BLUE}+============================================================+${NC}"
    log "${BOLD}${BLUE}|  Centralized Logging Setup                                 |${NC}"
    log "${BOLD}${BLUE}|  $(date)                              |${NC}"
    log "${BOLD}${BLUE}+============================================================+${NC}"

    # STEP 1: Create directory structure
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "Create log directory structure"

    local DIRS=(
        "$CENTRAL_LOG/nginx"
        "$CENTRAL_LOG/stack1/nodejs-api"
        "$CENTRAL_LOG/stack1/nextjs-app"
        "$CENTRAL_LOG/stack1/mongodb"
        "$CENTRAL_LOG/stack2/laravel"
        "$CENTRAL_LOG/stack2/mysql"
        "$CENTRAL_LOG/stack3/fastapi"
        "$CENTRAL_LOG/stack3/nextjs"
        "$CENTRAL_LOG/stack3/mysql"
    )

    for dir in "${DIRS[@]}"; do
        mkdir -p "$dir"
        info "Created: $dir"
    done

    # Set permissions
    chown -R syslog:adm "$CENTRAL_LOG"
    chmod -R 750 "$CENTRAL_LOG"
    pass "Directory structure created"

    # STEP 2: Deploy rsyslog configuration
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "Configure rsyslog forwarding"

    cat > /etc/rsyslog.d/50-devops-stacks.conf <<'RSYSLOG_CONF'
# DevOps Bootcamp — Centralized logging for all 3 stacks
# File: /etc/rsyslog.d/50-devops-stacks.conf

# --- Nginx ---
if $programname == 'nginx' and $msg contains 'stack1' then /var/log/centralized/nginx/stack1-access.log
if $programname == 'nginx' and $msg contains 'stack2' then /var/log/centralized/nginx/stack2-access.log
if $programname == 'nginx' and $msg contains 'stack3' then /var/log/centralized/nginx/stack3-access.log
if $programname == 'nginx' and $syslogseverity <= 4 then /var/log/centralized/nginx/error.log

# --- Stack 1: Node.js ---
if $programname startswith 'backend-' then /var/log/centralized/stack1/nodejs-api/express.log
if $programname startswith 'frontend-' then /var/log/centralized/stack1/nextjs-app/nextjs.log

# --- Stack 2: Laravel ---
if $programname startswith 'laravel-app' then /var/log/centralized/stack2/laravel/application.log
if $programname startswith 'laravel-worker' then /var/log/centralized/stack2/laravel/worker.log

# --- Stack 3: FastAPI ---
if $programname startswith 'fastapi-' then /var/log/centralized/stack3/fastapi/uvicorn.log
if $programname startswith 'nextjs-' then /var/log/centralized/stack3/nextjs/nextjs.log

# --- MySQL ---
if $programname == 'mysqld' then /var/log/centralized/stack2/mysql/mysql.log
if $programname == 'mysqld' and $msg contains 'slow' then /var/log/centralized/stack2/mysql/slow-query.log

# --- MongoDB ---
if $programname == 'mongod' then /var/log/centralized/stack1/mongodb/mongod.log
RSYSLOG_CONF

    # Test and restart rsyslog
    if rsyslogd -N1 2>&1 | grep -q "error" 2>/dev/null; then
        warn "rsyslog config has warnings (non-critical)"
    fi
    systemctl restart rsyslog 2>/dev/null || true
    pass "rsyslog configuration deployed"

    # STEP 3: Deploy logrotate configuration
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "Configure log rotation"

    cat > /etc/logrotate.d/devops-stacks <<'LOGROTATE_CONF'
# DevOps Bootcamp — Log rotation for all stacks

# Nginx access logs (30 days)
/var/log/centralized/nginx/*-access.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0640 www-data adm
    sharedscripts
    postrotate
        [ -f /var/run/nginx.pid ] && kill -USR1 $(cat /var/run/nginx.pid) 2>/dev/null || true
    endscript
}

# Nginx error logs (90 days)
/var/log/centralized/nginx/error.log {
    daily
    rotate 90
    compress
    delaycompress
    missingok
    notifempty
    create 0640 www-data adm
}

# Application logs - all stacks (60 days)
/var/log/centralized/stack1/nodejs-api/*.log
/var/log/centralized/stack1/nextjs-app/*.log
/var/log/centralized/stack2/laravel/*.log
/var/log/centralized/stack3/fastapi/*.log
/var/log/centralized/stack3/nextjs/*.log {
    daily
    rotate 60
    compress
    delaycompress
    missingok
    notifempty
    create 0640 syslog adm
    copytruncate
}

# Database logs (90 days)
/var/log/centralized/stack1/mongodb/*.log
/var/log/centralized/stack2/mysql/*.log
/var/log/centralized/stack3/mysql/*.log {
    daily
    rotate 90
    compress
    delaycompress
    missingok
    notifempty
    create 0640 syslog adm
    copytruncate
}
LOGROTATE_CONF

    pass "Logrotate configuration deployed"

    # STEP 4: Create symlinks for easy access
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "Create convenience symlinks"

    # Symlink from app directories to centralized logs
    local APP_LOG_DIRS=(
        "$SCRIPT_DIR/stack1_next_node_mongodb/var/log/apps"
        "$SCRIPT_DIR/stack2_laravel_mysql_api/var/log/apps"
        "$SCRIPT_DIR/stack3_next_fastapi_mysql/var/log/apps"
    )

    for dir in "${APP_LOG_DIRS[@]}"; do
        mkdir -p "$dir"
    done

    # Create symlink in each stack pointing to centralized logs
    ln -sf "$CENTRAL_LOG/stack1" "$SCRIPT_DIR/stack1_next_node_mongodb/var/log/centralized" 2>/dev/null || true
    ln -sf "$CENTRAL_LOG/stack2" "$SCRIPT_DIR/stack2_laravel_mysql_api/var/log/centralized" 2>/dev/null || true
    ln -sf "$CENTRAL_LOG/stack3" "$SCRIPT_DIR/stack3_next_fastapi_mysql/var/log/centralized" 2>/dev/null || true

    pass "Symlinks created"

    # STEP 5: Deploy log analyzer script
    CURRENT=$((CURRENT + 1))
    step "$CURRENT" "Deploy log analyzer"

    info "Log analyzer: logging/log_analyzer.sh"
    info "rsyslog config: /etc/rsyslog.d/50-devops-stacks.conf"
    info "logrotate config: /etc/logrotate.d/devops-stacks"
    pass "Log analyzer ready"

    # Summary
    sep
    log ""
    log "${BOLD}${GREEN}+============================================================+${NC}"
    log "${BOLD}${GREEN}|  Centralized logging configured                            |${NC}"
    log "${BOLD}${GREEN}+============================================================+${NC}"
    log ""
    log "  ${CYAN}Log directory:${NC}    $CENTRAL_LOG/"
    log "  ${CYAN}Retention:${NC}"
    log "    Access logs:      30 days"
    log "    Error logs:       90 days"
    log "    Application logs: 60 days"
    log "    Database logs:    90 days"
    log "  ${CYAN}Rotation:${NC}         Daily, compress after 1 day"
    log ""
    log "  ${CYAN}Useful commands:${NC}"
    log "    tail -f $CENTRAL_LOG/nginx/error.log"
    log "    ./logging/log_analyzer.sh --stack 1"
    log "    logrotate -d /etc/logrotate.d/devops-stacks"
    log ""

    log_info "Centralized logging setup completed"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)       show_usage; exit $EXIT_SUCCESS ;;
        -v|--verbose)    set -x ;;
        *)               log_error "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
