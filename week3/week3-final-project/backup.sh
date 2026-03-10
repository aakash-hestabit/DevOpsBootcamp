#!/bin/bash
set -euo pipefail

# backup.sh — Production-ready backup for all databases & configs
#
# Features:
#   - Compressed (gzip) database dumps
#   - Backup validation (file size check)
#   - Configurable retention (auto-delete old backups)
#   - Restore mode for disaster recovery
#   - Logging with timestamps
#   - Cleanup trap on failure
#
# Usage:
#   ./backup.sh                    # Run a full backup
#   ./backup.sh --restore <dir>    # Restore from a backup directory
#   ./backup.sh --list             # List available backups
#   ./backup.sh --help             # Show help

readonly SCRIPT_NAME="$(basename "$0")"
readonly PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly BACKUP_ROOT="${PROJECT_DIR}/backups"
readonly LOG_DIR="${PROJECT_DIR}/var/log"
readonly LOG_FILE="${LOG_DIR}/backup.log"
readonly DATE="$(date +%Y%m%d_%H%M%S)"
readonly BACKUP_DIR="${BACKUP_ROOT}/${DATE}"
readonly RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
readonly MIN_DUMP_SIZE=50  # minimum bytes for a valid dump

# Load environment 
if [[ -f "${PROJECT_DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${PROJECT_DIR}/.env"
  set +a
fi

USER_DB_USER="${USER_DB_USER:-userservice}"
USER_DB_NAME="${USER_DB_NAME:-userdb}"
ORDER_DB_USER="${ORDER_DB_USER:-orderservice}"
ORDER_DB_NAME="${ORDER_DB_NAME:-orderdb}"
MONGO_DB="${MONGO_INITDB_DATABASE:-productdb}"

# Logging 
mkdir -p "$LOG_DIR"
log()      { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "$LOG_FILE"; }
log_ok()   { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [OK]    $*" | tee -a "$LOG_FILE"; }
log_err()  { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_FILE" >&2; }
log_warn() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "$LOG_FILE"; }

# Cleanup on failure 
BACKUP_STARTED=false
cleanup() {
  local exit_code=$?
  if [[ "$BACKUP_STARTED" == true && $exit_code -ne 0 ]]; then
    log_err "Backup failed — cleaning up partial backup at ${BACKUP_DIR}"
    rm -rf "$BACKUP_DIR"
  fi
  log "Backup script finished (exit code: ${exit_code})"
}
trap cleanup EXIT

# Help 
show_help() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Production-ready backup tool for the microservices platform.

OPTIONS:
    (no args)             Run a full backup (databases + configs)
    --restore <dir>       Restore from a backup directory
    --list                List available backups
    --prune               Delete backups older than ${RETENTION_DAYS} days
    --help                Show this help message

ENVIRONMENT:
    BACKUP_RETENTION_DAYS  Number of days to keep backups (default: 7)

EXAMPLES:
    ${SCRIPT_NAME}                           # full backup
    ${SCRIPT_NAME} --list                    # show backups
    ${SCRIPT_NAME} --restore backups/20260310_120000
    ${SCRIPT_NAME} --prune                   # remove old backups
EOF
}

# Validation helper 
validate_file() {
  local file="$1"
  local label="$2"
  if [[ -f "$file" ]]; then
    local size
    size=$(stat -c%s "$file" 2>/dev/null || echo 0)
    if [[ "$size" -ge "$MIN_DUMP_SIZE" ]]; then
      log_ok "${label}: OK ($(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B"))"
      return 0
    else
      log_warn "${label}: File too small (${size} bytes) — may be empty/corrupt"
      return 1
    fi
  else
    log_err "${label}: File missing"
    return 1
  fi
}

# Check Docker is running 
check_docker() {
  if ! docker compose ps --quiet 2>/dev/null | head -1 >/dev/null; then
    log_err "Docker Compose services are not running. Start them first."
    exit 1
  fi
}

# Backup Databases 
backup_databases() {
  local failures=0

  # PostgreSQL: user-db
  log "Dumping user-db (PostgreSQL) ..."
  if docker compose exec -T user-db pg_dump -U "${USER_DB_USER}" "${USER_DB_NAME}" 2>/dev/null \
       | gzip > "${BACKUP_DIR}/user-db.sql.gz"; then
    validate_file "${BACKUP_DIR}/user-db.sql.gz" "user-db" || failures=$((failures + 1))
  else
    log_err "user-db dump FAILED (container may not be running)"
    failures=$((failures + 1))
  fi

  # PostgreSQL: order-db
  log "Dumping order-db (PostgreSQL) ..."
  if docker compose exec -T order-db pg_dump -U "${ORDER_DB_USER}" "${ORDER_DB_NAME}" 2>/dev/null \
       | gzip > "${BACKUP_DIR}/order-db.sql.gz"; then
    validate_file "${BACKUP_DIR}/order-db.sql.gz" "order-db" || failures=$((failures + 1))
  else
    log_err "order-db dump FAILED (container may not be running)"
    failures=$((failures + 1))
  fi

  # MongoDB: product-db
  log "Dumping product-db (MongoDB) ..."
  if docker compose exec -T product-db mongodump --db "${MONGO_DB}" --archive 2>/dev/null \
       | gzip > "${BACKUP_DIR}/product-db.archive.gz"; then
    validate_file "${BACKUP_DIR}/product-db.archive.gz" "product-db" || failures=$((failures + 1))
  else
    log_err "product-db dump FAILED (container may not be running)"
    failures=$((failures + 1))
  fi

  return "$failures"
}

