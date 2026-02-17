#!/bin/bash
set -euo pipefail

# Script: generate_baseline_report.sh
# Description: Master script to create system baseline reports by aggregating sub-scripts.
# Author: Aakash
# Date: 2026-02-09
# Usage: ./generate_baseline_report.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(TZ=Asia/Kolkata date '+%Y%m%d-%H%M%S')"
REPORT_FILE=""
LOG_FILE="var/log/apps/$(basename "$0" .sh).log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging functions 
log_info() { echo "[$(TZ=Asia/Kolkata date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"; }
log_error() { echo "[$(TZ=Asia/Kolkata date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"; }

# Report writing function
write_to_report() {
    echo "$1" >> "$REPORT_FILE"
}

# Help function
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Generates a comprehensive system baseline report including inventory, 
process snapshots, and health checks.

OPTIONS:
    -h, --help      Show this help message
    -v, --verbose   Enable verbose output
    --report FILE   Output report file (required)

Examples:
    $(basename "$0") --report /path/to/report.txt
EOF
}

# Main function
main() {
    if [[ -z "$REPORT_FILE" ]]; then
        echo "Error: --report parameter is required"
        show_usage
        exit $EXIT_ERROR
    fi

    log_info "Baseline report generation started"

    # Generate the report
    write_to_report "====================================================="
    write_to_report "             SYSTEM BASELINE REPORT"
    write_to_report "====================================================="
    write_to_report "Generated on : $(date)"
    write_to_report "Hostname     : $(hostname)"
    write_to_report "====================================================="
    write_to_report ""

    # System Inventory
    if [[ -x "$SCRIPT_DIR/system_inventory.sh" ]]; then
        write_to_report "================ SYSTEM INVENTORY ==================="
        "$SCRIPT_DIR/system_inventory.sh" --report "$REPORT_FILE" 2>&1 || write_to_report "[ERROR] system_inventory.sh failed"
        write_to_report ""
    else
        write_to_report "================ SYSTEM INVENTORY ==================="
        write_to_report "[SKIPPED] system_inventory.sh not found or not executable"
        write_to_report ""
        log_error "system_inventory.sh not found"
    fi

    # Process Snapshot
    if [[ -x "$SCRIPT_DIR/process_monitor.sh" ]]; then
        write_to_report "================ PROCESS SNAPSHOT ==================="
        "$SCRIPT_DIR/process_monitor.sh" --snapshot --report "$REPORT_FILE" 2>&1 || write_to_report "[ERROR] process_monitor.sh failed"
        write_to_report ""
    else
        write_to_report "================ PROCESS SNAPSHOT ==================="
        write_to_report "[SKIPPED] process_monitor.sh not found or not executable"
        write_to_report ""
        log_error "process_monitor.sh not found"
    fi

    # Health Check
    if [[ -x "$SCRIPT_DIR/health_check.sh" ]]; then
        write_to_report "================ HEALTH CHECK ======================="
        "$SCRIPT_DIR/health_check.sh" --report "$REPORT_FILE" 2>&1 || write_to_report "[ERROR] health_check.sh failed"
        write_to_report ""
    else
        write_to_report "================ HEALTH CHECK ======================="
        write_to_report "[SKIPPED] health_check.sh not found or not executable"
        write_to_report ""
        log_error "health_check.sh not found"
    fi

    write_to_report "================ END OF REPORT ======================"

    log_info "Report completed: $REPORT_FILE"
    log_info "Script completed successfully"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_usage; exit $EXIT_SUCCESS ;;
        -v|--verbose) set -x; shift ;;
        --report)
            REPORT_FILE="$2"
            shift 2
            ;;
        *) echo "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
done

main "$@"