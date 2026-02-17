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

Real-time process monitor showing:
  - Top 10 CPU consuming processes
  - Top 10 memory consuming processes
  - Total process count
  - Interactive process management

OPTIONS:
  -h, --help        Show this help message
  --snapshot        Generate snapshot and exit
  --report FILE     Output report file (required for snapshot mode)

Interactive Controls (monitor mode only):
  k  Kill process by PID
  q  Quit monitor

Examples:
  $(basename "$0") --snapshot --report /path/to/report.txt
  $(basename "$0")  # Interactive monitor mode

EOF
}

# Generate snapshot of processes
snapshot() {
    if [[ -z "$REPORT_FILE" ]]; then
        echo "Error: --report parameter is required for snapshot mode"
        show_usage
        exit $EXIT_ERROR
    fi

    log_info "Generating process snapshot"

    write_to_report "========== PROCESS SNAPSHOT =========="
    write_to_report "Generated on: $(date)"
    write_to_report ""

    local TOTAL_PROC
    TOTAL_PROC=$(ps aux | wc -l)
    write_to_report "Total Processes: $TOTAL_PROC"
    write_to_report ""

    write_to_report "--- Top 10 CPU Consuming Processes ---"
    ps aux --sort=-%cpu | head -n 11 >> "$REPORT_FILE" 2>&1
    write_to_report ""

    write_to_report "--- Top 10 Memory Consuming Processes ---"
    ps aux --sort=-%mem | head -n 11 >> "$REPORT_FILE" 2>&1
    write_to_report ""

    write_to_report "======================================"

    log_info "Process snapshot completed"
}

# Display real-time process statistics (interactive mode)
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

    # Log snapshot to file
    echo "--- Snapshot at $TIMESTAMP ---" >> "$LOG_FILE"
    ps aux --sort=-%cpu | head -n 6 >> "$LOG_FILE"
}

# Interactive monitor mode
interactive_monitor() {
    log_info "Process monitor started in interactive mode"

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
}

# Main function
main() {
    log_info "Process monitor initialized"
    interactive_monitor
    exit "$EXIT_SUCCESS"
}

# Parse arguments
SNAPSHOT_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --snapshot) 
            SNAPSHOT_MODE=true
            shift
            ;;
        --report)
            REPORT_FILE="$2"
            shift 2
            ;;
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

# Execute based on mode
if [[ "$SNAPSHOT_MODE" == true ]]; then
    snapshot
    exit $EXIT_SUCCESS
else
    main "$@"
fi