#!/bin/bash
set -euo pipefail

# Script: permission_audit.sh
# Description: Audits /home and /var/www for insecure permissions and generates a security report
# Author: Aakash
# Date: 2026-02-13
# Usage: sudo ./permission_audit.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/$(basename "$0" .sh).log"
REPORT_FILE=""
SCAN_PATHS=("/home" "/var/www")
VERBOSE=false

mkdir -p var/log/apps
touch "$LOG_FILE"

# Logging functions 
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" >> "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"; }

# Report writing function
write_to_report() {
    if [[ -n "$REPORT_FILE" ]]; then
        echo "$1" >> "$REPORT_FILE"
    fi
}

# Help function
show_usage() {
cat << EOF
Usage: sudo $(basename "$0") [OPTIONS]

Audits filesystem permissions for security risks.

OPTIONS:
    -h, --help       Show this help message
    -v, --verbose    Enable verbose output
    --report FILE    Output report file (required)

Examples:
    sudo $(basename "$0") --report /path/to/report.txt
    sudo $(basename "$0") --verbose --report /path/to/report.txt
EOF
}

# Section writer for report
section() {
    write_to_report ""
    write_to_report "--------------------------------------------"
    write_to_report "$1"
    write_to_report "--------------------------------------------"
}

# Main function
main() {
    if [[ -z "$REPORT_FILE" ]]; then
        echo "Error: --report parameter is required"
        show_usage
        exit $EXIT_ERROR
    fi

    log_info "Permission audit started"

    # Root check
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root."
        write_to_report "[ERROR] Permission audit requires root privileges"
        exit $EXIT_ERROR
    fi

    write_to_report "========== PERMISSION AUDIT REPORT =========="
    write_to_report "Generated on: $(date)"
    write_to_report "Scanned Paths: ${SCAN_PATHS[*]}"

    # Counters
    local count_777=0
    local count_world_writable=0
    local count_suid_sgid=0
    local count_nouser=0
    local count_nogroup=0

    for path in "${SCAN_PATHS[@]}"; do
        log_info "Scanning $path"

        # Skip if path doesn't exist
        if [[ ! -d "$path" ]]; then
            section "Skipping $path (does not exist)"
            continue
        fi

        # 777 files
        section "Files with 777 Permissions in $path"
        results=$(find "$path" -type f -perm 0777 2>/dev/null || true)
        if [[ -n "$results" ]]; then
            write_to_report "$results"
            count_777=$((count_777 + $(echo "$results" | wc -l)))
            write_to_report ""
            write_to_report "Suggested Fix: chmod 755 <file>"
        else
            write_to_report "None found."
        fi

        # World-writable directories (no sticky bit)
        section "World-Writable Directories WITHOUT Sticky Bit in $path"
        results=$(find "$path" -type d -perm -0002 ! -perm -1000 2>/dev/null || true)
        if [[ -n "$results" ]]; then
            write_to_report "$results"
            count_world_writable=$((count_world_writable + $(echo "$results" | wc -l)))
            write_to_report ""
            write_to_report "Suggested Fix: chmod o-w <directory>"
            write_to_report "If shared directory required: chmod +t <directory>"
        else
            write_to_report "None found."
        fi

        # SUID/SGID files
        section "SUID / SGID Files in $path"
        results=$(find "$path" -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null || true)
        if [[ -n "$results" ]]; then
            write_to_report "$results"
            count_suid_sgid=$((count_suid_sgid + $(echo "$results" | wc -l)))
            write_to_report ""
            write_to_report "Suggested Fix: chmod u-s <file> or chmod g-s <file> (if unnecessary)"
        else
            write_to_report "None found."
        fi

        # Files owned by deleted users
        section "Files Owned by Non-Existent Users in $path"
        results=$(find "$path" -nouser 2>/dev/null || true)
        if [[ -n "$results" ]]; then
            write_to_report "$results"
            count_nouser=$((count_nouser + $(echo "$results" | wc -l)))
            write_to_report ""
            write_to_report "Suggested Fix: chown validuser:group <file>"
        else
            write_to_report "None found."
        fi

        # Files owned by deleted groups
        section "Files Owned by Non-Existent Groups in $path"
        results=$(find "$path" -nogroup 2>/dev/null || true)
        if [[ -n "$results" ]]; then
            write_to_report "$results"
            count_nogroup=$((count_nogroup + $(echo "$results" | wc -l)))
            write_to_report ""
            write_to_report "Suggested Fix: chgrp validgroup <file>"
        else
            write_to_report "None found."
        fi
    done

    section "Audit Summary"
    write_to_report "777 Files Found: $count_777"
    write_to_report "World-Writable Directories Found: $count_world_writable"
    write_to_report "SUID/SGID Files Found: $count_suid_sgid"
    write_to_report "Files with No Owner Found: $count_nouser"
    write_to_report "Files with No Group Found: $count_nogroup"
    write_to_report "=============================================="

    log_info "Permission audit completed successfully"
    log_info "Report written to $REPORT_FILE"

    exit $EXIT_SUCCESS
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit $EXIT_SUCCESS
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --report)
            REPORT_FILE="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit $EXIT_ERROR
            ;;
    esac
done

main "$@"