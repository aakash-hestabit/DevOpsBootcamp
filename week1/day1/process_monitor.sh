#!/bin/bash
set -euo pipefail

# Script: process_monitor.sh
# Description: Real-time process monitor with logging and process control
# Author: Aakash
# Date: 2026-02-06
# Usage: ./process_monitor.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/$(basename "$0" .sh).log"

# Logging functions
log_info()  { echo "[$(TZ=Asia/Kolkata date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"  | tee -a "$LOG_FILE"; }
log_error() { echo "[$(TZ=Asia/Kolkata date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"| tee -a "$LOG_FILE" >&2; }

# Help function
show_usage() {
cat << EOF
Usage: $(basename "$0") [OPTIONS]

Shows:
  - Top 10 CPU consuming processes
  - Top 10 memory consuming processes
  - Total process count
  - Allows killing process by PID

OPTIONS:
  -h, --help     Show help

Controls while running:
  k  Kill process
  q  Quit monitor

EOF
}
# Snaphot of the processes at the present time
snapshot() {
    {
        echo "===== PROCESS SNAPSHOT ====="
        echo "Top 10 CPU processes:"
        ps aux --sort=-%cpu | head -n 11
        echo
        echo "Top 10 Memory processes:"
        ps aux --sort=-%mem | head -n 11
    } | tee -a "$LOG_FILE"
}

display_stats() {
    local TIMESTAMP
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

    clear
    echo "===== PROCESS MONITOR ====="
    echo "Time: $TIMESTAMP"

    local TOTAL_PROC
    TOTAL_PROC=$(ps aux | wc -l)
    echo "Total Processes: $TOTAL_PROC"
    echo "------------------------------------------------------"

    echo -e "\nTOP 10 PROCESSES BY CPU:"
    printf "%-7s %-8s %-5s %s\n" "PID" "USER" "%CPU" "COMMAND"
    ps aux --sort=-%cpu | awk 'NR>1 {printf "%-7s %-8s %-5s %s\n",$2,$1,$3,$11}' | head -n 10 || true

    echo -e "\nTOP 10 PROCESSES BY MEMORY:"
    printf "%-7s %-8s %-5s %s\n" "PID" "USER" "%MEM" "COMMAND"
    ps aux --sort=-%mem | awk 'NR>1 {printf "%-7s %-8s %-5s %s\n",$2,$1,$4,$11}' | head -n 10 || true

    echo "------------------------------------------------------"
    echo "Options: [k] Kill Process | [q] Quit | Auto refresh 5s"

    # Log snapshot
    echo "--- Snapshot at $TIMESTAMP ---" >> "$LOG_FILE"
    ps aux --sort=-%cpu | head -n 6 >> "$LOG_FILE"
}


main() {
    mkdir -p "$(dirname "$LOG_FILE")"
    log_info "Process monitor started"

    while true; do
        display_stats

        read -t 5 -n 1 action || true

        if [[ "${action:-}" == "k" ]]; then
            echo
            read -rp "Enter PID to kill: " pid_to_kill
            if kill -9 "$pid_to_kill" 2>/dev/null; then
                log_info "Killed process PID $pid_to_kill"
                echo "Process killed."
            else
                log_error "Failed to kill PID $pid_to_kill"
                echo "Error killing process."
            fi
            sleep 2
        elif [[ "${action:-}" == "q" ]]; then
            log_info "Process monitor exited by user"
            break
        fi
    done

    log_info "Process monitor stopped"
    exit "$EXIT_SUCCESS"
}


while [[ $# -gt 0 ]]; do
    case $1 in
        --snapshot) snapshot; exit 0 ;;
        -h|--help) show_usage; exit $EXIT_SUCCESS ;;
        *) log_error "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
