#!/bin/bash
set -euo pipefail

# Script: db_user_manager.sh
# Description: Interactive menu-driven user management for PostgreSQL, MySQL, and MongoDB
# Author: Aakash
# Date: 2026-02-22
# Usage: ./db_user_manager.sh [-h|--help] [-v|--verbose]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/db_user_manager.log"
OP_LOG="var/log/apps/db_user_operations.log"
VERBOSE=false

# DB connection defaults 
PG_ADMIN_USER="${PG_ADMIN_USER:-dbadmin}"
PG_ADMIN_PASS="${PG_ADMIN_PASS:-password123}"
MYSQL_ADMIN_USER="${MYSQL_ADMIN_USER:-root}"
MYSQL_ADMIN_PASS="${MYSQL_ADMIN_PASS:-RootPass@2026!}"
MONGO_ADMIN_USER="${MONGO_ADMIN_USER:-mongoadmin}"
MONGO_ADMIN_PASS="${MONGO_ADMIN_PASS:-AdminPass@2026!}"

# Logging
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }
log_op()    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OP]    $1" | tee -a "$OP_LOG"; }
log_debug() { $VERBOSE && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" | tee -a "$LOG_FILE"; }

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Interactive database user management for PostgreSQL, MySQL, and MongoDB.

OPTIONS:
    -h, --help      Show this help message
    -v, --verbose   Enable verbose output

Examples:
    $(basename "$0")
    $(basename "$0") --verbose
EOF
}


read_input() {
    local prompt="$1"
    local var_name="$2"
    read -rp "$prompt" "$var_name"
}

read_password() {
    local prompt="$1"
    local var_name="$2"
    read -rsp "$prompt" "$var_name"
    echo
}

validate_username() {
    local username="$1"
    if [[ ! "$username" =~ ^[a-zA-Z][a-zA-Z0-9_]{1,30}$ ]]; then
        log_error "Invalid username: must start with a letter, 2-31 chars, alphanumeric/underscore only"
        return 1
    fi
}

validate_dbname() {
    local dbname="$1"
    if [[ ! "$dbname" =~ ^[a-zA-Z][a-zA-Z0-9_]{0,62}$ ]]; then
        log_error "Invalid database name"
        return 1
    fi
}


pg_exec() {
    PGPASSWORD="$PG_ADMIN_PASS" psql -U "$PG_ADMIN_USER" -h 127.0.0.1 -d postgres -At "$@"
}

check_pg_connection() {
    if ! pg_exec -c "SELECT 1" &>/dev/null; then
        log_error "Cannot connect to PostgreSQL"
        return 1
    fi
}

create_pg_user() {
    echo ""
    read_input  "  Enter username:    " username
    validate_username "$username" || return 1
    read_password "  Enter password:    " password
    read_input  "  Enter database:    " dbname
    validate_dbname "$dbname" || return 1
    read_input  "  Privileges (full/read/write): " priv_level

    check_pg_connection || return 1

    PGPASSWORD="$PG_ADMIN_PASS" psql -U "$PG_ADMIN_USER" -h 127.0.0.1 postgres << SQL
CREATE USER "$username" WITH LOGIN PASSWORD '$password';
SQL

    # Create database if it doesn't exist
    if ! pg_exec -c "SELECT 1 FROM pg_database WHERE datname='$dbname'" | grep -q 1; then
        pg_exec -c "CREATE DATABASE \"$dbname\" OWNER \"$username\""
    fi

    case "$priv_level" in
        full)
            pg_exec -c "GRANT ALL PRIVILEGES ON DATABASE \"$dbname\" TO \"$username\""
            ;;
        read)
            pg_exec -c "GRANT CONNECT ON DATABASE \"$dbname\" TO \"$username\""
            PGPASSWORD="$PG_ADMIN_PASS" psql -U "$PG_ADMIN_USER" -h 127.0.0.1 "$dbname" \
                -c "GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"$username\";"
            ;;
        write)
            pg_exec -c "GRANT CONNECT ON DATABASE \"$dbname\" TO \"$username\""
            PGPASSWORD="$PG_ADMIN_PASS" psql -U "$PG_ADMIN_USER" -h 127.0.0.1 "$dbname" \
                -c "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"$username\";"
            ;;
        *)
            log_error "Invalid privilege level: $priv_level"
            return 1
            ;;
    esac

    log_op "PostgreSQL: Created user '$username' with '$priv_level' on '$dbname'"
    echo "PostgreSQL user '$username' created"
    echo "Privileges granted on database '$dbname'"
    echo "Operation logged"
}

