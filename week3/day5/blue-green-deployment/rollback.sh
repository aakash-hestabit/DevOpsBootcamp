#!/bin/bash

# rollback.sh — Instantly roll back to the previous (standby) slot
#
# Usage:
#   ./rollback.sh            # auto-detect standby slot and switch back to it
#   ./rollback.sh blue       # force rollback to blue
#   ./rollback.sh green      # force rollback to green

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
log_warn() { echo -e "\033[1;33m[WARN]\033[0m    $*"; }
log_info() { echo -e "\033[0;34m[INFO]\033[0m    $*"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $*"; }

log_warn "Rolling back deployment..."

# Delegate to the deploy script, targeting the requested slot
if [[ -n "${1:-}" ]]; then
  log_info "Rolling back to: $1"
  exec "${SCRIPT_DIR}/blue-green-deploy.sh" "$1"
else
  # Auto-detect the STANDBY slot (the one NOT in nginx.conf's active line)
  NGINX_CONF="${SCRIPT_DIR}/nginx/nginx.conf"
  if grep -qE "^\s+server app-blue:3000;" "$NGINX_CONF"; then
    STANDBY="green"
  else
    STANDBY="blue"
  fi
  log_info "Detected standby slot: ${STANDBY}"
  exec "${SCRIPT_DIR}/blue-green-deploy.sh" "$STANDBY"
fi
