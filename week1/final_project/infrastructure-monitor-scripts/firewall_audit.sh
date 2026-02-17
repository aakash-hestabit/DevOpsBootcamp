#!/bin/bash
set -euo pipefail

# Script: firewall_audit.sh
# Description: Audits UFW firewall rules and highlights security risks
# Author: Aakash
# Date: 2026-02-15
# Usage: sudo ./firewall_audit.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_FILE=""
LOG_FILE="var/log/apps/$(basename "$0" .sh).log"

# Globals
SECURITY_SCORE=100
ISSUES=()
SUGGESTIONS=()

# Ensure required directories exist
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
Usage: sudo $(basename "$0") [OPTIONS]

Audits UFW firewall rules and identifies common security misconfigurations.

OPTIONS:
    -h, --help       Show this help message
    --report FILE    Output report file (required)

Examples:
    sudo $(basename "$0") --report /path/to/report.txt
EOF
}

# Check if UFW is active
check_ufw_status() {
    if ! ufw status | grep -q "Status: active"; then
        ISSUES+=("[CRITICAL] Firewall is disabled")
        SUGGESTIONS+=("Enable firewall using: ufw enable")
        SECURITY_SCORE=$((SECURITY_SCORE - 30))
    fi
}

# Check SSH rate limiting
check_ssh_rate_limit() {
    if ufw status | grep -E "22/tcp" >/dev/null && \
       ! ufw status | grep -E "22/tcp.*LIMIT" >/dev/null; then
        ISSUES+=("[CRITICAL] SSH port 22 has no rate limiting")
        SUGGESTIONS+=("Apply SSH rate limiting: ufw limit 22/tcp")
        SECURITY_SCORE=$((SECURITY_SCORE - 20))
    fi
}

# Check dangerous legacy ports
check_dangerous_ports() {
    for port in 21 23; do
        if ufw status | grep -qE "$port/tcp"; then
            ISSUES+=("[CRITICAL] Dangerous port $port is open (FTP/Telnet)")
            SUGGESTIONS+=("Remove legacy service on port $port")
            SECURITY_SCORE=$((SECURITY_SCORE - 25))
        fi
    done
}

# Check MySQL exposure
check_mysql_exposure() {
    if ufw status | grep -E "3306.*Anywhere" >/dev/null; then
        ISSUES+=("[WARNING] MySQL (3306) exposed to the internet")
        SUGGESTIONS+=("Restrict MySQL to internal subnet only")
        SECURITY_SCORE=$((SECURITY_SCORE - 15))
    fi
}

# Check overly permissive rules
check_permissive_rules() {
    local count
    count=$(ufw status | grep -cE "ALLOW IN.*Anywhere" || true)
    if [[ "$count" -gt 5 ]]; then
        ISSUES+=("[WARNING] Multiple services open to Anywhere ($count rules)")
        SUGGESTIONS+=("Restrict services using IP-based rules")
        SECURITY_SCORE=$((SECURITY_SCORE - 10))
    fi
}

# Generate report
generate_report() {
    write_to_report "========== FIREWALL AUDIT =========="
    write_to_report "Date: $(date)"
    write_to_report ""
    
    local rule_count
    rule_count=$(ufw status 2>/dev/null | grep -cE 'ALLOW|DENY|LIMIT' || echo "0")
    write_to_report "Total Rules: $rule_count"
    write_to_report "Issues Found: ${#ISSUES[@]}"
    write_to_report ""
    
    write_to_report "Current Firewall Status:"
    write_to_report "----------------------------------------"
    ufw status verbose >> "$REPORT_FILE" 2>&1 || write_to_report "[ERROR] Unable to get UFW status"
    
    write_to_report ""
    write_to_report "---------- Findings ----------"
    if [[ "${#ISSUES[@]}" -eq 0 ]]; then
        write_to_report "✓ No security issues found"
    else
        for issue in "${ISSUES[@]}"; do
            write_to_report "$issue"
        done
    fi
    
    write_to_report ""
    write_to_report "---------- Recommendations ----------"
    if [[ "${#SUGGESTIONS[@]}" -eq 0 ]]; then
        write_to_report "✓ No immediate action required"
    else
        for suggestion in "${SUGGESTIONS[@]}"; do
            write_to_report "• $suggestion"
        done
    fi
    
    write_to_report ""
    write_to_report "Security Score: $SECURITY_SCORE/100"
    write_to_report "===================================="
}

# Main function
main() {
    if [[ -z "$REPORT_FILE" ]]; then
        echo "Error: --report parameter is required"
        show_usage
        exit $EXIT_ERROR
    fi

    log_info "Firewall audit started"

    # Check if running as root
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root"
        write_to_report "[ERROR] Firewall audit requires root privileges"
        exit $EXIT_ERROR
    fi

    # Run all checks
    check_ufw_status
    check_ssh_rate_limit
    check_dangerous_ports
    check_mysql_exposure
    check_permissive_rules

    # Generate report
    generate_report

    log_info "Firewall audit completed successfully"
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