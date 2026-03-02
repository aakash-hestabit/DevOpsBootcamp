#!/bin/bash
set -euo pipefail

# Script: manage-replicaset.sh
# Description: Start, stop, restart, and inspect the MongoDB 3-node replica set (rs0).
#              Use this after the replica set has been initialised by setup-replicaset.sh.
# Author: Aakash
# Date: 2026-03-01
# Usage: ./manage-replicaset.sh [COMMAND] [--help]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
LOG_FILE="$SCRIPT_DIR/../var/log/apps/$(basename "$0" .sh).log"

# Credentials used for status and health queries
ADMIN_URI="mongodb://admin:Admin%40123@localhost:27017/admin?authSource=admin"

# Colors
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
Usage: $(basename "$0") [COMMAND]

Manage the Stack 1 MongoDB replica set (rs0 — ports 27017, 27018, 27019).

COMMANDS:
    start       Start all 3 replica set nodes
    stop        Stop all 3 replica set nodes
    restart     Stop then start all nodes
    status      Show replica set member states
    logs        Tail recent logs from all nodes
    primary     Show which node is currently primary
    connect     Open mongosh connected to the primary
    health      Process-level and replica set health check

OPTIONS:
    -h, --help  Show this help message

EXAMPLES:
    $(basename "$0") start
    $(basename "$0") status
    $(basename "$0") restart
EOF
}

# Start all 3 nodes 
start_replicaset() {
    log_info "Starting MongoDB replica set nodes..."
    echo -e "${YELLOW}Starting MongoDB replica set nodes...${NC}"

    mkdir -p "$SCRIPT_DIR/data/node1" "$SCRIPT_DIR/data/node2" "$SCRIPT_DIR/data/node3"
    mkdir -p "$SCRIPT_DIR/logs"

    mongod --config "$CONFIG_DIR/mongod-node1.conf"
    sleep 2
    echo -e "${GREEN}   Node 1 started (port 27017)${NC}"

    mongod --config "$CONFIG_DIR/mongod-node2.conf"
    sleep 2
    echo -e "${GREEN}   Node 2 started (port 27018)${NC}"

    mongod --config "$CONFIG_DIR/mongod-node3.conf"
    sleep 2
    echo -e "${GREEN}   Node 3 started (port 27019)${NC}"

    echo ""
    log_info "All replica set nodes started"
    echo -e "${GREEN}All nodes started successfully!${NC}"
}

# Stop all 3 nodes 
stop_replicaset() {
    log_info "Stopping MongoDB replica set nodes..."
    echo -e "${YELLOW}Stopping MongoDB replica set nodes...${NC}"

    pkill -f "mongod.*27017" 2>/dev/null \
        && echo -e "${GREEN}   Node 1 stopped${NC}" \
        || echo "  Node 1 was not running"
    pkill -f "mongod.*27018" 2>/dev/null \
        && echo -e "${GREEN}   Node 2 stopped${NC}" \
        || echo "  Node 2 was not running"
    pkill -f "mongod.*27019" 2>/dev/null \
        && echo -e "${GREEN}   Node 3 stopped${NC}" \
        || echo "  Node 3 was not running"

    sleep 2
    echo ""
    log_info "All replica set nodes stopped"
    echo -e "${GREEN}All nodes stopped${NC}"
}

# Show current RS member states 
show_status() {
    echo -e "${BLUE}Replica Set Status:${NC}"
    echo ""

    mongosh "$ADMIN_URI" --quiet --eval "
    var status = rs.status();
    print('Replica Set: ' + status.set);
    print('');
    status.members.forEach(function(member) {
        print(member.name + '  —  ' + member.stateStr + '  (health: ' + member.health + ')');
    });
    " 2>/dev/null || echo -e "${RED}   Cannot connect to replica set${NC}"
}

#  Identify which node is currently primary 
show_primary() {
    echo -e "${BLUE}Finding primary node...${NC}"
    echo ""

    mongosh "$ADMIN_URI" --quiet --eval "
    var primary = rs.status().members.find(function(m) { return m.stateStr === 'PRIMARY'; });
    primary ? print('  Primary: ' + primary.name) : print('   No primary found');
    " 2>/dev/null || echo -e "${RED}   Cannot connect to replica set${NC}"
}

#  Tail recent log entries from all nodes 
view_logs() {
    local LOG_DIR="$SCRIPT_DIR/logs"
    echo -e "${YELLOW}Recent logs from all nodes:${NC}"
    echo ""

    for i in 1 2 3; do
        local port=$((27016 + i))
        echo -e "${BLUE}=== Node $i (port $port) ===${NC}"
        tail -n 10 "$LOG_DIR/mongod-node$i.log" 2>/dev/null || echo "  No log file found"
        echo ""
    done
}

# Open an interactive mongosh session on the primary 
connect_primary() {
    log_info "Opening mongosh connection to primary..."
    echo -e "${BLUE}Connecting to primary node...${NC}"
    mongosh "$ADMIN_URI&replicaSet=rs0"
}

# Process-level ping plus replica set status 
check_health() {
    echo -e "${BLUE}Health Check:${NC}"
    echo ""

    for i in 1 2 3; do
        local port=$((27016 + i))
        if pgrep -f "mongod.*$port" > /dev/null; then
            echo -e "${GREEN}   Node $i (port $port) — process running${NC}"
        else
            echo -e "${RED}   Node $i (port $port) — not running${NC}"
        fi
    done

    echo ""
    show_status
}

# Main function
main() {
    local cmd="${1:-}"
    log_info "manage-replicaset.sh called with command: '${cmd}'"

    case "$cmd" in
        start)   start_replicaset ;;
        stop)    stop_replicaset ;;
        restart) stop_replicaset; sleep 2; start_replicaset ;;
        status)  show_status ;;
        logs)    view_logs ;;
        primary) show_primary ;;
        connect) connect_primary ;;
        health)  check_health ;;
        "")
            # No command given — just show usage
            show_usage
            exit $EXIT_SUCCESS
            ;;
        *)
            log_error "Unknown command: $cmd"
            show_usage
            exit $EXIT_ERROR
            ;;
    esac

    log_info "Command '$cmd' completed"
}

# Parse arguments, handle --help before delegating to main
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_usage; exit $EXIT_SUCCESS ;;
        *)         break ;;   # pass the command and any remaining args to main
    esac
    shift
done

main "$@"
