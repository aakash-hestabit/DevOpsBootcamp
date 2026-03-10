#!/bin/bash

# Docker System Backup Script
# Backs up Docker volumes, compose configs, env files, and images
# Implements 7-day backup rotation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_ROOT="${BACKUP_ROOT:-$SCRIPT_DIR/backups}"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$BACKUP_ROOT/$DATE"
REPORT_DIR="$SCRIPT_DIR/reports"
REPORT_FILE="$REPORT_DIR/backup-report-$(date +%Y%m%d).txt"
COMPOSE_SEARCH_PATHS=("/opt/apps" "$(pwd)")
RETENTION_DAYS=7
ERRORS=0

mkdir -p "$BACKUP_DIR"/{volumes,configs,images}
mkdir -p "$REPORT_DIR"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$REPORT_FILE"; }
err() { echo "[$(date '+%H:%M:%S')] ERROR: $*" | tee -a "$REPORT_FILE"; ERRORS=$((ERRORS + 1)); }

# Header 
{
echo "========== Docker System Backup =========="
echo "Backup started at : $(date)"
echo "Backup directory  : $BACKUP_DIR"
echo "Retention policy  : last $RETENTION_DAYS days"
echo "=========================================="
echo ""
} | tee "$REPORT_FILE"

# Backup all Docker volumes 
log "--- Backing up Docker volumes ---"
VOLUME_COUNT=0

if docker volume ls -q 2>/dev/null | grep -q .; then
    docker volume ls -q | while read -r VOLUME; do
        log "  Volume: $VOLUME"
        if docker run --rm \
            -v "$VOLUME":/source:ro \
            -v "$BACKUP_DIR/volumes":/backup \
            alpine \
            tar czf "/backup/${VOLUME}.tar.gz" -C /source . 2>>"$REPORT_FILE"; then
            log "   Backed up successfully"
        else
            err "    Failed to backup volume: $VOLUME"
        fi
    done
    VOLUME_COUNT=$(docker volume ls -q | wc -l)
else
    log "  No Docker volumes found."
fi
log "  Volumes processed: $VOLUME_COUNT"
echo "" >> "$REPORT_FILE"

# Backup docker-compose files 
log "--- Backing up Docker Compose configurations ---"
COMPOSE_FILES_FOUND=0

for SEARCH_PATH in "${COMPOSE_SEARCH_PATHS[@]}"; do
    if [[ -d "$SEARCH_PATH" ]]; then
        while IFS= read -r -d '' FILE; do
            log "  Config: $FILE"
            COMPOSE_FILES_FOUND=$((COMPOSE_FILES_FOUND + 1))
        done < <(find "$SEARCH_PATH" -maxdepth 4 \( -name "docker-compose*.yml" -o -name "docker-compose*.yaml" \) -print0 2>/dev/null)
    fi
done

if [[ $COMPOSE_FILES_FOUND -gt 0 ]]; then
    TMPLIST=$(mktemp)
    for SEARCH_PATH in "${COMPOSE_SEARCH_PATHS[@]}"; do
        [[ -d "$SEARCH_PATH" ]] && find "$SEARCH_PATH" -maxdepth 4 \
            \( -name "docker-compose*.yml" -o -name "docker-compose*.yaml" \) \
            2>/dev/null >> "$TMPLIST"
    done
    tar czf "$BACKUP_DIR/configs/docker-compose-configs.tar.gz" -T "$TMPLIST" 2>>"$REPORT_FILE" \
        && log " Compose configs archived" \
        || err "  Failed to archive compose configs"
    rm -f "$TMPLIST"
else
    log "  No docker-compose files found in search paths."
fi
log "  Compose files found: $COMPOSE_FILES_FOUND"
echo "" >> "$REPORT_FILE"

# Backup environment files 
log "--- Backing up environment files ---"
ENV_FILES_FOUND=0

for SEARCH_PATH in "${COMPOSE_SEARCH_PATHS[@]}"; do
    if [[ -d "$SEARCH_PATH" ]]; then
        while IFS= read -r -d '' FILE; do
            log "  Env file: $FILE"
            ENV_FILES_FOUND=$((ENV_FILES_FOUND + 1))
        done < <(find "$SEARCH_PATH" -maxdepth 4 -name ".env*" -not -name ".env.example" -print0 2>/dev/null)
    fi
done

if [[ $ENV_FILES_FOUND -gt 0 ]]; then
    TMPLIST=$(mktemp)
    for SEARCH_PATH in "${COMPOSE_SEARCH_PATHS[@]}"; do
        [[ -d "$SEARCH_PATH" ]] && find "$SEARCH_PATH" -maxdepth 4 -name ".env*" -not -name ".env.example" \
            2>/dev/null >> "$TMPLIST"
    done
    tar czf "$BACKUP_DIR/configs/env-files.tar.gz" -T "$TMPLIST" 2>>"$REPORT_FILE" \
        && log " Environment files archived" \
        || err "  Failed to archive env files"
    rm -f "$TMPLIST"
