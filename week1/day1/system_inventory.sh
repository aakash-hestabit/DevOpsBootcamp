#!/bin/bash
set -euo pipefail

# Script: system_inventory.sh
# Description: Generates system inventory report (OS, CPU, Memory, Disk, Network)
# Author: Aakash
# Date: 2026-02-06
# Usage: ./system_inventory.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/$(basename "$0" .sh).log"

# Logging
log_info()  { echo "[$(TZ=Asia/Kolkata date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"  | tee -a "$LOG_FILE"; }
log_error() { echo "[$(TZ=Asia/Kolkata date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"| tee -a "$LOG_FILE" >&2; }

show_usage() {
cat << EOF
Usage: $(basename "$0") [OPTIONS]

Generates system inventory report.

OPTIONS:
  -h, --help    Show help

EOF
}


get_os() {
    if command -v lsb_release &>/dev/null; then
        lsb_release -ds
    else
        grep '^PRETTY_NAME' /etc/os-release | cut -d= -f2 | tr -d '"'
    fi
}

get_package_count() {
    if command -v dpkg &>/dev/null; then
        dpkg -l | grep '^ii' | wc -l
    elif command -v rpm &>/dev/null; then
        rpm -qa | wc -l
    else
        echo "N/A"
    fi
}

main() {
    mkdir -p "$(dirname "$LOG_FILE")"

    OS=$(get_os)
    KERNEL=$(uname -r)
    UPTIME=$(uptime -p)
    CPU=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d':' -f2 | xargs)
    MEM=$(free -h | awk '/^Mem:/ {print $2}')
    DISK=$(df -h / | awk 'NR==2 {print $2}')
    PKG_COUNT=$(get_package_count)

    REPORT=$(cat <<EOF

----- SYSTEM INVENTORY REPORT -----
COMPONENT        DETAILS
------------------------------------------------------------
OS               $OS
Kernel           $KERNEL
Uptime           $UPTIME
CPU              $CPU
RAM Total        $MEM
Disk (/)         $DISK
Packages         $PKG_COUNT
------------------------------------------------------------

Network Interfaces:
$(ip -br addr 2>/dev/null | column -t)

EOF
)


    log_info "$REPORT"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_usage; exit $EXIT_SUCCESS ;;
        *) log_error "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
