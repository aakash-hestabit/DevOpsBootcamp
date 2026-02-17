#!/bin/bash
set -euo pipefail

# Script: health_check.sh
# Description: Performs system health checks (services, disk, memory, network)
# Author: Aakash
# Date: 2026-02-06
# Usage: ./health_check.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

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

log_pass() {
    local msg="[PASS] $1"
    echo "[$(TZ=Asia/Kolkata date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
    write_to_report "$msg"
}

log_fail() {
    local msg="[FAIL] $1"
    echo "[$(TZ=Asia/Kolkata date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
    write_to_report "$msg"
}

# Help function
show_usage() {
cat << EOF
Usage: $(basename "$0") [OPTIONS]

Performs comprehensive system health checks including:
  - SSH and Cron services
  - Disk usage (<90%)
  - Memory usage (<85%)
  - Network connectivity

OPTIONS:
  -h, --help       Show this help message
  --report FILE    Output report file (required)

Examples:
  $(basename "$0") --report /path/to/report.txt

EOF
}

# Check if a service is active
check_service() {
    local SERVICE=$1
    log_info "Checking service: $SERVICE"
    
    if systemctl is-active --quiet "$SERVICE"; then
        log_pass "Service $SERVICE is active"
        return 0
    else
        log_fail "Service $SERVICE is inactive"
        return 1
    fi
}

# Check disk usage
check_disk() {
    local DISK_USAGE
    DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')

    log_info "Checking disk usage: ${DISK_USAGE}%"
    
    if [[ "$DISK_USAGE" -lt 90 ]]; then
        log_pass "Disk usage is ${DISK_USAGE}% (below 90% threshold)"
        return 0
    else
        log_fail "Disk usage is ${DISK_USAGE}% (exceeds 90% threshold)"
        return 1
    fi
}

# Check memory usage
check_memory() {
    local MEM_USAGE
    MEM_USAGE=$(free | awk '/Mem:/ {printf("%.0f"), $3/$2 * 100}')

    log_info "Checking memory usage: ${MEM_USAGE}%"
    
    if [[ "$MEM_USAGE" -lt 85 ]]; then
        log_pass "Memory usage is ${MEM_USAGE}% (below 85% threshold)"
        return 0
    else
        log_fail "Memory usage is ${MEM_USAGE}% (exceeds 85% threshold)"
        return 1
    fi
}

# Check network connectivity
check_network() {
    log_info "Checking network connectivity"
    
    if ping -c 2 8.8.8.8 > /dev/null 2>&1; then
        log_pass "Network connectivity is working (ping to 8.8.8.8 successful)"
        return 0
    else
        log_fail "Network connectivity failed (cannot ping 8.8.8.8)"
        return 1
    fi
}

# Main function
main() {
    if [[ -z "$REPORT_FILE" ]]; then
        echo "Error: --report parameter is required"
        show_usage
        exit $EXIT_ERROR
    fi

    log_info "System health check started"

    write_to_report "========== SYSTEM HEALTH CHECK =========="
    write_to_report "Generated on: $(date)"
    write_to_report ""

    local STATUS=$EXIT_SUCCESS

    write_to_report "--- Service Status ---"
    check_service ssh  || STATUS=$EXIT_ERROR
    check_service cron || STATUS=$EXIT_ERROR
    write_to_report ""

    write_to_report "--- Resource Usage ---"
    check_disk         || STATUS=$EXIT_ERROR
    check_memory       || STATUS=$EXIT_ERROR
    write_to_report ""

    write_to_report "--- Network Status ---"
    check_network      || STATUS=$EXIT_ERROR
    write_to_report ""

    write_to_report "--- Overall Status ---"
    if [[ "$STATUS" -eq "$EXIT_SUCCESS" ]]; then
        write_to_report "[PASS] System status: HEALTHY"
        log_info "System status: HEALTHY"
    else
        write_to_report "[FAIL] System status: UNHEALTHY"
        log_error "System status: UNHEALTHY"
    fi

    write_to_report ""
    write_to_report "=========================================="

    log_info "System health check completed with exit status: $STATUS"
    exit "$STATUS"
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