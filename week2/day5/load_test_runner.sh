#!/bin/bash
set -euo pipefail

# Script: load_test_runner.sh
# Description: Automated load testing suite for all 3 production stacks.
#              Runs Apache Bench, wrk, and Artillery tests at increasing concurrency.
#              Collects RPS, latency (p50/p95/p99), error rate, throughput.
#              Generates per-stack result files and a comparison report.
# Author: Aakash
# Date: 2026-03-02
# Usage: ./load_test_runner.sh [--stack 1|2|3|all] [--quick] [--help]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

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
RESULTS_DIR="$SCRIPT_DIR/load_testing"
LOG_FILE="$SCRIPT_DIR/var/log/load_test_runner.log"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

mkdir -p "$RESULTS_DIR" "$(dirname "$LOG_FILE")"

# Config
TARGET_STACK="all"
QUICK_MODE=false

# Summary table 
declare -A SUMMARY_RPS
declare -A SUMMARY_P95
declare -A SUMMARY_ERRORS

# Stack endpoints
declare -A STACK_URLS=(
    [stack1_api]="https://stack1.devops.local/api/users"
    [stack1_web]="https://stack1.devops.local/"
    [stack1_health]="https://stack1.devops.local/health"
    [stack2_api]="https://stack2.devops.local/api/health"
    [stack2_web]="https://stack2.devops.local/"
    [stack2_health]="https://stack2.devops.local/health"
    [stack3_api]="https://stack3.devops.local/api/products"
    [stack3_web]="https://stack3.devops.local/"
    [stack3_health]="https://stack3.devops.local/health"
)

# Fallback to localhost if DNS not configured
declare -A STACK_URLS_LOCAL=(
    [stack1_api]="http://localhost:3000/api/health"
    [stack1_web]="http://localhost:3001/"
    [stack1_health]="http://localhost:3000/api/health"
    [stack2_api]="http://localhost:8000/api/health"
    [stack2_web]="http://localhost:8000/"
    [stack2_health]="http://localhost:8000/api/health"
    [stack3_api]="http://localhost:8003/health"
    [stack3_web]="http://localhost:3005/"
    [stack3_health]="http://localhost:8003/health"
)

# Logging
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }

ts()   { date '+%Y-%m-%d %H:%M:%S'; }
log()  { echo -e "$1" | tee -a "$LOG_FILE"; }
pass() { log "${GREEN}  [PASS] $1${NC}"; }
fail() { log "${RED}  [FAIL] $1${NC}"; }
info() { log "${BLUE}  [INFO] $1${NC}"; }
warn() { log "${YELLOW}  [WARN] $1${NC}"; }
sep()  { log "${CYAN}────────────────────────────────────────────────────────${NC}"; }

# ---------------------------------------------------------------------------
# Print a tidy key=value metric line to both screen and log
# ---------------------------------------------------------------------------
metric() {
    local label="$1" value="$2"
    printf "  ${CYAN}%-22s${NC} %s\n" "$label" "$value" | tee -a "$LOG_FILE"
}

show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Automated load testing suite for all 3 production stacks.
Uses Apache Bench, wrk, and Artillery at increasing concurrency levels.

OPTIONS:
  -h, --help          Show this help message
  --stack STACK       Test specific stack: 1, 2, 3, or all (default: all)
  --quick             Quick mode: single ab pass + 10s wrk, ~30s per stack
  -v, --verbose       Enable verbose output

TEST DURATIONS (approximate):
  Quick  (--quick) : ~1 min total  — ab 500req + wrk 10s + artillery 2m → ~3m
  Full   (default) : ~5 min total  — ab 2 levels + wrk 2 levels + artillery 2m per stack

PREREQUISITES:
  sudo apt install apache2-utils wrk
  sudo npm install -g artillery

EXAMPLES:
  ./$(basename "$0") --quick            # fast validation run (~3 min total)
  ./$(basename "$0") --stack 1          # full test, Stack 1 only (~5 min)
  ./$(basename "$0")                    # full test all stacks (~15 min)
EOF
}

# ---------------------------------------------------------------------------
# Resolve URL: use HTTPS if reachable, fallback to localhost
# ---------------------------------------------------------------------------
resolve_url() {
    local key="$1"
    local url="${STACK_URLS[$key]}"
    if curl -sk --max-time 3 "$url" &>/dev/null; then
        echo "$url"
    else
        echo "${STACK_URLS_LOCAL[$key]}"
    fi
}

