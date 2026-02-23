#!/bin/bash
set -euo pipefail

# Script: db_health_monitor.sh
# Description: Health monitoring for PostgreSQL, MySQL, and MongoDB with threshold alerts
# Author: Aakash
# Date: 2026-02-22
# Usage: ./db_health_monitor.sh [-h|--help] [-v|--verbose]
# Cron:  */5 * * * * /path/to/db_health_monitor.sh

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${PARENT_DIR}/var/log/apps/db_health_monitor.log"
REPORT_DIR="${PARENT_DIR}/var/log/apps"
CONNECT_TIMEOUT=5       # Connection timeout in seconds
REPORT_FILE="${REPORT_DIR}/db_health_$(date '+%Y-%m-%d').log"
VERBOSE=false

# DB credentials
PG_USER="${PG_USER:-dbadmin}"
PG_PASS="${PG_PASS:-password123}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASS="${MYSQL_PASS:-RootPass@2026!}"
MONGO_USER="${MONGO_USER:-mongoadmin}"
MONGO_PASS="${MONGO_PASS:-AdminPass@2026!}"

# Thresholds
CONN_THRESHOLD_PCT=80          # Alert if connections > 80% of max
DISK_THRESHOLD_PCT=85          # Alert if disk usage > 85%
SLOW_QUERY_THRESHOLD=100       # Alert if slow queries > 100/hour
LONG_QUERY_SECONDS=30          # Alert if query running > 30s
REPLICATION_LAG_MB=50          # Alert if replication lag > 50 MB

# Logging
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }
log_debug() { $VERBOSE && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" | tee -a "$LOG_FILE"; }

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Checks health of PostgreSQL, MySQL, and MongoDB. Run every 5 minutes via cron.

OPTIONS:
    -h, --help      Show this help message
    -v, --verbose   Enable verbose output

Examples:
    $(basename "$0")
    $(basename "$0") --verbose
EOF
}

# Report helpers 

REPORT=""
ALERTS=""

report() {
    REPORT="${REPORT}$1\n"
    echo "$1" | tee -a "$REPORT_FILE" | tee -a "$LOG_FILE" > /dev/null
}

alert() {
    ALERTS="${ALERTS}  ⚠  ALERT: $1\n"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ALERT] $1" | tee -a "$REPORT_FILE" | tee -a "$LOG_FILE"
}

ok()   { report "   $1"; }
warn() { report "   $1"; }
fail() { report "   $1"; }

#  Disk check 

