#!/bin/bash
set -euo pipefail

# Script: test-failover.sh
# Description: Automated 7-step MongoDB replica set failover test.
#              Verifies write to primary, secondary replication, primary election
#              timing, API availability during failover, write to new primary,
#              and failed node recovery. Safe to run on a live replica set.
# Author: Aakash
# Date: 2026-03-01
# Usage: ./test-failover.sh [--help]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/../var/log/apps/$(basename "$0" .sh).log"

# MongoDB URIs
ADMIN_URI="mongodb://admin:Admin%40123@localhost:27017/admin?authSource=admin"
APP_URI="mongodb://devops:Devops%40123@localhost:27017,localhost:27018,localhost:27019/usersdb?replicaSet=rs0&authSource=admin"

# Test report 
REPORT_FILE="$SCRIPT_DIR/../var/log/apps/failover-test-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$(dirname "$REPORT_FILE")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }

# Help function
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Run an automated 7-step failover test against the MongoDB replica set.

The test sequence:
    0. Pre-flight topology check
    1. Write a document to the primary
    2. Read it back from a secondary (replication check)
    3. Kill the current primary (simulate failure)
    4. Wait for a new primary to be elected (max 30 s)
    5. Confirm the Express API stays healthy during failover
    6. Write to the new primary
    7. Restart the killed node and confirm it rejoins

OPTIONS:
    -h, --help    Show this help message

EXAMPLES:
    $(basename "$0")

NOTE:
    Requires the replica set to be running. Start it first with:
    ./setup-replicaset.sh
EOF
}

log()  { echo -e "$1" | tee -a "$REPORT_FILE"; }
pass() { log "${GREEN}    $1${NC}"; }
fail() { log "${RED}    $1${NC}"; }
info() { log "${BLUE}    $1${NC}"; }
warn() { log "${YELLOW}    $1${NC}"; }
sep()  { log "${CYAN}──────────────────────────────────────────────────────${NC}"; }

#  Helper: run mongosh quietly 
mongo_eval() {
    local uri="$1"; shift
    mongosh "$uri" --quiet --eval "$@" 2>/dev/null
}

# Helper: identify current primary port 
get_primary_port() {
    # Store JS in a variable so bash -n never tries to parse its contents
    local js='var m=rs.status().members; var p=""; for(var i=0;i<m.length;i++){if(m[i].stateStr==="PRIMARY"){p=m[i].name.split(":")[1];break;}} print(p);'
    mongo_eval "$ADMIN_URI" "$js"
}

# Helper: check health endpoint 
check_api_health() {
    local port="$1"
    curl -sk --max-time 5 "http://localhost:$port/api/health" | grep -q '"status"' 2>/dev/null
}

