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
REPORT_DIR="reports"
REPORT_FILE="$REPORT_DIR/permission_audit.txt"
SCAN_PATHS=("/home" "/var/www")
VERBOSE=false

mkdir -p var/log/apps
touch "$LOG_FILE"

# Logging functions
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }

# Help function
show_usage() {
cat << EOF
Usage: sudo $(basename "$0") [OPTIONS]

Audits filesystem permissions for security risks.

OPTIONS:
    -h, --help      Show this help message
    -v, --verbose   Enable verbose output

Examples:
    sudo $(basename "$0")
    sudo $(basename "$0") --verbose
EOF
}

# Section writer for report
section() {
    echo -e "\n--------------------------------------------" >> "$REPORT_FILE"
    echo "$1" >> "$REPORT_FILE"
    echo "-----------------------------------------------" >> "$REPORT_FILE"
}

# Main function
main() {

    log_info "Permission audit started"

    # Root check
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root."
        exit $EXIT_ERROR
    fi

    mkdir -p "$REPORT_DIR"
    : > "$REPORT_FILE"

    echo "--------------- Permission Audit Report ---------------" >> "$REPORT_FILE"
    echo "Generated on: $(date)" >> "$REPORT_FILE"
    echo "Scanned Paths: ${SCAN_PATHS[*]}" >> "$REPORT_FILE"

    # Counters
    local count_777=0
    local count_world_writable=0
    local count_suid_sgid=0
    local count_nouser=0
    local count_nogroup=0

    for path in "${SCAN_PATHS[@]}"; do

        log_info "Scanning $path"

        # 777 files
        section "Files with 777 Permissions in $path"
        results=$(find "$path" -type f -perm 0777 2>/dev/null || true)
        if [[ -n "$results" ]]; then
            echo "$results" >> "$REPORT_FILE"
            count_777=$(echo "$results" | wc -l)
            echo -e "\nSuggested Fix: chmod 755 <file>" >> "$REPORT_FILE"
        else
            echo "None found." >> "$REPORT_FILE"
        fi

        # World-writable directories (no sticky bit)
        section "World-Writable Directories WITHOUT Sticky Bit in $path"
        results=$(find "$path" -type d -perm -0002 ! -perm -1000 2>/dev/null || true)
        if [[ -n "$results" ]]; then
            echo "$results" >> "$REPORT_FILE"
            count_world_writable=$(echo "$results" | wc -l)
            echo -e "\nSuggested Fix: chmod o-w <directory>" >> "$REPORT_FILE"
            echo "If shared directory required: chmod +t <directory>" >> "$REPORT_FILE"
        else
            echo "None found." >> "$REPORT_FILE"
        fi

        # SUID/SGID files
        section "SUID / SGID Files in $path"
        results=$(find "$path" -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null || true)
        if [[ -n "$results" ]]; then
            echo "$results" >> "$REPORT_FILE"
            count_suid_sgid=$(echo "$results" | wc -l)
            echo -e "\nSuggested Fix: chmod u-s <file> or chmod g-s <file> (if unnecessary)" >> "$REPORT_FILE"
        else
            echo "None found." >> "$REPORT_FILE"
        fi

        # Files owned by deleted users
        section "Files Owned by Non-Existent Users in $path"
        results=$(find "$path" -nouser 2>/dev/null || true)
        if [[ -n "$results" ]]; then
            echo "$results" >> "$REPORT_FILE"
            count_nouser=$(echo "$results" | wc -l)
            echo -e "\nSuggested Fix: chown validuser:group <file>" >> "$REPORT_FILE"
        else
            echo "None found." >> "$REPORT_FILE"
        fi

        # Files owned by deleted groups
        section "Files Owned by Non-Existent Groups in $path"
        results=$(find "$path" -nogroup 2>/dev/null || true)
        if [[ -n "$results" ]]; then
            echo "$results" >> "$REPORT_FILE"
            count_nogroup=$(echo "$results" | wc -l)
            echo -e "\nSuggested Fix: chgrp validgroup <file>" >> "$REPORT_FILE"
        else
            echo "None found." >> "$REPORT_FILE"
        fi

    done

    section "Audit Summary"
    echo "777 Files Found: $count_777" >> "$REPORT_FILE"
    echo "World-Writable Directories Found: $count_world_writable" >> "$REPORT_FILE"
    echo "SUID/SGID Files Found: $count_suid_sgid" >> "$REPORT_FILE"
    echo "Files with No Owner Found: $count_nouser" >> "$REPORT_FILE"
    echo "Files with No Group Found: $count_nogroup" >> "$REPORT_FILE"

    log_info "Permission audit completed successfully"
    log_info "Report generated at $REPORT_FILE"

    exit $EXIT_SUCCESS
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit $EXIT_SUCCESS
            ;;
        -v|--verbose)
            VERBOSE=true
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