else
    log "  No .env files found."
fi
log "  Environment files found: $ENV_FILES_FOUND"
echo "" >> "$REPORT_FILE"

# Backup Docker images 
log "--- Backing up Docker images ---"
IMAGE_COUNT=0

if docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -v "<none>" | grep -q .; then
    docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>" | while read -r IMAGE; do
        FILENAME=$(echo "$IMAGE" | tr '/:' '_')
        log "  Image: $IMAGE"
        if docker save "$IMAGE" | gzip > "$BACKUP_DIR/images/${FILENAME}.tar.gz" 2>>"$REPORT_FILE"; then
            log "   Saved"
        else
            err "    Failed to save image: $IMAGE"
        fi
    done
    IMAGE_COUNT=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -v "<none>" | wc -l)
else
    log "  No Docker images found."
fi
log "  Images processed: $IMAGE_COUNT"
echo "" >> "$REPORT_FILE"

# Create backup manifest 
log "--- Creating backup manifest ---"
VOLUME_BACKUP_COUNT=$(ls -1 "$BACKUP_DIR/volumes" 2>/dev/null | wc -l)
IMAGE_BACKUP_COUNT=$(ls -1 "$BACKUP_DIR/images" 2>/dev/null | wc -l)
CONFIG_BACKUP_COUNT=$(ls -1 "$BACKUP_DIR/configs" 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)

cat > "$BACKUP_DIR/manifest.txt" << EOF
Docker System Backup Manifest
==============================
Date           : $(date)
Hostname       : $(hostname)
Docker Version : $(docker --version 2>/dev/null || echo "N/A")
Backup Dir     : $BACKUP_DIR

Volumes backed up        : $VOLUME_BACKUP_COUNT
Images backed up         : $IMAGE_BACKUP_COUNT
Config archives created  : $CONFIG_BACKUP_COUNT
Errors encountered       : $ERRORS

Total backup size        : $TOTAL_SIZE
EOF

log " Manifest written to $BACKUP_DIR/manifest.txt"
echo "" >> "$REPORT_FILE"

# Backup rotation keep last N days 
log "--- Cleaning up old backups (older than $RETENTION_DAYS days) ---"
OLD_BACKUPS=$(find "$BACKUP_ROOT" -maxdepth 1 -type d -mtime +$RETENTION_DAYS -not -path "$BACKUP_ROOT" 2>/dev/null | wc -l)
if [[ $OLD_BACKUPS -gt 0 ]]; then
    find "$BACKUP_ROOT" -maxdepth 1 -type d -mtime +$RETENTION_DAYS -not -path "$BACKUP_ROOT" -exec rm -rf {} \;
    log "  Removed $OLD_BACKUPS old backup(s)"
else
    log "  No backups older than $RETENTION_DAYS days found."
fi
echo "" >> "$REPORT_FILE"

log "--- Restore verification (dry-run) ---"
MANIFEST_OK="FAIL"
VOLUMES_OK="FAIL"
IMAGES_OK="FAIL"
CONFIGS_OK="FAIL"

[[ -f "$BACKUP_DIR/manifest.txt" ]] && MANIFEST_OK="PASS"
[[ -d "$BACKUP_DIR/volumes" ]]      && VOLUMES_OK="PASS"
[[ -d "$BACKUP_DIR/images" ]]       && IMAGES_OK="PASS"
[[ -d "$BACKUP_DIR/configs" ]]      && CONFIGS_OK="PASS"

log "  Manifest exists      : $MANIFEST_OK"
log "  Volumes dir exists   : $VOLUMES_OK"
log "  Images dir exists    : $IMAGES_OK"
log "  Configs dir exists   : $CONFIGS_OK"

# Verify at least one archive per non-empty category is readable
for ARCHIVE in "$BACKUP_DIR"/volumes/*.tar.gz "$BACKUP_DIR"/images/*.tar.gz "$BACKUP_DIR"/configs/*.tar.gz; do
    if [[ -f "$ARCHIVE" ]]; then
        if gzip -t "$ARCHIVE" 2>/dev/null; then
            log " Archive integrity OK: $(basename "$ARCHIVE")"
        else
            err "  Archive corrupted: $(basename "$ARCHIVE")"
        fi
    fi
done
echo "" >> "$REPORT_FILE"

# Summary 
{
echo "=========================================="
echo "Backup completed at : $(date)"
echo "Total size          : $TOTAL_SIZE"
echo "Errors              : $ERRORS"
echo "Report file         : $REPORT_FILE"
echo "=========================================="
} | tee -a "$REPORT_FILE"

exit $ERRORS