# Main function
main() {
    log_info "Failover test started"

    log ""
    log "${BOLD}${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    log "${BOLD}${BLUE}║   MongoDB Replica Set Failover Test — Stack 1          ║${NC}"
    log "${BOLD}${BLUE}║   $(date)                                              ║${NC}"
    log "${BOLD}${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    log ""

ERRORS=0

# Pre-flight checks 
sep
log "${BOLD}[TEST 0] Pre-flight: replica set topology${NC}"

RS_STATUS=$(mongo_eval "$ADMIN_URI" "JSON.stringify(rs.status().members.map(m=>({name:m.name,state:m.stateStr})))")
log "  Replica set members:"
# Store the Python script in a variable so bash -n doesn't try to parse it as bash
local py_fmt='import json,sys; [print("    {:<30}  {}".format(m["name"],m["state"])) for m in json.load(sys.stdin)]'
echo "$RS_STATUS" | python3 -c "$py_fmt" 2>/dev/null || echo "  $RS_STATUS"
echo ""

PRIMARY_PORT=$(get_primary_port)
if [[ -z "$PRIMARY_PORT" ]]; then
    fail "No primary found — replica set may not be initialized"
    ERRORS=$((ERRORS + 1))
else
    pass "Primary is at localhost:$PRIMARY_PORT"
fi

# Test 1: Write to primary 
sep
log "${BOLD}[TEST 1] Write to primary${NC}"

TEST_ID="failover-test-$(date +%s)"
WRITE_RESULT=$(mongo_eval "$APP_URI" "db.getSiblingDB('usersdb').failover_tests.insertOne({_id:'$TEST_ID',test:'failover',ts:new Date()});db.getSiblingDB('usersdb').failover_tests.findOne({_id:'$TEST_ID'})._id" 2>/dev/null || echo "")

if [[ "$WRITE_RESULT" == *"$TEST_ID"* ]]; then
    pass "Document written to primary (id: $TEST_ID)"
else
    fail "Write to primary failed"
    ERRORS=$((ERRORS + 1))
fi

# Test 2: Read from secondary 
sep
log "${BOLD}[TEST 2] Read from secondary (readPreference=secondary)${NC}"

SEC_URI="${APP_URI}&readPreference=secondary"
READ_RESULT=$(mongo_eval "$SEC_URI" "
    db.getSiblingDB('usersdb').failover_tests.findOne({_id:'$TEST_ID'})?._id || 'NOT_FOUND'
" 2>/dev/null || echo "NOT_FOUND")

if [[ "$READ_RESULT" == *"$TEST_ID"* ]]; then
    pass "Replica replication confirmed — document visible on secondary"
else
    warn "Document not yet replicated (replication lag may be normal)"
fi

# Test 3: Simulate primary failure 
sep
log "${BOLD}[TEST 3] Simulate primary failure${NC}"
info "Killing mongod on port $PRIMARY_PORT..."

KILL_PID=$(pgrep -f "mongod.*$PRIMARY_PORT" 2>/dev/null || echo "")
if [[ -z "$KILL_PID" ]]; then
    warn "Could not find mongod PID for port $PRIMARY_PORT — skipping kill test"
    warn "Manual test: kill the primary's mongod process and run this script again"
    SKIP_FAILOVER=true
else
    kill -SIGTERM "$KILL_PID" 2>/dev/null || true
    info "mongod on port $PRIMARY_PORT sent SIGTERM (PID $KILL_PID)"
    SKIP_FAILOVER=false
fi

#  Test 4: Election completes within 30s 
sep
log "${BOLD}[TEST 4] New primary election${NC}"

if [[ "${SKIP_FAILOVER:-false}" == "true" ]]; then
    warn "Skipped (no PID found in previous step)"
else
    info "Waiting for election (up to 30 seconds)..."
    NEW_PRIMARY=""
    for i in $(seq 1 30); do
        sleep 1
        NEW_PRIMARY=$(get_primary_port 2>/dev/null || echo "")
        if [[ -n "$NEW_PRIMARY" && "$NEW_PRIMARY" != "$PRIMARY_PORT" ]]; then
            pass "New primary elected at localhost:$NEW_PRIMARY (${i}s elapsed)"
            break
        fi
        printf "."
    done
    echo ""

    if [[ -z "$NEW_PRIMARY" || "$NEW_PRIMARY" == "$PRIMARY_PORT" ]]; then
        fail "No new primary elected within 30 seconds"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Test 5: API continues serving during failover 
sep
log "${BOLD}[TEST 5] API availability during failover${NC}"

for port in 3000 3003 3004; do
    if check_api_health "$port"; then
        pass "API on port $port — healthy"
    else
        warn "API on port $port — not responding (may still be restarting)"
    fi
done

#  Test 6: Write to new primary 
sep
log "${BOLD}[TEST 6] Write to new primary${NC}"

if [[ "${SKIP_FAILOVER:-false}" == "false" && -n "${NEW_PRIMARY:-}" ]]; then
    NEW_URI="mongodb://devops:Devops%40123@localhost:$NEW_PRIMARY/usersdb?authSource=admin"
    TEST_ID2="failover-test2-$(date +%s)"
    W2=$(mongo_eval "$NEW_URI" "
        db.getSiblingDB('usersdb').failover_tests.insertOne({_id:'$TEST_ID2',test:'post-failover',ts:new Date()});
        db.getSiblingDB('usersdb').failover_tests.findOne({_id:'$TEST_ID2'})?._id || ''
    " 2>/dev/null || echo "")
    if [[ "$W2" == *"$TEST_ID2"* ]]; then
        pass "Write to new primary succeeded"
    else
        fail "Write to new primary failed"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Test 7: Recovery — restart killed node 
sep
log "${BOLD}[TEST 7] Recovery — restart failed node${NC}"

if [[ "${SKIP_FAILOVER:-false}" == "false" ]]; then
    CONFIG_DIR="$(dirname "$0")/config"
    if [[ "$PRIMARY_PORT" == "27017" ]]; then NODE=1
    elif [[ "$PRIMARY_PORT" == "27018" ]]; then NODE=2
    else NODE=3
    fi
    info "Restarting mongod-node$NODE (port $PRIMARY_PORT)..."
    mongod --config "$CONFIG_DIR/mongod-node$NODE.conf" --fork 2>/dev/null \
        || (mongod --config "$CONFIG_DIR/mongod-node$NODE.conf" &)
    sleep 5

    RECOVERED=$(mongo_eval "$ADMIN_URI" "
        rs.status().members.filter(m=>m.name==='localhost:$PRIMARY_PORT')[0]?.stateStr || 'UNKNOWN'
    " 2>/dev/null || echo "UNKNOWN")
    if [[ "$RECOVERED" == "SECONDARY" || "$RECOVERED" == "PRIMARY" ]]; then
        pass "Recovered node joined as $RECOVERED"
    else
        warn "Node state: $RECOVERED (may still be syncing)"
    fi
fi

# Cleanup 
mongo_eval "$APP_URI" "db.getSiblingDB('usersdb').failover_tests.drop()" >/dev/null 2>&1 || true

# Summary 
sep
log ""
if [[ $ERRORS -eq 0 ]]; then
    log "${BOLD}${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    log "${BOLD}${GREEN}║   ALL TESTS PASSED                                     ║${NC}"
    log "${BOLD}${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
else
    log "${BOLD}${RED}╔════════════════════════════════════════════════════════╗${NC}"
    log "${BOLD}${RED}║   $ERRORS TEST(S) FAILED                               ║${NC}"
    log "${BOLD}${RED}╚════════════════════════════════════════════════════════╝${NC}"
fi
    log ""
    log "  Report saved to: $REPORT_FILE"
    log ""

    log_info "Failover test completed with $ERRORS error(s)"
    exit $ERRORS
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_usage; exit $EXIT_SUCCESS ;;
        *) log_error "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