check_disk() {
    local path="$1" label="$2"
    local usage
    usage=$(df -P "$path" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
    if [[ -n "$usage" ]]; then
        if (( usage > DISK_THRESHOLD_PCT )); then
            alert "Disk usage on $label is ${usage}% (threshold: ${DISK_THRESHOLD_PCT}%)"
            warn "Disk $label: ${usage}% used"
        else
            ok "Disk $label: ${usage}% used"
        fi
    fi
}

#  PostgreSQL Health 

check_postgresql() {
    report ""
    report "PostgreSQL:"
    report "  ─────────────────────────────────────────"

    # Service status
    if systemctl is-active --quiet postgresql; then
        ok "Service: running"
    else
        fail "Service: DOWN"
        alert "PostgreSQL service is not running"
        return
    fi

    # Connection test
    if timeout $CONNECT_TIMEOUT bash -c "PGPASSWORD='$PG_PASS' psql -U '$PG_USER' -h 127.0.0.1 -At -c 'SELECT 1' postgres >/dev/null 2>&1"; then
        ok "Connection: successful"
    else
        fail "Connection: FAILED"
        alert "PostgreSQL connection test failed"
        return
    fi

    # Active connections vs max
    local active max pct
    active=$(PGPASSWORD="$PG_PASS" psql -U "$PG_USER" -h 127.0.0.1 -At \
        -c "SELECT count(*) FROM pg_stat_activity WHERE state='active'" postgres 2>/dev/null)
    max=$(PGPASSWORD="$PG_PASS" psql -U "$PG_USER" -h 127.0.0.1 -At \
        -c "SHOW max_connections" postgres 2>/dev/null)
    pct=$(( active * 100 / max ))
    if (( pct > CONN_THRESHOLD_PCT )); then
        alert "PostgreSQL connections: ${active}/${max} (${pct}%)"
        warn "Connections: ${active}/${max} (${pct}%)"
    else
        ok "Connections: ${active}/${max} (${pct}%)"
    fi

    # Database sizes
    report "  Database sizes:"
    PGPASSWORD="$PG_PASS" psql -U "$PG_USER" -h 127.0.0.1 -At \
        -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database WHERE datistemplate=false ORDER BY pg_database_size(datname) DESC" \
        postgres 2>/dev/null | while IFS='|' read -r db size; do
            report "    $db: $size"
        done

    # Long-running queries
    local long_queries
    long_queries=$(PGPASSWORD="$PG_PASS" psql -U "$PG_USER" -h 127.0.0.1 -At \
        -c "SELECT count(*) FROM pg_stat_activity WHERE state='active' AND query_start < NOW() - INTERVAL '${LONG_QUERY_SECONDS} seconds' AND query NOT LIKE '%pg_stat_activity%'" \
        postgres 2>/dev/null)
    if (( long_queries > 0 )); then
        alert "PostgreSQL: $long_queries queries running > ${LONG_QUERY_SECONDS}s"
        warn "Long-running queries: $long_queries"
    else
        ok "Long-running queries: none"
    fi

    # Replication lag
    local repl_lag
    repl_lag=$(PGPASSWORD="$PG_PASS" psql -U "$PG_USER" -h 127.0.0.1 -At \
        -c "SELECT COALESCE(pg_wal_lsn_diff(sent_lsn, replay_lsn)/1024/1024, 0) FROM pg_stat_replication LIMIT 1" \
        postgres 2>/dev/null || echo "0")
    if [[ -z "$repl_lag" ]]; then repl_lag=0; fi
    ok "Replication lag: ${repl_lag:-0} MB (or standalone)"

    check_disk "/var/lib/postgresql" "PostgreSQL data"
}

#  MySQL Health 

check_mysql() {
    report ""
    report "MySQL:"
    report "  ─────────────────────────────────────────"

    # Service status
    if systemctl is-active --quiet mysql; then
        ok "Service: running"
    else
        fail "Service: DOWN"
        alert "MySQL service is not running"
        return
    fi

    # Connection test
    if timeout $CONNECT_TIMEOUT bash -c "mysql -u '$MYSQL_USER' -p'$MYSQL_PASS' -h localhost -e 'SELECT 1' >/dev/null 2>&1"; then
        ok "Connection: successful"
    else
        fail "Connection: FAILED"
        alert "MySQL connection test failed (try localhost instead of 127.0.0.1)"
        return
    fi

    # Thread connections
    local threads max_conn pct
    threads=$(timeout $CONNECT_TIMEOUT mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -h localhost \
        -e "SHOW STATUS LIKE 'Threads_connected';" --skip-column-names 2>/dev/null | awk '{print $2}')
    max_conn=$(timeout $CONNECT_TIMEOUT mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -h localhost \
        -e "SHOW VARIABLES LIKE 'max_connections';" --skip-column-names 2>/dev/null | awk '{print $2}')
    pct=$(( threads * 100 / max_conn ))
    if (( pct > CONN_THRESHOLD_PCT )); then
        alert "MySQL connections: ${threads}/${max_conn} (${pct}%)"
        warn "Connections: ${threads}/${max_conn} (${pct}%)"
    else
        ok "Connections: ${threads}/${max_conn} (${pct}%)"
    fi

    # InnoDB buffer pool usage
    local pool_total pool_free pool_used pool_pct
    pool_total=$(timeout $CONNECT_TIMEOUT mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -h localhost \
        -e "SHOW STATUS LIKE 'Innodb_buffer_pool_pages_total';" --skip-column-names 2>/dev/null | awk '{print $2}')
    pool_free=$(timeout $CONNECT_TIMEOUT mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -h localhost \
        -e "SHOW STATUS LIKE 'Innodb_buffer_pool_pages_free';" --skip-column-names 2>/dev/null | awk '{print $2}')
    if [[ -n "$pool_total" && "$pool_total" -gt 0 ]]; then
        pool_used=$(( pool_total - pool_free ))
        pool_pct=$(( pool_used * 100 / pool_total ))
        ok "InnoDB buffer pool: ${pool_pct}% used"
    fi

    # Slow queries
    local slow_q
    slow_q=$(timeout $CONNECT_TIMEOUT mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -h localhost \
        -e "SHOW STATUS LIKE 'Slow_queries';" --skip-column-names 2>/dev/null | awk '{print $2}')
    if (( slow_q > SLOW_QUERY_THRESHOLD )); then
        alert "MySQL slow queries: $slow_q (threshold: $SLOW_QUERY_THRESHOLD)"
        warn "Slow queries (cumulative): $slow_q"
    else
        ok "Slow queries (cumulative): $slow_q"
    fi

    # Database sizes
    report "  Database sizes:"
    timeout $CONNECT_TIMEOUT mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -h localhost \
        -e "SELECT table_schema, ROUND(SUM(data_length+index_length)/1024/1024,1) AS 'MB' FROM information_schema.tables WHERE table_schema NOT IN ('information_schema','performance_schema','mysql','sys') GROUP BY table_schema;" \
        --skip-column-names 2>/dev/null | while read -r db size; do
            report "    $db: ${size} MB"
        done

    check_disk "/var/lib/mysql" "MySQL data"
}

# MongoDB Health 

check_mongodb() {
    report ""
    report "MongoDB:"
    report "  ─────────────────────────────────────────"

    local mongosh_auth="mongosh --quiet -u \"$MONGO_USER\" -p \"$MONGO_PASS\" --authenticationDatabase admin"

    # Service status
    if systemctl is-active --quiet mongod; then
        ok "Service: running"
    else
        fail "Service: DOWN"
        alert "MongoDB service is not running"
        return
    fi

    # Connection test
    if timeout $CONNECT_TIMEOUT bash -c "$mongosh_auth --eval 'db.runCommand({ping:1})' >/dev/null 2>&1"; then
        ok "Connection: successful"
    else
        fail "Connection: FAILED"
        alert "MongoDB connection test failed"
        return
    fi

    # Replica set status
    local rs_status
    rs_status=$(timeout $CONNECT_TIMEOUT bash -c "$mongosh_auth --eval \"
        try { rs.status().ok } catch(e) { 'standalone' }\" 2>/dev/null" | tail -1)
    ok "Replica set: ${rs_status}"

    # Database sizes
    report "  Database sizes:"
    $mongosh_auth --eval "
        db.adminCommand({listDatabases:1}).databases.forEach(d => {
            print('    ' + d.name + ': ' + (d.sizeOnDisk/1024/1024).toFixed(1) + ' MB');
        });
    " 2>/dev/null | grep -v "^$" || true

    # Index usage
    local index_count
    index_count=$($mongosh_auth --eval "
        var total = 0;
        db.adminCommand({listDatabases:1}).databases.forEach(d => {
            var dbc = db.getSiblingDB(d.name);
            dbc.getCollectionNames().forEach(c => {
                total += dbc[c].getIndexes().length;
            });
        });
        print(total);
    " 2>/dev/null | tail -1)
    ok "Total indexes: ${index_count:-unknown}"

    check_disk "/var/lib/mongodb" "MongoDB data"
}

#  Summary 

print_summary() {
    {
        echo ""
        echo "========================================"
        echo "Health check completed: $(date '+%Y-%m-%d %H:%M:%S')"
        if [[ -n "$ALERTS" ]]; then
            echo ""
            echo "ALERTS:"
            echo -e "$ALERTS"
        else
            echo "  All systems healthy — no alerts"
        fi
        echo "========================================"
    } | tee -a "$REPORT_FILE"
}

main() {
    mkdir -p var/log/apps
    log_info "Script started"

    {
        echo ""
        echo "DB HEALTH REPORT — $(date '+%Y-%m-%d %H:%M:%S')"
        echo "========================================"
    } | tee -a "$REPORT_FILE"

    check_postgresql 2>/dev/null || { fail "PostgreSQL check failed"; alert "PostgreSQL health check encountered an error"; }
    check_mysql      2>/dev/null || { fail "MySQL check failed";      alert "MySQL health check encountered an error"; }
    check_mongodb    2>/dev/null || { fail "MongoDB check failed";    alert "MongoDB health check encountered an error"; }

    print_summary
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
