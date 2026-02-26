#!/bin/bash
# Script: performance_check.sh
# Description: Tests response times and throughput for all health check endpoints.
#              Makes N requests to each endpoint and reports avg/min/max times.
# Author: Aakash
# Date: 2026-02-26
# Usage: ./scripts/performance_check.sh [options]

set -euo pipefail

readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${ROOT_DIR}/var/log/apps"
REPORT_DIR="${ROOT_DIR}/var/reports"
LOG_FILE="${LOG_DIR}/performance_check.log"
REPORT_FILE="${REPORT_DIR}/performance_$(date '+%Y-%m-%d_%H-%M').txt"

mkdir -p "${LOG_DIR}" "${REPORT_DIR}"

VERBOSE=false
REQUESTS=10
THRESHOLD_MS=500

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "${LOG_FILE}"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "${LOG_FILE}" >&2; }

show_usage() {
  cat << EOF
Usage: $(basename $0) [OPTIONS]
Description: Performance-tests all application health endpoints.

OPTIONS:
  -h, --help          Show this help message
  -v, --verbose       Enable verbose output
  -n, --requests N    Number of requests per endpoint (default: 10)
  -t, --threshold MS  Warning threshold in milliseconds (default: 500)

Examples:
  $(basename $0)
  $(basename $0) --requests 50 --threshold 200
EOF
}

test_endpoint() {
  local name="$1"
  local url="$2"
  local total_ms=0
  local min_ms=99999
  local max_ms=0
  local success=0

  echo "" | tee -a "${REPORT_FILE}"
  echo "${name} — ${url}" | tee -a "${REPORT_FILE}"

  for i in $(seq 1 "${REQUESTS}"); do
    local result
    result=$(curl -s -o /dev/null -w "%{http_code}:%{time_total}" --max-time 5 "${url}" 2>/dev/null || echo "000:9.999")
    local code="${result%%:*}"
    local time_s="${result##*:}"
    local time_ms
    time_ms=$(echo "${time_s} * 1000" | bc 2>/dev/null | cut -d. -f1 || echo "9999")

    if [[ "${code}" == "200" || "${code}" == "503" ]]; then
      success=$((success + 1))
    fi

    total_ms=$((total_ms + time_ms))
    [[ "${time_ms}" -lt "${min_ms}" ]] && min_ms="${time_ms}"
    [[ "${time_ms}" -gt "${max_ms}" ]] && max_ms="${time_ms}"

    [[ "${VERBOSE}" == "true" ]] && echo "  Request ${i}: HTTP ${code} — ${time_ms}ms"
    sleep 0.1
  done

  local avg_ms=$((total_ms / REQUESTS))
  local icon=""
  [[ "${avg_ms}" -gt "${THRESHOLD_MS}" ]] && icon="⚠"

  echo "  Requests: ${REQUESTS} | Success: ${success}" | tee -a "${REPORT_FILE}"
  echo "  ${icon} Avg: ${avg_ms}ms | Min: ${min_ms}ms | Max: ${max_ms}ms (threshold: ${THRESHOLD_MS}ms)" | tee -a "${REPORT_FILE}"
}

main() {
  log_info "Performance check started (${REQUESTS} requests per endpoint)"

  {
    echo "Performance Check Report - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Requests per endpoint: ${REQUESTS} | Threshold: ${THRESHOLD_MS}ms"
    echo "============================================================="
  } | tee -a "${REPORT_FILE}"

  test_endpoint "Express API"   "http://localhost:3000/api/health"
  test_endpoint "Next.js App"   "http://localhost:3001/api/health"
  test_endpoint "FastAPI"       "http://localhost:8000/health"
  test_endpoint "Laravel API"   "http://localhost:8880/api/health"

  echo "" | tee -a "${REPORT_FILE}"
  echo "Report: ${REPORT_FILE}" | tee -a "${LOG_FILE}"
  log_info "Performance check completed"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)      show_usage; exit "${EXIT_SUCCESS}" ;;
    -v|--verbose)   VERBOSE=true ;;
    -n|--requests)  REQUESTS="${2:-10}"; shift ;;
    -t|--threshold) THRESHOLD_MS="${2:-500}"; shift ;;
    *) echo "Unknown option: $1"; show_usage; exit "${EXIT_ERROR}" ;;
  esac
  shift
done

main "$@"