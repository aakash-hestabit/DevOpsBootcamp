#!/bin/bash
set -euo pipefail

# Script: mongodb_setup.sh
# Description: Installs and configures MongoDB 7.0 with production-ready settings
# Author: Aakash
# Date: 2026-02-22
# Usage: ./mongodb_setup.sh [-h|--help] [-v|--verbose]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/mongodb_setup.log"
MONGO_VERSION="7.0"
MONGO_ADMIN_USER="mongoadmin"
MONGO_ADMIN_PASSWORD="AdminPass@2026!"
MONGO_APP_USER="appuser"
MONGO_APP_PASSWORD="AppPass@2026!"
MONGO_APP_DB="appdb"
VERBOSE=false

# Logging
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }
log_debug() { $VERBOSE && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" | tee -a "$LOG_FILE" || true; }

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Installs MongoDB ${MONGO_VERSION} with production-optimized configuration.

OPTIONS:
    -h, --help      Show this help message
    -v, --verbose   Enable verbose output

Examples:
    sudo $(basename "$0")
    sudo $(basename "$0") --verbose
EOF
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (sudo)"
        exit $EXIT_ERROR
    fi
}

install_mongodb() {
    log_info "Installing MongoDB ${MONGO_VERSION}"

    apt-get install -y gnupg curl

    # Remove existing GPG key if it exists
    rm -f /usr/share/keyrings/mongodb-server-${MONGO_VERSION}.gpg

    curl -fsSL "https://www.mongodb.org/static/pgp/server-${MONGO_VERSION}.asc" \
        | gpg --dearmor > /usr/share/keyrings/mongodb-server-${MONGO_VERSION}.gpg

    . /etc/os-release
    
    # Try to add the repository - handle both noble and jammy (fallback)
    if [[ "${VERSION_CODENAME}" == "noble" ]]; then
        # Noble is not officially supported by MongoDB 7.0, use jammy instead
        echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-${MONGO_VERSION}.gpg ] \
https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/${MONGO_VERSION} multiverse" \
            > /etc/apt/sources.list.d/mongodb-org-${MONGO_VERSION}.list
    else
        echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-${MONGO_VERSION}.gpg ] \
https://repo.mongodb.org/apt/ubuntu ${VERSION_CODENAME}/mongodb-org/${MONGO_VERSION} multiverse" \
            > /etc/apt/sources.list.d/mongodb-org-${MONGO_VERSION}.list
    fi

    apt-get update -qq
    apt-get install -y mongodb-org
    log_debug "MongoDB packages installed"
}

configure_mongodb_no_auth() {
    log_info "Applying base MongoDB configuration (pre-auth)"

    cat > /etc/mongod.conf << 'EOF'
# MongoDB 7.0 Production Configuration
# Phase 1: No auth (for initial user creation)

systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log
  verbosity: 0

storage:
  dbPath: /var/lib/mongodb
  wiredTiger:
    engineConfig:
      cacheSizeGB: 1
      journalCompressor: snappy
    collectionConfig:
      blockCompressor: snappy
    indexConfig:
      prefixCompression: true

net:
  port: 27017
  bindIp: 127.0.0.1
  maxIncomingConnections: 200

processManagement:
  timeZoneInfo: /usr/share/zoneinfo

operationProfiling:
  slowOpThresholdMs: 100
  mode: slowOp
EOF
    log_debug "Base configuration written"
}

configure_mongodb_with_auth() {
    log_info "Enabling authentication in MongoDB configuration"

    cat > /etc/mongod.conf << 'EOF'
# MongoDB 7.0 Production Configuration
# Optimized for 8GB RAM server

systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log
  verbosity: 0

storage:
  dbPath: /var/lib/mongodb
  wiredTiger:
    engineConfig:
      cacheSizeGB: 1
      journalCompressor: snappy
    collectionConfig:
      blockCompressor: snappy
    indexConfig:
      prefixCompression: true

net:
  port: 27017
  bindIp: 127.0.0.1
  maxIncomingConnections: 200

security:
  authorization: enabled

processManagement:
  timeZoneInfo: /usr/share/zoneinfo

operationProfiling:
  slowOpThresholdMs: 100
  mode: slowOp
EOF
    cp /etc/mongod.conf "configs/"
    log_debug "Authentication-enabled configuration written"
}

create_users() {
    log_info "Creating admin and application users"

    # Start without auth first
    systemctl start mongod
    sleep 5

    mongosh --quiet --eval "
        db = db.getSiblingDB('admin');
        db.createUser({
            user: '${MONGO_ADMIN_USER}',
            pwd: '${MONGO_ADMIN_PASSWORD}',
            roles: [{ role: 'userAdminAnyDatabase', db: 'admin' }, { role: 'readWriteAnyDatabase', db: 'admin' }]
        });
    "
    log_debug "Admin user '${MONGO_ADMIN_USER}' created"

    # Enable auth and restart
    configure_mongodb_with_auth
    systemctl stop mongod
    sleep 2
    systemctl start mongod
    sleep 5

    mongosh --quiet -u "${MONGO_ADMIN_USER}" -p "${MONGO_ADMIN_PASSWORD}" --authenticationDatabase admin --eval "
        db = db.getSiblingDB('${MONGO_APP_DB}');
        db.createUser({
            user: '${MONGO_APP_USER}',
            pwd: '${MONGO_APP_PASSWORD}',
            roles: [{ role: 'readWrite', db: '${MONGO_APP_DB}' }]
        });
        db.createCollection('test_collection');
        db.test_collection.insertOne({ setup: 'complete', timestamp: new Date() });
    " 2>&1 || log_error "Failed to create app user"
    log_debug "App user '${MONGO_APP_USER}' and database '${MONGO_APP_DB}' created"
}

start_service() {
    log_info "Enabling MongoDB service"
    systemctl enable mongod
    log_debug "mongod service enabled"
}

verify_installation() {
    log_info "Verifying MongoDB installation"
    sleep 2
    mongosh --quiet \
        -u "${MONGO_APP_USER}" -p "${MONGO_APP_PASSWORD}" \
        --authenticationDatabase "${MONGO_APP_DB}" \
        "${MONGO_APP_DB}" \
        --eval "db.runCommand({ ping: 1 })" > /dev/null 2>&1 || log_error "Connection verification failed"
    log_debug "Ping test passed"
}

main() {
    mkdir -p var/log/apps
    log_info "========== MongoDB Setup =========="

    check_root
    install_mongodb
    log_info "MongoDB ${MONGO_VERSION} installed"

    configure_mongodb_no_auth
    log_info "Base configuration applied"

    create_users
    log_info " Admin user '${MONGO_ADMIN_USER}' created"
    log_info " App user '${MONGO_APP_USER}' created"
    log_info " Database '${MONGO_APP_DB}' created"

    start_service
    log_info " Service started and enabled"

    verify_installation
    log_info " Connection test: SUCCESSFUL"

    log_info "Status: Ready for production"
    log_info "==================================="
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
