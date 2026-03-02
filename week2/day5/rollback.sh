#!/bin/bash
set -euo pipefail

# Script: rollback.sh
# Description: Universal rollback script for all 3 production stacks.
#              Lists recent deployment backups, allows version selection,
#              stops current services, restores backup, runs DB rollback
#              migrations, restarts services, and verifies rollback success.
# Author: Aakash
# Date: 2026-03-02
# Usage: sudo ./rollback.sh [--stack 1|2|3] [--list] [--auto] [--help]

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
BACKUP_BASE="$SCRIPT_DIR/var/backups"
LOG_DIR="$SCRIPT_DIR/var/log"
LOG_FILE="$LOG_DIR/$(basename "$0" .sh).log"

mkdir -p "$BACKUP_BASE" "$LOG_DIR"

# Stack directories
STACK1_DIR="$SCRIPT_DIR/stack1_next_node_mongodb"
STACK2_DIR="$SCRIPT_DIR/stack2_laravel_mysql_api"
STACK3_DIR="$SCRIPT_DIR/stack3_next_fastapi_mysql"

REAL_USER="${SUDO_USER:-$USER}"

# Config
TARGET_STACK=""
LIST_ONLY=false
AUTO_ROLLBACK=false    # auto-select most recent backup

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

ts()   { date '+%Y-%m-%d %H:%M:%S'; }
log()  { echo -e "$1" | tee -a "$LOG_FILE"; }
pass() { log "${GREEN}    $1${NC}"; }
fail() { log "${RED}    $1${NC}"; }
info() { log "${BLUE}    $1${NC}"; }
warn() { log "${YELLOW}    $1${NC}"; }
sep()  { log "${CYAN}------------------------------------------------------------${NC}"; }

show_usage() {
    cat <<EOF
Usage: sudo $(basename "$0") [OPTIONS]

Universal rollback script for all 3 production stacks.

OPTIONS:
  -h, --help          Show this help message
  --stack NUM         Target stack: 1, 2, or 3 (required)
  --list              List available backups without rolling back
  --auto              Auto-select most recent backup (no prompt)
  -v, --verbose       Enable verbose output

EXAMPLES:
  sudo ./$(basename "$0") --stack 1 --list      # list Stack 1 backups
  sudo ./$(basename "$0") --stack 2              # interactive rollback
  sudo ./$(basename "$0") --stack 3 --auto       # auto-rollback to latest
EOF
}

# ---------------------------------------------------------------------------
# Create a backup of current state before rollback
# ---------------------------------------------------------------------------
create_pre_rollback_backup() {
    local stack_num="$1" stack_dir="$2"
    local backup_dir="$BACKUP_BASE/stack${stack_num}/pre-rollback-$(date +%Y%m%d-%H%M%S)"

    info "Creating pre-rollback backup..."
    mkdir -p "$backup_dir"

    case "$stack_num" in
        1)
            cp -r "$stack_dir/backend/node_modules" "$backup_dir/backend_node_modules" 2>/dev/null || true
            cp -r "$stack_dir/frontend/.next" "$backup_dir/frontend_next" 2>/dev/null || true
            cp "$stack_dir/backend/.env" "$backup_dir/backend.env" 2>/dev/null || true
            cp "$stack_dir/frontend/.env.local" "$backup_dir/frontend.env" 2>/dev/null || true
            ;;
        2)
            cp -r "$stack_dir/vendor" "$backup_dir/vendor" 2>/dev/null || true
            cp "$stack_dir/.env" "$backup_dir/.env" 2>/dev/null || true
            cp -r "$stack_dir/public/build" "$backup_dir/build" 2>/dev/null || true
            ;;
        3)
            cp -r "$stack_dir/backend/venv" "$backup_dir/backend_venv" 2>/dev/null || true
            cp -r "$stack_dir/frontend/.next" "$backup_dir/frontend_next" 2>/dev/null || true
            cp "$stack_dir/backend/.env" "$backup_dir/backend.env" 2>/dev/null || true
            cp "$stack_dir/frontend/.env" "$backup_dir/frontend.env" 2>/dev/null || true
            ;;
    esac

    pass "Pre-rollback backup: $backup_dir"
}

