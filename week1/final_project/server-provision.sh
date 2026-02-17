#!/bin/bash
set -euo pipefail

# Script: server-provision.sh
# Description: Full server provisioning and hardening
# Author: Aakash
# Date: 2026-02-16

readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_FILE="/var/log/apps/server-provision.log"

log() { echo "[$(date '+%F %T')] $1" | tee -a "$LOG_FILE"; }

main() {
    log "=== Server Provisioning Started ==="

    log "Running system inventory"
    bash "$BASE_DIR/day1/system_inventory.sh"

    log "Provisioning users"
    bash "$BASE_DIR/day2/user_provision.sh" "$BASE_DIR/day2/users.txt"

    log "Applying firewall rules"
    bash "$BASE_DIR/day4/firewall_audit.sh"

    log "Applying security hardening"
    bash "$BASE_DIR/day4/security_hardening.sh"

    log "Verifying DNS resolution"
    dig google.com >/dev/null || log "DNS check failed"

    log "Server provisioning completed"
}

main "$@"
