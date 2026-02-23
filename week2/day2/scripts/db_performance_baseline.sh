#!/bin/bash
set -euo pipefail

# Script: db_performance_baseline.sh
# Description: Runs INSERT/SELECT/UPDATE benchmarks on PostgreSQL, MySQL, and MongoDB
# Author: Aakash
# Date: 2026-02-22
# Usage: ./db_performance_baseline.sh [-h|--help] [-v|--verbose] [-n|--iterations N]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${PARENT_DIR}/var/log/apps/db_performance_baseline.log"
REPORT_FILE="${PARENT_DIR}/var/log/apps/db_performance_baseline.txt"
ITERATIONS=1000
VERBOSE=false
CONNECT_TIMEOUT=5

# DB credentials
PG_USER="${PG_USER:-dbadmin}"
PG_PASS="${PG_PASS:-password123}"
PG_DB="${PG_DB:-testdb}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASS="${MYSQL_PASS:-RootPass@2026!}"
MYSQL_DB="${MYSQL_DB:-appdb}"
MONGO_USER="${MONGO_USER:-mongoadmin}"
MONGO_PASS="${MONGO_PASS:-AdminPass@2026!}"
MONGO_DB="${MONGO_DB:-appdb}"

# Logging
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }
log_debug() { $VERBOSE && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" | tee -a "$LOG_FILE"; }

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Runs performance baseline tests on PostgreSQL, MySQL, and MongoDB.

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -n, --iterations N      Number of operations per test (default: 1000)

Examples:
    $(basename "$0")
    $(basename "$0") --iterations 500
    $(basename "$0") --verbose
EOF
}

# Timing helpers 

elapsed_ms() {
    local start="$1" end="$2"
    echo "scale=3; ($end - $start) * 1000" | bc
}

calc_qps() {
    local count="$1" elapsed_s="$2"
    echo "scale=0; $count / $elapsed_s" | bc 2>/dev/null || echo "N/A"
}

avg_ms() {
    local total_ms="$1" count="$2"
    echo "scale=2; $total_ms / $count" | bc
}

# PostgreSQL Benchmark 

benchmark_postgresql() {
    log_info "Running PostgreSQL benchmark ($ITERATIONS iterations)"

    PGPASSWORD="$PG_PASS" timeout $CONNECT_TIMEOUT psql -U "$PG_USER" -h 127.0.0.1 "$PG_DB" -q << 'SETUP'
DROP TABLE IF EXISTS bench_test;
CREATE TABLE bench_test (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    value DOUBLE PRECISION,
    created_at TIMESTAMP DEFAULT NOW()
);
SETUP

    # INSERT
    local t_start t_end elapsed_s
    t_start=$(date +%s%3N)
    PGPASSWORD="$PG_PASS" timeout $CONNECT_TIMEOUT psql -U "$PG_USER" -h 127.0.0.1 "$PG_DB" -q \
        -c "INSERT INTO bench_test (name, value) SELECT 'bench_' || generate_series(1, ${ITERATIONS}), random() * 1000"
    t_end=$(date +%s%3N)
    local insert_ms=$(( t_end - t_start ))
    local insert_s
    insert_s=$(echo "scale=3; $insert_ms / 1000" | bc)
    local insert_qps
    insert_qps=$(echo "scale=0; $ITERATIONS * 1000 / $insert_ms" | bc)
    log_debug "PG INSERT: ${insert_ms}ms"

    # SELECT
    t_start=$(date +%s%3N)
    PGPASSWORD="$PG_PASS" timeout $CONNECT_TIMEOUT psql -U "$PG_USER" -h 127.0.0.1 "$PG_DB" -q \
        -c "SELECT * FROM bench_test LIMIT ${ITERATIONS}" > /dev/null
    t_end=$(date +%s%3N)
    local select_ms=$(( t_end - t_start ))
    local select_s
    select_s=$(echo "scale=3; $select_ms / 1000" | bc)
    local select_qps
    select_qps=$(echo "scale=0; $ITERATIONS * 1000 / $select_ms" | bc)
    log_debug "PG SELECT: ${select_ms}ms"

    # UPDATE
    t_start=$(date +%s%3N)
    PGPASSWORD="$PG_PASS" timeout $CONNECT_TIMEOUT psql -U "$PG_USER" -h 127.0.0.1 "$PG_DB" -q \
        -c "UPDATE bench_test SET value = value * 1.1 WHERE id <= ${ITERATIONS}"
    t_end=$(date +%s%3N)
    local update_ms=$(( t_end - t_start ))
    local update_s
    update_s=$(echo "scale=3; $update_ms / 1000" | bc)
    local update_qps
    update_qps=$(echo "scale=0; $ITERATIONS * 1000 / $update_ms" | bc)
    log_debug "PG UPDATE: ${update_ms}ms"

    local avg_ms
    avg_ms=$(echo "scale=2; ($insert_ms + $select_ms + $update_ms) / (3 * $ITERATIONS)" | bc)

    # Cleanup
    PGPASSWORD="$PG_PASS" timeout $CONNECT_TIMEOUT psql -U "$PG_USER" -h 127.0.0.1 "$PG_DB" -q \
        -c "DROP TABLE IF EXISTS bench_test"

    PG_RESULT="PostgreSQL (${PG_DB}):
  INSERT: ${ITERATIONS} queries in ${insert_s}s (${insert_qps} qps)
  SELECT: ${ITERATIONS} queries in ${select_s}s (${select_qps} qps)
  UPDATE: ${ITERATIONS} queries in ${update_s}s (${update_qps} qps)
  Avg query time: ${avg_ms}ms"
}

