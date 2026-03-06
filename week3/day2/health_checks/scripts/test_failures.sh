#!/bin/bash
# test_failures.sh — test health check behaviour under failure scenarios.
# Stops individual databases and verifies the app /ready endpoints return 503,
# then restores everything and confirms recovery.

COMPOSE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS_COUNT=0
FAIL_COUNT=0

USAGE="$(cat <<'EOF'
Usage: test_failures.sh [OPTIONS]

Tests health check behaviour under simulated failure scenarios.
Requires Docker Compose services to already be running.

What it tests:
  1. Baseline: node_api /health and /ready return 200
  2. Baseline: python_app /health and /ready return 200
  3. Failure : stop postgres --> node_api /ready must return 503 (DB down)
               node_api /health must still return 200 (process alive)
  4. Recovery: restart postgres --> node_api /ready returns 200 again
  5. Failure : stop mysql --> python_app /ready must return 503
               python_app /health must still return 200
  6. Recovery: restart mysql --> python_app /ready returns 200 again
  7. Summary of passed / failed assertions

Options:
  --help   Show this help message

Prerequisites:
  - docker compose up --build -d  (from health_checks/)
  - curl available on the host

EOF
)"

if [[ "$1" == "--help" ]]; then
  echo "$USAGE"
  exit 0
fi


assert_http() {
  local label="$1" url="$2" expected="$3"
  local got
  got=$(curl -s -o /dev/null -w "%{http_code}" --max-time 6 "$url" 2>/dev/null)
  if [[ "$got" == "$expected" ]]; then
    printf "  [PASS] %-55s --> HTTP %s\n" "$label" "$got"
    PASS_COUNT=$((PASS_COUNT+1))
  else
    printf "  [FAIL] %-55s --> expected %s, got %s\n" "$label" "$expected" "$got"
    FAIL_COUNT=$((FAIL_COUNT+1))
  fi
}

wait_for_http() {
  local url="$1" expected="$2" label="$3" retries="${4:-15}"
  local i=1
  while (( i <= retries )); do
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
    if [[ "$code" == "$expected" ]]; then
      printf "  [OK]   %s recovered (HTTP %s) after %ds\n" "$label" "$code" "$((i*3))"
      return 0
    fi
    sleep 3
    i=$((i+1))
  done
  printf "  [TIMEOUT] %s did not recover to HTTP %s within %ds\n" "$label" "$expected" "$((retries*3))"
  return 1
}

dc() { docker compose -f "$COMPOSE_DIR/docker-compose.yml" "$@"; }


echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║        Health Check Failure Scenario Tests           ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Baseline checks
echo "── [1] Baseline: all services up ──"
assert_http "node_api  /health" "http://localhost:3000/health" "200"
assert_http "node_api  /ready"  "http://localhost:3000/ready"  "200"
assert_http "python_app /health" "http://localhost:5000/health" "200"
assert_http "python_app /ready"  "http://localhost:5000/ready"  "200"

echo ""
echo "── [2] Failure: stopping postgres (node_api DB) ──"
dc stop postgres > /dev/null 2>&1
sleep 5

assert_http "node_api  /health (process still alive)" "http://localhost:3000/health" "200"
assert_http "node_api  /ready  (DB down --> must be 503)" "http://localhost:3000/ready" "503"

echo ""
echo "── [3] Recovery: restarting postgres ──"
dc start postgres > /dev/null 2>&1
wait_for_http "http://localhost:3000/ready" "200" "node_api /ready"
assert_http "node_api  /ready  (after recovery)" "http://localhost:3000/ready" "200"

echo ""
echo "── [4] Failure: stopping mysql (python_app DB) ──"
dc stop mysql > /dev/null 2>&1
sleep 5

assert_http "python_app /health (process still alive)" "http://localhost:5000/health" "200"
assert_http "python_app /ready  (DB down --> must be 503)" "http://localhost:5000/ready" "503"

echo ""
echo "── [5] Recovery: restarting mysql ──"
dc start mysql > /dev/null 2>&1
wait_for_http "http://localhost:5000/ready" "200" "python_app /ready"
assert_http "python_app /ready  (after recovery)" "http://localhost:5000/ready" "200"


echo ""
echo "══════════════════════════════════════════════════════"
echo "  Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "══════════════════════════════════════════════════════"

if (( FAIL_COUNT > 0 )); then
  exit 1
fi
exit 0
