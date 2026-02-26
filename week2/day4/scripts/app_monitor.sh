#!/bin/bash
# Script:  app_monitor.sh
# Author:  Aakash
# Date:    2026-02-26
# Usage:   ./scripts/app_monitor.sh [-v] [-e EMAIL]
# Exits:   0 = healthy | 1 = one or more critical issues
#
# NOTE: -e intentionally omitted from set flags.
#       grep -c exits 1 on zero matches; that would abort under "set -e".

set -uo pipefail

# Paths & global config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${ROOT_DIR}/var/log/apps"
REPORT_DIR="${ROOT_DIR}/var/reports"
LOG_FILE="${LOG_DIR}/app_monitor.log"
REPORT_FILE="${REPORT_DIR}/monitor_$(date '+%Y-%m-%d').log"
mkdir -p "${LOG_DIR}" "${REPORT_DIR}"

EMAIL=""
ISSUES=0
WARNINGS=0
MEM_WARN_MB=500
RT_WARN_MS=1000

# 
# Logging helpers
# 
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"; }
emit() { echo "$1" | tee -a "${REPORT_FILE}"; }

show_usage() {
  echo "Usage: $(basename "$0") [-h] [-v] [-e EMAIL]"
  echo "  -h  Help    -v  Verbose (set -x)    -e  Alert email"
}

# 
# Low-level helpers
# 

# proc_mem/cpu/cnt: use bracket trick e.g. '[u]vicorn' to avoid self-match
proc_mem() { ps aux | grep "$1" | awk '{s+=$6} END{printf "%.0f",s/1024}'; }
proc_cpu() { ps aux | grep "$1" | awk '{s+=$3} END{printf "%.1f",s}'; }
proc_cnt() { ps aux | grep "$1" | wc -l; }

http_check() {
  # Returns "HTTP_CODE:MILLISECONDS"
  local r
  r=$(curl -s -o /dev/null -w "%{http_code}:%{time_total}" --max-time 5 "$1" 2>/dev/null \
      || echo "000:9.999")
  local ms; ms=$(awk "BEGIN{printf \"%d\", ${r##*:} * 1000}")
  echo "${r%%:*}:${ms}"
}

# 
# PM2 helper — parses pm2 jlist JSON via Python (no walrus, works on 3.6+)
# Returns: "online_count:mem_mb:uptime_str:cpu_pct"
# 
pm2_stats() {
  local app="$1"
  command -v pm2 &>/dev/null || { echo "0:0:N/A:0.0"; return; }
  
  pm2 jlist 2>/dev/null | python3 -c "
import json, time, sys
try:
    data = json.load(sys.stdin)
except:
    print('0:0:N/A:0.0'); sys.exit(1)

app_name = '$app'
apps = [a for a in data if a.get('name') == app_name]
if not apps:
    print('0:0:N/A:0.0'); sys.exit(0)

online  = sum(1 for a in apps if a.get('pm2_env', {}).get('status') == 'online')
mem_mb  = sum(a.get('monit', {}).get('memory', 0) for a in apps) // (1024 * 1024)
cpu     = sum(a.get('monit', {}).get('cpu', 0)    for a in apps)

uptimes = [a['pm2_env']['pm_uptime']
           for a in apps if a.get('pm2_env', {}).get('pm_uptime')]
if uptimes:
    elapsed = int((time.time() * 1000 - min(uptimes)) / 1000)
    uptime  = '{}h {}m'.format(elapsed // 3600, (elapsed % 3600) // 60)
else:
    uptime = 'N/A'

print('{}:{}:{}:{:.1f}'.format(online, mem_mb, uptime, cpu))
"
}

# 
# Reporting helpers
# 
report_line() {
  # Usage: report_line PASS|WARN|ISSUE "message"
  case "$1" in
    WARN)  WARNINGS=$((WARNINGS + 1)); emit "  [WARN]  $2" ;;
    ISSUE) ISSUES=$((ISSUES + 1));     emit "  [ISSUE] $2" ;;
    *)                                 emit "  [PASS]  $2" ;;
  esac
}

health_line() {
  # Usage: health_line "label" "CODE:MS"
  local label="$1" code="${2%%:*}" ms="${2##*:}"
  if   [[ "${code}" != "200" ]];          then report_line ISSUE "${label}: HTTP ${code} (${ms}ms)"
  elif [[ "${ms}" -gt "${RT_WARN_MS}" ]]; then report_line WARN  "${label}: HTTP ${code} (${ms}ms) — slow response"
  else                                         report_line PASS  "${label}: HTTP ${code} (${ms}ms)"
  fi
}

