#!/bin/bash
set -euo pipefail

# Script: system_health_check.sh
# Description: Performs system health (services, disk, memory, network)
# Author: Aakash
# Date: 2026-02-06
# Usage: ./system_health_check.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/$(basename "$0" .sh).log"

log_info()  { echo "[$(TZ=Asia/Kolkata date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"  | tee -a "$LOG_FILE"; }
log_error() { echo "[$(TZ=Asia/Kolkata date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"| tee -a "$LOG_FILE" >&2; }


# Help function
show_usage() {
cat << EOF
Usage: $(basename "$0") [OPTIONS]

Checks:
  - SSH and Cron services
  - Disk usage (<90%)
  - Memory usage (<85%)
  - Network connectivity

OPTIONS:
  -h, --help     Show this help message

EOF
}
# This function checks the services like cron and ssh 
check_service() {
    local SERVICE=$1
    if systemctl is-active --quiet "$SERVICE"; then
        log_info "SERVICE $SERVICE : PASS"
    else
        log_error "SERVICE $SERVICE : FAIL"
        return 1
    fi
}

# this function checks the disk usage 
check_disk() {
    local DISK_USAGE
    DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')

    if [[ "$DISK_USAGE" -lt 90 ]]; then
        log_info "DISK USAGE ($DISK_USAGE%) : PASS"
    else
        log_error "DISK USAGE ($DISK_USAGE%) : FAIL"
        return 1
    fi
}
# this function checks the memory usage 
check_memory() {
    local MEM_USAGE
    MEM_USAGE=$(free | awk '/Mem:/ {printf("%.0f"), $3/$2 * 100}')

    if [[ "$MEM_USAGE" -lt 85 ]]; then
        log_info "MEMORY USAGE ($MEM_USAGE%) : PASS"
    else
        log_error "MEMORY USAGE ($MEM_USAGE%) : FAIL"
        return 1
    fi
}
#this function checks the network usage 
check_network() {
    if ping -c 2 8.8.8.8 > /dev/null 2>&1; then
        log_info "NETWORK CONNECTIVITY : PASS"
    else
        log_error "NETWORK CONNECTIVITY : FAIL"
        return 1
    fi
}


main() {
    log_info "---------- SYSTEM HEALTH CHECK  ----------"

    mkdir -p "$(dirname "$LOG_FILE")"

    local STATUS=$EXIT_SUCCESS

    check_service ssh  || STATUS=$EXIT_ERROR
    check_service cron || STATUS=$EXIT_ERROR
    check_disk         || STATUS=$EXIT_ERROR
    check_memory       || STATUS=$EXIT_ERROR
    check_network      || STATUS=$EXIT_ERROR

    if [[ "$STATUS" -eq "$EXIT_SUCCESS" ]]; then
        log_info "SYSTEM STATUS : HEALTHY"
    else
        log_error "SYSTEM STATUS : UNHEALTHY"
    fi

    log_info "Exiting with status code: $STATUS"

    log_info " ----------------------------------- "
    exit "$STATUS"
}


while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_usage; exit $EXIT_SUCCESS ;;
        *) log_error "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
