#!/bin/bash
# Script: log_analyzer.sh
# Description: Analyzes log files for all applications, summarises error counts,
#              top error messages, and generates a daily report.
# Author: Aakash
# Date: 2026-02-26
# Usage: ./scripts/log_analyzer.sh [options]

set -euo pipefail

readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${ROOT_DIR}/var/log/apps"
REPORT_DIR="${ROOT_DIR}/var/reports"
LOG_FILE="${LOG_DIR}/log_analyzer.log"
REPORT_FILE="${REPORT_DIR}/log_analysis_$(date '+%Y-%m-%d').txt"

mkdir -p "${LOG_DIR}" "${REPORT_DIR}"

VERBOSE=false
LINES=500

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "${LOG_FILE}"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "${LOG_FILE}" >&2; }

show_usage() {
  cat << EOF
Usage: $(basename $0) [OPTIONS]
Description: Analyzes application log files and generates a summary report.

OPTIONS:
  -h, --help        Show this help message
  -v, --verbose     Enable verbose output
  -l, --lines N     Number of recent log lines to analyze (default: 500)

Examples:
  $(basename $0)
  $(basename $0) --lines 1000 --verbose
EOF
}

analyze_log() {
  local app_name="$1"
  local log_pattern="$2"
  local error_pattern="${3:-error}"

  echo "" | tee -a "${REPORT_FILE}"
  echo "=== ${app_name} ===" | tee -a "${REPORT_FILE}"

  local log_files
  log_files=$(ls ${LOG_DIR}/${log_pattern} 2>/dev/null || true)

  if [[ -z "${log_files}" ]]; then
    echo "  No log files found matching: ${log_pattern}" | tee -a "${REPORT_FILE}"
    return
  fi

  for f in ${log_files}; do
    local error_count
    error_count=$(tail -"${LINES}" "${f}" 2>/dev/null | grep -ci "${error_pattern}" || echo "0")
    local warn_count
    warn_count=$(tail -"${LINES}" "${f}" 2>/dev/null | grep -ci "warn" || echo "0")
    local total_lines
    total_lines=$(wc -l < "${f}" 2>/dev/null || echo "0")
    echo "  File: $(basename ${f}) | Lines: ${total_lines} | Errors: ${error_count} | Warnings: ${warn_count}" | tee -a "${REPORT_FILE}"
  done
}

main() {
  log_info "Log analysis started"

  {
    echo "Log Analysis Report - $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Analyzed last ${LINES} lines per file"
    echo "============================================="
  } | tee -a "${REPORT_FILE}"

  analyze_log "Express API" "express-api-*" "\"level\":\"error\""
  analyze_log "FastAPI"     "fastapi-*"     "ERROR"
  analyze_log "Next.js"     "nextjs-*"      "error"
  analyze_log "App Monitor" "app_monitor*"  "ERROR"

  echo "" | tee -a "${REPORT_FILE}"
  echo "Report saved: ${REPORT_FILE}" | tee -a "${LOG_FILE}"
  log_info "Log analysis completed"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)    show_usage; exit "${EXIT_SUCCESS}" ;;
    -v|--verbose) VERBOSE=true ;;
    -l|--lines)   LINES="${2:-500}"; shift ;;
    *) echo "Unknown option: $1"; show_usage; exit "${EXIT_ERROR}" ;;
  esac
  shift
done

main "$@"