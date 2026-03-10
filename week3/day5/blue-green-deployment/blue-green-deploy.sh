#!/bin/bash

# blue-green-deploy.sh — Zero-downtime Blue-Green Deployment
#
# Usage:
#   ./blue-green-deploy.sh            # auto-detect current slot, deploy to the other
#   ./blue-green-deploy.sh blue       # force deploy to blue slot
#   ./blue-green-deploy.sh green      # force deploy to green slot
#
# Prerequisites:
#   - Docker network 'bg-network' exists  (run ./blue-green-deploy.sh init)
#   - Nginx container is running          (docker compose -f docker-compose.nginx.yml up -d)


set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NGINX_CONF="${SCRIPT_DIR}/nginx/nginx.conf"
NGINX_CONTAINER="bg-nginx"

# Colors 
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}    $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $*"; }
log_step()    { echo -e "${CYAN}[STEP]${NC}    $*"; }

# Special: init sub-command 
if [[ "${1:-}" == "init" ]]; then
  log_info "Creating shared Docker network 'bg-network'..."
  docker network create bg-network 2>/dev/null && \
    log_success "Network 'bg-network' created." || \
    log_warn "Network 'bg-network' already exists — skipping."

  log_info "Starting Nginx router..."
  cd "$SCRIPT_DIR"
  docker compose -f docker-compose.nginx.yml up -d
  sleep 3

  log_info "Starting initial BLUE deployment..."
  docker compose -f docker-compose.blue.yml up -d --build
  sleep 10

  docker compose -f docker-compose.nginx.yml ps
  docker compose -f docker-compose.blue.yml ps
  log_success "Init complete. Blue is live at http://localhost:8080"
  exit 0
fi

# Detect active/inactive slots 
cd "$SCRIPT_DIR"

if [[ -n "${1:-}" ]]; then
  NEW_ENV="$1"
  CURRENT_ENV=$([[ "$NEW_ENV" == "blue" ]] && echo "green" || echo "blue")
  log_info "Forced target: $NEW_ENV  (treating $CURRENT_ENV as current)"
else
  # Read active slot from nginx.conf — the uncommented server line tells us
  if grep -qE "^\s+server app-blue:3000;" "$NGINX_CONF"; then
    CURRENT_ENV="blue"
    NEW_ENV="green"
  elif grep -qE "^\s+server app-green:3000;" "$NGINX_CONF"; then
    CURRENT_ENV="green"
    NEW_ENV="blue"
  else
    log_error "Cannot detect active slot from $NGINX_CONF"
    exit 1
  fi
fi

echo ""
echo "============================================================"
echo "  Blue-Green Deploy"
echo "  Current (active) : ${CURRENT_ENV}"
echo "  New     (target) : ${NEW_ENV}"
echo "============================================================"
echo ""

# Build & start the new environment 
log_step "1/5  Building and starting ${NEW_ENV} environment..."
docker compose -f "docker-compose.${NEW_ENV}.yml" up -d --build

# Wait for container health 
log_step "2/5  Waiting up to 60 s for app-${NEW_ENV} to become healthy..."
TIMEOUT=60
ELAPSED=0
until docker inspect --format='{{.State.Health.Status}}' "app-${NEW_ENV}" 2>/dev/null | grep -q "^healthy$"; do
  if (( ELAPSED >= TIMEOUT )); then
    log_error "app-${NEW_ENV} did not become healthy within ${TIMEOUT}s. Rolling back..."
    docker compose -f "docker-compose.${NEW_ENV}.yml" down
    exit 1
  fi
  sleep 3
  ELAPSED=$(( ELAPSED + 3 ))
  echo -n "."
done
echo ""
log_success "app-${NEW_ENV} is healthy."

# Direct health-check request against the new container 
log_step "3/5  Running health check against app-${NEW_ENV}..."
HEALTH=$(docker exec "app-${NEW_ENV}" wget -qO- http://localhost:3000/health 2>/dev/null || true)
if [[ "$HEALTH" != *'"status":"OK"'* ]]; then
  log_error "Health check response did not contain '\"status\":\"OK\"'."
  log_error "Response: $HEALTH"
  log_warn  "Rolling back — stopping app-${NEW_ENV}..."
  docker compose -f "docker-compose.${NEW_ENV}.yml" down
  exit 1
fi
log_success "Health check passed: $HEALTH"

# Switch nginx upstream 
log_step "4/5  Switching nginx upstream from ${CURRENT_ENV} → ${NEW_ENV}..."

python3 - <<PYEOF
conf = open("${NGINX_CONF}").read()
conf = conf.replace("    server app-${CURRENT_ENV}:3000;", "    # server app-${CURRENT_ENV}:3000;")
conf = conf.replace("    # server app-${NEW_ENV}:3000;",   "    server app-${NEW_ENV}:3000;")
open("${NGINX_CONF}", "w").write(conf)
PYEOF

# Reload nginx (no downtime)
docker exec "$NGINX_CONTAINER" nginx -s reload
log_success "Nginx reloaded — traffic is now routed to app-${NEW_ENV}."

# Verify traffic through nginx 
log_step "5/5  Verifying traffic through nginx..."
sleep 2
NGINX_RESP=$(curl -s http://localhost:8080/ 2>/dev/null || true)
if [[ "$NGINX_RESP" == *"${NEW_ENV}"* ]]; then
  log_success "Nginx is serving the ${NEW_ENV} slot correctly."
else
  log_warn "Nginx response did not mention '${NEW_ENV}'. Response: $NGINX_RESP"
  log_warn "Traffic may still have switched — check manually."
fi

echo ""
echo "============================================================"
log_success "Deployment complete!"
echo "  Live slot  : ${NEW_ENV} (app-${NEW_ENV})"
echo "  Standby    : ${CURRENT_ENV} (app-${CURRENT_ENV} — still running)"
echo ""
echo "  Test: curl http://localhost:8080/"
echo ""
echo "  To finish (remove old slot):"
echo "    docker compose -f docker-compose.${CURRENT_ENV}.yml down"
echo ""
echo "  To rollback (re-run deploy targeting old slot):"
echo "    ./blue-green-deploy.sh ${CURRENT_ENV}"
echo "============================================================"
