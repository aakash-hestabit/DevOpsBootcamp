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
REPORT_DIR="/var/log/apps/reports"
REPORT_FILE="${REPORT_DIR}/health-$(date +%Y-%m-%d).txt"

# Ensure report directory exists
mkdir -p "$REPORT_DIR"

# Logging helper
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

# Help function
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Generates a daily system health report including system info,
resource usage, processes, network status, and services.

OPTIONS:
    -h, --help      Show this help message

Examples:
    $(basename "$0")
EOF
}

# Generate report
generate_report() {
    {
        echo "==========================================="
        echo "          SYSTEM HEALTH REPORT"
        echo "   Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "==========================================="
        echo ""

        echo "--- SYSTEM INFORMATION ---"
        echo "Hostname : $(hostname)"
        echo "OS       : $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
        echo "Kernel   : $(uname -r)"
        echo "Uptime   : $(uptime -p)"
        echo ""

        echo "--- DISK USAGE ---"
        df -h | grep -vE '^Filesystem|tmpfs|cdrom|loop'
        echo ""

        echo "--- MEMORY USAGE ---"
        free -h
        echo ""

        echo "--- CPU LOAD ---"
        uptime
        echo ""

        echo "--- TOP PROCESSES (CPU) ---"
        ps aux --sort=-%cpu | head -6
        echo ""

        echo "--- TOP PROCESSES (MEMORY) ---"
        ps aux --sort=-%mem | head -6
        echo ""

        echo "--- NETWORK INTERFACES ---"
        ip -br addr
        echo ""

        echo "--- ACTIVE CONNECTIONS ---"
        local conn_count
        conn_count=$(ss -tuln | wc -l)
        echo "Total connections: $conn_count"
        echo ""

        echo "--- RECENT ERRORS (Last 50) ---"
        tail -50 /var/log/apps/errors.log 2>/dev/null || echo "No error log found"
        echo ""

        echo "--- SERVICE STATUS ---"
        systemctl is-active ssh  &>/dev/null && echo "SSH  : Active" || echo "SSH  : Inactive"
        systemctl is-active cron &>/dev/null && echo "Cron : Active" || echo "Cron : Inactive"
        echo ""

        echo "==========================================="
        echo "            END OF REPORT"
        echo "==========================================="

    } > "$REPORT_FILE"
}

# Argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit $EXIT_SUCCESS
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit $EXIT_ERROR
            ;;
    esac
done

# Main execution
log_info "Generating system health report..."
generate_report
log_info "Report generated successfully: $REPORT_FILE"

exit $EXIT_SUCCESS
