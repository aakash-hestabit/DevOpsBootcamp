#!/bin/bash
set -euo pipefail

# Script: backup_system.sh
# Description: Performs secure system backups of /etc, /home/hestabit, and /var/log
# Author: Aakash
# Date: 2026-02-12
# Usage: sudo ./backup_system.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/$(basename $0 .sh).log"
readonly BACKUP_DIR="/backup"
readonly RETENTION_DAYS=7
readonly TIMESTAMP="$(date +'%Y%m%d_%H%M%S')"

mkdir -p "var/log/apps"

# Logging functions
log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }

# Help function
show_usage() {
    cat << EOF
Usage: sudo $(basename $0) [OPTIONS]

Backs up /etc, /home/hestabit, /var/log into timestamped archives.

OPTIONS:
    -h, --help      Show this help message

Examples:
    $(basename $0)
EOF
}

main() {

    log_info "Backup script started"

    # Ensure running as root
    if [[ "$EUID" -ne 0 ]]; then
        log_error "Script must be run as root"
        logger -p user.err "backup_system.sh: FAILED - Must run as root"
        exit $EXIT_ERROR
    fi

    # Create backup directory if not exists
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"

    # Backup targets
    TARGETS=("/etc" "/home/hestabit" "/var/log")

    for target in "${TARGETS[@]}"; do
        archive_name="$(basename "$target")_${TIMESTAMP}.tar.gz"
        archive_path="${BACKUP_DIR}/${archive_name}"

        log_info "Backing up $target to $archive_path"

        tar -czpf "$archive_path" "$target"

        # Set secure permissions
        chmod 600 "$archive_path"

        # Verify integrity
        if tar -tzf "$archive_path" > /dev/null; then
            log_info "Integrity check passed for $archive_name"
        else
            log_error "Integrity check FAILED for $archive_name"
            logger -p user.err "backup_system.sh: FAILED integrity check for $archive_name"
            exit $EXIT_ERROR
        fi
    done

    # Retention policy (delete backups older than 7 days)
    log_info "Applying retention policy (older than $RETENTION_DAYS days)"

    find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime +$RETENTION_DAYS -exec rm -f {} \;

    log_info "Old backups cleaned"

    logger -p user.info "backup_system.sh: Backup completed successfully"

    log_info "Backup script completed successfully"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_usage; exit $EXIT_SUCCESS ;;
        *) echo "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