# MySQL Benchmark 

benchmark_mysql() {
    log_info "Running MySQL benchmark ($ITERATIONS iterations)"

    mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -h localhost "$MYSQL_DB" -e \
        "DROP TABLE IF EXISTS bench_test;
         CREATE TABLE bench_test (
             id INT AUTO_INCREMENT PRIMARY KEY,
             name VARCHAR(100),
             value DOUBLE,
             created_at TIMESTAMP DEFAULT NOW()
         ) ENGINE=InnoDB;" 2>/dev/null

    # Build bulk INSERT
    local sql="INSERT INTO bench_test (name, value) VALUES "
    local vals=()
    for (( i=1; i<=ITERATIONS; i++ )); do
        vals+=("('bench_${i}', $(awk 'BEGIN{srand(); printf "%.4f\n", rand()*1000}')")
    done
    sql+=$(IFS=','; echo "${vals[*]}")

    local t_start t_end
    t_start=$(date +%s%3N)
    timeout $CONNECT_TIMEOUT mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -h localhost "$MYSQL_DB" -e "$sql" 2>/dev/null
    t_end=$(date +%s%3N)
    local insert_ms=$(( t_end - t_start ))
    local insert_s insert_qps
    insert_s=$(echo "scale=3; $insert_ms / 1000" | bc)
    insert_qps=$(echo "scale=0; $ITERATIONS * 1000 / $insert_ms" | bc)

    # SELECT
    t_start=$(date +%s%3N)
    timeout $CONNECT_TIMEOUT mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -h localhost "$MYSQL_DB" \
        -e "SELECT * FROM bench_test LIMIT ${ITERATIONS}" > /dev/null 2>&1
    t_end=$(date +%s%3N)
    local select_ms=$(( t_end - t_start ))
    local select_s select_qps
    select_s=$(echo "scale=3; $select_ms / 1000" | bc)
    select_qps=$(echo "scale=0; $ITERATIONS * 1000 / $select_ms" | bc)

    # UPDATE
    t_start=$(date +%s%3N)
    timeout $CONNECT_TIMEOUT mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -h localhost "$MYSQL_DB" \
        -e "UPDATE bench_test SET value = value * 1.1 WHERE id <= ${ITERATIONS}" 2>/dev/null
    t_end=$(date +%s%3N)
    local update_ms=$(( t_end - t_start ))
    local update_s update_qps
    update_s=$(echo "scale=3; $update_ms / 1000" | bc)
    update_qps=$(echo "scale=0; $ITERATIONS * 1000 / $update_ms" | bc)

    local avg_ms
    avg_ms=$(echo "scale=2; ($insert_ms + $select_ms + $update_ms) / (3 * $ITERATIONS)" | bc)

    # Cleanup
    mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -h localhost "$MYSQL_DB" \
        -e "DROP TABLE IF EXISTS bench_test" 2>/dev/null

    MYSQL_RESULT="MySQL (${MYSQL_DB}):
  INSERT: ${ITERATIONS} queries in ${insert_s}s (${insert_qps} qps)
  SELECT: ${ITERATIONS} queries in ${select_s}s (${select_qps} qps)
  UPDATE: ${ITERATIONS} queries in ${update_s}s (${update_qps} qps)
  Avg query time: ${avg_ms}ms"
}

