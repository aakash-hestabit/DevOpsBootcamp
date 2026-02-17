#!/bin/bash
set -euo pipefail

# Script: dns_backup.sh
# Description: Backs up BIND DNS configuration and zone files with retention policy
# Author: Aakash
# Date: 2026-02-14
# Usage: ./dns_backup.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/backup/dns"
BIND_DIR="/etc/bind"
RETENTION_DAYS=30

LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/$(basename "$0" .sh).log"

DRY_RUN=false
VERBOSE=false

mkdir -p "$BACKUP_DIR" "$LOG_DIR"

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
Usage: $(basename $0) [OPTIONS]

Backs up BIND DNS configuration and zone files.

OPTIONS:
  -h, --help        Show this help message
  -v, --verbose     Enable verbose output
  --dry-run         Simulate backup without writing files

Examples:
  $(basename $0)
  $(basename $0) --dry-run
EOF
}

# Verify environment safety
verify_environment() {
    [[ -d "$BIND_DIR" ]] || {
        log_error "BIND directory not found: $BIND_DIR"
        exit $EXIT_ERROR
    }

    [[ "$BACKUP_DIR" == "/backup/dns" ]] || {
        log_error "Unsafe BACKUP_DIR detected: $BACKUP_DIR"
        exit $EXIT_ERROR
    }
}

# Create backup archive
create_backup() {
    local ts archive
    ts=$(date +%Y%m%d_%H%M%S)
    archive="${BACKUP_DIR}/dns_backup_${ts}.tar.gz"

    log_info "Preparing DNS backup: $archive"
    log_info "Including full BIND configuration (/etc/bind)"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Backup archive would be created"
        return
    fi

    tar -czf "$archive" "$BIND_DIR" || {
        log_error "Backup archive creation failed"
        exit $EXIT_ERROR
    }

    # Verify archive integrity
    if tar -tzf "$archive" >/dev/null 2>&1; then
        log_info "Backup archive verified successfully"
    else
        log_error "Backup archive verification failed"
        exit $EXIT_ERROR
    fi

    test_restore "$archive"
}

# Restore test
test_restore() {
    local archive="$1"

    log_info "Testing restore procedure (archive readability)"
    tar -tzf "$archive" >/dev/null 2>&1 || {
        log_error "Restore test failed: archive unreadable"
        exit $EXIT_ERROR
    }

    log_info "Restore test passed"
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

    find "$BACKUP_DIR" -type f -name "dns_backup_*.tar.gz" -mtime +"$RETENTION_DAYS" -print -delete | \
    while read -r file; do
        log_info "Deleted old backup: $file"
    done
}

main() {
    log_info "DNS backup started"

    verify_environment
    create_backup
    cleanup_old_backups

    log_info "DNS backup completed successfully"
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
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit $EXIT_ERROR
            ;;
    esac
    shift
done

main "$@"
