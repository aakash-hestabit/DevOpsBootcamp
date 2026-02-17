#!/bin/bash
set -euo pipefail

# Script: system_inventory.sh
# Description: Generates system inventory report (OS, CPU, Memory, Disk, Network)
# Author: Aakash
# Date: 2026-02-17
# Usage: ./system_inventory.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="../var/log/apps/$(basename "$0" .sh).log"
REPORT_FILE=""

mkdir -p "$(dirname "$LOG_FILE")"

# Logging functions
log_info() {
    echo "[$(TZ=Asia/Kolkata date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
    logger -t "$(basename "$0")" -p local0.info "$1" 2>/dev/null || true
}

log_error() {
    echo "[$(TZ=Asia/Kolkata date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE" >&2
    logger -t "$(basename "$0")" -p local0.err "$1" 2>/dev/null || true
}

# Report writing function
write_to_report() {
    if [[ -n "$REPORT_FILE" ]]; then
        echo "$1" >> "$REPORT_FILE"
    fi
}

show_usage() {
cat << EOF
Usage: $(basename "$0") [OPTIONS]

Generates system inventory report.

OPTIONS:
  -h, --help       Show help
  --report FILE    Output report file (required)

EOF
}

get_os() {
    if command -v lsb_release &>/dev/null; then
        lsb_release -ds
    else
        grep '^PRETTY_NAME' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "Unknown"
    fi
}

get_package_count() {
    if command -v dpkg &>/dev/null; then
        dpkg -l | grep -c '^ii' || echo "0"
    elif command -v rpm &>/dev/null; then
        rpm -qa | wc -l
    else
        echo "N/A"
    fi
}

main() {
    if [[ -z "$REPORT_FILE" ]]; then
        echo "Error: --report parameter is required"
        show_usage
        exit $EXIT_ERROR
    fi

    log_info "System inventory started"

    local OS KERNEL UPTIME CPU MEM DISK PKG_COUNT
    OS=$(get_os)
    KERNEL=$(uname -r)
    UPTIME=$(uptime -p)
    CPU=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -n1 | cut -d':' -f2 | xargs || echo "Unknown")
    MEM=$(free -h | awk '/^Mem:/ {print $2}')
    DISK=$(df -h / | awk 'NR==2 {print $2}')
    PKG_COUNT=$(get_package_count)

    write_to_report "========== SYSTEM INVENTORY =========="
    write_to_report "Generated on: $(date)"
    write_to_report ""
    write_to_report "--- System Information ---"
    write_to_report "Operating System : $OS"
    write_to_report "Kernel Version   : $KERNEL"
    write_to_report "System Uptime    : $UPTIME"
    write_to_report ""
    write_to_report "--- Hardware ---"
    write_to_report "CPU              : $CPU"
    write_to_report "Total RAM        : $MEM"
    write_to_report "Disk (/)         : $DISK"
    write_to_report ""
    write_to_report "--- Software ---"
    write_to_report "Installed Packages: $PKG_COUNT"
    write_to_report ""
    write_to_report "--- Network Interfaces ---"
    ip -br addr 2>/dev/null >> "$REPORT_FILE" || write_to_report "Unable to retrieve interfaces"
    write_to_report ""
    write_to_report "======================================"

    log_info "System inventory completed"
}

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
            log_error "Unknown option: $1"
            show_usage
            exit $EXIT_ERROR
            ;;
    esac
done

main "$@"