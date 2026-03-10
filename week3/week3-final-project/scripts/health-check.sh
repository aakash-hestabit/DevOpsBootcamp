#!/bin/bash
set -euo pipefail

# health-check.sh — Verify every service is alive and responding
#
# Checks:
#   - Gateway aggregate health endpoint
#   - Individual API endpoints (users, products, orders)
#   - Monitoring stack (Prometheus, Grafana, cAdvisor)
#   - SSL/TLS availability on port 8443
#
# Usage:
#   ./scripts/health-check.sh
#   GATEWAY_URL=http://remote:8081 ./scripts/health-check.sh

readonly SCRIPT_NAME="$(basename "$0")"
readonly GATEWAY_URL="${GATEWAY_URL:-http://localhost:8081}"
readonly GATEWAY_SSL="${GATEWAY_SSL:-https://localhost:${FRONTEND_SSL_PORT:-8443}}"

PASSED=0
FAILED=0
TOTAL=0
declare -a FAILED_CHECKS=()


log()     { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
log_ok()  { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [OK]    $*"; }
log_err() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [FAIL]  $*"; }

cleanup() {
  echo ""
  echo "========================================"
  echo "Health Check Summary"
  echo "========================================"
  echo "  Passed : ${PASSED}/${TOTAL}"
  echo "  Failed : ${FAILED}/${TOTAL}"
  if [[ ${#FAILED_CHECKS[@]} -gt 0 ]]; then
    echo ""
    echo "  Failed checks:"
    for f in "${FAILED_CHECKS[@]}"; do
      echo "    - ${f}"
    done
  fi
  echo "========================================"
  log "Health check finished."
}
trap cleanup EXIT

check() {
  local name="$1"
  local url="$2"
  local expected="${3:-200}"
  local extra_curl="${4:-}"

  TOTAL=$((TOTAL + 1))
  local code
  # shellcheck disable=SC2086
  code=$(curl -sf -o /dev/null -w "%{http_code}" $extra_curl "$url" 2>/dev/null || echo "000")

  if [[ "$code" == "$expected" ]]; then
    echo "  [PASS] ${name} -> ${code}"
    PASSED=$((PASSED + 1))
  else
    echo "  [FAIL] ${name} -> ${code} (expected ${expected})"
    FAILED=$((FAILED + 1))
    FAILED_CHECKS+=("${name} (got ${code})")
  fi
}

# Gateway Aggregate Health 
echo ""
log "Checking aggregate gateway health ..."
echo ""

health_json=$(curl -sf "${GATEWAY_URL}/health" 2>/dev/null || true)
if [[ -n "$health_json" ]]; then
  echo "$health_json" | python3 -m json.tool 2>/dev/null || echo "$health_json"
  TOTAL=$((TOTAL + 1))
  PASSED=$((PASSED + 1))
  echo ""
  echo "  [PASS] Gateway health endpoint"
else
  TOTAL=$((TOTAL + 1))
  FAILED=$((FAILED + 1))
  FAILED_CHECKS+=("Gateway health endpoint")
  echo "  [FAIL] Gateway health endpoint — unreachable"
fi

# Individual API Endpoints 
echo ""
log "Checking API endpoints ..."
check "GET /api/users"    "${GATEWAY_URL}/api/users"
check "GET /api/products" "${GATEWAY_URL}/api/products"
check "GET /api/orders"   "${GATEWAY_URL}/api/orders"

# SSL/TLS Check 
echo ""
log "Checking SSL/TLS on port ${FRONTEND_SSL_PORT:-8443} ..."
check "HTTPS frontend" "${GATEWAY_SSL}/" "200" "--insecure"

#  Monitoring Stack 
echo ""
log "Checking monitoring services ..."
check "Prometheus" "http://localhost:9090/-/healthy"
check "Grafana"    "http://localhost:3001/api/health"
check "cAdvisor"   "http://localhost:9091/healthz"

# ── Docker Containers ─────────────────────────────────────────
echo ""
log "Container status ..."
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || docker compose ps

# Exit code based on failures
if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
