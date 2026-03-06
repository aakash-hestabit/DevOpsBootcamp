#!/bin/sh
# Health check script embedded in the Node.js API container.
# Checks both /health (liveness) and /ready (readiness + DB connectivity).

if [ "$1" = "--help" ]; then
  cat <<'EOF'
Usage: healthcheck.sh [--help]

Embedded Docker health check for the Node.js API container.
Runs two checks in sequence:
  1. /health  — confirms the process is alive (HTTP 200 expected)
  2. /ready   — confirms the app + PostgreSQL DB are reachable (HTTP 200 expected)

Exit codes:
  0  All checks passed (container is healthy)
  1  One or more checks failed (container is unhealthy)

Environment (read from container env):
  PORT  Port the API is listening on (default: 3000)
EOF
  exit 0
fi

PORT="${PORT:-3000}"
BASE="http://localhost:$PORT"

check() {
  local endpoint="$1"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${BASE}${endpoint}" 2>/dev/null)
  if [ "$code" = "200" ]; then
    return 0
  else
    echo "FAIL ${endpoint} --> HTTP ${code}"
    return 1
  fi
}

check /health || exit 1
check /ready  || exit 1
exit 0