# Usage: mem_line "label" mem_mb [limit_mb]
mem_line() {
  local label="$1" mem="$2" limit="${3:-0}"
  if [[ "${limit}" -gt 0 ]]; then
    local pct; pct=$(awk "BEGIN{printf \"%d\", ${mem}/${limit}*100}")
    local txt="${mem}MB / ${limit}MB (${pct}%)"
    [[ "${pct}" -ge 80 ]] && report_line WARN "${label}: ${txt}" \
                          || report_line PASS "${label}: ${txt}"
  else
    [[ "${mem}" -gt "${MEM_WARN_MB}" ]] \
      && report_line WARN  "${label}: ${mem}MB — high" \
      || report_line PASS  "${label}: ${mem}MB"
  fi
}

# 
# Application checks
# 

check_express() {
  emit ""; emit "Express API (Port 3000):"

  # pm2_stats returns "online:mem_mb:uptime:cpu"
  local stats; stats=$(pm2_stats "express-api")
  local online="${stats%%:*}"; stats="${stats#*:}"
  local mem="${stats%%:*}";    stats="${stats#*:}"
  local uptime="${stats%%:*}"; local cpu="${stats##*:}"

  [[ "${online}" -ge 1 ]] \
    && report_line PASS  "PM2 Status: online (${online} instances)" \
    || report_line ISSUE "PM2 Status: offline / not found in PM2"

  health_line "Health Check" "$(http_check "http://localhost:3000/api/health")"
  mem_line    "Memory"       "${mem}" 500
  report_line PASS "CPU: ${cpu}%"
  report_line PASS "Uptime: ${uptime}"

  # Error log (written by winston to LOG_DIR)
  local logf="${LOG_DIR}/express-api-error-$(date '+%Y-%m-%d').log"
  local errs=0
  [[ -f "${logf}" ]] && errs=$(grep -c '"level":"error"' "${logf}" 2>/dev/null) || errs=0
  [[ "${errs}" -eq 0 ]] \
    && report_line PASS "Error log: No recent errors" \
    || report_line WARN "Error log: ${errs} error(s) today"
}

check_nextjs() {
  emit ""; emit "Next.js App (Port 3001):"

  local stats; stats=$(pm2_stats "nextjs-app")
  local online="${stats%%:*}"; stats="${stats#*:}"
  local mem="${stats%%:*}";    stats="${stats#*:}"
  local uptime="${stats%%:*}"; local cpu="${stats##*:}"

  [[ "${online}" -ge 1 ]] \
    && report_line PASS  "PM2 Status: online (${online} instances)" \
    || report_line ISSUE "PM2 Status: offline / not found in PM2"

  health_line "Health Check" "$(http_check "http://localhost:3001/api/health")"
  mem_line    "Memory"       "${mem}" 500
  report_line PASS "CPU: ${cpu}%"
  report_line PASS "Uptime: ${uptime}"
}

check_fastapi() {
  emit ""; emit "FastAPI (Port 8000):"

  # Deployed via Supervisor (conf: fastapi-mysql-api)
  local svc="unknown"
  if command -v supervisorctl &>/dev/null; then
    local raw; raw=$(supervisorctl status fastapi-mysql-api 2>/dev/null | awk '{print $2}' || true)
    # Only accept known supervisord state words
    [[ "${raw}" =~ ^(RUNNING|STOPPED|FATAL|STARTING|STOPPING|BACKOFF|EXITED|UNKNOWN)$ ]] \
      && svc="${raw}" || svc="supervisor-error"
  fi
  # Fallback: raw process check
  if [[ "${svc}" == "unknown" || "${svc}" == "supervisor-error" ]]; then
    ps aux | grep -q '[u]vicorn' && svc="running (process)" || svc="not running"
  fi

  [[ "${svc}" == "RUNNING" || "${svc}" == "running (process)" ]] \
    && report_line PASS "Service Status: ${svc}" \
    || report_line WARN "Service Status: ${svc}"

  health_line "Health Check" "$(http_check "http://localhost:8000/health")"
  mem_line    "Memory"       "$(proc_mem '[u]vicorn')"
  report_line PASS "CPU: $(proc_cpu '[u]vicorn')%"

  # Get configured worker count from supervisor config
  local configured_workers=4
  if [[ -f /etc/supervisor/conf.d/fastapi-mysql-api.conf ]]; then
    configured_workers=$(grep -oP '(?<=--workers\s)\d+' /etc/supervisor/conf.d/fastapi-mysql-api.conf || echo "4")
  fi
  
  # Count actual uvicorn worker processes
  # Uvicorn master spawns child python3 processes for each worker
  local actual_workers=0
  
  # Get uvicorn master process PID and count its child processes
  if command -v pgrep &>/dev/null; then
    local master_pid
    master_pid=$(pgrep -f 'uvicorn.*--port 8000' 2>/dev/null | head -1)
    if [[ -n "${master_pid}" ]]; then
      actual_workers=$(pgrep -P "${master_pid}" 2>/dev/null | wc -l)
      # Uvicorn may have 1 extra process for monitoring, so adjust if needed
      [[ ${actual_workers} -gt ${configured_workers} ]] && actual_workers=${configured_workers}
    fi
  fi
  
  # Alert based on actual worker count vs configured
  if [[ ${actual_workers} -eq ${configured_workers} ]]; then
    report_line PASS "Workers: ${actual_workers}/${configured_workers} active"
  elif [[ ${actual_workers} -gt 0 && ${actual_workers} -lt ${configured_workers} ]]; then
    report_line WARN "Workers: ${actual_workers}/${configured_workers} active (${configured_workers} expected)"
  else
    ps aux | grep -q '[u]vicorn' && \
      report_line WARN "Workers: 0/${configured_workers} active (process running but workers not spawned)" || \
      report_line ISSUE "Workers: 0/${configured_workers} active (not running)"
  fi
}

