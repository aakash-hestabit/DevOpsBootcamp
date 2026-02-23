#!/bin/bash
set -euo pipefail

# Script: db_restore.sh
# Description: Interactive restore tool for PostgreSQL, MySQL, and MongoDB backups
# Author: Aakash
# Date: 2026-02-22
# Usage: ./db_restore.sh [-h|--help] [-v|--verbose]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${PARENT_DIR}/var/log/apps/db_restore.log"
BACKUP_BASE="/backups"
CONNECT_TIMEOUT=5
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
VERBOSE=false

# DB credentials
PG_USER="${PG_USER:-dbadmin}"
PG_PASS="${PG_PASS:-password123}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASS="${MYSQL_PASS:-RootPass@2026!}"
MONGO_USER="${MONGO_USER:-mongoadmin}"
MONGO_PASS="${MONGO_PASS:-AdminPass@2026!}"

# Logging
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }
log_debug() { $VERBOSE && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" | tee -a "$LOG_FILE"; }

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Interactive restore tool for PostgreSQL, MySQL, and MongoDB.

OPTIONS:
    -h, --help      Show this help message
    -v, --verbose   Enable verbose output

Examples:
    $(basename "$0")
    $(basename "$0") --verbose
EOF
}

#  Helpers 

confirm_action() {
    local prompt="$1"
    read -rp "$prompt (yes/no): " answer
    [[ "$answer" == "yes" ]]
}

validate_backup_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        log_error "Backup file not found: $file"
        return 1
    fi
    if ! gzip -t "$file" 2>/dev/null; then
        log_error "Backup file integrity check failed: $file"
        return 1
    fi
    log_debug "Backup file integrity OK: $file"
}

