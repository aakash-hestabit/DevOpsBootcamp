#!/bin/bash
# backup-volumes.sh — Backup Docker named volumes to compressed tar archives.
#
# Usage:
#   ./backup-volumes.sh [OPTIONS] [VOLUME...]
#
# Options:
#   -d, --dir DIR      Destination directory for backups (default: ./backups)
#   -r, --retain DAYS  Delete backups older than DAYS days (default: 7)
#   -v, --volumes LIST Comma-separated list of volume names to back up
#                      (default: all named volumes)
#   -h, --help         Show this help message and exit
#
# Examples:
#   ./backup-volumes.sh                            # back up all volumes
#   ./backup-volumes.sh -d /mnt/nas/docker-vols    # custom output dir
#   ./backup-volumes.sh -v postgres_data,mysql_data # specific volumes
#   ./backup-volumes.sh --retain 14               # keep 14 days

set -euo pipefail

# Defaults 
BACKUP_DIR="$(cd "$(dirname "$0")" && pwd)/backups"
RETAIN_DAYS=7
VOLUME_FILTER=""        # empty = all volumes
LOG_FILE=""             # set below after BACKUP_DIR is resolved

# Colours 
GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; RESET="\033[0m"
info()    { echo -e "${GREEN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

# Help 
usage() {
cat <<EOF
backup-volumes.sh — Docker Named Volume Backup Utility

USAGE
  ./backup-volumes.sh [OPTIONS]

OPTIONS
  -d, --dir DIR        Backup destination directory  (default: ./backups)
  -r, --retain DAYS    Retention period in days       (default: 7)
  -v, --volumes LIST   Comma-separated volume names   (default: all)
  -h, --help           Print this message and exit

EXAMPLES
  # Back up every named volume to the default ./backups directory
  ./backup-volumes.sh

  # Back up only two specific volumes, keep 30 days worth
  ./backup-volumes.sh -v postgres_data,mysql_data --retain 30

  # Use a custom output directory
  ./backup-volumes.sh --dir /mnt/nas/docker-backups

OUTPUT
  Each volume produces one file:
    <VOLUME_NAME>-<YYYYMMDD-HHMMSS>.tar.gz

  A run summary is appended to:
    <BACKUP_DIR>/backup.log

RESTORE
  Use the companion restore-volume.sh script:
    ./restore-volume.sh <archive.tar.gz> <target-volume-name>
EOF
}

# Argument parsing 
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)    usage; exit 0 ;;
    -d|--dir)     BACKUP_DIR="$2";   shift 2 ;;
    -r|--retain)  RETAIN_DAYS="$2";  shift 2 ;;
    -v|--volumes) VOLUME_FILTER="$2"; shift 2 ;;
    *) error "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# Setup 
DATE=$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUP_DIR"
LOG_FILE="$BACKUP_DIR/backup.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "===== Backup run started (${DATE}) ====="
log "Backup dir : $BACKUP_DIR"
log "Retention  : ${RETAIN_DAYS} days"

# Volume selection 
if [[ -n "$VOLUME_FILTER" ]]; then
  IFS=',' read -ra VOLUMES <<< "$VOLUME_FILTER"
else
  mapfile -t VOLUMES < <(docker volume ls -q)
fi

if [[ ${#VOLUMES[@]} -eq 0 ]]; then
  warn "No volumes found — nothing to back up."
  log "No volumes found."
  exit 0
fi

log "Volumes to back up: ${VOLUMES[*]}"

# Backup loop 
SUCCESS=0
FAIL=0

for VOLUME in "${VOLUMES[@]}"; do
  VOLUME=$(echo "$VOLUME" | xargs)          # trim whitespace
  [[ -z "$VOLUME" ]] && continue

  ARCHIVE="${BACKUP_DIR}/${VOLUME}-${DATE}.tar.gz"
  info "Backing up volume: ${VOLUME}"

  if docker run --rm \
       -v "${VOLUME}:/source:ro" \
       -v "${BACKUP_DIR}:/backup" \
       alpine \
       tar czf "/backup/${VOLUME}-${DATE}.tar.gz" -C /source . 2>/dev/null; then

    SIZE=$(du -sh "$ARCHIVE" 2>/dev/null | cut -f1)
    info "  ✓ ${VOLUME}-${DATE}.tar.gz  (${SIZE})"
    log "SUCCESS  ${VOLUME}  ->  $(basename "$ARCHIVE")  [${SIZE}]"
    (( SUCCESS++ )) || true
  else
    error "  ✗ Failed to back up volume: ${VOLUME}"
    log "FAILED   ${VOLUME}"
    rm -f "$ARCHIVE"   # remove partial archive
    (( FAIL++ )) || true
  fi
done

# Cleanup old backups 
info "Removing backups older than ${RETAIN_DAYS} days…"
CLEANED=$(find "$BACKUP_DIR" -name "*.tar.gz" -mtime +"$RETAIN_DAYS" -print -delete | wc -l)
log "Cleanup: removed ${CLEANED} archive(s) older than ${RETAIN_DAYS} days"

# Summary 
echo ""
info "===== Backup Summary ====="
info "  Total   : $((SUCCESS + FAIL))"
info "  Success : ${SUCCESS}"
info "  Failed  : ${FAIL}"
info "  Saved to: ${BACKUP_DIR}"
info "  Log     : ${LOG_FILE}"

log "===== Backup run finished — success=${SUCCESS} failed=${FAIL} ====="

[[ $FAIL -gt 0 ]] && exit 1 || exit 0
