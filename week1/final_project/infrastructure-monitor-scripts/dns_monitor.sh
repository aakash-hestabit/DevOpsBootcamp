#!/bin/bash
set -euo pipefail

# Script: dns_monitor.sh
# Description: Monitors DNS forward/reverse resolution and query latency
# Author: Aakash
# Date: 2026-02-14
# Usage: ./dns_monitor.sh [OPTIONS]

readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FORWARD_ZONE="devops.lab"
REVERSE_ZONE="1.168.192.in-addr.arpa"
FORWARD_ZONE_FILE="/etc/bind/zones/db.devops.lab"

DNS_SERVER="127.0.0.1"
LATENCY_WARN_MS=100

LOG_DIR="var/log/apps"
LOG_FILE="${LOG_DIR}/dns_monitor.log"

VERBOSE=false
REPORT_FILE=""

mkdir -p "$LOG_DIR"

# Logging functions 
log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"; }
log_warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$LOG_FILE"; }

log_debug() {
    if $VERBOSE; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" >> "$LOG_FILE"
    fi
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

show_usage() {
cat << EOF
Usage: $(basename "$0") [OPTIONS]

Description:
  Monitors DNS forward and reverse resolution for all A records
  defined in a zone file and measures query latency.

OPTIONS:
  -s, --server IP        DNS server to query (default: 127.0.0.1)
  -z, --zone FILE        Forward zone file path
  -l, --latency MS       Latency warning threshold in ms (default: 100)
  -v, --verbose          Enable verbose/debug logging
  -h, --help             Show this help message
  --report FILE          Output report file (required)

Examples:
  $(basename "$0") --report /path/to/report.txt
  $(basename "$0") --server 192.168.1.10 --latency 200 --report /path/to/report.txt
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--server)
            DNS_SERVER="$2"
            shift 2
            ;;
        -z|--zone)
            FORWARD_ZONE_FILE="$2"
            shift 2
            ;;
        -l|--latency)
            LATENCY_WARN_MS="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
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

# Extract A records from forward zone file
get_a_records() {
    awk '
        $1 !~ /^;/ && $3 == "A" { print $1, $4 }
    ' "$FORWARD_ZONE_FILE"
}

# Measure DNS query latency (ms)
measure_latency() {
    local name="$1"
    local start end elapsed

    start=$(date +%s%3N)
    dig @"$DNS_SERVER" +short "$name" >/dev/null 2>&1 || return 1
    end=$(date +%s%3N)

    elapsed=$((end - start))
    echo "$elapsed"
}

# Forward lookup check
check_forward() {
    local host="$1"
    local expected_ip="$2"

    result=$(dig @"$DNS_SERVER" +short "$host.$FORWARD_ZONE" 2>/dev/null)

    if [[ "$result" == "$expected_ip" ]]; then
        log_pass "Forward lookup OK: $host → $expected_ip"
    else
        log_fail "Forward lookup FAILED: $host (expected $expected_ip, got ${result:-NONE})"
    fi
}

# Reverse lookup check
check_reverse() {
    local ip="$1"
    local expected_host="$2"

    result=$(dig @"$DNS_SERVER" +short -x "$ip" 2>/dev/null)

    if [[ "$result" == "$expected_host.$FORWARD_ZONE." ]]; then
        log_pass "Reverse lookup OK: $ip → $expected_host"
    else
        log_fail "Reverse lookup FAILED: $ip (expected $expected_host)"
    fi
}

main() {
    if [[ -z "$REPORT_FILE" ]]; then
        echo "Error: --report parameter is required"
        show_usage
        exit $EXIT_ERROR
    fi

    log_info "DNS monitoring started"
    log_debug "DNS server: $DNS_SERVER"
    log_debug "Zone file: $FORWARD_ZONE_FILE"
    log_debug "Latency threshold: ${LATENCY_WARN_MS}ms"

    write_to_report "========== DNS MONITORING =========="
    write_to_report "Generated on: $(date)"
    write_to_report "DNS Server: $DNS_SERVER"
    write_to_report "Zone File: $FORWARD_ZONE_FILE"
    write_to_report "Latency Threshold: ${LATENCY_WARN_MS}ms"
    write_to_report ""

    if [[ ! -f "$FORWARD_ZONE_FILE" ]]; then
        log_fail "Forward zone file not found: $FORWARD_ZONE_FILE"
        write_to_report "[ERROR] Zone file not found: $FORWARD_ZONE_FILE"
        write_to_report "========================================"
        exit $EXIT_ERROR
    fi

    while read -r host ip; do
        fqdn="$host.$FORWARD_ZONE"

        check_forward "$host" "$ip"
        check_reverse "$ip" "$host"

        latency=$(measure_latency "$fqdn" || echo "")
        if [[ -z "$latency" ]]; then
            log_fail "DNS query failed for $fqdn"
        elif (( latency > LATENCY_WARN_MS )); then
            log_warn_report "High DNS latency for $fqdn: ${latency}ms"
        else
            log_pass "DNS latency OK for $fqdn: ${latency}ms"
        fi
    done < <(get_a_records)

    write_to_report ""
    write_to_report "========================================"

    log_info "DNS monitoring completed"
    log_info "Report written to $REPORT_FILE"
    exit $EXIT_SUCCESS
}

main "$@"