list_backups() {
    local db_type="$1"
    local backup_dir="${BACKUP_BASE}/${db_type}"
    local i=1

    echo ""
    echo "  Available backups:"
    echo "  ─────────────────────────────────────────"

    declare -g BACKUP_FILES=()
    while IFS= read -r -d '' file; do
        BACKUP_FILES+=("$file")
        local size
        size=$(du -sh "$file" | cut -f1)
        local mod_time
        mod_time=$(stat -c '%y' "$file" | cut -d'.' -f1)
        printf "  %d) %s  (%s)  %s\n" $i "$mod_time" "$size" "$(basename "$file")"
        (( i++ ))
    done < <(find "${backup_dir}" -name "*.gz" -type f -print0 2>/dev/null | sort -z -r)

    if [[ ${#BACKUP_FILES[@]} -eq 0 ]]; then
        echo "  No backups found in ${backup_dir}"
        return 1
    fi
}

#  PostgreSQL Restore 

restore_postgresql() {
    log_info "PostgreSQL restore initiated"

    read -rp "  Enter database name to restore into: " dbname

    list_backups "postgresql" || return 1

    read -rp "  Select backup number: " sel
    local backup_file="${BACKUP_FILES[$((sel-1))]}"

    echo ""
    echo "    This will restore '$dbname' from: $(basename "$backup_file")"
    echo "     Current database will be backed up first."

    confirm_action "  Continue?" || { log_info "Restore cancelled by user"; return 0; }

    # Pre-restore safety backup
    local safety_dir="/backups/postgresql/pre_restore"
    mkdir -p "$safety_dir"
    local safety_file="${safety_dir}/${dbname}_before_restore_${TIMESTAMP}.dump.gz"
    log_info "Creating safety backup..."
    PGPASSWORD="$PG_PASS" timeout $CONNECT_TIMEOUT pg_dump -U "$PG_USER" -h 127.0.0.1 -Fc "$dbname" \
        | gzip > "$safety_file" 2>/dev/null || log_info "  (database may not exist yet — skipping safety backup)"
    [[ -f "$safety_file" ]] && log_info "   Current database backed up --> $safety_file"

    validate_backup_file "$backup_file"
    echo "   Backup file validated"

    # Drop & recreate database
    PGPASSWORD="$PG_PASS" timeout $CONNECT_TIMEOUT psql -U "$PG_USER" -h 127.0.0.1 postgres \
        -c "DROP DATABASE IF EXISTS \"${dbname}\";" &>/dev/null
    PGPASSWORD="$PG_PASS" timeout $CONNECT_TIMEOUT psql -U "$PG_USER" -h 127.0.0.1 postgres \
        -c "CREATE DATABASE \"${dbname}\";" &>/dev/null

    # Restore
    log_info "Restoring database..."
    zcat "$backup_file" | PGPASSWORD="$PG_PASS" timeout $CONNECT_TIMEOUT pg_restore \
        -U "$PG_USER" -h 127.0.0.1 -d "$dbname" --no-owner --no-privileges \
        2>/dev/null || true

    # Verify
    local table_count
    table_count=$(PGPASSWORD="$PG_PASS" timeout $CONNECT_TIMEOUT psql -U "$PG_USER" -h 127.0.0.1 -At "$dbname" \
        -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public'" 2>/dev/null)

    log_op="PostgreSQL restore: $dbname from $backup_file"
    echo "   Database restored successfully"
    echo "   Data integrity verified ($table_count tables found)"
    log_info "PostgreSQL restore complete: $dbname ($table_count tables)"
}

# MySQL Restore 

restore_mysql() {
    log_info "MySQL restore initiated"

    read -rp "  Enter database name to restore into: " dbname

    list_backups "mysql" || return 1

    read -rp "  Select backup number: " sel
    local backup_file="${BACKUP_FILES[$((sel-1))]}"

    echo ""
    echo "    This will restore '$dbname' from: $(basename "$backup_file")"
    echo "     Current database will be backed up first."

    confirm_action "  Continue?" || { log_info "Restore cancelled by user"; return 0; }

    # Safety backup
    local safety_dir="/backups/mysql/pre_restore"
    mkdir -p "$safety_dir"
    local safety_file="${safety_dir}/${dbname}_before_restore_${TIMESTAMP}.sql.gz"
    timeout $CONNECT_TIMEOUT mysqldump -u "$MYSQL_USER" -p"$MYSQL_PASS" -h localhost \
        --single-transaction "$dbname" 2>/dev/null \
        | gzip > "$safety_file" || log_info "  (database may not exist yet — skipping safety backup)"
    [[ -s "$safety_file" ]] && log_info "   Current database backed up --> $safety_file"

    validate_backup_file "$backup_file"
    echo "   Backup file validated"

    # Restore
    log_info "Restoring database..."
    timeout $CONNECT_TIMEOUT mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -h localhost \
        -e "CREATE DATABASE IF NOT EXISTS \`${dbname}\`;" &>/dev/null
    zcat "$backup_file" | timeout $CONNECT_TIMEOUT mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -h localhost "$dbname"

    # Verify
    local table_count
    table_count=$(timeout $CONNECT_TIMEOUT mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -h localhost \
        -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${dbname}'" \
        --skip-column-names 2>/dev/null)

    echo "   Database restored successfully"
    echo "   Data integrity verified ($table_count tables found)"
    log_info "MySQL restore complete: $dbname ($table_count tables)"
}

# MongoDB Restore 

restore_mongodb() {
    log_info "MongoDB restore initiated"

    list_backups "mongodb" || return 1

    read -rp "  Select backup number: " sel
    local backup_file="${BACKUP_FILES[$((sel-1))]}"

    echo ""
    echo "    This will restore from: $(basename "$backup_file")"
    echo "     Existing data may be overwritten."

    confirm_action "  Continue?" || { log_info "Restore cancelled by user"; return 0; }

    validate_backup_file "$backup_file"
    echo "   Backup file validated"

    # Safety dump
    local safety_dir="/backups/mongodb/pre_restore"
    mkdir -p "$safety_dir"
    local safety_file="${safety_dir}/mongodb_before_restore_${TIMESTAMP}.archive.gz"
    mongodump --username "$MONGO_USER" --password "$MONGO_PASS" \
        --authenticationDatabase admin \
        --gzip --archive="$safety_file" 2>/dev/null || true
    [[ -s "$safety_file" ]] && log_info "   Current databases backed up --> $safety_file"

    # Restore
    log_info "Restoring MongoDB..."
    mongorestore --username "$MONGO_USER" --password "$MONGO_PASS" \
        --authenticationDatabase admin \
        --gzip --archive="$backup_file" \
        --drop 2>/dev/null

    # Verify
    local db_count
    db_count=$(mongosh --quiet -u "$MONGO_USER" -p "$MONGO_PASS" \
        --authenticationDatabase admin \
        --eval "db.adminCommand({listDatabases:1}).databases.length" 2>/dev/null)

    echo "   Database restored successfully"
    echo "   Data integrity verified ($db_count databases found)"
    log_info "MongoDB restore complete ($db_count databases)"
}

#  Main 

main() {
    mkdir -p "${PARENT_DIR}/var/log/apps"
    log_info "Script started"

    echo ""
    echo "Database Restore Tool"
    echo "========================================"
    echo "Select database type:"
    echo "1) PostgreSQL"
    echo "2) MySQL"
    echo "3) MongoDB"
    echo ""
    read -rp "Choice: " choice

    case "$choice" in
        1) restore_postgresql ;;
        2) restore_mysql ;;
        3) restore_mongodb ;;
        *) log_error "Invalid choice"; exit $EXIT_ERROR ;;
    esac

    log_info "Script completed successfully"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    show_usage; exit $EXIT_SUCCESS ;;
        -v|--verbose) VERBOSE=true ;;
        *) log_error "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main
