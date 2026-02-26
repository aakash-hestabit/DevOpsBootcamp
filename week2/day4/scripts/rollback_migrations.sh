#!/bin/bash
# Script: rollback_migrations.sh
# Description: Rolls back database migrations. Drops tables created by run_migrations.sh.
#              For Laravel, delegates to Artisan rollback.
# Author: Aakash
# Date: 2026-02-26
# Usage: ./scripts/rollback_migrations.sh [options]

set -euo pipefail

readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_FILE="${ROOT_DIR}/var/log/apps/rollback_migrations.log"

mkdir -p "${ROOT_DIR}/var/log/apps"

TARGET="all"

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "${LOG_FILE}"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "${LOG_FILE}" >&2; }

show_usage() {
  cat << EOF
Usage: $(basename $0) [OPTIONS]
Description: Rolls back database migrations (drops tables). Use with caution.

OPTIONS:
  -h, --help            Show this help message
  -v, --verbose         Enable verbose output
  -t, --target TARGET   Rollback for: all | express | fastapi | laravel (default: all)

Examples:
  $(basename $0) --target express
EOF
}

rollback_express() {
  log_info "Rolling back Express PostgreSQL migrations"
  local rollback="${ROOT_DIR}/migrations/express/001_rollback_users_table.sql"
  PGPASSWORD="${DB_PASSWORD:-}" psql -h "${DB_HOST:-localhost}" -U "${DB_USER:-apiuser}" \
    -d "${DB_NAME:-apidb}" -f "${rollback}" && log_info " Express rollback done" || {
      log_error " Express rollback failed"; return 1
    }
}

rollback_fastapi() {
  log_info "Rolling back FastAPI MySQL migrations"
  local rollback="${ROOT_DIR}/migrations/fastapi/001_rollback_products_table.sql"
  mysql -h "${DB_HOST:-localhost}" -u "${DB_USER:-fastapiuser}" \
    -p"${DB_PASSWORD:-}" "${DB_NAME:-fastapidb}" \
    < "${rollback}" && log_info " FastAPI rollback done" || {
      log_error " FastAPI rollback failed"; return 1
    }
}

rollback_laravel() {
  log_info "Rolling back Laravel migrations"
  cd "${ROOT_DIR}/laravel-mysql-api"
  php artisan migrate:rollback --force && log_info " Laravel rollback done" || {
    log_error " Laravel rollback failed"; return 1
  }
  cd "${ROOT_DIR}"
}

main() {
  log_info "Rollback started (target: ${TARGET})"
  echo "⚠ WARNING: This will drop tables. You have 5 seconds to cancel (Ctrl+C)."
  sleep 5

  case "${TARGET}" in
    all)     rollback_express; rollback_fastapi; rollback_laravel ;;
    express) rollback_express ;;
    fastapi) rollback_fastapi ;;
    laravel) rollback_laravel ;;
    *)       log_error "Unknown target: ${TARGET}"; exit "${EXIT_ERROR}" ;;
  esac

  log_info "Rollback completed"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)    show_usage; exit "${EXIT_SUCCESS}" ;;
    -v|--verbose) ;;
    -t|--target)  TARGET="${2:-all}"; shift ;;
    *) echo "Unknown option: $1"; show_usage; exit "${EXIT_ERROR}" ;;
  esac
  shift
done

main "$@"