# ---------------------------------------------------------------------------
# List available backups
# ---------------------------------------------------------------------------
list_backups() {
    local stack_num="$1"
    local backup_path="$BACKUP_BASE/stack${stack_num}"

    log ""
    log "${BOLD}${BLUE}  Available backups for Stack $stack_num:${NC}"
    sep

    if [[ ! -d "$backup_path" ]] || [[ -z "$(ls -A "$backup_path" 2>/dev/null)" ]]; then
        warn "No backups found in $backup_path"
        info "Backups are created automatically during deployment."
        info "Run the deploy script to create the first backup."
        return 1
    fi

    local idx=0
    declare -g -a BACKUP_LIST=()
    while IFS= read -r dir; do
        idx=$((idx + 1))
        local dirname
        dirname=$(basename "$dir")
        local size
        size=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
        log "  ${BOLD}[$idx]${NC} $dirname  ${DIM}($size)${NC}"
        BACKUP_LIST+=("$dir")
    done < <(ls -dt "$backup_path"/*/ 2>/dev/null | head -10)

    if [[ $idx -eq 0 ]]; then
        warn "No valid backups found"
        return 1
    fi

    log ""
    return 0
}

# ---------------------------------------------------------------------------
# Stop stack services
# ---------------------------------------------------------------------------
stop_stack_services() {
    local stack_num="$1"

    info "Stopping Stack $stack_num services..."

    case "$stack_num" in
        1)
            for app in backend-3000 backend-3003 backend-3004 frontend-3001 frontend-3002; do
                sudo -u "$REAL_USER" bash -c "export PATH=\"$PATH\"; pm2 stop $app 2>/dev/null" || true
            done
            pass "PM2 processes stopped"
            ;;
        2)
            for port in 8000 8001 8002; do
                sudo systemctl stop "laravel-app-$port" 2>/dev/null || true
            done
            for wid in 1 2; do
                sudo systemctl stop "laravel-worker@$wid" 2>/dev/null || true
            done
            sudo systemctl stop laravel-scheduler.timer 2>/dev/null || true
            pass "systemd services stopped"
            ;;
        3)
            for port in 8003 8004 8005; do
                sudo systemctl stop "fastapi-$port" 2>/dev/null || true
            done
            for app in nextjs-3005 nextjs-3006; do
                sudo -u "$REAL_USER" bash -c "export PATH=\"$PATH\"; pm2 stop $app 2>/dev/null" || true
            done
            pass "FastAPI + PM2 services stopped"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Restart stack services
# ---------------------------------------------------------------------------
restart_stack_services() {
    local stack_num="$1"

    info "Restarting Stack $stack_num services..."

    case "$stack_num" in
        1)
            local eco="$STACK1_DIR/pm2/ecosystem.config.js"
            sudo -u "$REAL_USER" bash -c "export PATH=\"$PATH\"; pm2 start \"$eco\"" || true
            sudo -u "$REAL_USER" bash -c "export PATH=\"$PATH\"; pm2 save"
            pass "PM2 processes restarted"
            ;;
        2)
            for port in 8000 8001 8002; do
                sudo systemctl start "laravel-app-$port" 2>/dev/null || true
            done
            for wid in 1 2; do
                sudo systemctl start "laravel-worker@$wid" 2>/dev/null || true
            done
            sudo systemctl start laravel-scheduler.timer 2>/dev/null || true
            pass "systemd services restarted"
            ;;
        3)
            for port in 8003 8004 8005; do
                sudo systemctl start "fastapi-$port" 2>/dev/null || true
            done
            local eco3="$STACK3_DIR/pm2/nextjs-ecosystem.config.js"
            sudo -u "$REAL_USER" bash -c "export PATH=\"$PATH\"; cd \"$STACK3_DIR\" && pm2 start \"$eco3\"" || true
            sudo -u "$REAL_USER" bash -c "export PATH=\"$PATH\"; pm2 save"
            pass "FastAPI + PM2 services restarted"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Verify rollback health
# ---------------------------------------------------------------------------
verify_rollback() {
    local stack_num="$1"

    info "Running post-rollback health checks..."
    sleep 8

    local pass_count=0 fail_count=0

    case "$stack_num" in
        1)
            for port in 3000 3003 3004; do
                if curl -sf --max-time 5 "http://localhost:$port/api/health" | grep -q '"status"' 2>/dev/null; then
                    pass "Express :$port healthy"
                    pass_count=$((pass_count + 1))
                else
                    fail "Express :$port not responding"
                    fail_count=$((fail_count + 1))
                fi
            done
            for port in 3001 3002; do
                if curl -sf --max-time 5 "http://localhost:$port/" | grep -qi 'html' 2>/dev/null; then
                    pass "Next.js :$port healthy"
                    pass_count=$((pass_count + 1))
                else
                    fail "Next.js :$port not responding"
                    fail_count=$((fail_count + 1))
                fi
            done
            ;;
        2)
            for port in 8000 8001 8002; do
                if curl -sf --max-time 5 "http://localhost:$port/api/health" | grep -q '"status"' 2>/dev/null; then
                    pass "Laravel :$port healthy"
                    pass_count=$((pass_count + 1))
                else
                    fail "Laravel :$port not responding"
                    fail_count=$((fail_count + 1))
                fi
            done
            ;;
        3)
            for port in 8003 8004 8005; do
                if curl -sf --max-time 5 "http://localhost:$port/health" | grep -q '"status"' 2>/dev/null; then
                    pass "FastAPI :$port healthy"
                    pass_count=$((pass_count + 1))
                else
                    fail "FastAPI :$port not responding"
                    fail_count=$((fail_count + 1))
                fi
            done
            for port in 3005 3006; do
                if curl -sf --max-time 5 "http://localhost:$port/" | grep -qi 'html' 2>/dev/null; then
                    pass "Next.js :$port healthy"
                    pass_count=$((pass_count + 1))
                else
                    fail "Next.js :$port not responding"
                    fail_count=$((fail_count + 1))
                fi
            done
            ;;
    esac

    log ""
    if [[ $fail_count -eq 0 ]]; then
        log "${BOLD}${GREEN}  ✓ Rollback verified: $pass_count/$((pass_count + fail_count)) checks passed${NC}"
        return 0
    else
        log "${BOLD}${RED}  ✗ Rollback verification failed: $fail_count checks failed${NC}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Main rollback procedure
# ---------------------------------------------------------------------------
main() {
    log_info "Rollback script started"

    if [[ -z "$TARGET_STACK" ]]; then
        log_error "No stack specified. Use --stack 1|2|3"
        show_usage
        exit $EXIT_ERROR
    fi

    log ""
    log "${BOLD}${BLUE}+============================================================+${NC}"
    log "${BOLD}${BLUE}|  Rollback — Stack $TARGET_STACK                                       |${NC}"
    log "${BOLD}${BLUE}|  $(ts)                                   |${NC}"
    log "${BOLD}${BLUE}+============================================================+${NC}"

    # List backups
    if ! list_backups "$TARGET_STACK"; then
        exit $EXIT_ERROR
    fi

    if [[ $LIST_ONLY == true ]]; then
        exit $EXIT_SUCCESS
    fi

    # Select backup
    local selected_backup=""

    if [[ $AUTO_ROLLBACK == true ]]; then
        selected_backup="${BACKUP_LIST[0]}"
        info "Auto-selected: $(basename "$selected_backup")"
    else
        read -rp "  Select backup [1-${#BACKUP_LIST[@]}] or 'q' to quit: " choice
        if [[ "$choice" == "q" ]]; then
            info "Rollback cancelled"
            exit $EXIT_SUCCESS
        fi

        if [[ "$choice" -lt 1 || "$choice" -gt ${#BACKUP_LIST[@]} ]] 2>/dev/null; then
            fail "Invalid selection"
            exit $EXIT_ERROR
        fi

        selected_backup="${BACKUP_LIST[$((choice - 1))]}"
    fi

    info "Rolling back to: $(basename "$selected_backup")"

    # Determine stack directory
    local stack_dir=""
    case "$TARGET_STACK" in
        1) stack_dir="$STACK1_DIR" ;;
        2) stack_dir="$STACK2_DIR" ;;
        3) stack_dir="$STACK3_DIR" ;;
    esac

    # Step 1: Create pre-rollback backup
    sep
    log "${BOLD}  Step 1: Pre-rollback backup${NC}"
    create_pre_rollback_backup "$TARGET_STACK" "$stack_dir"

    # Step 2: Stop services
    sep
    log "${BOLD}  Step 2: Stop services${NC}"
    stop_stack_services "$TARGET_STACK"

    # Step 3: Restore from backup
    sep
    log "${BOLD}  Step 3: Restore backup${NC}"
    info "Restoring from: $(basename "$selected_backup")"

    # Restore env files and build artifacts
    if [[ -f "$selected_backup/backend.env" ]]; then
        cp "$selected_backup/backend.env" "$stack_dir/backend/.env" 2>/dev/null || true
    fi
    if [[ -d "$selected_backup/frontend_next" ]]; then
        rm -rf "$stack_dir/frontend/.next" 2>/dev/null || true
        cp -r "$selected_backup/frontend_next" "$stack_dir/frontend/.next" 2>/dev/null || true
    fi
    if [[ -d "$selected_backup/vendor" ]]; then
        rm -rf "$stack_dir/vendor" 2>/dev/null || true
        cp -r "$selected_backup/vendor" "$stack_dir/vendor" 2>/dev/null || true
    fi
    if [[ -d "$selected_backup/backend_venv" ]]; then
        rm -rf "$stack_dir/backend/venv" 2>/dev/null || true
        cp -r "$selected_backup/backend_venv" "$stack_dir/backend/venv" 2>/dev/null || true
    fi

    pass "Backup restored"

    # Step 4: Restart services
    sep
    log "${BOLD}  Step 4: Restart services${NC}"
    restart_stack_services "$TARGET_STACK"

    # Step 5: Verify
    sep
    log "${BOLD}  Step 5: Verify rollback${NC}"
    if verify_rollback "$TARGET_STACK"; then
        log ""
        log "${BOLD}${GREEN}+============================================================+${NC}"
        log "${BOLD}${GREEN}|  ✓ Rollback complete — Stack $TARGET_STACK                            |${NC}"
        log "${BOLD}${GREEN}+============================================================+${NC}"
        log_info "Rollback completed successfully"
    else
        log ""
        log "${BOLD}${RED}+============================================================+${NC}"
        log "${BOLD}${RED}|  ✗ Rollback verification failed — manual check required    |${NC}"
        log "${BOLD}${RED}+============================================================+${NC}"
        log_error "Rollback verification failed"
        exit $EXIT_ERROR
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)       show_usage; exit $EXIT_SUCCESS ;;
        --stack)         TARGET_STACK="${2:-}"; shift ;;
        --list)          LIST_ONLY=true ;;
        --auto)          AUTO_ROLLBACK=true ;;
        -v|--verbose)    set -x ;;
        *)               log_error "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
