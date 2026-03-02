#!/bin/bash
set -euo pipefail

# Script: setup-replicaset.sh
# Description: Initialise a 3-node MongoDB replica set (rs0) for Stack 1.
#              Creates a shared auth keyfile, starts mongod on ports 27017/27018/27019,
#              initialises replication, creates admin and application users, then
#              restarts all nodes with authentication enabled.
# Author: Aakash
# Date: 2026-03-01
# Usage: ./setup-replicaset.sh [--help]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
KEYFILE="$CONFIG_DIR/replica-keyfile"
LOG_FILE="$SCRIPT_DIR/../var/log/apps/$(basename "$0" .sh).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info()  { mkdir -p "$(dirname "$LOG_FILE")"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { mkdir -p "$(dirname "$LOG_FILE")"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }

# Help function
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Initialise a 3-node MongoDB replica set (rs0) for Stack 1.
Runs the full setup: keyfile generation, mongod startup, replication init,
user creation, and a final restart with authentication enabled.

OPTIONS:
    -h, --help    Show this help message

EXAMPLES:
    $(basename "$0")

NOTE:
    Run this once on a fresh machine. To manage a running replica set use:
    ./manage-replicaset.sh [start|stop|status|health]
EOF
}

# Main function
main() {
    log_info "Replica set setup started"

    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      MongoDB Replica Set Setup - Stack 1                     ║${NC}"
    echo -e "${BLUE}║      3 Nodes: 27017 (Primary), 27018, 27019 (Secondaries)    ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Step 1: Generate replica set keyfile (if it doesn't already exist)
    log_info "[1/6] Generating replica set keyfile..."
    echo -e "${YELLOW}[1/6] Generating replica set keyfile...${NC}"
    if [ ! -f "$KEYFILE" ]; then
        openssl rand -base64 756 > "$KEYFILE"
        chmod 400 "$KEYFILE"
        log_info "Keyfile generated at $KEYFILE"
        echo -e "${GREEN} Keyfile generated at $KEYFILE${NC}"
    else
        echo -e "${GREEN} Keyfile already exists${NC}"
    fi

    # Step 2: Check MongoDB installation
    log_info "[2/6] Checking MongoDB installation..."
    echo -e "\n${YELLOW}[2/6] Checking MongoDB installation...${NC}"
    if ! command -v mongod &> /dev/null; then
        log_error "MongoDB is not installed"
        echo -e "${RED} MongoDB is not installed${NC}"
        echo "Install MongoDB and try again."
        exit $EXIT_ERROR
    fi
    echo -e "${GREEN} MongoDB is installed: $(mongod --version | head -1)${NC}"

    # Step 3: Stop any running instances
    log_info "[3/6] Stopping any existing replica set instances..."
    echo -e "\n${YELLOW}[3/6] Stopping any existing replica set instances...${NC}"
    # Graceful then forced kill to ensure ports are freed
    pkill -f "mongod.*2701[7-9]" 2>/dev/null || true
    sleep 2
    pkill -9 -f "mongod.*2701[7-9]" 2>/dev/null || true
    sleep 2
    # Double check ports are free
    for port in 27017 27018 27019; do
        local pid
        pid=$(lsof -ti :$port 2>/dev/null || true)
        if [[ -n "$pid" ]]; then
            kill -9 "$pid" 2>/dev/null || true
            sleep 1
        fi
    done
    echo -e "${GREEN} Cleaned up existing instances${NC}"

    # Step 4: Start all 3 nodes without auth so we can create the initial users
    log_info "[4/6] Starting MongoDB instances without auth (for initial user creation)..."
    echo -e "\n${YELLOW}[4/6] Starting MongoDB instances (without auth)...${NC}"

    # Create data directories if they don't exist
    for node in 1 2 3; do
        mkdir -p "$SCRIPT_DIR/data/node$node"
    done
    mkdir -p "$SCRIPT_DIR/logs"

    # Temporarily disable auth in config so we can run rs.initiate() without credentials
    for node in 1 2 3; do
        sed -i 's/^  authorization: enabled/  authorization: disabled/' "$CONFIG_DIR/mongod-node$node.conf" 2>/dev/null || true
        sed -i 's/^  keyFile:/#  keyFile:/' "$CONFIG_DIR/mongod-node$node.conf" 2>/dev/null || true
    done

    mongod --config "$CONFIG_DIR/mongod-node1.conf"
    sleep 3
    mongod --config "$CONFIG_DIR/mongod-node2.conf"
    sleep 2
    mongod --config "$CONFIG_DIR/mongod-node3.conf"
    sleep 3

    echo -e "${GREEN} All 3 MongoDB instances started${NC}"
    echo "  - Node 1: localhost:27017"
    echo "  - Node 2: localhost:27018"
    echo "  - Node 3: localhost:27019"

    # Step 5: Initialise the replica set — node1 is preferred primary (priority 2)
    log_info "[5/6] Initialising replica set rs0..."
    echo -e "\n${YELLOW}[5/6] Initializing replica set 'rs0'...${NC}"

    mongosh --port 27017 --quiet --eval "
try {
    rs.initiate({
        _id: 'rs0',
        members: [
            { _id: 0, host: 'localhost:27017', priority: 2 },
            { _id: 1, host: 'localhost:27018', priority: 1 },
            { _id: 2, host: 'localhost:27019', priority: 1 }
        ]
    });
    print(' Replica set initialized');
} catch(e) {
    print('Note: ' + e.message);
}
" || echo "Replica set might already be initialized"

    echo "Waiting for replica set to stabilize..."
    sleep 5

    # Wait for primary election (up to 60 seconds)
    echo "Waiting for primary to be elected..."
    PRIMARY_READY=false
    for i in $(seq 1 30); do
        if mongosh --port 27017 --quiet --eval "
            var s = rs.status();
            var hasPrimary = s.members && s.members.some(function(m) { return m.stateStr === 'PRIMARY'; });
            if (hasPrimary) { print('PRIMARY_ELECTED'); }
        " 2>/dev/null | grep -q "PRIMARY_ELECTED"; then
            PRIMARY_READY=true
            echo -e "${GREEN} Primary elected${NC}"
            break
        fi
        sleep 2
    done
    if [[ $PRIMARY_READY != true ]]; then
        echo -e "${YELLOW} Warning: primary may not be elected yet - continuing anyway${NC}"
        sleep 5
    fi

    # Step 6: Create the admin (root) user and the application user
    log_info "[6/6] Creating users..."
    echo -e "\n${YELLOW}[6/6] Creating users...${NC}"

    # User creation must run on the PRIMARY. We embed the primary-wait + user
    # creation inside a single mongosh session so there is no gap between the
    # readiness check and the write.
    local USER_CREATED=false
    for attempt in $(seq 1 5); do
        if mongosh --port 27017 --quiet --eval "
// ─── Wait for this node to become primary (up to 60 s) ───
var deadline = Date.now() + 60000;
while (Date.now() < deadline) {
    var hello = db.hello();
    if (hello.isWritablePrimary || hello.ismaster) break;
    sleep(2000);
}
var h = db.hello();
if (!(h.isWritablePrimary || h.ismaster)) {
    throw new Error('Timed out waiting for primary');
}

// ─── Create users ───
db = db.getSiblingDB('admin');

try {
    db.createUser({
        user: 'admin',
        pwd: 'Admin@123',
        roles: [
            { role: 'root', db: 'admin' },
            { role: 'clusterAdmin', db: 'admin' }
        ]
    });
    print(' Admin user created: admin/Admin@123');
} catch(e) {
    if (e.message.indexOf('already exists') > -1) {
        print(' Admin user already exists');
    } else { throw e; }
}

try {
    db.createUser({
        user: 'devops',
        pwd: 'Devops@123',
        roles: [
            { role: 'readWrite', db: 'usersdb' },
            { role: 'dbAdmin', db: 'usersdb' }
        ]
    });
    print(' Application user created: devops/Devops@123 (authSource=admin)');
} catch(e) {
    if (e.message.indexOf('already exists') > -1) {
        print(' Application user already exists');
    } else { throw e; }
}
print('USER_CREATION_OK');
" 2>&1 | grep -q "USER_CREATION_OK"; then
            USER_CREATED=true
            break
        fi
        echo "  User creation attempt $attempt failed, retrying in 5s..."
        sleep 5
    done

    if [[ "$USER_CREATED" != true ]]; then
        log_error "Failed to create MongoDB users after 5 attempts"
        echo -e "${RED} Failed to create users — check if replica set has a primary${NC}"
        exit $EXIT_ERROR
    fi

    # Restart all nodes with authentication enabled
    log_info "Enabling authentication and restarting..."
    echo -e "\n${YELLOW}Enabling authentication and restarting...${NC}"

    # Stop all instances cleanly first via mongosh, then force
    mongosh --port 27017 --quiet --eval "db.adminCommand({shutdown: 1})" 2>/dev/null || true
    mongosh --port 27018 --quiet --eval "db.adminCommand({shutdown: 1})" 2>/dev/null || true
    mongosh --port 27019 --quiet --eval "db.adminCommand({shutdown: 1})" 2>/dev/null || true
    sleep 3
    pkill -f "mongod.*2701[7-9]" 2>/dev/null || true
    sleep 2
    pkill -9 -f "mongod.*2701[7-9]" 2>/dev/null || true
    sleep 2
    # Ensure ports are free
    for port in 27017 27018 27019; do
        local pid
        pid=$(lsof -ti :$port 2>/dev/null || true)
        if [[ -n "$pid" ]]; then
            kill -9 "$pid" 2>/dev/null || true
            sleep 1
        fi
    done

    # Re-enable auth in all config files
    for node in 1 2 3; do
        sed -i 's/^  authorization: disabled/  authorization: enabled/' "$CONFIG_DIR/mongod-node$node.conf"
        sed -i 's/^#  keyFile:/  keyFile:/' "$CONFIG_DIR/mongod-node$node.conf"
    done

    # Restart with auth
    mongod --config "$CONFIG_DIR/mongod-node1.conf"
    sleep 3
    mongod --config "$CONFIG_DIR/mongod-node2.conf"
    sleep 2
    mongod --config "$CONFIG_DIR/mongod-node3.conf"
    sleep 5

    log_info "Authentication enabled and all nodes restarted"
    echo -e "${GREEN} Authentication enabled${NC}"

    # Wait for primary election after auth restart
    echo "Waiting for replica set to elect primary with auth enabled..."
    for i in $(seq 1 20); do
        if mongosh "mongodb://admin:Admin%40123@localhost:27017/admin?authSource=admin" --quiet --eval "
            var s = rs.status();
            var hasPrimary = s.members && s.members.some(function(m) { return m.stateStr === 'PRIMARY'; });
            if (hasPrimary) { print('PRIMARY_ELECTED'); }
        " 2>/dev/null | grep -q "PRIMARY_ELECTED"; then
            break
        fi
        sleep 2
    done

    # Final verification — confirm all members are visible
    log_info "Verifying replica set status..."
    echo -e "\n${YELLOW}Verifying replica set status...${NC}"
    sleep 5

    mongosh "mongodb://admin:Admin%40123@localhost:27017/admin?authSource=admin" --quiet --eval "
    rs.status().members.forEach(function(member) {
        print(member.name + ' - ' + member.stateStr);
    });
    " 2>/dev/null || true

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Replica Set Setup Complete!                       ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Connection Strings:${NC}"
    echo ""
    echo "  Admin (root access):"
    echo "  mongodb://admin:Admin%40123@localhost:27017,localhost:27018,localhost:27019/admin?replicaSet=rs0&authSource=admin"
    echo ""
    echo "  Application (usersdb):"
    echo "  mongodb://devops:Devops%40123@localhost:27017,localhost:27018,localhost:27019/usersdb?replicaSet=rs0&authSource=admin"
    echo ""
    echo -e "${BLUE}Management Commands:${NC}"
    echo "  Check status:    ./manage-replicaset.sh status"
    echo "  Stop all:        ./manage-replicaset.sh stop"
    echo "  Start all:       ./manage-replicaset.sh start"
    echo "  View logs:       ./manage-replicaset.sh logs"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "  1. Update backend/.env with the replica set connection string"
    echo "  2. Restart your backend services: pm2 restart all"
    echo "  3. Test connection: curl http://localhost:3000/api/health"
    echo ""

    log_info "Replica set setup completed successfully"
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