# Backup Configs 
backup_configs() {
  log "Copying configuration files ..."
  mkdir -p "${BACKUP_DIR}/configs"

  local files=(.env docker-compose.yml docker-compose.prod.yml docker-compose.dev.yml)
  for f in "${files[@]}"; do
    if [[ -f "${PROJECT_DIR}/${f}" ]]; then
      cp "${PROJECT_DIR}/${f}" "${BACKUP_DIR}/configs/"
    fi
  done

  # Directories
  for d in monitoring database ssl; do
    if [[ -d "${PROJECT_DIR}/${d}" ]]; then
      cp -r "${PROJECT_DIR}/${d}" "${BACKUP_DIR}/configs/${d}/"
    fi
  done

  log_ok "Configuration backup complete"
}

# Prune old backups 
prune_backups() {
  log "Pruning backups older than ${RETENTION_DAYS} days ..."
  local count=0
  while IFS= read -r -d '' dir; do
    log "  Removing: $(basename "$dir")"
    rm -rf "$dir"
    count=$((count + 1))
  done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -mtime +"$RETENTION_DAYS" -print0 2>/dev/null)

  if [[ "$count" -eq 0 ]]; then
    log "  No old backups to prune."
  else
    log_ok "Pruned ${count} old backup(s)."
  fi
}

# List backups 
list_backups() {
  echo ""
  echo "Available Backups"
  echo "========================================"
  if [[ ! -d "$BACKUP_ROOT" ]] || [[ -z "$(ls -A "$BACKUP_ROOT" 2>/dev/null)" ]]; then
    echo "  No backups found."
    echo ""
    return
  fi

  printf "  %-22s  %s\n" "BACKUP" "SIZE"
  printf "  %-22s  %s\n" "------" "----"
  for dir in "${BACKUP_ROOT}"/*/; do
    [[ -d "$dir" ]] || continue
    local name size
    name=$(basename "$dir")
    size=$(du -sh "$dir" 2>/dev/null | cut -f1)
    printf "  %-22s  %s\n" "$name" "$size"
  done
  echo "========================================"
  echo ""
}

# Restore 
restore_backup() {
  local restore_dir="$1"

  if [[ ! -d "$restore_dir" ]]; then
    log_err "Backup directory not found: ${restore_dir}"
    exit 1
  fi

  log "Restoring from: ${restore_dir}"
  echo ""
  echo "  WARNING: This will OVERWRITE current database contents."
  read -rp "  Continue? (yes/no): " confirm
  if [[ "$confirm" != "yes" ]]; then
    log "Restore cancelled."
    exit 0
  fi

  # Restore PostgreSQL: user-db
  if [[ -f "${restore_dir}/user-db.sql.gz" ]]; then
    log "Restoring user-db ..."
    gunzip -c "${restore_dir}/user-db.sql.gz" \
      | docker compose exec -T user-db psql -U "${USER_DB_USER}" -d "${USER_DB_NAME}" 2>/dev/null \
      && log_ok "user-db restored" \
      || log_err "user-db restore FAILED"
  fi

  # Restore PostgreSQL: order-db
  if [[ -f "${restore_dir}/order-db.sql.gz" ]]; then
    log "Restoring order-db ..."
    gunzip -c "${restore_dir}/order-db.sql.gz" \
      | docker compose exec -T order-db psql -U "${ORDER_DB_USER}" -d "${ORDER_DB_NAME}" 2>/dev/null \
      && log_ok "order-db restored" \
      || log_err "order-db restore FAILED"
  fi

  # Restore MongoDB: product-db
  if [[ -f "${restore_dir}/product-db.archive.gz" ]]; then
    log "Restoring product-db ..."
    gunzip -c "${restore_dir}/product-db.archive.gz" \
      | docker compose exec -T product-db mongorestore --db "${MONGO_DB}" --archive --drop 2>/dev/null \
      && log_ok "product-db restored" \
      || log_err "product-db restore FAILED"
  fi

  log "Restore complete."
}

# Full backup (main flow) 
run_backup() {
  log "=== Backup started ==="
  BACKUP_STARTED=true
  check_docker

  mkdir -p "$BACKUP_DIR"
  log "Backup target: ${BACKUP_DIR}"

  # Databases
  local db_failures=0
  backup_databases || db_failures=$?

  # Configs
  backup_configs

  # Create checksum
  log "Generating checksums ..."
  (cd "$BACKUP_DIR" && find . -type f ! -name "checksums.sha256" -exec sha256sum {} + > checksums.sha256)
  log_ok "Checksums saved"

  # Auto-prune
  prune_backups

  # Summary
  echo ""
  echo "========================================"
  log "Backup complete!"
  echo "  Location : ${BACKUP_DIR}"
  echo "  Size     : $(du -sh "$BACKUP_DIR" | cut -f1)"
  echo "  Files    :"
  ls -lh "$BACKUP_DIR/" | tail -n+2 | sed 's/^/    /'
  echo "========================================"

  if [[ "$db_failures" -gt 0 ]]; then
    log_warn "${db_failures} database backup(s) had issues — check logs."
    exit 1
  fi

  log "=== Backup completed successfully ==="
}

# Argument parsing 
case "${1:-}" in
  --help|-h)
    show_help
    exit 0
    ;;
  --list|-l)
    list_backups
    exit 0
    ;;
  --prune)
    prune_backups
    exit 0
    ;;
  --restore|-r)
    if [[ -z "${2:-}" ]]; then
      log_err "Usage: ${SCRIPT_NAME} --restore <backup_dir>"
      exit 1
    fi
    restore_backup "$2"
    exit 0
    ;;
  "")
    run_backup
    ;;
  *)
    log_err "Unknown option: $1"
    show_help
    exit 1
    ;;
esac
