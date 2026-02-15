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
REPORT_DIR="reports"
REPORT_FILE="$REPORT_DIR/firewall_audit_$(date +%Y%m%d).txt"
LOG_FILE="var/log/apps/$(basename "$0" .sh).log"

# Globals
SECURITY_SCORE=100
ISSUES=()
SUGGESTIONS=()

# Ensure required directories exist
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
Usage: sudo $(basename "$0") [OPTIONS]

Audits UFW firewall rules and identifies common security misconfigurations.

OPTIONS:
    -h, --help      Show this help message

Examples:
    sudo $(basename "$0")
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
    {
        echo "========== FIREWALL AUDIT =========="
        echo "Date: $(date)"
        echo
        echo "Rules : $(ufw status | grep -E 'ALLOW|DENY|LIMIT' | wc -l)"
        echo 
        echo "Issues : ${#ISSUES[@]}"
        echo
        ufw status verbose
        echo
        echo "---------- Findings ----------"
        if [[ "${#ISSUES[@]}" -eq 0 ]]; then
            echo "No issues found "
        else
            for issue in "${ISSUES[@]}"; do
                echo "$issue"
            done
        fi
        echo
        echo "---------- Recommendations ----------"
        if [[ "${#SUGGESTIONS[@]}" -eq 0 ]]; then
            echo "No immediate action required"
        else
            for suggestion in "${SUGGESTIONS[@]}"; do
                echo "- $suggestion"
            done
        fi
        echo
        echo "Security Score: $SECURITY_SCORE/100"
        echo "===================================="
    } | tee "$REPORT_FILE"
}

# Main function
main() {
    log_info "Firewall audit started"

    check_ufw_status
    check_ssh_rate_limit
    check_dangerous_ports
    check_mysql_exposure
    check_permissive_rules

    generate_report

    log_info "Firewall audit completed successfully"
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
