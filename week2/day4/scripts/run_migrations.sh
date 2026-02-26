#!/bin/bash
# Script: run_migrations.sh
# Description: Runs database migrations for Express (PostgreSQL) and FastAPI (MySQL) projects.
#              For Laravel, delegates to Artisan migrate.
# Author: Aakash
# Date: 2026-02-26
# Usage: ./scripts/run_migrations.sh [options]
# Exit codes:
#   0 - All migrations successful
#   1 - One or more migrations failed

set -euo pipefail

readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_FILE="${ROOT_DIR}/var/log/apps/run_migrations.log"

mkdir -p "${ROOT_DIR}/var/log/apps"

VERBOSE=false
TARGET="all"   # all | express | fastapi | laravel

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "${LOG_FILE}"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "${LOG_FILE}" >&2; }

show_usage() {
  cat << EOF
Usage: $(basename $0) [OPTIONS]
Description: Runs all database migrations in order.

OPTIONS:
  -h, --help            Show this help message
  -v, --verbose         Enable verbose output
  -t, --target TARGET   Run migrations for: all | express | fastapi | laravel (default: all)

Examples:
  $(basename $0)
  $(basename $0) --target express
  $(basename $0) --target fastapi --verbose
EOF
}

# Express Migrations (PostgreSQL) 
run_express_migrations() {
  log_info "--- Running Express (PostgreSQL) migrations ---"

  local migration="${ROOT_DIR}/migrations/express/001_create_users_table.sql"
  if [[ ! -f "${migration}" ]]; then
    log_error "Migration file not found: ${migration}"
    return 1
  fi

  if ! command -v psql &>/dev/null; then
    log_error "psql not found. Install PostgreSQL client."
    return 1
  fi

  # Required env vars (can be set before running this script)
  local PG_HOST="${DB_HOST:-localhost}"
  local PG_PORT="${DB_PORT:-5432}"
  local PG_DB="${DB_NAME:-apidb}"
  local PG_USER="${DB_USER:-apiuser}"

  log_info "Connecting to PostgreSQL: ${PG_USER}@${PG_HOST}:${PG_PORT}/${PG_DB}"
  PGPASSWORD="${DB_PASSWORD:-}" psql -h "${PG_HOST}" -p "${PG_PORT}" \
    -U "${PG_USER}" -d "${PG_DB}" \
    -f "${migration}" && log_info " Express migration 001 applied" || {
      log_error " Express migration 001 failed"
      return 1
    }
}

# FastAPI Migrations (MySQL) 
run_fastapi_migrations() {
  log_info "--- Running FastAPI (MySQL) migrations ---"

  local migration="${ROOT_DIR}/migrations/fastapi/001_create_products_table.sql"
  if [[ ! -f "${migration}" ]]; then
    log_error "Migration file not found: ${migration}"
    return 1
  fi

  if ! command -v mysql &>/dev/null; then
    log_error "mysql client not found. Install MySQL client."
    return 1
  fi

  local MY_HOST="${DB_HOST:-localhost}"
  local MY_PORT="${DB_PORT:-3306}"
  local MY_DB="${DB_NAME:-fastapidb}"
  local MY_USER="${DB_USER:-fastapiuser}"

  log_info "Connecting to MySQL: ${MY_USER}@${MY_HOST}:${MY_PORT}/${MY_DB}"
  mysql -h "${MY_HOST}" -P "${MY_PORT}" -u "${MY_USER}" \
    -p"${DB_PASSWORD:-}" "${MY_DB}" \
    < "${migration}" && log_info " FastAPI migration 001 applied" || {
      log_error " FastAPI migration 001 failed"
      return 1
    }
}

#  Laravel Migrations (Artisan) 
run_laravel_migrations() {
  log_info "--- Running Laravel (MySQL) migrations ---"

  local laravel_dir="${ROOT_DIR}/laravel-mysql-api"
  if [[ ! -d "${laravel_dir}" ]]; then
    log_error "Laravel project not found at: ${laravel_dir}"
    return 1
  fi

  if ! command -v php &>/dev/null; then
    log_error "php not found. Install PHP."
    return 1
  fi

  cd "${laravel_dir}"
  php artisan migrate --force && log_info " Laravel migrations applied" || {
    log_error " Laravel migrations failed"
    return 1
  }
  cd "${ROOT_DIR}"
}

#  Main 
main() {
  log_info "Migration runner started (target: ${TARGET})"
  local failed=0

  case "${TARGET}" in
    all)
      run_express_migrations || failed=$((failed + 1))
      run_fastapi_migrations  || failed=$((failed + 1))
      run_laravel_migrations  || failed=$((failed + 1))
      ;;
    express)  run_express_migrations || failed=$((failed + 1)) ;;
    fastapi)  run_fastapi_migrations  || failed=$((failed + 1)) ;;
    laravel)  run_laravel_migrations  || failed=$((failed + 1)) ;;
    *) log_error "Unknown target: ${TARGET}"; exit "${EXIT_ERROR}" ;;
  esac

  if [[ "${failed}" -gt 0 ]]; then
    log_error "Migration runner completed with ${failed} failure(s)"
    exit "${EXIT_ERROR}"
  fi

  log_info "All migrations completed successfully"
}

#  Argument Parsing 
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)    show_usage; exit "${EXIT_SUCCESS}" ;;
    -v|--verbose) VERBOSE=true ;;
    -t|--target)  TARGET="${2:-all}"; shift ;;
    *) echo "Unknown option: $1"; show_usage; exit "${EXIT_ERROR}" ;;
  esac
  shift
done

main "$@"