delete_pg_user() {
    read_input "  Enter username to delete: " username
    validate_username "$username" || return 1
    check_pg_connection || return 1

    pg_exec -c "DROP USER IF EXISTS \"$username\""
    log_op "PostgreSQL: Deleted user '$username'"
    echo " PostgreSQL user '$username' deleted"
}

list_pg_users() {
    check_pg_connection || return 1
    echo ""
    echo "  PostgreSQL Users:"
    echo "  ─────────────────────────────────────────"
    pg_exec -c "SELECT usename, usesuper, usecreatedb FROM pg_user ORDER BY usename" \
        | awk -F'|' '{ printf "  %-20s superuser=%-5s createdb=%s\n", $1, $2, $3 }'
}

grant_revoke_pg() {
    read_input "  Enter username: " username
    read_input "  Enter database: " dbname
    read_input "  Action (grant/revoke): " action
    read_input "  Privilege (ALL/SELECT/INSERT/UPDATE/DELETE): " priv
    check_pg_connection || return 1

    if [[ "$action" == "grant" ]]; then
        pg_exec -c "GRANT $priv ON DATABASE \"$dbname\" TO \"$username\""
        log_op "PostgreSQL: Granted $priv on $dbname to $username"
        echo "  Granted $priv on '$dbname' to '$username'"
    else
        pg_exec -c "REVOKE $priv ON DATABASE \"$dbname\" FROM \"$username\""
        log_op "PostgreSQL: Revoked $priv on $dbname from $username"
        echo "  Revoked $priv on '$dbname' from '$username'"
    fi
}

# MySQL 

mysql_exec() {
    mysql -u "$MYSQL_ADMIN_USER" -p"$MYSQL_ADMIN_PASS" "$@"
}

check_mysql_connection() {
    if ! mysql_exec -e "SELECT 1" &>/dev/null; then
        log_error "Cannot connect to MySQL"
        return 1
    fi
}

