#!/bin/bash
set -eEuo pipefail

# Script: user_activity_monitor.sh
# Description: Audits user login activity, command history, and inactive accounts.
# Author: Aakash
# Date: 2026-02-12
# Usage: sudo ./user_activity_monitor.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_FILE=""
LOG_FILE="var/log/apps/$(basename "$0" .sh).log"
VERBOSE=false

# Ensure required directories exist
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

# Global error handler
error_handler() {
    local exit_code="$1"
    local line_no="$2"
    local cmd="$3"

    log_error "Script failed at line $line_no"
    log_error "Exit code: $exit_code"
    log_error "Command: $cmd"

    write_to_report "[ERROR] User activity monitoring failed at line $line_no"
    exit $exit_code
}

trap 'error_handler $? ${LINENO} "$BASH_COMMAND"' ERR

# Help function
show_usage() {
cat << EOF
Usage: sudo $(basename "$0") [OPTIONS]

Audits user login activity and identifies inactive users.

OPTIONS:
    -h, --help       Show this help message
    -v, --verbose    Enable verbose output
    --report FILE    Output report file (required)

Examples:
    sudo $(basename "$0") --report /path/to/report.txt
    sudo $(basename "$0") --verbose --report /path/to/report.txt
EOF
}

# Section formatter
section() {
    write_to_report ""
    write_to_report "-------------------------------------------"
    write_to_report "$1"
    write_to_report "-------------------------------------------"
}

# Root check
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root."
        write_to_report "[ERROR] User activity monitoring requires root privileges"
        exit $EXIT_ERROR
    fi
}

# Main function
main() {
    if [[ -z "$REPORT_FILE" ]]; then
        echo "Error: --report parameter is required"
        show_usage
        exit $EXIT_ERROR
    fi

    check_root
    log_info "User Activity Monitor started"

    write_to_report "========== USER ACTIVITY REPORT =========="
    write_to_report "Generated on: $(date)"

    # Currently logged in users 
    section "Currently Logged-In Users"
    who >> "$REPORT_FILE" 2>&1 || write_to_report "Unable to fetch who output"

    write_to_report ""
    write_to_report "Detailed View (w):"
    w -h >> "$REPORT_FILE" 2>&1 || write_to_report "Unable to fetch w output"

    # Recent login history 
    section "Recent Login History (Last 20)"
    last -n 20 >> "$REPORT_FILE" 2>&1 || write_to_report "Unable to fetch last output"

    # Last Login Per User (Human Accounts Only)
    section "Last Login Per Human User (UID >= 1000)"

    awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | while read -r user; do
        last -n 1 "$user" 2>&1 | grep -v "wtmp begins" >> "$REPORT_FILE" \
            || write_to_report "$user    No login records found"
    done

    # Recent Command History (Last 10 Commands)
    section "Recent Command History (Last 10 Commands Per User)"

    for home_dir in /home/*; do
        [[ -d "$home_dir" ]] || continue
        user_name=$(basename "$home_dir")
        history_file="$home_dir/.bash_history"

        write_to_report ""
        write_to_report "User: $user_name"

        if [[ -f "$history_file" ]]; then
            tail -n 10 "$history_file" >> "$REPORT_FILE" 2>/dev/null \
                || write_to_report "  [Permission denied or unreadable]"
        else
            write_to_report "  [No .bash_history found]"
        fi
    done

    section "Inactive Users (No Login > 90 Days)"

    THRESHOLD_EPOCH=$(date --date="90 days ago" +%s)

    awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | while read -r user; do
        last_line=$(last -n 1 "$user" 2>/dev/null | head -n 1)

        # Skip users with no login record
        [[ -z "$last_line" || "$last_line" == *"wtmp begins"* ]] && continue

        # Skip currently logged-in users
        [[ "$last_line" == *"still logged in"* ]] && continue

        # Extract date safely (fields 4-8 usually hold date info)
        login_date=$(echo "$last_line" | awk '{print $4,$5,$6,$7,$8}')

        login_epoch=$(date -d "$login_date" +%s 2>/dev/null || echo 0)

        if [[ "$login_epoch" -ne 0 && "$login_epoch" -lt "$THRESHOLD_EPOCH" ]]; then
            write_to_report "$user  Last login: $login_date"
        fi
    done

    # Summary
    section "Summary"

    logged_in_count=$(who | wc -l)
    
    # Count inactive users from report
    inactive_count=0
    in_inactive_section=false
    while IFS= read -r line; do
        if [[ "$line" == *"Inactive Users"* ]]; then
            in_inactive_section=true
            continue
        fi
        if [[ "$line" == *"Summary"* ]]; then
            break
        fi
        if [[ "$in_inactive_section" == true && "$line" == *"Last login:"* ]]; then
            ((inactive_count++))
        fi
    done < "$REPORT_FILE"

    write_to_report "Currently Logged-In Users: $logged_in_count"
    write_to_report "Inactive Users (>90 days): $inactive_count"
    write_to_report "=========================================="

    log_info "Report written to $REPORT_FILE"
    log_info "User Activity Monitor completed successfully"

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
            set -x
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