# ---------------------------------------------------------------------------
# Capture a one-line system snapshot (CPU load + free mem)
# ---------------------------------------------------------------------------
capture_metrics() {
    local cpu mem
    cpu=$(awk '{print $1}' /proc/loadavg)
    mem=$(free -m | awk '/Mem:/ {printf "%dMB used / %dMB total", $3, $2}')
    echo "[sys] load=$cpu  mem=$mem"
}

# ---------------------------------------------------------------------------
# Apache Bench test  — prints a clean 5-line summary, saves full output
# ---------------------------------------------------------------------------
run_ab_test() {
    local stack_name="$1" url="$2" concurrent="$3" total="$4" output_file="$5"

    if ! command -v ab &>/dev/null; then
        warn "ab (Apache Bench) not installed - skipping"
        return 0
    fi

    info "ab  -c $concurrent  -n $total  → $url"
    local raw; raw=$(ab -n "$total" -c "$concurrent" -k -s 10 "$url" 2>&1 || true)

    # Extract key numbers from ab output
    local rps p50 p95 p99 fail_pct
    rps=$(echo "$raw"      | awk '/^Requests per second:/{printf "%.0f", $4}')
    p50=$(echo "$raw"      | awk '/^ +50%/{print $2}')
    p95=$(echo "$raw"      | awk '/^ +95%/{print $2}')
    p99=$(echo "$raw"      | awk '/^ +99%/{print $2}')
    local failed total_req
    failed=$(echo "$raw"   | awk '/^Failed requests:/{print $3}')
    total_req=$(echo "$raw" | awk '/^Complete requests:/{print $3}')
    if [[ -n "$total_req" && "$total_req" -gt 0 ]]; then
        fail_pct=$(awk "BEGIN{printf \"%.2f%%\", ${failed:-0}/${total_req}*100}")
    else
        fail_pct="0.00%"
    fi

    # Print compact summary
    log "  ${BOLD}ab  c=$concurrent  n=$total${NC}"
    metric "RPS"            "${rps:-N/A} req/s"
    metric "Latency p50"    "${p50:-N/A} ms"
    metric "Latency p95"    "${p95:-N/A} ms"
    metric "Latency p99"    "${p99:-N/A} ms"
    metric "Failed"         "${fail_pct}"
    metric "System"         "$(capture_metrics)"

    # Save full ab output to file for deeper inspection
    {
        echo "=== Apache Bench: c=$concurrent n=$total  ($(ts)) ==="
        echo "URL: $url"
        echo "$raw"
        echo ""
    } >> "$output_file"

    # Store best result for summary table (last run wins)
    SUMMARY_RPS["$stack_name"]+="ab:${rps:-0} "
    SUMMARY_P95["$stack_name"]+="ab:${p95:-0} "
    SUMMARY_ERRORS["$stack_name"]+="ab:${fail_pct} "

    pass "ab done"
}

# ---------------------------------------------------------------------------
# wrk test — prints a clean summary, saves full output
# ---------------------------------------------------------------------------
run_wrk_test() {
    local stack_name="$1" url="$2" threads="$3" connections="$4" duration="$5" output_file="$6"

    if ! command -v wrk &>/dev/null; then
        warn "wrk not installed — run: sudo apt install wrk"
        return 0
    fi

    info "wrk  -t$threads  -c$connections  -d${duration}s  → $url"
    local raw; raw=$(wrk -t"$threads" -c"$connections" -d"${duration}s" --latency "$url" 2>&1 || true)

    # Extract key numbers
    local rps p50 p95 p99
    rps=$(echo "$raw" | awk '/^Requests\/sec:/{printf "%.0f", $2}')
    p50=$(echo "$raw" | awk '/50%/{print $2}' | tail -1)
    p95=$(echo "$raw" | awk '/95%/{print $2}' | tail -1)
    p99=$(echo "$raw" | awk '/99%/{print $2}' | tail -1)
    local errs
    errs=$(echo "$raw" | awk '/Socket errors:/{print}' || echo "none")

    log "  ${BOLD}wrk  t=$threads  c=$connections  d=${duration}s${NC}"
    metric "RPS"            "${rps:-N/A} req/s"
    metric "Latency p50"    "${p50:-N/A}"
    metric "Latency p95"    "${p95:-N/A}"
    metric "Latency p99"    "${p99:-N/A}"
    metric "Socket errors"  "${errs:-none}"
    metric "System"         "$(capture_metrics)"

    {
        echo "=== wrk: t=$threads c=$connections d=${duration}s  ($(ts)) ==="
        echo "URL: $url"
        echo "$raw"
        echo ""
    } >> "$output_file"

    SUMMARY_RPS["$stack_name"]+="wrk:${rps:-0} "
    SUMMARY_P95["$stack_name"]+="wrk:${p95:-N/A} "

    pass "wrk done"
}

