#!/bin/bash
set -euo pipefail

# Script: dns_backup.sh
# Description: Backs up BIND DNS configuration and zone files
# Author: Aakash
# Date: 2026-02-17
# Usage: sudo ./dns_backup.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/backup/dns"
BIND_DIR="/etc/bind"
RETENTION_DAYS=30

LOG_FILE="var/log/apps/$(basename "$0" .sh).log"

DRY_RUN=false
VERBOSE=false

mkdir -p "$BACKUP_DIR" "$(dirname "$LOG_FILE")"

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2
}

# Help function
show_usage() {
cat << EOF
Usage: sudo $(basename "$0") [OPTIONS]

Backs up BIND DNS configuration and zone files.

Backed up DNS components:
  - /etc/bind/named.conf
  - /etc/bind/named.conf.local
  - /etc/bind/named.conf.options
  - /etc/bind/zones/ (all zone files)

OPTIONS:
  -h, --help        Show this help message
  -v, --verbose     Enable verbose output
  --dry-run         Simulate backup without writing files

Examples:
  sudo $(basename "$0")
  sudo $(basename "$0") --dry-run
EOF
}

# Verify BIND directory exists
verify_environment() {
    if [[ ! -d "$BIND_DIR" ]]; then
        log_info "BIND directory not found: $BIND_DIR"
        log_info "DNS may not be configured on this system"
        log_info "Skipping DNS backup"
        exit $EXIT_SUCCESS
    fi

    if [[ "$BACKUP_DIR" != "/backup/dns" ]]; then
        log_error "Unsafe BACKUP_DIR detected: $BACKUP_DIR"
        exit $EXIT_ERROR
    fi
}

# Create backup archive
create_backup() {
    local ts archive
    ts=$(date +%Y%m%d_%H%M%S)
    archive="${BACKUP_DIR}/dns_backup_${ts}.tar.gz"

    log_info "Creating DNS backup: $archive"
    log_info "Source: $BIND_DIR"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Backup archive would be created"
        return
    fi

    tar -czf "$archive" "$BIND_DIR" 2>/dev/null || {
        log_error "Backup archive creation failed"
        exit $EXIT_ERROR
    }

    # Set secure permissions
    chmod 600 "$archive"

    # Verify archive integrity
    if tar -tzf "$archive" >/dev/null 2>&1; then
        log_info "Backup archive verified successfully"
        log_info "Archive size: $(du -h "$archive" | cut -f1)"
    else
        log_error "Backup archive verification failed"
        exit $EXIT_ERROR
    fi

    test_restore "$archive"
}

# Test restore procedure
test_restore() {
    local archive="$1"

    log_info "Testing restore procedure (archive readability)"
    
    if tar -tzf "$archive" >/dev/null 2>&1; then
        log_info "Restore test PASSED"
    else
        log_error "Restore test FAILED: archive unreadable"
        exit $EXIT_ERROR
    fi
}

# Apply retention policy
cleanup_old_backups() {
    log_info "Applying retention policy (${RETENTION_DAYS} days)"

    if [[ "$DRY_RUN" == true ]]; then
        find "$BACKUP_DIR" -type f -name "dns_backup_*.tar.gz" -mtime +"$RETENTION_DAYS" -print | \
        while read -r file; do
            log_info "[DRY-RUN] Would delete old backup: $file"
        done
        return
    fi

    local deleted=0
    while IFS= read -r file; do
        log_info "Deleted old backup: $file"
        ((deleted++))
    done < <(find "$BACKUP_DIR" -type f -name "dns_backup_*.tar.gz" -mtime +"$RETENTION_DAYS" -delete -print)

    if [[ $deleted -gt 0 ]]; then
        log_info "Removed $deleted old backup(s)"
    else
        log_info "No old backups to remove"
    fi
}

main() {
    log_info "DNS backup started"

    # Ensure running as root
    if [[ "$EUID" -ne 0 ]]; then
        log_error "Script must be run as root"
        exit $EXIT_ERROR
    fi

    verify_environment
    create_backup
    cleanup_old_backups

    log_info "DNS backup completed successfully"
    logger -p user.info "dns_backup.sh: DNS backup completed successfully"
    exit $EXIT_SUCCESS
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit $EXIT_SUCCESS
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --dry-run)
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