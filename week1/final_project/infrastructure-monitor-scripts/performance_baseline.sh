#!/bin/bash
set -euo pipefail

# Script: performance_baseline.sh
# Description: Captures baseline system performance metrics for comparison after tuning
# Author: Aakash
# Date: 2026-02-15
# Usage: ./performance_baseline.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_FILE=""
LOG_FILE="var/log/apps/$(basename "$0" .sh).log"

# Sampling configuration
DURATION=60
INTERVAL=5
SAMPLES=$((DURATION / INTERVAL))

# Ensure directories exist
mkdir -p "$(dirname "$LOG_FILE")"

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"
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

Captures system performance baseline over 60 seconds
Sampling interval: 5 seconds

OPTIONS:
    -h, --help       Show this help message
    --report FILE    Output report file (required)

Examples:
    $(basename "$0") --report /path/to/report.txt
EOF
}

# Collect baseline metrics
collect_metrics() {
    local cpu_total=0 cpu_peak=0
    local load1_peak=0 load5_peak=0 load15_peak=0
    local mem_used_peak=0 swap_used_peak=0
    local rx_total=0 tx_total=0
    local process_peak=0

    write_to_report "Collecting performance metrics (${DURATION}s sampling period)..."
    write_to_report ""

    for ((i=1; i<=SAMPLES; i++)); do
        # CPU
        cpu=$(top -bn1 | awk '/Cpu\(s\)/ {print 100 - $8}')
        cpu_total=$(awk "BEGIN {print $cpu_total + $cpu}")
        (( $(awk "BEGIN {print ($cpu > $cpu_peak)}") )) && cpu_peak=$cpu

        # Load averages
        read l1 l5 l15 _ < <(awk '{print $1, $2, $3}' /proc/loadavg)
        (( $(awk "BEGIN {print ($l1 > $load1_peak)}") )) && load1_peak=$l1
        (( $(awk "BEGIN {print ($l5 > $load5_peak)}") )) && load5_peak=$l5
        (( $(awk "BEGIN {print ($l15 > $load15_peak)}") )) && load15_peak=$l15

        # Memory
        mem_used=$(free -m | awk '/Mem:/ {print $3}')
        swap_used=$(free -m | awk '/Swap:/ {print $3}')
        (( mem_used > mem_used_peak )) && mem_used_peak=$mem_used
        (( swap_used > swap_used_peak )) && swap_used_peak=$swap_used

        # Network
        read rx tx < <(awk '/:/ {rx+=$2; tx+=$10} END {print rx, tx}' /proc/net/dev)
        rx_total=$rx
        tx_total=$tx

        # Process count
        proc_count=$(ps -e --no-headers | wc -l)
        (( proc_count > process_peak )) && process_peak=$proc_count

        sleep "$INTERVAL"
    done

    cpu_avg=$(awk "BEGIN {print $cpu_total / $SAMPLES}")

    write_to_report "----- CPU Usage -----"
    write_to_report "Average CPU Usage: ${cpu_avg}%"
    write_to_report "Peak CPU Usage: ${cpu_peak}%"
    write_to_report ""
    write_to_report "Per-Core CPU Usage:"
    mpstat -P ALL 1 1 >> "$REPORT_FILE" 2>&1
    write_to_report ""
    
    write_to_report "----- Load Average -----"
    write_to_report "Peak Load (1m):  $load1_peak"
    write_to_report "Peak Load (5m):  $load5_peak"
    write_to_report "Peak Load (15m): $load15_peak"
    write_to_report ""
    
    write_to_report "----- Memory Usage -----"
    free -h >> "$REPORT_FILE" 2>&1
    write_to_report ""
    write_to_report "Peak Memory Used: ${mem_used_peak} MB"
    write_to_report "Peak Swap Used:   ${swap_used_peak} MB"
    write_to_report ""
    
    write_to_report "----- Disk I/O -----"
    iostat -x 1 1 >> "$REPORT_FILE" 2>&1
    write_to_report ""
    
    write_to_report "----- Network Activity -----"
    write_to_report "Total RX Bytes: $rx_total"
    write_to_report "Total TX Bytes: $tx_total"
    write_to_report ""
    
    write_to_report "----- Process Information -----"
    write_to_report "Peak Process Count: $process_peak"
    write_to_report ""
    write_to_report "Top CPU Consumers:"
    ps -eo pid,comm,%cpu --sort=-%cpu | head -n 6 >> "$REPORT_FILE" 2>&1
    write_to_report ""
    write_to_report "Top Memory Consumers:"
    ps -eo pid,comm,%mem --sort=-%mem | head -n 6 >> "$REPORT_FILE" 2>&1
}

# Main function
main() {
    if [[ -z "$REPORT_FILE" ]]; then
        echo "Error: --report parameter is required"
        show_usage
        exit $EXIT_ERROR
    fi

    log_info "Performance baseline capture started"
    
    write_to_report "========== PERFORMANCE BASELINE =========="
    write_to_report "Date: $(date)"
    write_to_report "Duration: ${DURATION}s (sampling interval: ${INTERVAL}s)"
    write_to_report ""
    
    collect_metrics
    
    write_to_report ""
    write_to_report "=========================================="
    
    log_info "Performance baseline capture completed"
    log_info "Report written to $REPORT_FILE"
}

# Parse arguments
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

main "$@"