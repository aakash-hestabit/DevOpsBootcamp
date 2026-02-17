#!/bin/bash
set -euo pipefail

# Script: setup_logging.sh
# Description: Validates and deploys centralized logging (rsyslog) and log rotation (logrotate)
# Author: Aakash
# Date: 2026-02-17
# Usage: sudo ./setup_logging.sh [OPTIONS]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/$(basename "$0" .sh).log"

# Source config files 
RSYSLOG_SRC="${SCRIPT_DIR}/10-custom.conf"
LOGROTATE_SRC="${SCRIPT_DIR}/custom-apps"

# Deployment targets
RSYSLOG_DEST="/etc/rsyslog.d/10-custom.conf"
LOGROTATE_DEST="/etc/logrotate.d/custom-apps"
LOG_DIR="/var/log/apps"

DRY_RUN=false

mkdir -p "$(dirname "$LOG_FILE")"

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"
    logger -t "$(basename "$0")" -p local0.info "$1" 2>/dev/null || true
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2
    logger -t "$(basename "$0")" -p local0.err "$1" 2>/dev/null || true
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" | tee -a "$LOG_FILE"
    logger -t "$(basename "$0")" -p local0.warning "$1" 2>/dev/null || true
}

# Help function
show_usage() {
    cat << EOF
Usage: sudo $(basename "$0") [OPTIONS]

Validates and deploys:
  - rsyslog config  (10-custom.conf → /etc/rsyslog.d/)
  - logrotate config (custom-apps  → /etc/logrotate.d/)
Creates /var/log/apps/ with correct permissions.

OPTIONS:
    -h, --help      Show this help message
    -n, --dry-run   Validate only, do not deploy

Examples:
    sudo $(basename "$0")
    sudo $(basename "$0") --dry-run
EOF
}

# Validate environment
validate_env() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root"
        exit $EXIT_ERROR
    fi

    for f in "$RSYSLOG_SRC" "$LOGROTATE_SRC"; do
        if [[ ! -f "$f" ]]; then
            log_error "Required config file not found: $f"
            exit $EXIT_ERROR
        fi
    done
}

# Validate rsyslog config syntax
validate_rsyslog() {
    log_info "Validating rsyslog config: $RSYSLOG_SRC"

    # Check it contains at least one log directive
    if ! grep -qE '^\s*(local[0-9]|auth|authpriv|\*)\.' "$RSYSLOG_SRC"; then
        log_error "rsyslog config looks empty or malformed: $RSYSLOG_SRC"
        return 1
    fi

    # Check all referenced log directories exist or are /var/log/apps (will be created)
    while IFS= read -r line; do
        [[ "$line" =~ ^# ]] && continue
        [[ -z "$line" ]] && continue
        local dest
        dest=$(echo "$line" | awk '{print $2}')
        # Only check file paths (not @host:port forwarding rules)
        if [[ "$dest" == /* ]]; then
            local dir
            dir=$(dirname "$dest")
            if [[ "$dir" != "/var/log/apps" && ! -d "$dir" ]]; then
                log_warn "Log directory does not exist and won't be created: $dir"
            fi
        fi
    done < "$RSYSLOG_SRC"

    log_info "rsyslog config validation passed"
}

# Validate logrotate config syntax
validate_logrotate() {
    log_info "Validating logrotate config: $LOGROTATE_SRC"

    if ! command -v logrotate &>/dev/null; then
        log_warn "logrotate not installed — skipping syntax check"
        return 0
    fi

    # Use logrotate debug mode to validate syntax
    if logrotate -d "$LOGROTATE_SRC" 2>&1 | tee -a "$LOG_FILE" | grep -qi "error"; then
        log_error "logrotate config validation failed: $LOGROTATE_SRC"
        return 1
    fi

    log_info "logrotate config validation passed"
}

# Create log directory with correct permissions
setup_log_dir() {
    log_info "Creating log directory: $LOG_DIR"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would create: $LOG_DIR (0755 root:adm)"
        return
    fi

    mkdir -p "$LOG_DIR"
    chmod 0755 "$LOG_DIR"

    # Create log files referenced in config so rsyslog can write immediately
    for logfile in application.log security.log monitoring.log auth.log errors.log; do
        local path="${LOG_DIR}/${logfile}"
        if [[ ! -f "$path" ]]; then
            touch "$path"
            chmod 0640 "$path"
            chown root:adm "$path" 2>/dev/null || chown root:root "$path"
        fi
    done

    log_info "Log directory ready: $LOG_DIR"
}

# Deploy rsyslog config
deploy_rsyslog() {
    log_info "Deploying rsyslog config → $RSYSLOG_DEST"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would copy: $RSYSLOG_SRC → $RSYSLOG_DEST"
        log_info "[DRY-RUN] Would restart rsyslog"
        return
    fi

    # Backup existing config if present
    if [[ -f "$RSYSLOG_DEST" ]]; then
        cp "$RSYSLOG_DEST" "${RSYSLOG_DEST}.bak.$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing rsyslog config"
    fi

    cp "$RSYSLOG_SRC" "$RSYSLOG_DEST"
    chmod 644 "$RSYSLOG_DEST"

    systemctl restart rsyslog
    log_info "rsyslog restarted successfully"
}

# Deploy logrotate config
deploy_logrotate() {
    log_info "Deploying logrotate config → $LOGROTATE_DEST"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would copy: $LOGROTATE_SRC → $LOGROTATE_DEST"
        log_info "[DRY-RUN] Would test: logrotate -d $LOGROTATE_DEST"
        return
    fi

    # Backup existing config if present
    if [[ -f "$LOGROTATE_DEST" ]]; then
        cp "$LOGROTATE_DEST" "${LOGROTATE_DEST}.bak.$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing logrotate config"
    fi

    cp "$LOGROTATE_SRC" "$LOGROTATE_DEST"
    chmod 644 "$LOGROTATE_DEST"

    # Final live validation after deployment
    logrotate -d "$LOGROTATE_DEST" 2>&1 | tee -a "$LOG_FILE" || {
        log_error "Post-deploy logrotate validation failed"
        exit $EXIT_ERROR
    }

    log_info "logrotate config deployed successfully"
}

# Main function
main() {
    validate_env

    log_info "========================================"
    log_info "Logging setup started"
    log_info "========================================"

    # Validate both configs before touching anything
    validate_rsyslog || exit $EXIT_ERROR
    validate_logrotate || exit $EXIT_ERROR

    log_info "All validations passed — proceeding with deployment"

    setup_log_dir
    deploy_rsyslog
    deploy_logrotate

    log_info "========================================"
    log_info "Logging setup completed successfully"
    log_info "========================================"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit $EXIT_SUCCESS
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit $EXIT_ERROR
            ;;
    esac
done

main "$@"