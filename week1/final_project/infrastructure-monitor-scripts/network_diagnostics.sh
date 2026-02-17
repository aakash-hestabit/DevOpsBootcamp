#!/bin/bash
set -euo pipefail

# Script: network_diagnostics.sh
# Description: Comprehensive network diagnostics and connectivity checks
# Author: Aakash
# Date: 2026-02-13
# Usage: ./network_diagnostics.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="var/log/apps"
LOG_FILE="${LOG_DIR}/network_diag_$(date +%Y%m%d).log"

# Defaults
VERBOSE=false
LATENCY_WARN_MS=200
REPORT_FILE=""

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Logging functions 
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE" >&2
}

# Report writing functions
write_to_report() {
    if [[ -n "$REPORT_FILE" ]]; then
        echo "$1" >> "$REPORT_FILE"
    fi
}

log_pass() {
    local msg="[PASS] $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
    write_to_report "$msg"
}

log_fail() {
    local msg="[FAIL] $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
    write_to_report "$msg"
}

log_warn_report() {
    local msg="[WARN] $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
    write_to_report "$msg"
}

# Help function
show_usage() {
    cat << EOF
Usage: $(basename $0) [OPTIONS]

Network diagnostics and connectivity validation.

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    --port HOST:PORT        Test TCP connectivity to host:port
    --report FILE           Output report file (required)

Examples:
    $(basename $0) --report /path/to/report.txt
    $(basename $0) --port localhost:80 --report /path/to/report.txt
    $(basename $0) --verbose --report /path/to/report.txt
EOF
}

run_cmd() {
    if [[ "$VERBOSE" == true ]]; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

# Check internet connectivity
check_internet() {
    log_info "Checking internet connectivity"
    if ping -c 3 -W 2 8.8.8.8 >/dev/null 2>&1 && ping -c 3 -W 2 1.1.1.1 >/dev/null 2>&1; then
        log_pass "Internet connectivity: OK"
    else
        log_fail "Internet connectivity: FAILED"
    fi
}

# Check DNS resolution
check_dns() {
    log_info "Checking DNS resolution"
    if dig +short google.com 2>/dev/null | grep -qE '^[0-9]'; then
        log_pass "DNS resolution: OK"
    else
        log_fail "DNS resolution: FAILED"
    fi
}

# Display network interfaces
show_interfaces() {
    log_info "Listing network interfaces and IP addresses"
    write_to_report ""
    write_to_report "Network Interfaces:"
    ip addr >> "$REPORT_FILE" 2>&1
}

# Show routing table
show_routes() {
    log_info "Displaying routing table"
    write_to_report ""
    write_to_report "Routing Table:"
    ip route >> "$REPORT_FILE" 2>&1
}

# List open ports
list_ports() {
    log_info "Listing listening ports"
    write_to_report ""
    write_to_report "Listening Ports:"
    ss -tuln >> "$REPORT_FILE" 2>&1
}

# Test port connectivity
test_port() {
    local target="$1"
    local host="${target%%:*}"
    local port="${target##*:}"

    log_info "Testing TCP connectivity to ${host}:${port}"
    if nc -z -w 3 "$host" "$port" >/dev/null 2>&1; then
        log_pass "Port ${port} on ${host}: Connection successful"
    else
        log_fail "Port ${port} on ${host}: Connection refused"
    fi
}

# Measure latency
measure_latency() {
    local host="$1"
    log_info "Measuring latency to ${host}"

    local avg_latency
    avg_latency=$(ping -c 5 "$host" 2>/dev/null | awk -F'/' 'END {print $5}')

    if [[ -z "$avg_latency" ]]; then
        log_fail "Latency check to ${host}: FAILED"
        return
    fi

    avg_latency_int=${avg_latency%.*}

    if (( avg_latency_int > LATENCY_WARN_MS )); then
        log_warn_report "High latency to ${host}: ${avg_latency} ms"
    else
        log_pass "Latency to ${host}: ${avg_latency} ms"
    fi
}

# Main function
main() {
    if [[ -z "$REPORT_FILE" ]]; then
        echo "Error: --report parameter is required"
        show_usage
        exit $EXIT_ERROR
    fi

    log_info "Network diagnostics started"
    
    write_to_report "========== NETWORK DIAGNOSTICS =========="
    write_to_report "Generated on: $(date)"
    write_to_report ""

    check_internet
    check_dns
    show_interfaces
    show_routes
    list_ports

    if [[ -n "${PORT_TARGET:-}" ]]; then
        write_to_report ""
        write_to_report "Port Connectivity Test:"
        test_port "$PORT_TARGET"
    fi

    # Latency checks
    write_to_report ""
    write_to_report "Latency Checks:"
    measure_latency "8.8.8.8"
    measure_latency "1.1.1.1"

    write_to_report ""
    write_to_report "=========================================="

    log_info "Network diagnostics completed"
    log_info "Report written to $REPORT_FILE"
}

# Parse arguments
PORT_TARGET=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit $EXIT_SUCCESS
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --port)
            PORT_TARGET="$2"
            shift 2
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