#!/bin/bash
set -euo pipefail

# Script: db_backup_automation.sh
# Description: Automated backup for PostgreSQL, MySQL, and MongoDB with rotation strategy
# Author: Aakash
# Date: 2026-02-22
# Usage: ./db_backup_automation.sh [-h|--help] [-v|--verbose] [-t|--type TYPE]
# Cron:  0 2 * * * /path/to/db_backup_automation.sh

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/db_backup_automation.log"
BACKUP_BASE="/backups"
REPORT_DIR="var/log/apps"
DATE="$(date '+%Y-%m-%d')"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
VERBOSE=false
BACKUP_TYPE="all"   # all | postgresql | mysql | mongodb

# DB credentials
PG_USER="${PG_USER:-dbadmin}"
PG_PASS="${PG_PASS:-password123}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASS="${MYSQL_PASS:-RootPass@2026!}"
MONGO_USER="${MONGO_USER:-mongoadmin}"
MONGO_PASS="${MONGO_PASS:-AdminPass@2026!}"

# Retention
DAILY_KEEP=7
WEEKLY_KEEP=4
MONTHLY_KEEP=12

# Logging
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }
log_debug() { $VERBOSE && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" | tee -a "$LOG_FILE" || true; }

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Performs backups for PostgreSQL, MySQL, and MongoDB with rotation.

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -t, --type TYPE         Backup type: all | postgresql | mysql | mongodb (default: all)

Examples:
    $(basename "$0")
    $(basename "$0") --type postgresql
    $(basename "$0") --verbose
EOF
}

#  Helpers 

determine_backup_category() {
    local day_of_week month_day
    day_of_week="$(date '+%u')"   # 1=Mon … 7=Sun
    month_day="$(date '+%d')"

    if [[ "$month_day" == "01" ]]; then
        echo "monthly"
    elif [[ "$day_of_week" == "7" ]]; then
        echo "weekly"
    else
        echo "daily"
    fi
}

make_backup_dir() {
    local db_type="$1" category="$2"
    local dir="${BACKUP_BASE}/${db_type}/${category}/${DATE}"
    mkdir -p "$dir"
    echo "$dir"
}

rotate_backups() {
    local dir="$1" keep="$2"
    # Delete oldest directories beyond retention count
    local count
    count=$(find "$dir" -mindepth 1 -maxdepth 1 -type d | wc -l)
    if (( count > keep )); then
        find "$dir" -mindepth 1 -maxdepth 1 -type d \
            | sort | head -n $(( count - keep )) \
            | xargs rm -rf
        log_debug "Rotated old backups in $dir (kept $keep)"
    fi
}

human_size() {
    du -sh "$1" 2>/dev/null | cut -f1
}

# PostgreSQL Backup 

backup_postgresql() {
    log_info "Starting PostgreSQL backup"
    local category
    category="$(determine_backup_category)"

    local backup_dir
    backup_dir="$(make_backup_dir "postgresql" "$category")"

    local keep=$DAILY_KEEP
    [[ "$category" == "weekly" ]]  && keep=$WEEKLY_KEEP
    [[ "$category" == "monthly" ]] && keep=$MONTHLY_KEEP

    # Get list of databases (exclude system dbs)
    local databases
    databases=$(PGPASSWORD="$PG_PASS" psql -U "$PG_USER" -h 127.0.0.1 -d postgres -At \
        -c "SELECT datname FROM pg_database WHERE datistemplate=false AND datname NOT IN ('postgres','template0','template1')" \
        2>/dev/null)

    for db in $databases; do
        local file="${backup_dir}/${db}_${TIMESTAMP}.dump.gz"
        log_debug "Backing up PostgreSQL database: $db"
        PGPASSWORD="$PG_PASS" pg_dump -U "$PG_USER" -h 127.0.0.1 \
            -Fc "$db" | gzip > "$file"
        log_info "   PostgreSQL/$db --> $file ($(human_size "$file"))"
    done

    rotate_backups "${BACKUP_BASE}/postgresql/${category}" $keep
    log_info "PostgreSQL backup complete [$category]"
}

# MySQL Backup 

