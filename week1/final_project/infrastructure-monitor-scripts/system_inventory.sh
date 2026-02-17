#!/bin/bash
set -euo pipefail

# Script: system_inventory.sh
# Description: Generates comprehensive system inventory report (OS, CPU, Memory, Disk, Network)
# Author: Aakash
# Date: 2026-02-06
# Usage: ./system_inventory.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/$(basename "$0" .sh).log"
REPORT_FILE=""

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging functions
log_info() { 
    echo "[$(TZ=Asia/Kolkata date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
}

log_error() { 
    echo "[$(TZ=Asia/Kolkata date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"
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

Generates a comprehensive system inventory report including:
  - Operating System information
  - Kernel version
  - System uptime
  - CPU information
  - Memory capacity
  - Disk space
  - Installed packages count
  - Network interfaces

OPTIONS:
  -h, --help       Show this help message
  --report FILE    Output report file (required)

Examples:
  $(basename "$0") --report /path/to/report.txt

EOF
}

# Get OS information
get_os() {
    if command -v lsb_release &>/dev/null; then
        lsb_release -ds
    else
        grep '^PRETTY_NAME' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "Unknown"
    fi
}

# Get package count
get_package_count() {
    if command -v dpkg &>/dev/null; then
        dpkg -l | grep -c '^ii' || echo "0"
    elif command -v rpm &>/dev/null; then
        rpm -qa | wc -l
    else
        echo "N/A"
    fi
}

# Main function
main() {
    if [[ -z "$REPORT_FILE" ]]; then
        echo "Error: --report parameter is required"
        show_usage
        exit $EXIT_ERROR
    fi

    log_info "Generating system inventory"

    # Gather system information
    local OS KERNEL UPTIME CPU MEM DISK PKG_COUNT
    OS=$(get_os)
    KERNEL=$(uname -r)
    UPTIME=$(uptime -p)
    CPU=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -n1 | cut -d':' -f2 | xargs || echo "Unknown")
    MEM=$(free -h | awk '/^Mem:/ {print $2}')
    DISK=$(df -h / | awk 'NR==2 {print $2}')
    PKG_COUNT=$(get_package_count)

    # Write to report
    write_to_report "========== SYSTEM INVENTORY =========="
    write_to_report "Generated on: $(date)"
    write_to_report ""
    write_to_report "--- System Information ---"
    write_to_report "Operating System : $OS"
    write_to_report "Kernel Version   : $KERNEL"
    write_to_report "System Uptime    : $UPTIME"
    write_to_report ""
    write_to_report "--- Hardware Information ---"
    write_to_report "CPU Model        : $CPU"
    write_to_report "Total RAM        : $MEM"
    write_to_report "Disk Size (/)    : $DISK"
    write_to_report ""
    write_to_report "--- Software Information ---"
    write_to_report "Installed Packages: $PKG_COUNT"
    write_to_report ""
    write_to_report "--- Network Interfaces ---"
    
    if command -v ip &>/dev/null; then
        ip -br addr 2>/dev/null >> "$REPORT_FILE" || write_to_report "Unable to retrieve network interfaces"
    else
        write_to_report "ip command not available"
    fi
    
    write_to_report ""
    write_to_report "======================================"

    log_info "System inventory completed successfully"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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

main "$@"