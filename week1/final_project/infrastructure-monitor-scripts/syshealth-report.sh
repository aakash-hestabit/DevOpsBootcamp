#!/bin/bash
set -euo pipefail

# Script: syshealth-report.sh
# Description: Generates a comprehensive system health report for auditing and diagnostics
# Author: Aakash
# Date: 2026-02-16
# Usage: ./syshealth-report.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_FILE=""
LOG_FILE="var/log/apps/$(basename "$0" .sh).log"

mkdir -p "$(dirname "$LOG_FILE")"

# Logging helper
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
}

# Report writing function
write_to_report() {
    if [[ -n "$REPORT_FILE" ]]; then
        echo "$1" >> "$REPORT_FILE"
    fi
}

# Help function
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Generates a comprehensive system health report including system info,
resource usage, processes, network status, and services.

OPTIONS:
    -h, --help       Show this help message
    --report FILE    Output report file (required)

Examples:
    $(basename "$0") --report /path/to/report.txt
EOF
}

# Generate report
generate_report() {
    write_to_report "========================================="
    write_to_report "        SYSTEM HEALTH REPORT"
    write_to_report "   Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    write_to_report "========================================="
    write_to_report ""

    write_to_report "--- SYSTEM INFORMATION ---"
    write_to_report "Hostname : $(hostname)"
    write_to_report "OS       : $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2 2>/dev/null || echo 'Unknown')"
    write_to_report "Kernel   : $(uname -r)"
    write_to_report "Uptime   : $(uptime -p)"
    write_to_report ""

    write_to_report "--- DISK USAGE ---"
    df -h | grep -vE '^Filesystem|tmpfs|cdrom|loop' >> "$REPORT_FILE" 2>&1
    write_to_report ""

    write_to_report "--- MEMORY USAGE ---"
    free -h >> "$REPORT_FILE" 2>&1
    write_to_report ""

    write_to_report "--- CPU LOAD ---"
    uptime >> "$REPORT_FILE" 2>&1
    write_to_report ""

    write_to_report "--- TOP PROCESSES (CPU) ---"
    ps aux --sort=-%cpu | head -n 6 >> "$REPORT_FILE" 2>&1
    write_to_report ""

    write_to_report "--- TOP PROCESSES (MEMORY) ---"
    ps aux --sort=-%mem | head -n 6 >> "$REPORT_FILE" 2>&1
    write_to_report ""

    write_to_report "--- NETWORK INTERFACES ---"
    ip -br addr >> "$REPORT_FILE" 2>&1
    write_to_report ""

    write_to_report "--- ACTIVE CONNECTIONS ---"
    local conn_count
    conn_count=$(ss -tuln | wc -l)
    write_to_report "Total connections: $conn_count"
    write_to_report ""

    write_to_report "--- RECENT ERRORS (Last 50) ---"
    if [[ -f /var/log/apps/errors.log ]]; then
        tail -50 /var/log/apps/errors.log >> "$REPORT_FILE" 2>/dev/null || write_to_report "Unable to read error log"
    else
        write_to_report "No error log found at /var/log/apps/errors.log"
    fi
    write_to_report ""

    write_to_report "--- SERVICE STATUS ---"
    systemctl is-active ssh  &>/dev/null && write_to_report "SSH  : Active" || write_to_report "SSH  : Inactive"
    systemctl is-active cron &>/dev/null && write_to_report "Cron : Active" || write_to_report "Cron : Inactive"
    write_to_report ""

    write_to_report "========================================="
    write_to_report "          END OF REPORT"
    write_to_report "========================================="
}

# Main execution
main() {
    if [[ -z "$REPORT_FILE" ]]; then
        echo "Error: --report parameter is required"
        show_usage
        exit $EXIT_ERROR
    fi

    log_info "Generating system health report..."
    generate_report
    log_info "Report generated successfully: $REPORT_FILE"
}

# Argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit $EXIT_SUCCESS
            ;;
        --report)
            REPORT_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit $EXIT_ERROR
            ;;
    esac
done

main
exit $EXIT_SUCCESS