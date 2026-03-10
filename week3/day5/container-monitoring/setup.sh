#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="$(dirname "$0")/docker-compose.yml"

usage() {
  echo "Usage: $0 {up|down|status|logs}"
  exit 1
}

cmd="${1:-up}"

case "$cmd" in
  up)
    echo "[*] Starting container monitoring stack ..."
    docker compose -f "$COMPOSE_FILE" up -d --pull always
    echo ""
    echo "[*] Waiting 10 s for services to initialize ..."
    sleep 10
    docker compose -f "$COMPOSE_FILE" ps
    echo ""
    echo "  cAdvisor  --> http://localhost:9091"
    echo "  Prometheus --> http://localhost:9090"
    echo "  Grafana    --> http://localhost:3001  (admin / admin)"
    ;;
  down)
    echo "[*] Stopping container monitoring stack ..."
    docker compose -f "$COMPOSE_FILE" down
    ;;
  status)
    docker compose -f "$COMPOSE_FILE" ps
    ;;
  logs)
    docker compose -f "$COMPOSE_FILE" logs -f --tail=50
    ;;
  *)
    usage
    ;;
esac
