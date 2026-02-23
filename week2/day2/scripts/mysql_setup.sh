#!/bin/bash
set -euo pipefail

# Script: mysql_setup.sh
# Description: Installs and configures MySQL 8.0 with production-ready settings
# Author: Aakash
# Date: 2026-02-22
# Usage: ./mysql_setup.sh [-h|--help] [-v|--verbose]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/mysql_setup.log"
MYSQL_ROOT_PASSWORD="RootPass@2026!"
MYSQL_APP_USER="appuser"
MYSQL_APP_PASSWORD="AppPass@2026!"
MYSQL_APP_DB="appdb"
VERBOSE=false

# Logging
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }
log_debug() { $VERBOSE && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" | tee -a "$LOG_FILE" || true; }

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Installs MySQL 8.0 with production-optimized configuration.

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

install_mysql() {
    log_info "Installing MySQL 8.0"
    apt-get update -qq
    apt-get install -y mysql-server mysql-client
    log_debug "MySQL packages installed"
}

secure_mysql() {
    log_info "Securing MySQL installation"

    # Check if root password is already set by trying to connect without password
    if sudo -u mysql mysql -u root -e "SELECT 1;" &>/dev/null; then
        # Root has no password, so we can set it
        sudo -u mysql mysql -u root << EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
        log_debug "MySQL secured: anonymous users removed, test db dropped, remote root disabled"
    else
        log_debug "MySQL already secured (root password already set)"
    fi
}

configure_mysql() {
    log_info "Applying optimized MySQL configuration"

    cat > /etc/mysql/conf.d/production.cnf << 'EOF'
# Production MySQL 8.0 Configuration
# Optimized for 8GB RAM server

[mysqld]
# InnoDB Settings
innodb_buffer_pool_size         = 512M
innodb_buffer_pool_instances    = 4
innodb_redo_log_capacity        = 1G
innodb_flush_log_at_trx_commit  = 1
innodb_flush_method             = O_DIRECT
innodb_file_per_table           = 1
innodb_stats_on_metadata        = 0

# Connection Settings
max_connections                 = 150
max_connect_errors              = 100000
wait_timeout                    = 600
interactive_timeout             = 600
thread_cache_size               = 16

# Slow Query Log
slow_query_log                  = 1
slow_query_log_file             = /var/log/mysql/slow.log
long_query_time                 = 2
log_queries_not_using_indexes   = 1

# Binary Logging (for backups and replication)
log_bin                         = /var/log/mysql/mysql-bin
expire_logs_days                = 7
max_binlog_size                 = 128M
sync_binlog                     = 1

# General Settings
character_set_server            = utf8mb4
collation_server                = utf8mb4_unicode_ci
skip_name_resolve               = 1
max_allowed_packet              = 64M
tmp_table_size                  = 64M
max_heap_table_size             = 64M

[client]
default-character-set           = utf8mb4
EOF

    cp /etc/mysql/conf.d/production.cnf "configs/"
    log_debug "Configuration written to /etc/mysql/conf.d/production.cnf"
}

create_app_user_and_db() {
    log_info "Creating application user and database"

    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" << EOF
CREATE DATABASE IF NOT EXISTS \`${MYSQL_APP_DB}\`
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '${MYSQL_APP_USER}'@'localhost'
    IDENTIFIED BY '${MYSQL_APP_PASSWORD}';

GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER
    ON \`${MYSQL_APP_DB}\`.* TO '${MYSQL_APP_USER}'@'localhost';

FLUSH PRIVILEGES;
EOF
    log_debug "User '${MYSQL_APP_USER}' created with privileges on '${MYSQL_APP_DB}'"
}

restart_service() {
    log_info "Restarting and enabling MySQL service"
    systemctl restart mysql
    systemctl enable mysql
    log_debug "MySQL service enabled and restarted"
}

verify_installation() {
    log_info "Verifying MySQL installation"
    mysql -u "${MYSQL_APP_USER}" -p"${MYSQL_APP_PASSWORD}" -e "SELECT VERSION();" "${MYSQL_APP_DB}" > /dev/null
    log_debug "Connection test passed"
}

main() {
    mkdir -p var/log/apps
    log_info "========== MySQL Setup =========="

    check_root
    install_mysql
    log_info "MySQL 8.0 installed"

    secure_mysql
    log_info "MySQL secured (root password set, test db removed)"

    configure_mysql
    log_info "Configuration optimized"

    restart_service
    log_info " Service started and enabled"

    create_app_user_and_db
    log_info " User '${MYSQL_APP_USER}' created"
    log_info " Database '${MYSQL_APP_DB}' created"

    verify_installation
    log_info " Connection test: SUCCESSFUL"

    log_info "Status: Ready for production"
    log_info "================================="
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