backup_mysql() {
    log_info "Starting MySQL backup"
    local category
    category="$(determine_backup_category)"

    local backup_dir
    backup_dir="$(make_backup_dir "mysql" "$category")"

    local keep=$DAILY_KEEP
    [[ "$category" == "weekly" ]]  && keep=$WEEKLY_KEEP
    [[ "$category" == "monthly" ]] && keep=$MONTHLY_KEEP

    # Get list of databases (exclude system dbs)
    local databases
    databases=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" \
        -e "SHOW DATABASES;" 2>/dev/null \
        | grep -Ev "^(Database|information_schema|performance_schema|mysql|sys)$")

    for db in $databases; do
        local file="${backup_dir}/${db}_${TIMESTAMP}.sql.gz"
        log_debug "Backing up MySQL database: $db"
        mysqldump -u "$MYSQL_USER" -p"$MYSQL_PASS" \
            --single-transaction \
            --routines \
            --triggers \
            --events \
            "$db" | gzip > "$file"
        log_info "   MySQL/$db --> $file ($(human_size "$file"))"
    done

    rotate_backups "${BACKUP_BASE}/mysql/${category}" $keep
    log_info "MySQL backup complete [$category]"
}

# MongoDB Backup 

backup_mongodb() {
    log_info "Starting MongoDB backup"
    local category
    category="$(determine_backup_category)"

    local backup_dir
    backup_dir="$(make_backup_dir "mongodb" "$category")"

    local keep=$DAILY_KEEP
    [[ "$category" == "weekly" ]]  && keep=$WEEKLY_KEEP
    [[ "$category" == "monthly" ]] && keep=$MONTHLY_KEEP

    local archive="${backup_dir}/mongodb_${TIMESTAMP}.archive.gz"

    # Try to dump all databases, fallback to appdb only if permission issues
    mongodump \
        --username "$MONGO_USER" \
        --password "$MONGO_PASS" \
        --authenticationDatabase admin \
        --gzip \
        --archive="$archive" \
        2>/dev/null || mongodump \
        --username "$MONGO_USER" \
        --password "$MONGO_PASS" \
        --authenticationDatabase admin \
        --db appdb \
        --gzip \
        --archive="$archive" \
        2>/dev/null || true

    if [[ -f "$archive" ]] && [[ -s "$archive" ]]; then
        log_info "    MongoDB --> $archive ($(human_size "$archive"))"
    else
        log_error "MongoDB backup failed or created empty archive"
    fi

    rotate_backups "${BACKUP_BASE}/mongodb/${category}" $keep
    log_info "MongoDB backup complete [$category]"
}

# Backup Report 

generate_report() {
    local report_file="${REPORT_DIR}/backup_report_${DATE}.txt"
    local category
    category="$(determine_backup_category)"

    {
        echo "BACKUP REPORT"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Category:  $category"
        echo "========================================"
        echo ""

        for db_type in postgresql mysql mongodb; do
            local backup_path="${BACKUP_BASE}/${db_type}/${category}/${DATE}"
            if [[ -d "$backup_path" ]]; then
                local files
                files=$(find "$backup_path" -maxdepth 1 -type f -name "*.gz" 2>/dev/null | sort)
                if [[ -n "$files" ]]; then
                    echo "${db_type^^}:"
                    while IFS= read -r f; do
                        echo "  $(basename "$f")  $(human_size "$f")"
                    done <<< "$files"
                    echo ""
                fi
            fi
        done

        echo "Retention Policy:"
        echo "  Daily:   last ${DAILY_KEEP} days"
        echo "  Weekly:  last ${WEEKLY_KEEP} weeks"
        echo "  Monthly: last ${MONTHLY_KEEP} months"
    } > "$report_file"

    log_info "Backup report: $report_file"
}

main() {
    mkdir -p var/log/apps "${BACKUP_BASE}"/{postgresql,mysql,mongodb}/{daily,weekly,monthly}
    log_info "Script started"
    log_info "========== Backup Automation =========="

    case "$BACKUP_TYPE" in
        all)
            backup_postgresql
            backup_mysql
            backup_mongodb
            ;;
        postgresql) backup_postgresql ;;
        mysql)      backup_mysql ;;
        mongodb)    backup_mongodb ;;
        *)
            log_error "Unknown backup type: $BACKUP_TYPE"
            exit $EXIT_ERROR
            ;;
    esac

    generate_report
    log_info "======================================="
    log_info "Script completed successfully"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    show_usage; exit $EXIT_SUCCESS ;;
        -v|--verbose) VERBOSE=true ;;
        -t|--type)    shift; BACKUP_TYPE="${1:-all}" ;;
        *) log_error "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main
