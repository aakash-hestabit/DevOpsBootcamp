#!/bin/bash
set -euo pipefail

# deploy.sh — Deploy the microservices stack
#
# Supports:
#   dev   — development  (hot reload, debug ports, relaxed limits)
#   prod  — production   (SSL, strict limits, log rotation)
#   down  — stop all services
#   restart — restart all services in current mode
#   status  — show container status
#
# Usage:
#   ./deploy.sh dev
#   ./deploy.sh prod
#   ./deploy.sh down
#   ./deploy.sh restart
#   ./deploy.sh status

readonly SCRIPT_NAME="$(basename "$0")"
readonly PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LOG_DIR="${PROJECT_DIR}/var/log"
readonly LOG_FILE="${LOG_DIR}/deploy.log"
readonly HEALTH_RETRIES=30
readonly HEALTH_INTERVAL=5

# Load environment 
if [[ -f "${PROJECT_DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${PROJECT_DIR}/.env"
  set +a
fi

FRONTEND_PORT="${FRONTEND_PORT:-8081}"
FRONTEND_SSL_PORT="${FRONTEND_SSL_PORT:-443}"

# Logging 
mkdir -p "$LOG_DIR"
log()      { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "$LOG_FILE"; }
log_ok()   { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [OK]    $*" | tee -a "$LOG_FILE"; }
log_err()  { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_FILE" >&2; }
log_warn() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "$LOG_FILE"; }

# Cleanup trap 
cleanup() {
  log "Deploy script finished."
}
trap cleanup EXIT

# Help 
show_help() {
  cat <<EOF
Usage: ${SCRIPT_NAME} {dev|prod|down|restart|status}

Deploy the microservices platform.

COMMANDS:
    dev       Start in development mode (hot reload, debug ports)
    prod      Start in production mode (SSL on 443, strict limits)
    down      Stop and remove all containers
    restart   Restart all services
    status    Show container status

EXAMPLES:
    ${SCRIPT_NAME} dev
    ${SCRIPT_NAME} prod
    ${SCRIPT_NAME} down
EOF
}

# Input validation 
if [[ $# -lt 1 ]]; then
  show_help
  exit 1
fi

ENV="$1"

# Pre-flight checks 
preflight() {
  if ! command -v docker &>/dev/null; then
    log_err "docker is not installed"
    exit 1
  fi

  if ! docker info &>/dev/null; then
    log_err "Docker daemon is not running"
    exit 1
  fi

  # Ensure SSL certs exist for production
  if [[ "$ENV" == "prod" ]]; then
    if [[ ! -f "${PROJECT_DIR}/ssl/server.crt" || ! -f "${PROJECT_DIR}/ssl/server.key" ]]; then
      log_err "SSL certificates not found at ssl/server.crt and ssl/server.key"
      log "Generate them with: openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ssl/server.key -out ssl/server.crt -subj '/CN=localhost'"
      exit 1
    fi
    log_ok "SSL certificates found"
  fi
}

# Wait for health 
wait_for_health() {
  log "Waiting for services to become healthy ..."
  sleep 10

  local healthy=0
  for i in $(seq 1 "$HEALTH_RETRIES"); do
    local status
    status=$(curl -sf "http://localhost:${FRONTEND_PORT}/health" 2>/dev/null \
             | grep -o '"status":"[^"]*"' | head -1 || true)

    if echo "$status" | grep -q "healthy"; then
      healthy=1
      break
    fi
    log "  Attempt ${i}/${HEALTH_RETRIES} — waiting ${HEALTH_INTERVAL}s ..."
    sleep "$HEALTH_INTERVAL"
  done

  if [[ "$healthy" -eq 1 ]]; then
    log_ok "All services are healthy!"
    return 0
  else
    log_warn "Some services may not be healthy yet. Run: docker compose ps"
    return 1
  fi
}

# Print access info 
print_access_info() {
  echo ""
  echo "========================================"
  echo "  Access Points"
  echo "========================================"
  echo "  Frontend (HTTP):  http://localhost:${FRONTEND_PORT}"
  echo "  Frontend (HTTPS): https://localhost:${FRONTEND_SSL_PORT}"
  echo "  Prometheus:       http://localhost:9090"
  echo "  Grafana:          http://localhost:3001  (admin / admin)"
  echo "  cAdvisor:         http://localhost:9091"
  echo "========================================"
  echo ""
}

# Deploy 
cd "$PROJECT_DIR"

case "$ENV" in
  dev)
    preflight
    log "=== Deploying DEVELOPMENT environment ==="
    docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build -d
    wait_for_health || true
    print_access_info
    ;;

  prod)
    preflight
    log "=== Deploying PRODUCTION environment ==="
    docker compose -f docker-compose.yml -f docker-compose.prod.yml up --build -d
    wait_for_health || true
    print_access_info
    ;;

  down)
    log "=== Stopping all services ==="
    docker compose down
    log_ok "All services stopped."
    ;;

  restart)
    log "=== Restarting all services ==="
    docker compose restart
    wait_for_health || true
    print_access_info
    ;;

  status)
    echo ""
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || docker compose ps
    echo ""
    ;;

  -h|--help)
    show_help
    ;;

  *)
    log_err "Unknown command: ${ENV}"
    show_help
    exit 1
    ;;
esac