create_mysql_user() {
    echo ""
    read_input  "  Enter username:    " username
    validate_username "$username" || return 1
    read_password "  Enter password:    " password
    read_input  "  Enter database:    " dbname
    validate_dbname "$dbname" || return 1
    read_input  "  Privileges (full/read/write): " priv_level

    check_mysql_connection || return 1

    mysql_exec << SQL
CREATE DATABASE IF NOT EXISTS \`${dbname}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${username}'@'localhost' IDENTIFIED BY '${password}';
SQL

    case "$priv_level" in
        full)  mysql_exec -e "GRANT ALL PRIVILEGES ON \`${dbname}\`.* TO '${username}'@'localhost'; FLUSH PRIVILEGES;" ;;
        read)  mysql_exec -e "GRANT SELECT ON \`${dbname}\`.* TO '${username}'@'localhost'; FLUSH PRIVILEGES;" ;;
        write) mysql_exec -e "GRANT SELECT,INSERT,UPDATE,DELETE ON \`${dbname}\`.* TO '${username}'@'localhost'; FLUSH PRIVILEGES;" ;;
        *)     log_error "Invalid privilege level: $priv_level"; return 1 ;;
    esac

    log_op "MySQL: Created user '$username' with '$priv_level' on '$dbname'"
    echo " MySQL user '$username' created"
    echo " Privileges granted on database '$dbname'"
    echo " Operation logged"
}

delete_mysql_user() {
    read_input "  Enter username to delete: " username
    validate_username "$username" || return 1
    check_mysql_connection || return 1

    mysql_exec -e "DROP USER IF EXISTS '${username}'@'localhost'; FLUSH PRIVILEGES;"
    log_op "MySQL: Deleted user '$username'"
    echo "  ✓ MySQL user '$username' deleted"
}

list_mysql_users() {
    check_mysql_connection || return 1
    echo ""
    echo "  MySQL Users:"
    echo "  ─────────────────────────────────────────"
    mysql_exec -e "SELECT User, Host, account_locked FROM mysql.user ORDER BY User;" 2>/dev/null \
        | column -t | sed 's/^/  /'
}

grant_revoke_mysql() {
    read_input "  Enter username: " username
    read_input "  Enter database: " dbname
    read_input "  Action (grant/revoke): " action
    read_input "  Privilege (ALL/SELECT/INSERT/UPDATE/DELETE): " priv
    check_mysql_connection || return 1

    if [[ "$action" == "grant" ]]; then
        mysql_exec -e "GRANT $priv ON \`${dbname}\`.* TO '${username}'@'localhost'; FLUSH PRIVILEGES;"
        log_op "MySQL: Granted $priv on $dbname to $username"
        echo "  ✓ Granted $priv on '$dbname' to '$username'"
    else
        mysql_exec -e "REVOKE $priv ON \`${dbname}\`.* FROM '${username}'@'localhost'; FLUSH PRIVILEGES;"
        log_op "MySQL: Revoked $priv on $dbname from $username"
        echo "  ✓ Revoked $priv on '$dbname' from '$username'"
    fi
}

# MongoDB 

mongo_exec() {
    mongosh --quiet -u "$MONGO_ADMIN_USER" -p "$MONGO_ADMIN_PASS" \
        --authenticationDatabase admin "$@"
}

check_mongo_connection() {
    if ! mongo_exec --eval "db.runCommand({ping:1})" &>/dev/null; then
        log_error "Cannot connect to MongoDB"
        return 1
    fi
}

create_mongo_user() {
    echo ""
    read_input  "  Enter username:    " username
    validate_username "$username" || return 1
    read_password "  Enter password:    " password
    read_input  "  Enter database:    " dbname
    validate_dbname "$dbname" || return 1
    read_input  "  Privileges (full/read/write): " priv_level

    check_mongo_connection || return 1

    local role
    case "$priv_level" in
        full)  role="dbOwner" ;;
        read)  role="read" ;;
        write) role="readWrite" ;;
        *)     log_error "Invalid privilege level: $priv_level"; return 1 ;;
    esac

    mongo_exec --eval "
        db = db.getSiblingDB('${dbname}');
        db.createUser({ user: '${username}', pwd: '${password}', roles: [{ role: '${role}', db: '${dbname}' }] });
    "

    log_op "MongoDB: Created user '$username' with role '$role' on '$dbname'"
    echo "  MongoDB user '$username' created"
    echo "  Role '$role' assigned on database '$dbname'"
    echo "  Operation logged"
}

delete_mongo_user() {
    read_input "  Enter username to delete: " username
    read_input "  Enter database: " dbname
    validate_username "$username" || return 1
    check_mongo_connection || return 1

    mongo_exec --eval "db.getSiblingDB('${dbname}').dropUser('${username}')"
    log_op "MongoDB: Deleted user '$username' from '$dbname'"
    echo "  ✓ MongoDB user '$username' deleted"
}

list_mongo_users() {
    check_mongo_connection || return 1
    echo ""
    echo "  MongoDB Users:"
    echo "  ─────────────────────────────────────────"
    mongo_exec --eval "
        db.getSiblingDB('admin').system.users.find({}, {user:1, db:1, roles:1, _id:0}).forEach(u => {
            print('  ' + u.user + ' @ ' + u.db + '  roles: ' + u.roles.map(r=>r.role).join(', '));
        });
    "
}

#  Delete user 

delete_user_menu() {
    echo ""
    echo "  Select database:"
    echo "  1) PostgreSQL"
    echo "  2) MySQL"
    echo "  3) MongoDB"
    read_input "  Choice: " db_choice
    case "$db_choice" in
        1) delete_pg_user ;;
        2) delete_mysql_user ;;
        3) delete_mongo_user ;;
        *) log_error "Invalid choice" ;;
    esac
}

# List all users 

list_all_users() {
    list_pg_users    2>/dev/null || echo "  [PostgreSQL] Connection failed"
    echo ""
    list_mysql_users 2>/dev/null || echo "  [MySQL] Connection failed"
    echo ""
    list_mongo_users 2>/dev/null || echo "  [MongoDB] Connection failed"
}

# Grant/revoke menu 

grant_revoke_menu() {
    echo ""
    echo "  Select database:"
    echo "  1) PostgreSQL"
    echo "  2) MySQL"
    read_input "  Choice: " db_choice
    case "$db_choice" in
        1) grant_revoke_pg ;;
        2) grant_revoke_mysql ;;
        *) log_error "MongoDB privilege changes done via create user menu" ;;
    esac
}

# Main menu 

print_menu() {
    echo ""
    echo "Database User Manager"
    echo "========================================"
    echo "1) Create PostgreSQL user"
    echo "2) Create MySQL user"
    echo "3) Create MongoDB user"
    echo "4) Delete user"
    echo "5) List all users"
    echo "6) Grant/revoke privileges"
    echo "7) Exit"
    echo ""
}

main() {
    mkdir -p var/log/apps
    log_info "Script started"

    while true; do
        print_menu
        read_input "Choice: " choice
        echo ""
        case "$choice" in
            1) create_pg_user ;;
            2) create_mysql_user ;;
            3) create_mongo_user ;;
            4) delete_user_menu ;;
            5) list_all_users ;;
            6) grant_revoke_menu ;;
            7) log_info "Script completed successfully"; exit $EXIT_SUCCESS ;;
            *) echo "  Invalid choice, please try again." ;;
        esac
        echo ""
    done
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
