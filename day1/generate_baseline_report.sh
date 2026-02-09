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
REPORT_DIR="$SCRIPT_DIR/reports"
TIMESTAMP="$(TZ=Asia/Kolkata date '+%Y%m%d-%H%M%S')"
REPORT_FILE="$REPORT_DIR/baseline-$TIMESTAMP.txt"
LOG_FILE="/tmp/$(basename "$0" .sh).log" # Adjusted to /tmp as /var/log/apps often requires sudo

# Logging functions
log_info() { echo "[$(TZ=Asia/Kolkata date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(TZ=Asia/Kolkata date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }
 
# Help function
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Generates a comprehensive system baseline report including inventory, 
process snapshots, and health checks.

OPTIONS:
    -h, --help      Show this help message
    -v, --verbose   Enable verbose output

Examples:
    $(basename "$0")
EOF
}

# Main function
main() {
    log_info "Baseline report generation started"

    mkdir -p "$REPORT_DIR"

    # Generate the report
    {
        echo "====================================================="
        echo "             SYSTEM BASELINE REPORT"
        echo "====================================================="
        echo "Generated on : $(date)"
        echo "Hostname     : $(hostname)"
        echo "====================================================="
        echo

        echo "================ SYSTEM INVENTORY ==================="
        "$SCRIPT_DIR/system_inventory.sh" || echo "Error: system_inventory.sh failed"
        echo

        echo "================ PROCESS SNAPSHOT ==================="
        "$SCRIPT_DIR/process_monitor.sh" --snapshot || echo "Error: process_monitor.sh failed"
        echo

        echo "================ HEALTH CHECK ======================="
        "$SCRIPT_DIR/health_check.sh" || echo "Error: health_check.sh failed"
        echo

        echo "================ END OF REPORT ======================"
    } > "$REPORT_FILE" 2>&1

    log_info "Report saved to: $REPORT_FILE"
    log_info "Script completed successfully"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_usage; exit $EXIT_SUCCESS ;;
        -v|--verbose) set -x; shift ;;
        *) echo "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
done

main "$@"