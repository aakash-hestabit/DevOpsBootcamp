#!/bin/bash
# External health check script for the Node.js API service.
# Can be run from the host or any networked machine.

USAGE="$(cat <<'EOF'
Usage: node_healthcheck.sh [OPTIONS]

External health check script for the Node.js API service.
Probes /health (liveness) and /ready (readiness + PostgreSQL connectivity).

Options:
  -h, --host HOST       API hostname or IP  (default: localhost)
  -p, --port PORT       API port            (default: 3000)
  -t, --timeout SECS    Request timeout     (default: 5)
      --only-health     Check /health only
      --only-ready      Check /ready only
      --help            Show this help message

Exit codes:
  0  All requested checks passed
  1  One or more checks failed

Examples:
  ./node_healthcheck.sh
  ./node_healthcheck.sh --host 192.168.1.10 --port 3000
  ./node_healthcheck.sh --only-ready --timeout 3
EOF
)"

HOST="localhost"
PORT="3000"
TIMEOUT=5
CHECK_HEALTH=true
CHECK_READY=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)         echo "$USAGE"; exit 0 ;;
    -h|--host)      HOST="$2";    shift 2 ;;
    -p|--port)      PORT="$2";    shift 2 ;;
    -t|--timeout)   TIMEOUT="$2"; shift 2 ;;
    --only-health)  CHECK_READY=false;  shift ;;
    --only-ready)   CHECK_HEALTH=false; shift ;;
    *) echo "Unknown option: $1"; echo "$USAGE"; exit 1 ;;
  esac
done

BASE="http://${HOST}:${PORT}"
PASS=true

probe() {
  local label="$1"
  local endpoint="$2"
  local result body code

  body=$(curl -s --max-time "$TIMEOUT" "${BASE}${endpoint}" 2>/dev/null)
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "${BASE}${endpoint}" 2>/dev/null)

  if [[ "$code" == "200" ]]; then
    printf "  [OK]   %-8s --> HTTP %s  %s\n" "$label" "$code" "$body"
  else
    printf "  [FAIL] %-8s --> HTTP %s  %s\n" "$label" "$code" "$body"
    PASS=false
  fi
}

echo "=== Node.js API Health Check ==="
echo "Target : ${BASE}"
echo "Timeout: ${TIMEOUT}s"
echo "---"

$CHECK_HEALTH && probe "/health" "/health"
$CHECK_READY  && probe "/ready"  "/ready"

echo "---"
if $PASS; then
  echo "Result : HEALTHY"
  exit 0
else
  echo "Result : UNHEALTHY"
  exit 1
fi
