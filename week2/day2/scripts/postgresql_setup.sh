#!/bin/bash
set -euo pipefail

# Script: postgresql_setup.sh
# Description: Installs and configures PostgreSQL 15 with production-ready settings
# Author: Aakash
# Date: 2026-02-22
# Usage: ./postgresql_setup.sh

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/postgresql_setup.log"
PG_VERSION="15"
PG_CONF_DIR="/etc/postgresql/${PG_VERSION}/main"
CONF_D_DIR="${PG_CONF_DIR}/conf.d"
CUSTOM_CONF_FILE="99-custom-production.conf"
CUSTOM_HBA_FILE="99-custom-pg_hba.conf"
DB_USER="dbadmin"
DB_NAME="testdb"
DB_USER_PASSWORD="password123"

# Logging
log_info() { echo "[$(date '+%F %T')] [INFO] $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%F %T')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }

# Help
show_usage() {
cat << EOF
Usage: $(basename "$0")

Installs PostgreSQL 15 and applies production configuration.

Options:
  -h, --help    Show this help message
EOF
}

install_postgres() {
    log_info "Installing PostgreSQL ${PG_VERSION}"

    apt install -y curl ca-certificates
    install -d /usr/share/postgresql-common/pgdg
    curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
        https://www.postgresql.org/media/keys/ACCC4CF8.asc

    . /etc/os-release
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list

    apt update
    apt install -y postgresql-${PG_VERSION}
}

configure_postgresql() {
    log_info "Configuring PostgreSQL"

    mkdir -p "$CONF_D_DIR"

    grep -q "include_dir = 'conf.d'" "$PG_CONF_DIR/postgresql.conf" || \
    echo "include_dir = 'conf.d'" >> "$PG_CONF_DIR/postgresql.conf"

    cat > "${CONF_D_DIR}/${CUSTOM_CONF_FILE}" << EOF
# Custom production settings
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 16MB
maintenance_work_mem = 128MB
max_connections = 100
EOF

    cat >> "${PG_CONF_DIR}/pg_hba.conf" << 'EOF'

# Custom authentication rules
host    all       all   127.0.0.1/32   scram-sha-256
host    all       all   ::1/128        scram-sha-256
EOF

}

setup_users_and_db() {
    log_info "Creating database user and database"

    sudo -u postgres psql << EOF
CREATE ROLE ${DB_USER} WITH LOGIN SUPERUSER PASSWORD '${DB_USER_PASSWORD}';
CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};
EOF
}

start_service() {
    log_info "Starting PostgreSQL service"
    systemctl enable postgresql
    systemctl restart postgresql
}

verify_installation() {
    log_info "Verifying PostgreSQL installation"
    sudo -u postgres psql -c "\conninfo" >/dev/null
}

main() {
    mkdir -p var/log/apps
    log_info "========== PostgreSQL Setup =========="

    install_postgres
    log_info " PostgreSQL ${PG_VERSION} installed"

    configure_postgresql
    log_info " Configuration optimized"

    start_service
    log_info " Service started and enabled"

    setup_users_and_db
    log_info " User '${DB_USER}' created"
    log_info " Test database '${DB_NAME}' created"

    verify_installation
    log_info " Connection test: SUCCESSFUL"

    log_info "Status: Ready for production"
    log_info "======================================"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_usage; exit $EXIT_SUCCESS ;;
        *) log_error "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
done

main