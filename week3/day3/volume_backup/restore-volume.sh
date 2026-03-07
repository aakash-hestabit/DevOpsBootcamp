#!/bin/bash
# restore-volume.sh — Restore a Docker named volume from a .tar.gz backup.
#
# Usage:
#   ./restore-volume.sh [OPTIONS] <archive.tar.gz> <volume-name>
#
# Options:
#   -f, --force     Overwrite target volume without confirmation prompt
#   -h, --help      Show this help message and exit
#
# Examples:
#   ./restore-volume.sh backups/postgres_data-20260307-120000.tar.gz postgres_data
#   ./restore-volume.sh --force backups/mysql_data-20260307-120000.tar.gz mysql_data_restored
# ---------------------------------------------------------------------------

set -euo pipefail

GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; RESET="\033[0m"
info()  { echo -e "${GREEN}[INFO]${RESET}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }

# Help 
usage() {
cat <<EOF
restore-volume.sh — Docker Named Volume Restore Utility

USAGE
  ./restore-volume.sh [OPTIONS] <archive.tar.gz> <volume-name>

ARGUMENTS
  archive.tar.gz   Path to the backup archive created by backup-volumes.sh
  volume-name      Target Docker volume name (created if it does not exist)

OPTIONS
  -f, --force      Skip confirmation prompt and overwrite existing volume data
  -h, --help       Print this message and exit

EXAMPLES
  # Restore a backup into its original volume
  ./restore-volume.sh backups/postgres_data-20260307-120000.tar.gz postgres_data

  # Restore into a new volume (useful for testing without touching production)
  ./restore-volume.sh backups/postgres_data-20260307-120000.tar.gz postgres_data_test

  # Non-interactive restore (useful in scripts/CI)
  ./restore-volume.sh --force backups/mysql_data-20260307.tar.gz mysql_data
EOF
}

# Argument parsing 
FORCE=false
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)  usage; exit 0 ;;
    -f|--force) FORCE=true; shift ;;
    -*) error "Unknown option: $1"; usage; exit 1 ;;
    *)  POSITIONAL+=("$1"); shift ;;
  esac
done

if [[ ${#POSITIONAL[@]} -lt 2 ]]; then
  error "Two positional arguments required: <archive> <volume-name>"
  usage
  exit 1
fi

ARCHIVE="${POSITIONAL[0]}"
VOLUME="${POSITIONAL[1]}"

# Validate archive 
if [[ ! -f "$ARCHIVE" ]]; then
  error "Archive not found: $ARCHIVE"
  exit 1
fi

# Convert to absolute path so the Docker bind mount works from any cwd
ARCHIVE_ABS=$(realpath "$ARCHIVE")
ARCHIVE_DIR=$(dirname  "$ARCHIVE_ABS")
ARCHIVE_FILE=$(basename "$ARCHIVE_ABS")

# Confirm overwrite if volume already exists 
if docker volume inspect "$VOLUME" &>/dev/null; then
  if [[ "$FORCE" == false ]]; then
    warn "Volume '${VOLUME}' already exists. All current data will be replaced."
    read -r -p "Continue? [y/N] " REPLY
    [[ "${REPLY,,}" != "y" ]] && { info "Aborted."; exit 0; }
  else
    warn "Force flag set — overwriting existing volume '${VOLUME}'."
  fi
else
  info "Volume '${VOLUME}' does not exist — it will be created."
  docker volume create "$VOLUME" >/dev/null
fi

# Restore 
info "Restoring '${ARCHIVE_FILE}' → volume '${VOLUME}'…"

# Step 1: clear the volume contents
docker run --rm \
  -v "${VOLUME}:/target" \
  alpine \
  sh -c "rm -rf /target/* /target/.[!.]*" 2>/dev/null || true

# Step 2: extract archive into the volume
docker run --rm \
  -v "${VOLUME}:/target" \
  -v "${ARCHIVE_DIR}:/backup:ro" \
  alpine \
  tar xzf "/backup/${ARCHIVE_FILE}" -C /target

# Verify 
FILE_COUNT=$(docker run --rm \
  -v "${VOLUME}:/target:ro" \
  alpine \
  sh -c "find /target -maxdepth 2 | wc -l")

info "✓ Restore complete."
info "  Volume        : ${VOLUME}"
info "  Archive used  : ${ARCHIVE_FILE}"
info "  Files (depth 2): ${FILE_COUNT}"