#  MongoDB Benchmark 

benchmark_mongodb() {
    log_info "Running MongoDB benchmark ($ITERATIONS iterations)"

    local mongosh_auth="mongosh --quiet -u '$MONGO_USER' -p '$MONGO_PASS' --authenticationDatabase admin $MONGO_DB"

    # INSERT
    local t_start t_end
    t_start=$(date +%s%3N)
    timeout $CONNECT_TIMEOUT $mongosh_auth --eval "
        db.bench_test.drop();
        var docs = [];
        for (var i=0; i<${ITERATIONS}; i++) {
            docs.push({ name: 'bench_' + i, value: Math.random() * 1000, created_at: new Date() });
        }
        db.bench_test.insertMany(docs);
    " > /dev/null 2>&1
    t_end=$(date +%s%3N)
    local insert_ms=$(( t_end - t_start ))
    local insert_s insert_qps
    insert_s=$(echo "scale=3; $insert_ms / 1000" | bc)
    insert_qps=$(echo "scale=0; $ITERATIONS * 1000 / $insert_ms" | bc)

    # FIND
    t_start=$(date +%s%3N)
    timeout $CONNECT_TIMEOUT $mongosh_auth --eval "
        db.bench_test.find({}).limit(${ITERATIONS}).toArray();
    " > /dev/null 2>&1
    t_end=$(date +%s%3N)
    local find_ms=$(( t_end - t_start ))
    local find_s find_qps
    find_s=$(echo "scale=3; $find_ms / 1000" | bc)
    find_qps=$(echo "scale=0; $ITERATIONS * 1000 / $find_ms" | bc)

    # UPDATE
    t_start=$(date +%s%3N)
    timeout $CONNECT_TIMEOUT $mongosh_auth --eval "
        db.bench_test.updateMany({}, { \$mul: { value: 1.1 } });
    " > /dev/null 2>&1
    t_end=$(date +%s%3N)
    local update_ms=$(( t_end - t_start ))
    local update_s update_qps
    update_s=$(echo "scale=3; $update_ms / 1000" | bc)
    update_qps=$(echo "scale=0; $ITERATIONS * 1000 / $update_ms" | bc)

    local avg_ms
    avg_ms=$(echo "scale=2; ($insert_ms + $find_ms + $update_ms) / (3 * $ITERATIONS)" | bc)

    # Cleanup
    timeout $CONNECT_TIMEOUT $mongosh_auth --eval "db.bench_test.drop();" > /dev/null 2>&1

    MONGO_RESULT="MongoDB (${MONGO_DB}):
  insert: ${ITERATIONS} docs in ${insert_s}s (${insert_qps} ops/s)
  find:   ${ITERATIONS} docs in ${find_s}s (${find_qps} ops/s)
  update: ${ITERATIONS} docs in ${update_s}s (${update_qps} ops/s)
  Avg operation time: ${avg_ms}ms"
}

#  Report 

generate_report() {
    {
        echo "DATABASE PERFORMANCE BASELINE"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Iterations: $ITERATIONS per operation"
        echo "========================================"
        echo ""
        echo "$PG_RESULT"
        echo ""
        echo "$MYSQL_RESULT"
        echo ""
        echo "$MONGO_RESULT"
        echo ""
        echo "========================================"
    } | tee "$REPORT_FILE" | tee -a "$LOG_FILE"

    log_info "Report saved to $REPORT_FILE"
}

PG_RESULT=""
MYSQL_RESULT=""
MONGO_RESULT=""

main() {
    mkdir -p "${PARENT_DIR}/var/log/apps"
    log_info "Script started"

    benchmark_postgresql 2>/dev/null || { PG_RESULT="PostgreSQL: FAILED (check connection)"; log_error "PostgreSQL benchmark failed"; }
    benchmark_mysql      2>/dev/null || { MYSQL_RESULT="MySQL: FAILED (check connection)";   log_error "MySQL benchmark failed"; }
    benchmark_mongodb    2>/dev/null || { MONGO_RESULT="MongoDB: FAILED (check connection)"; log_error "MongoDB benchmark failed"; }

    generate_report
    log_info "Script completed successfully"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)       show_usage; exit $EXIT_SUCCESS ;;
        -v|--verbose)    VERBOSE=true ;;
        -n|--iterations) shift; ITERATIONS="${1:-1000}" ;;
        *) log_error "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main
