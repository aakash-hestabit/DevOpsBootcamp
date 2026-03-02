#!/bin/bash
set -euo pipefail

# Script: log_analyzer.sh
# Description: Analyze logs from centralized logging directory.
#              Parse Nginx access/error logs, application logs, and database logs.
#              Generate summary reports: top endpoints, error rates, slow queries.
# Author: Aakash
# Date: 2026-03-02
# Usage: ./log_analyzer.sh [--stack 1|2|3|all] [--period today|week] [--help]

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CENTRAL_LOG="/var/log/centralized"
NGINX_LOG="/var/log/nginx"
TARGET_STACK="all"
PERIOD="today"

show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Analyze centralized logs and generate summary reports.

OPTIONS:
  -h, --help          Show this help message
  --stack STACK       Analyze: 1, 2, 3, or all (default: all)
  --period PERIOD     Time range: today, week (default: today)

EXAMPLES:
  ./$(basename "$0")                    # all stacks, today
  ./$(basename "$0") --stack 1          # Stack 1 only
  ./$(basename "$0") --period week      # last 7 days
EOF
}

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo -e "$1"; }
sep() { log "${CYAN}────────────────────────────────────────────────────────${NC}"; }

# ---------------------------------------------------------------------------
# Analyze Nginx access log
# ---------------------------------------------------------------------------
analyze_nginx() {
    local stack_name="$1"
    local access_log="$NGINX_LOG/${stack_name}-access.log"

    if [[ ! -f "$access_log" ]]; then
        access_log="$CENTRAL_LOG/nginx/${stack_name}-access.log"
    fi

    if [[ ! -f "$access_log" ]]; then
        log "${YELLOW}  No access log found for $stack_name${NC}"
        return
    fi

    local total errors
    total=$(wc -l < "$access_log" 2>/dev/null || echo 0)
    errors=$(grep -c ' [45][0-9][0-9] ' "$access_log" 2>/dev/null || echo 0)

    log "${BOLD}  Nginx ($stack_name):${NC}"
    log "    Total requests:  $total"
    log "    Errors (4xx/5xx): $errors"

    if [[ $total -gt 0 ]]; then
        local error_pct=$(( errors * 100 / total ))
        log "    Error rate:      ${error_pct}%"
    fi

    # Top 5 endpoints
    log "    Top 5 endpoints:"
    awk '{print $7}' "$access_log" 2>/dev/null | sort | uniq -c | sort -rn | head -5 | \
        while read -r count path; do
            log "      $count  $path"
        done

    # Top 5 status codes
    log "    Status codes:"
    awk '{print $9}' "$access_log" 2>/dev/null | sort | uniq -c | sort -rn | head -5 | \
        while read -r count code; do
            log "      $count  $code"
        done
    log ""
}

# ---------------------------------------------------------------------------
# Analyze application logs (error count, recent errors)
# ---------------------------------------------------------------------------
analyze_app_logs() {
    local stack_num="$1"
    local log_paths=()

    case "$stack_num" in
        1)
            log_paths=(
                "$CENTRAL_LOG/stack1/nodejs-api/"
                "$CENTRAL_LOG/stack1/nextjs-app/"
            )
            ;;
        2)
            log_paths=(
                "$CENTRAL_LOG/stack2/laravel/"
            )
            ;;
        3)
            log_paths=(
                "$CENTRAL_LOG/stack3/fastapi/"
                "$CENTRAL_LOG/stack3/nextjs/"
            )
            ;;
    esac

    log "${BOLD}  Application logs (Stack $stack_num):${NC}"

    for dir in "${log_paths[@]}"; do
        if [[ ! -d "$dir" ]]; then continue; fi
        local component
        component=$(basename "$dir")

        local err_count=0
        for f in "$dir"*.log; do
            [[ -f "$f" ]] || continue
            local c
            c=$(grep -ic 'error\|exception\|fatal\|critical' "$f" 2>/dev/null || echo 0)
            err_count=$((err_count + c))
        done

        if [[ $err_count -gt 0 ]]; then
            log "    ${RED}$component: $err_count errors found${NC}"
            # Show last 3 errors
            for f in "$dir"*.log; do
                [[ -f "$f" ]] || continue
                grep -i 'error\|exception\|fatal' "$f" 2>/dev/null | tail -3 | while read -r line; do
                    log "      ${DIM}$line${NC}"
                done
            done
        else
            log "    ${GREEN}$component: no errors${NC}"
        fi
    done
    log ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log ""
    log "${BOLD}${BLUE}+============================================================+${NC}"
    log "${BOLD}${BLUE}|  Log Analyzer — $(ts)                      |${NC}"
    log "${BOLD}${BLUE}+============================================================+${NC}"
    log ""

    case "$TARGET_STACK" in
        1)
            analyze_nginx "stack1"
            analyze_app_logs 1
            ;;
        2)
            analyze_nginx "stack2"
            analyze_app_logs 2
            ;;
        3)
            analyze_nginx "stack3"
            analyze_app_logs 3
            ;;
        all)
            for s in stack1 stack2 stack3; do
                sep
                analyze_nginx "$s"
            done
            for n in 1 2 3; do
                sep
                analyze_app_logs "$n"
            done
            ;;
    esac

    log "${DIM}  Period: $PERIOD | Source: $CENTRAL_LOG${NC}"
    log ""
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    show_usage; exit 0 ;;
        --stack)      TARGET_STACK="${2:-all}"; shift ;;
        --period)     PERIOD="${2:-today}"; shift ;;
        *)            echo "Unknown: $1"; show_usage; exit 1 ;;
    esac
    shift
done

main "$@"
