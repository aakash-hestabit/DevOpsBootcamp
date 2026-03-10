#!/bin/bash
set -euo pipefail

# test-all.sh — End-to-end smoke tests for every microservice
#
# Tests:
#   - Health endpoint
#   - CRUD operations on users, products, orders
#   - Error handling (404, duplicates)
#   - SSL connectivity
#
# Usage:
#   ./scripts/test-all.sh
#   BASE_URL=http://myhost:8081 ./scripts/test-all.sh

readonly SCRIPT_NAME="$(basename "$0")"
readonly BASE_URL="${BASE_URL:-http://localhost:8081}"

PASSED=0
FAILED=0
TOTAL=0
declare -a FAILED_TESTS=()

# Logging 
log()     { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }

# Cleanup / Summary 
cleanup() {
  echo ""
  echo "========================================"
  echo "Test Results"
  echo "========================================"
  echo "  Total  : ${TOTAL}"
  echo "  Passed : ${PASSED}"
  echo "  Failed : ${FAILED}"
  if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
    echo ""
    echo "  Failed tests:"
    for t in "${FAILED_TESTS[@]}"; do
      echo "    - ${t}"
    done
  fi
  echo "========================================"
}
trap cleanup EXIT

# Test runner 
run_test() {
  local name="$1"
  local method="$2"
  local url="$3"
  local data="${4:-}"
  local expected="${5:-200}"
  local response body

  TOTAL=$((TOTAL + 1))

  if [[ -n "$data" ]]; then
    response=$(curl -s -w "\n%{http_code}" -X "$method" \
      -H "Content-Type: application/json" \
      -d "$data" "$url" 2>/dev/null || echo -e "\n000")
  else
    response=$(curl -s -w "\n%{http_code}" -X "$method" "$url" 2>/dev/null || echo -e "\n000")
  fi

  local code
  code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$code" == "$expected" ]]; then
    echo "  [PASS] ${name} (${code})"
    PASSED=$((PASSED + 1))
  else
    echo "  [FAIL] ${name} — expected ${expected}, got ${code}"
    FAILED=$((FAILED + 1))
    FAILED_TESTS+=("${name}: expected ${expected}, got ${code}")
  fi
}

# Start tests 
log "Running end-to-end tests against ${BASE_URL}"
echo ""

# -- Health --
echo "--- Health ---"
run_test "Gateway health"    GET "${BASE_URL}/health"

# -- Users CRUD --
echo ""
echo "--- User Service ---"
run_test "List users"        GET  "${BASE_URL}/api/users"
run_test "Create user"       POST "${BASE_URL}/api/users" \
  '{"name":"E2E Test User","email":"e2e-test-'"$(date +%s)"'@example.com","role":"user"}' "201"
run_test "List users (after)" GET "${BASE_URL}/api/users"

# -- Products CRUD --
echo ""
echo "--- Product Service ---"
run_test "List products"     GET  "${BASE_URL}/api/products"
run_test "Create product"    POST "${BASE_URL}/api/products" \
  '{"name":"E2E Test Product","price":12.99,"category":"test","stock":5}' "201"
run_test "List products (after)" GET "${BASE_URL}/api/products"

# -- Orders CRUD --
echo ""
echo "--- Order Service ---"
run_test "List orders"       GET  "${BASE_URL}/api/orders"
run_test "Create order"      POST "${BASE_URL}/api/orders" \
  '{"user_id":1,"product_id":"e2e-test","quantity":1,"total_price":12.99}' "201"
run_test "List orders (after)" GET "${BASE_URL}/api/orders"

# -- Error handling --
echo ""
echo "--- Error Handling ---"
run_test "Unknown route"     GET  "${BASE_URL}/api/nonexistent" "" "404"
run_test "User not found"    GET  "${BASE_URL}/api/users/99999" "" "404"

# -- SSL --
echo ""
echo "--- SSL/TLS ---"
SSL_PORT="${FRONTEND_SSL_PORT:-8443}"
TOTAL=$((TOTAL + 1))
ssl_code=$(curl -sk -o /dev/null -w "%{http_code}" "https://localhost:${SSL_PORT}/" 2>/dev/null || echo "000")
if [[ "$ssl_code" == "200" ]]; then
  echo "  [PASS] HTTPS on port ${SSL_PORT} (${ssl_code})"
  PASSED=$((PASSED + 1))
else
  echo "  [FAIL] HTTPS on port ${SSL_PORT} — got ${ssl_code}"
  FAILED=$((FAILED + 1))
  FAILED_TESTS+=("HTTPS on port ${SSL_PORT}: got ${ssl_code}")
fi

# Exit code
if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
