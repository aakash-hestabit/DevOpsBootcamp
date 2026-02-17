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
REPORT_DIR="reports"
REPORT_FILE="$REPORT_DIR/performance_baseline.txt"
LOG_FILE="var/log/apps/$(basename "$0" .sh).log"

# Sampling configuration
DURATION=60
INTERVAL=5
SAMPLES=$((DURATION / INTERVAL))

# Ensure directories exist
mkdir -p "$REPORT_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2
}

# Help function
show_usage() {
    cat << EOF
Usage: $(basename "$0")

Captures system performance baseline over 60 seconds
Sampling interval: 5 seconds

Output:
  reports/performance_baseline.txt
EOF
}

# Collect baseline metrics
collect_metrics() {
    local cpu_total=0 cpu_peak=0
    local load1_peak=0 load5_peak=0 load15_peak=0
    local mem_used_peak=0 swap_used_peak=0
    local rx_total=0 tx_total=0
    local process_peak=0

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

    {
        echo " PERFORMANCE REPORT "
        echo "Date: $(date)"
        echo "Duration: ${DURATION}s (interval ${INTERVAL}s)"
        echo
        echo "----- CPU -----"
        echo "Average CPU Usage: ${cpu_avg}%"
        echo "Peak CPU Usage: ${cpu_peak}%"
        echo "Per-core CPU:"
        mpstat -P ALL 1 1
        echo
        echo "----- Load Average -----"
        echo "Peak Load (1m):  $load1_peak"
        echo "Peak Load (5m):  $load5_peak"
        echo "Peak Load (15m): $load15_peak"
        echo
        echo "----- Memory -----"
        free -h
        echo "Peak Memory Used: ${mem_used_peak} MB"
        echo "Peak Swap Used:   ${swap_used_peak} MB"
        echo
        echo "----- Disk I/O -----"
        iostat -x 1 1
        echo
        echo "----- Network -----"
        echo "Total RX Bytes: $rx_total"
        echo "Total TX Bytes: $tx_total"
        echo
        echo "----- Processes -----"
        echo "Peak Process Count: $process_peak"
        echo
        echo "Top CPU Consumers:"
        ps -eo pid,comm,%cpu --sort=-%cpu | head -n 6
        echo
        echo "Top Memory Consumers:"
        ps -eo pid,comm,%mem --sort=-%mem | head -n 6
        echo "--------------------------------------"
    } | tee "$REPORT_FILE"
}

# Main function
main() {
    log_info "Performance baseline capture started"
    collect_metrics
    log_info "Performance baseline capture completed"
}

# Parse arguments
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
    shift
done

main "$@"
