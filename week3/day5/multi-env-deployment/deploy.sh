#!/bin/bash
# deploy.sh — Multi-environment deployment script
# Usage: ./deploy.sh [dev|staging|prod] [up|down|status|logs]

set -euo pipefail

# Defaults 
ENVIRONMENT=${1:-dev}
ACTION=${2:-up}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env.${ENVIRONMENT}"

# Colors 
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC}    $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $*"; }

# Validate environment file 
if [[ ! -f "$ENV_FILE" ]]; then
  log_error "Environment file '$ENV_FILE' not found."
  echo "Available environments: dev | staging | prod"
  exit 1
fi

log_info "Loading environment variables from $ENV_FILE"
# Export only non-comment, non-empty lines
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# Select compose files 
case "$ENVIRONMENT" in
  dev)
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.dev.yml"
    ;;
  staging)
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.staging.yml"
    ;;
  prod)
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.prod.yml"
    ;;
  *)
    log_error "Unknown environment: '$ENVIRONMENT'. Valid options: dev | staging | prod"
    exit 1
    ;;
esac

dc() {
  docker compose $COMPOSE_FILES "$@"
}

# Actions 
action_up() {
  log_info "Deploying to '${ENVIRONMENT}' environment..."

  log_info "Pulling latest base images..."
  dc pull --quiet || log_warn "Pull step had warnings (this is OK for local builds)"

  log_info "Building application image..."
  dc build --no-cache

  log_info "Running database migrations..."
  dc run --rm api node migrate.js || log_warn "Migration step skipped (DB may not be ready yet)"

  log_info "Starting all services (rolling update, remove orphans)..."
  dc up -d --remove-orphans

  log_info "Waiting 15 s for services to become healthy..."
  sleep 15

  action_status
  log_success "Deployment to '${ENVIRONMENT}' completed!"
}

action_down() {
  log_warn "Stopping all services in '${ENVIRONMENT}' environment..."
  dc down --remove-orphans
  log_success "Services stopped."
}

action_status() {
  log_info "Service status for '${ENVIRONMENT}':"
  dc ps
}

action_logs() {
  log_info "Tailing logs for '${ENVIRONMENT}' (Ctrl-C to exit)..."
  dc logs -f --tail=50
}

# Dispatch 
echo ""
echo "============================================================"
echo "  Multi-Env Deployment Script"
echo "  Environment : ${ENVIRONMENT}"
echo "  Action      : ${ACTION}"
echo "============================================================"
echo ""

cd "$SCRIPT_DIR"

case "$ACTION" in
  up)     action_up     ;;
  down)   action_down   ;;
  status) action_status ;;
  logs)   action_logs   ;;
  *)
    log_error "Unknown action: '$ACTION'. Valid options: up | down | status | logs"
    exit 1
    ;;
esac