check_laravel() {
  emit ""; emit "Laravel API (Port 8880):"

  health_line "Health Check" "$(http_check "http://localhost:8880/api/health")"

  # artisan serve process count (bracket trick)
  local api_cnt; api_cnt=$(proc_cnt '[a]rtisan serve')
  report_line PASS "Laravel API instances: ${api_cnt}"
  mem_line    "Memory" "$(proc_mem '[a]rtisan serve')"
  report_line PASS "CPU: $(proc_cpu '[a]rtisan serve')%"

  emit ""; emit "Laravel Queue Worker:"

  # Queue worker deployed via systemd (laravel-worker.service)
  local svc="unknown"
  command -v systemctl &>/dev/null && \
    svc=$(systemctl is-active laravel-worker 2>/dev/null || echo "inactive")
  # Fallback: raw process check
  [[ "${svc}" == "inactive" || "${svc}" == "unknown" ]] && \
    ps aux | grep -q '[a]rtisan queue' && svc="active (process)"

  [[ "${svc}" =~ ^active ]] \
    && report_line PASS "Systemd Status: ${svc}" \
    || report_line WARN "Systemd Status: ${svc}"

  report_line PASS "Queue worker instances: $(proc_cnt '[a]rtisan queue')"

  # Parse processed/failed counts from Laravel log (last hour)
  local llog="/var/www/laravel-mysql-api/storage/logs/laravel.log"
  local processed=0 failed=0
  if [[ -f "${llog}" ]]; then
    local cutoff; cutoff=$(date -d '1 hour ago' '+%Y-%m-%d %H' 2>/dev/null || \
                           date -v-1H '+%Y-%m-%d %H' 2>/dev/null || echo "")
    if [[ -n "${cutoff}" ]]; then
      processed=$(grep "Processed" "${llog}" 2>/dev/null | grep "${cutoff}" | wc -l)
      failed=$(grep "Failed" "${llog}" 2>/dev/null | grep "${cutoff}" | wc -l)
    fi
  fi
  report_line PASS "Queue Jobs: ${processed} processed last hour"
  [[ "${failed}" -eq 0 ]] && report_line PASS "Failed Jobs: 0" \
                           || report_line WARN "Failed Jobs: ${failed}"

  mem_line    "Memory" "$(proc_mem '[a]rtisan queue')"
  report_line PASS "CPU: $(proc_cpu '[a]rtisan queue')%"
}

# 
# Summary + optional alert email
# 
print_summary() {
  emit ""; emit "----------------------------------------------------"
  [[ "${ISSUES}" -eq 0 && "${WARNINGS}" -eq 0 ]] \
    && emit "Overall Status:  All systems healthy" \
    || emit "Overall Status:  ${WARNINGS} warning(s), ${ISSUES} critical issue(s)"
  log "Complete — warnings: ${WARNINGS}, issues: ${ISSUES}. Report: ${REPORT_FILE}"
}

send_alert() {
  [[ -z "${EMAIL}" || $(( ISSUES + WARNINGS )) -eq 0 ]] && return
  command -v mail &>/dev/null \
    && mail -s "[ALERT] ${ISSUES} critical, ${WARNINGS} warning(s) on $(hostname)" \
             "${EMAIL}" < "${REPORT_FILE}" \
    || log "WARN: 'mail' not found, skipping email alert"
}

# 
# Main
# 
main() {
  log "Monitoring started"
  emit ""
  emit "Application Monitoring Report - $(date '+%Y-%m-%d %H:%M:%S')"
  emit "===================================================="
  check_express
  check_nextjs
  check_fastapi
  check_laravel
  print_summary
  send_alert
  [[ "${ISSUES}" -gt 0 ]] && exit 1 || exit 0
}

# 
# Argument parsing
# 
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)    show_usage; exit 0 ;;
    -v|--verbose) set -x ;;
    -e|--email)   EMAIL="${2:-}"; shift ;;
    *) echo "Unknown option: $1"; show_usage; exit 1 ;;
  esac
  shift
done

main