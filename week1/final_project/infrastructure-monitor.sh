#!/bin/bash
set -euo pipefail

# Script: infrastructure-monitor.sh
# Description: Central monitoring orchestrator that runs all monitoring scripts
#              and generates a consolidated infrastructure health report
# Author: Aakash
# Date: 2026-02-16
# Usage: ./infrastructure-monitor.sh

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/infrastructure-monitor-scripts"
ROOT_DIR="$(realpath "$SCRIPT_DIR/..")"

REPORT_DIR="reports"
TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
REPORT_FILE="${REPORT_DIR}/infrastructure-monitor-${TIMESTAMP}.txt"

ALERT_KEYWORDS="CRITICAL|ERROR"

mkdir -p "$REPORT_DIR"

# Logging
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

log_section() {
    local msg="$1"
    echo ""
    echo "=================================================="
    echo "$msg"
    echo "=================================================="
}

# Write section header to report
write_section() {
    {
        echo ""
        echo "=================================================="
        echo "$1"
        echo "=================================================="
        echo ""
    } >> "$REPORT_FILE"
}

# Run a monitoring script
run_script() {
    local description="$1"
    local script_path="$2"
    shift 2

    log_info "Running: $description"
    write_section "$description"

    if [[ -x "$script_path" ]]; then
        # Pass the report file to the script
        if "$script_path" --report "$REPORT_FILE" "$@"; then
            log_info " $description completed successfully"
        else
            local exit_code=$?
            log_info " $description exited with status $exit_code"
            echo "[WARN] $description exited with non-zero status ($exit_code)" >> "$REPORT_FILE"
        fi
    else
        log_info " Script not found or not executable: $script_path"
        echo "[SKIPPED] Script not executable or not found: $script_path" >> "$REPORT_FILE"
    fi
}

# Generate dashboard
generate_dashboard() {
    local critical_count errors_count warnings_count overall

    critical_count=$(grep -c "CRITICAL" "$REPORT_FILE" 2>/dev/null || echo "0")
    errors_count=$(grep -c "\[ERROR\]\|\[FAIL\]" "$REPORT_FILE" 2>/dev/null || echo "0")
    warnings_count=$(grep -c "\[WARN\]" "$REPORT_FILE" 2>/dev/null || echo "0")

    if grep -Eq "CRITICAL|\[ERROR\]|\[FAIL\]" "$REPORT_FILE" 2>/dev/null; then
        overall="DEGRADED"
    else
        overall="HEALTHY"
    fi

    cat << EOF | tee -a "$REPORT_FILE"

==================================================
             INFRASTRUCTURE DASHBOARD
==================================================
Host        : $(hostname)
Timestamp   : $(date)
Report File : $REPORT_FILE
Critical    : ${critical_count}
Errors      : ${errors_count}
Warnings    : ${warnings_count}
Overall     : ${overall}
==================================================
EOF
}

# Send alert if issues detected
send_alert() {
    local report="$1"
    logger -t infra-monitor "Infrastructure issues detected. Check report: $report"
    log_info "[ALERT] Issues logged via system logger. Report: $report"
}


# Main execution
main() {
    log_info "Infrastructure monitoring started"
    log_info "Report file: $REPORT_FILE"
    
    # Initialize report file with header
    {
        echo "===================================================="
        echo "       INFRASTRUCTURE MONITORING REPORT"
        echo "===================================================="
        echo "Generated : $(date)"
        echo "Hostname  : $(hostname)"
        echo "Report ID : infrastructure-monitor-${TIMESTAMP}"
        echo "===================================================="
    } > "$REPORT_FILE"

    # SYSTEM ENGINEERING
    log_section "SYSTEM ENGINEERING & FUNDAMENTALS"
    run_script "Baseline Report Generator" \
        "$SCRIPT_DIR/generate_baseline_report.sh"

    #  USERS & PERMISSIONS
    log_section "FILESYSTEM, PERMISSIONS & USERS"
    run_script "Permission Audit" \
        "$SCRIPT_DIR/permission_audit.sh"
    run_script "User Activity Monitoring" \
        "$SCRIPT_DIR/user_activity_monitor.sh"

    #  NETWORKING & DNS
    log_section "NETWORKING & DNS"
    run_script "Network Diagnostics" \
        "$SCRIPT_DIR/network_diagnostics.sh"
    run_script "DNS Monitoring" \
        "$SCRIPT_DIR/dns_monitor.sh"

    #  SECURITY & PERFORMANCE
    log_section "SECURITY & PERFORMANCE"
    run_script "Firewall Audit" \
        "$SCRIPT_DIR/firewall_audit.sh"
    run_script "Performance Baseline" \
        "$SCRIPT_DIR/performance_baseline.sh"

    #  CORE MONITORING & REPORTING
    log_section "SYSTEM HEALTH"
    run_script "System Health Report Generator" \
        "$SCRIPT_DIR/syshealth-report.sh"

    # SYSTEMD MONITORING STATUS
    log_section "SYSTEMD MONITORING STATUS"
    write_section "SYSTEMD MONITORING STATUS"
    
    {
        echo "--- monitor.service ---"
        if systemctl status monitor.service --no-pager 2>/dev/null; then
            echo ""
        else
            echo "monitor.service not found or inactive"
        fi
        
        echo ""
        echo "--- monitor.timer ---"
        if systemctl list-timers --no-pager 2>/dev/null | grep -q monitor; then
            systemctl list-timers --no-pager | grep monitor
        else
            echo "monitor.timer not found"
        fi
    } >> "$REPORT_FILE"

    generate_dashboard

    log_info "Infrastructure monitoring completed"
    log_info "Report generated: $REPORT_FILE"
    
    echo ""
    echo "Summary:"
    echo "  Report Location: $REPORT_FILE"
    echo "  Size: $(du -h "$REPORT_FILE" | cut -f1)"
    echo ""
}

main

exit $EXIT_SUCCESS