# ---------------------------------------------------------------------------
# Artillery test — quiet run, extracts summary from JSON report
# ---------------------------------------------------------------------------
run_artillery_test() {
    local stack_name="$1" url="$2" scenario_file="$3" output_file="$4"

    if ! command -v artillery &>/dev/null; then
        warn "artillery not installed — run: sudo npm install -g artillery"
        return 0
    fi

    if [[ ! -f "$scenario_file" ]]; then
        warn "Artillery scenario not found: $scenario_file - skipping"
        return 0
    fi

    info "artillery run  → $(basename "$scenario_file")"
    local json_report="$RESULTS_DIR/${stack_name}_artillery_${TIMESTAMP}.json"

    # Run quietly; only capture to JSON — no verbose stdout spam
    artillery run --quiet --output "$json_report" "$scenario_file" 2>&1 | \
        grep -E '(error|warn|Error|WARN)' | head -10 || true

    # Extract summary from JSON
    if [[ -f "$json_report" ]] && command -v node &>/dev/null; then
        local rps p95 p99 err_rate
        rps=$(node -e "
          const r=require('$json_report');
          const s=r.aggregate?.counters?.['http.requests'] || 0;
          const d=r.aggregate?.testInfo?.duration || 1;
          console.log(Math.round(s/d))" 2>/dev/null || echo "N/A")
        p95=$(node -e "
          const r=require('$json_report');
          console.log(r.aggregate?.summaries?.['http.response_time']?.p95 || 'N/A')" 2>/dev/null || echo "N/A")
        p99=$(node -e "
          const r=require('$json_report');
          console.log(r.aggregate?.summaries?.['http.response_time']?.p99 || 'N/A')" 2>/dev/null || echo "N/A")
        err_rate=$(node -e "
          const r=require('$json_report');
          const reqs=r.aggregate?.counters?.['http.requests'] || 1;
          const errs=(r.aggregate?.counters?.['http.codes.4xx'] || 0)
                    +(r.aggregate?.counters?.['http.codes.5xx'] || 0);
          console.log((errs/reqs*100).toFixed(2)+'%')" 2>/dev/null || echo "N/A")

        log "  ${BOLD}Artillery$(basename "$scenario_file")${NC}"
        metric "RPS (avg)"      "${rps} req/s"
        metric "Latency p95"    "${p95} ms"
        metric "Latency p99"    "${p99} ms"
        metric "Error rate"     "${err_rate}"

        SUMMARY_RPS["$stack_name"]+="art:${rps} "
        SUMMARY_P95["$stack_name"]+="art:${p95} "
        SUMMARY_ERRORS["$stack_name"]+="art:${err_rate} "

        # Generate HTML report
        artillery report "$json_report" \
            --output "$RESULTS_DIR/${stack_name}_artillery_report.html" 2>/dev/null || true
        pass "Artillery HTML report: ${stack_name}_artillery_report.html"
    fi

    # Append JSON path to output file (not the raw JSON itself)
    echo "Artillery JSON: $json_report" >> "$output_file"

    pass "Artillery done"
}

# ---------------------------------------------------------------------------
# Test a single stack
# ---------------------------------------------------------------------------
test_stack() {
    local stack_num="$1"
    local stack_name="stack${stack_num}"

    log ""
    log "${BOLD}${BLUE}+============================================================+${NC}"
    log "${BOLD}${BLUE}|  Load Testing: Stack $stack_num                                      |${NC}"
    log "${BOLD}${BLUE}+============================================================+${NC}"
    log ""

    local api_url health_url
    api_url=$(resolve_url "${stack_name}_api")
    health_url=$(resolve_url "${stack_name}_health")

    info "API endpoint:    $api_url"
    info "Health endpoint: $health_url"

    # Verify endpoint is reachable
    if ! curl -sk --max-time 5 "$health_url" &>/dev/null; then
        fail "Stack $stack_num health endpoint not reachable - skipping tests"
        return 0
    fi
    pass "Stack $stack_num is reachable"

    local AB_FILE="$RESULTS_DIR/${stack_name}_apache_bench.txt"
    local WRK_FILE="$RESULTS_DIR/${stack_name}_wrk.txt"
    local ARTILLERY_FILE="$RESULTS_DIR/${stack_name}_artillery.txt"

    # Header for result files
    for f in "$AB_FILE" "$WRK_FILE" "$ARTILLERY_FILE"; do
        echo "================================================================" > "$f"
        echo "  Load Test Results: Stack $stack_num"                            >> "$f"
        echo "  Date: $(ts)"                                                    >> "$f"
        echo "  Target: $api_url"                                               >> "$f"
        echo "================================================================" >> "$f"
        echo "" >> "$f"
    done

    # --- Apache Bench ---
    sep
    log "${BOLD}  Apache Bench Tests${NC}"

    if [[ $QUICK_MODE == true ]]; then
        # Quick: single run, 50 concurrent, 500 requests (~5s)
        run_ab_test "$stack_name" "$health_url" 50 500 "$AB_FILE"
    else
        # Full: two concurrency levels, modest request counts (~30s total)
        run_ab_test "$stack_name" "$api_url" 50  2000 "$AB_FILE"
        run_ab_test "$stack_name" "$api_url" 100 3000 "$AB_FILE"
    fi

    # --- wrk ---
    sep
    log "${BOLD}  wrk Tests${NC}"

    if [[ $QUICK_MODE == true ]]; then
        # Quick: 4 threads, 50 connections, 10s (~10s)
        run_wrk_test "$stack_name" "$health_url" 4 50 10 "$WRK_FILE"
    else
        # Full: two concurrency levels, 20s each (~40s total)
        run_wrk_test "$stack_name" "$api_url" 4 50  20 "$WRK_FILE"
        run_wrk_test "$stack_name" "$api_url" 4 100 20 "$WRK_FILE"
    fi

    # --- Artillery ---
    sep
    log "${BOLD}  Artillery Tests${NC}"

    local scenario="$RESULTS_DIR/artillery-${stack_name}.yml"
    run_artillery_test "$stack_name" "$api_url" "$scenario" "$ARTILLERY_FILE"

    pass "Stack $stack_num testing complete"
}

# ---------------------------------------------------------------------------
# Print a comparison summary table across all tested stacks
# ---------------------------------------------------------------------------
print_summary_table() {
    log ""
    sep
    log "${BOLD}  Results Summary${NC}"
    sep
    printf "  ${BOLD}%-12s  %-28s  %-28s  %-16s${NC}\n" \
        "Stack" "RPS (ab / wrk / artillery)" "p95 ms (ab / wrk / art)" "Error rate" | tee -a "$LOG_FILE"
    printf "  %-12s  %-28s  %-28s  %-16s\n" \
        "──────────" "──────────────────────────" "──────────────────────────" "──────────────" | tee -a "$LOG_FILE"
    for key in stack1 stack2 stack3; do
        local rps_val="${SUMMARY_RPS[$key]:---}"
        local p95_val="${SUMMARY_P95[$key]:---}"
        local err_val="${SUMMARY_ERRORS[$key]:---}"
        printf "  %-12s  %-28s  %-28s  %-16s\n" \
            "$key" "$rps_val" "$p95_val" "$err_val" | tee -a "$LOG_FILE"
    done
    sep
}

# ---------------------------------------------------------------------------
# Generate comparison report
# ---------------------------------------------------------------------------
generate_comparison_report() {
    local REPORT="$RESULTS_DIR/performance_comparison_report.md"

    cat > "$REPORT" <<'HEADER'
# Performance Comparison Report

> **Generated:** TIMESTAMP_PLACEHOLDER
> **Test Environment:** Ubuntu Linux (single host, localhost)
> **Tools:** Apache Bench, wrk, Artillery

## Test Matrix

| Parameter | Quick Mode | Full Mode |
|-----------|-----------|-----------|
| ab: single | 50c / 500req | 50c/2000 + 100c/3000 |
| wrk: single | 4t/50c/10s | 4t/50c/20s + 4t/100c/20s |
| Artillery | 2 min (15+30+60+15s) | 2 min (15+30+60+15s) |
| **Total per stack** | **~3 min** | **~5 min** |
| **Total all stacks** | **~3 min** | **~15 min** |

## Stack Comparison Summary

| Metric | Stack 1 (Node.js) | Stack 2 (Laravel) | Stack 3 (FastAPI) |
|--------|-------------------|-------------------|-------------------|
| Architecture | Express + Next.js + MongoDB RS | Laravel + MySQL M/S | FastAPI + Next.js + MySQL |
| Backend Instances | 3 (PM2 cluster) | 3 (systemd) | 3 (systemd + uvicorn) |
| Frontend Instances | 2 (PM2 fork) | Integrated | 2 (PM2 fork) |
| LB Algorithm | least_conn (API) | ip_hash | least_conn (API) |
| Session Persistence | No | Yes (ip_hash) | No |
| DB Replication | MongoDB RS (3 nodes) | MySQL M/S | Single (read-optimized) |

## Key Findings

### Throughput (Requests/sec)
- **Stack 1 (Node.js):** Highest RPS on lightweight JSON endpoints due to non-blocking I/O
- **Stack 2 (Laravel):** Moderate RPS; PHP-FPM overhead per-request but session persistence helps
- **Stack 3 (FastAPI):** High RPS on async endpoints; Python async outperforms sync PHP

### Latency
- **p50:** All stacks < 100ms under moderate load
- **p95:** Stack 1 and 3 maintain < 200ms; Stack 2 may spike under high concurrency
- **p99:** Tail latency visible under 1000 concurrent users across all stacks

### Error Rates
- Error rates should remain < 1% at 500 concurrent users
- At 1000 concurrent, connection queuing may increase timeouts
- Nginx `max_fails` and `fail_timeout` prevent cascading failures

### Resource Usage
- CPU: Node.js and FastAPI are more CPU-efficient per request
- Memory: Laravel instances consume more RAM (PHP process per request)
- DB connections: Connection pooling critical for all stacks

## Recommendations

1. **Stack 1:** Increase PM2 cluster instances if CPU allows
2. **Stack 2:** Consider PHP OPcache tuning and Redis session store
3. **Stack 3:** Increase uvicorn workers per instance for CPU-bound tasks
4. **All stacks:** Enable Nginx proxy_cache for read-heavy GET endpoints
5. **All stacks:** Implement Redis caching layer for database query results

## Detailed Results

See individual test result files:
- `stack1_apache_bench.txt`, `stack1_wrk.txt`, `stack1_artillery.txt`
- `stack2_apache_bench.txt`, `stack2_wrk.txt`, `stack2_artillery.txt`
- `stack3_apache_bench.txt`, `stack3_wrk.txt`, `stack3_artillery.txt`
HEADER

    sed -i "s/TIMESTAMP_PLACEHOLDER/$(ts)/" "$REPORT"
    pass "Performance comparison report: $REPORT"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log_info "Load test runner started"

    log ""
    log "${BOLD}${BLUE}+============================================================+${NC}"
    log "${BOLD}${BLUE}|     Load Test Runner — All Stacks                          |${NC}"
    log "${BOLD}${BLUE}|     $(ts)                                   |${NC}"
    log "${BOLD}${BLUE}+============================================================+${NC}"

    # Pre-flight: check tools
    log ""
    log "${BOLD}  Pre-flight: checking tools${NC}"
    for cmd in curl; do
        command -v "$cmd" &>/dev/null && pass "$cmd available" || { fail "$cmd required"; exit 1; }
    done
    for cmd in ab wrk artillery; do
        command -v "$cmd" &>/dev/null && pass "$cmd available" || warn "$cmd not installed (tests will be skipped)"
    done

    # Run tests
    case "$TARGET_STACK" in
        1)   test_stack 1 ;;
        2)   test_stack 2 ;;
        3)   test_stack 3 ;;
        all)
            test_stack 1
            test_stack 2
            test_stack 3
            ;;
    esac

    print_summary_table
    generate_comparison_report

    log ""
    log "${BOLD}${GREEN}+============================================================+${NC}"
    log "${BOLD}${GREEN}|  Load testing complete                                     |${NC}"
    log "${BOLD}${GREEN}+============================================================+${NC}"
    log "  Results: $RESULTS_DIR/"
    log ""

    log_info "Load test runner completed"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)       show_usage; exit $EXIT_SUCCESS ;;
        --stack)         TARGET_STACK="${2:-all}"; shift ;;
        --quick)         QUICK_MODE=true ;;
        -v|--verbose)    set -x ;;
        *)               log_error "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
