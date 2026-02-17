#!/bin/bash
set -euo pipefail

# Script: monitor.sh
# Description: Monitors system health by checking disk, memory, and CPU usage
# Author: Aakash
# Date: 2026-02-16
# Usage: ./monitor.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/var/log/apps"
LOG_FILE="${LOG_DIR}/monitor.log"
ALERT_LOG="${LOG_DIR}/alerts.log"

# Thresholds (percentage)
DISK_THRESHOLD=80
MEM_THRESHOLD=80
CPU_THRESHOLD=80

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ALERT] $1" >> "$ALERT_LOG"
}

# Help function
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Monitors system health and logs alerts if thresholds are exceeded.

OPTIONS:
    -h, --help      Show this help message

Examples:
    $(basename "$0")
EOF
}

# Disk usage check
check_disk() {
    log_info "Checking disk usage..."

    while read -r usage mount; do
        if [[ "$usage" -gt "$DISK_THRESHOLD" ]]; then
            log_error "Disk usage HIGH: ${mount} is at ${usage}% (threshold: ${DISK_THRESHOLD}%)"
            return 1
        fi
    done < <(
        df -h --output=pcent,target | tail -n +2 | \
        grep -vE 'tmpfs|cdrom|loop' | sed 's/%//g'
    )

    log_info "Disk usage: OK"
    return 0
}

# Memory usage check
check_memory() {
    log_info "Checking memory usage..."

    local mem_usage
    mem_usage=$(free | awk '/Mem/ {printf "%.0f", ($3/$2) * 100}')

    if [[ "$mem_usage" -gt "$MEM_THRESHOLD" ]]; then
        log_error "Memory usage HIGH: ${mem_usage}% (threshold: ${MEM_THRESHOLD}%)"
        return 1
    fi

    log_info "Memory usage: ${mem_usage}% - OK"
    return 0
}

# CPU usage check
check_cpu() {
    log_info "Checking CPU usage..."

    local cpu_usage
    cpu_usage=$(top -bn1 | awk '/Cpu\(s\)/ {print int($2)}')

    if [[ "$cpu_usage" -gt "$CPU_THRESHOLD" ]]; then
        log_error "CPU usage HIGH: ${cpu_usage}% (threshold: ${CPU_THRESHOLD}%)"
        return 1
    fi

    log_info "CPU usage: ${cpu_usage}% - OK"
    return 0
}

# Main function
main() {
    log_info "========== System Health Check Started =========="

    local status=0
    check_disk   || status=1
    check_memory || status=1
    check_cpu    || status=1

    if [[ "$status" -eq 0 ]]; then
        log_info "All system checks passed successfully"
    else
        log_warn "One or more system checks failed. Review alerts."
    fi

    log_info "========== System Health Check Completed =========="
    exit "$status"
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

main "$@"
