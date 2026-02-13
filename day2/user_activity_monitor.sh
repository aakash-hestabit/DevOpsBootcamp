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
REPORT_DIR="reports"
REPORT_FILE="$REPORT_DIR/user_activity_report.txt"
LOG_FILE="var/log/apps/$(basename "$0" .sh).log"
VERBOSE=false

# Ensure required directories exist
mkdir -p var/log/apps
mkdir -p "$REPORT_DIR"
touch "$LOG_FILE"

# Logging functions
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }

# Global error handler
error_handler() {
    local exit_code="$1"
    local line_no="$2"
    local cmd="$3"

    log_error "Script failed at line $line_no"
    log_error "Exit code: $exit_code"
    log_error "Command: $cmd"

    exit $exit_code
}

trap 'error_handler $? ${LINENO} "$BASH_COMMAND"' ERR

# Help function
show_usage() {
cat << EOF
Usage: sudo $(basename "$0") [OPTIONS]

Audits user login activity and identifies inactive users.

OPTIONS:
    -h, --help      Show this help message
    -v, --verbose   Enable verbose output

Examples:
    sudo $(basename "$0")
    sudo $(basename "$0") --verbose
EOF
}

# Section formatter
section() {
    echo -e "\n-------------------------------------------" >> "$REPORT_FILE"
    echo "$1" >> "$REPORT_FILE"
    echo "----------------------------------------------" >> "$REPORT_FILE"
}

# Root check
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root."
        exit $EXIT_ERROR
    fi
}


# Main function
main() {

    check_root
    log_info "User Activity Monitor started"

    : > "$REPORT_FILE"

    echo "USER ACTIVITY REPORT" >> "$REPORT_FILE"
    echo "Generated on: $(date)" >> "$REPORT_FILE"

    # currently logged in users 
    section "Currently Logged-In Users"
    who >> "$REPORT_FILE" || echo "Unable to fetch who output" >> "$REPORT_FILE"

    echo -e "\nDetailed View (w):" >> "$REPORT_FILE"
    w -h >> "$REPORT_FILE" || echo "Unable to fetch w output" >> "$REPORT_FILE"

    # recent login history 
    section "Recent Login History (Last 20)"
    last -n 20 >> "$REPORT_FILE" || echo "Unable to fetch last output" >> "$REPORT_FILE"

    # Last Login Per User (Human Accounts Only)
    section "Last Login Per Human User (UID >= 1000)"

    awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | while read -r user; do
        last -n 1 "$user" | grep -v "wtmp begins" >> "$REPORT_FILE" \
            || echo "$user    No login records found" >> "$REPORT_FILE"
    done


    # Recent Command History (Last 10 Commands)
    section "Recent Command History (Last 10 Commands Per User)"

    for home_dir in /home/*; do
        [[ -d "$home_dir" ]] || continue
        user_name=$(basename "$home_dir")
        history_file="$home_dir/.bash_history"

        echo -e "\nUser: $user_name" >> "$REPORT_FILE"

        if [[ -f "$history_file" ]]; then
            tail -n 10 "$history_file" >> "$REPORT_FILE" 2>/dev/null \
                || echo "  [Permission denied or unreadable]" >> "$REPORT_FILE"
        else
            echo "  [No .bash_history found]" >> "$REPORT_FILE"
        fi
    done

    section "Inactive Users (No Login > 90 Days)"

    THRESHOLD_EPOCH=$(date --date="90 days ago" +%s)

    awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | while read -r user; do
        last_line=$(last -n 1 "$user" | head -n 1)

        # Skip users with no login record
        [[ -z "$last_line" || "$last_line" == *"wtmp begins"* ]] && continue

        # Skip currently logged-in users
        [[ "$last_line" == *"still logged in"* ]] && continue

        # Extract date safely (fields 4–8 usually hold date info)
        login_date=$(echo "$last_line" | awk '{print $4,$5,$6,$7,$8}')

        login_epoch=$(date -d "$login_date" +%s 2>/dev/null || echo 0)

        if [[ "$login_epoch" -ne 0 && "$login_epoch" -lt "$THRESHOLD_EPOCH" ]]; then
            echo "$user  Last login: $login_date" >> "$REPORT_FILE"
        fi
    done

    # Summary
    section "Summary"

    logged_in_count=$(who | wc -l)
    inactive_count=$(awk '/Inactive Users/{flag=1;next}/Summary/{flag=0}flag && /Last login:/{c++} END{print c+0}' "$REPORT_FILE")

    echo "Currently Logged-In Users: $logged_in_count" >> "$REPORT_FILE"
    echo "Inactive Users (>90 days): $inactive_count" >> "$REPORT_FILE"

    log_info "Report generated at $REPORT_FILE"
    log_info "User Activity Monitor completed successfully"

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
            set -x
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
