#!/bin/bash
set -euo pipefail

# Script: master-slave-setup.sh
# Description: Configures MySQL master-slave replication on a single host.
#              Master  = the existing system MySQL service (port 3306).
#              Slave   = a second mysqld instance started in the background (port 3307).
#              Uses GTID-based replication for reliable position tracking.
# Author: Aakash
# Date: 2026-03-01
# Usage: sudo bash mysql/master-slave-setup.sh

readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/var/log/apps"
LOG_FILE="$LOG_DIR/mysql-setup.log"

mkdir -p "$LOG_DIR"

# MySQL credentials
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-Root@123}"
REPLICATION_USER="replication"
REPLICATION_PASSWORD="Repl@123"
APP_USER="laraveluser"
APP_PASSWORD="Laravel@123"
APP_DB="laraveldb"

# Ports
MASTER_PORT=3306
SLAVE_PORT=3307

# Debian maintenance user -- used to bootstrap admin access on Ubuntu
DEBIAN_CNF="/etc/mysql/debian.cnf"

log()  { echo -e "$1" | tee -a "$LOG_FILE"; }
pass() { log "${GREEN}  [OK]   $1${NC}"; }
fail() { log "${RED}  [FAIL] $1${NC}"; }
info() { log "${BLUE}  [INFO] $1${NC}"; }
warn() { log "${YELLOW}  [WARN] $1${NC}"; }
sep()  { log "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
step() { log ""; sep; log "${BOLD}${BLUE}  [$1/$TOTAL_STEPS] $2${NC}"; sep; }

TOTAL_STEPS=7

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    fail "This script must be run as root (sudo)."
    exit $EXIT_ERROR
fi

# Helper: run SQL against master using debian-sys-maint credentials
master_sql() {
    mysql --defaults-file="$DEBIAN_CNF" --socket=/var/run/mysqld/mysqld.sock 2>/dev/null <<< "$1"
}

# Helper: run SQL against slave (uses root password -- replicated from master after first sync)
slave_sql() {
    # Try with root password first (replicated from master), fall back to no-password (fresh init)
    mysql --socket=/var/run/mysqld/mysqld-slave.sock -u root -p"${MYSQL_ROOT_PASSWORD}" 2>/dev/null <<< "$1" \
        || mysql --socket=/var/run/mysqld/mysqld-slave.sock -u root 2>/dev/null <<< "$1"
}

# -----------------------------------------------------------------------
# Step 1: Pre-flight checks
# -----------------------------------------------------------------------
step 1 "Pre-flight checks"

if ! command -v mysqld &>/dev/null; then
    fail "mysqld is not installed. Install MySQL server first."
    info "  Ubuntu/Debian: sudo apt install mysql-server"
    exit $EXIT_ERROR
fi
pass "mysqld found: $(mysqld --version 2>&1 | head -1)"

if ! command -v mysql &>/dev/null; then
    fail "mysql client is not installed."
    exit $EXIT_ERROR
fi
pass "mysql client found"

if [[ ! -f "$DEBIAN_CNF" ]]; then
    fail "$DEBIAN_CNF not found -- cannot access MySQL admin user."
    exit $EXIT_ERROR
fi
pass "Debian maintenance credentials found"

# -----------------------------------------------------------------------
# Step 2: Configure system MySQL as master
# -----------------------------------------------------------------------
step 2 "Configure system MySQL as master (port $MASTER_PORT)"

# Drop a config fragment into conf.d -- this adds only the replication
# settings without touching the main mysqld.cnf.
MASTER_FRAGMENT="/etc/mysql/conf.d/stack2-master.cnf"
cat > "$MASTER_FRAGMENT" <<EOF
# Stack 2: master replication settings
# Managed by mysql/master-slave-setup.sh -- do not edit by hand.
[mysqld]
server-id                 = 1
log_bin                   = /var/log/mysql/mysql-bin
binlog_format             = ROW
binlog_row_image          = FULL
sync_binlog               = 1
gtid_mode                 = ON
enforce_gtid_consistency  = ON
expire_logs_days          = 7
EOF
pass "Master config fragment written to $MASTER_FRAGMENT"

# Restart system MySQL to apply the new settings
info "Restarting mysql.service to apply master config..."
systemctl restart mysql
sleep 5

# Wait for master to accept connections
MASTER_READY=false
for i in $(seq 1 20); do
    if mysql --defaults-file="$DEBIAN_CNF" --socket=/var/run/mysqld/mysqld.sock -e "SELECT 1" &>/dev/null 2>&1; then
        MASTER_READY=true
        break
    fi
    sleep 2
done

if [[ $MASTER_READY == false ]]; then
    fail "System MySQL failed to come up after restart. Check: journalctl -u mysql -n 50"
    exit $EXIT_ERROR
fi
pass "System MySQL is running on port $MASTER_PORT"

# -----------------------------------------------------------------------
# Step 3: Configure master -- users and database
# -----------------------------------------------------------------------
step 3 "Configure master -- users and database"

# Set the root password (may already be set -- ignore errors)
master_sql "ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '${MYSQL_ROOT_PASSWORD}';" 2>/dev/null || true

# Create replication user (use mysql_native_password for non-SSL replication)
master_sql "
CREATE USER IF NOT EXISTS '${REPLICATION_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${REPLICATION_PASSWORD}';
ALTER USER '${REPLICATION_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${REPLICATION_PASSWORD}';
GRANT REPLICATION SLAVE ON *.* TO '${REPLICATION_USER}'@'%';
FLUSH PRIVILEGES;
"
pass "Replication user created: ${REPLICATION_USER}"

# Create application database and user
# Use mysql_native_password for PHP PDO compatibility
master_sql "
CREATE DATABASE IF NOT EXISTS ${APP_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${APP_USER}'@'localhost' IDENTIFIED WITH mysql_native_password BY '${APP_PASSWORD}';
CREATE USER IF NOT EXISTS '${APP_USER}'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${APP_PASSWORD}';
ALTER USER '${APP_USER}'@'localhost' IDENTIFIED WITH mysql_native_password BY '${APP_PASSWORD}';
ALTER USER '${APP_USER}'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${APP_PASSWORD}';
GRANT ALL PRIVILEGES ON ${APP_DB}.* TO '${APP_USER}'@'localhost';
GRANT ALL PRIVILEGES ON ${APP_DB}.* TO '${APP_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
"
pass "Application database created: ${APP_DB}"
pass "Application user created: ${APP_USER}"

info "Master binary log status:"
master_sql "SHOW MASTER STATUS\G" | tee -a "$LOG_FILE"

# -----------------------------------------------------------------------
# Step 4: Initialize slave data directory
# -----------------------------------------------------------------------
step 4 "Prepare slave data directory (/var/lib/mysql-slave)"

# Ensure runtime directories exist
mkdir -p /var/run/mysqld /var/log/mysql
chown mysql:mysql /var/run/mysqld /var/log/mysql 2>/dev/null || true

# AppArmor on Ubuntu restricts mysqld to /var/lib/mysql/ by default.
# Add /var/lib/mysql-slave/ to the local AppArmor override so the slave instance
# can create its data directory and write to it.
APPARMOR_LOCAL="/etc/apparmor.d/local/usr.sbin.mysqld"
if [[ -d /etc/apparmor.d/local ]] && ! grep -q "mysql-slave" "$APPARMOR_LOCAL" 2>/dev/null; then
    info "Adding MySQL slave permissions to AppArmor local overrides..."
    cat > "$APPARMOR_LOCAL" <<'EOAA'
# Stack 2: Allow slave data directory for master-slave replication
/var/lib/mysql-slave/ rw,
/var/lib/mysql-slave/** rwk,

# Stack 2: Allow slave socket and pid files
/var/run/mysqld/mysqld-slave.pid rw,
/var/run/mysqld/mysqld-slave.sock rw,
/var/run/mysqld/mysqld-slave.sock.lock rw,
/run/mysqld/mysqld-slave.pid rw,
/run/mysqld/mysqld-slave.sock rw,
/run/mysqld/mysqld-slave.sock.lock rw,

# Stack 2: Allow slave log and binlog files
/var/log/mysql/error-slave.log rw,
/var/log/mysql/slow-slave.log rw,
/var/log/mysql/mysql-slave-bin* rw,
/var/log/mysql/relay-bin* rw,

# Stack 2: Allow slave runtime config
/etc/mysql/stack2-slave.cnf r,
EOAA
    apparmor_parser -r /etc/apparmor.d/usr.sbin.mysqld 2>/dev/null || true
    pass "AppArmor updated for mysql-slave instance"
fi

# ---- Robust cleanup of any existing slave instance ----
# This ensures the previous slave is fully dead and has released the InnoDB
# lock on /var/lib/mysql-slave/ibdata1 before we start a new one.
_slave_is_alive() {
    fuser "${SLAVE_PORT}/tcp" &>/dev/null 2>&1
}

if _slave_is_alive; then
    info "Stopping existing slave instance..."

    # 1. Graceful: MySQL SHUTDOWN via TCP (most reliable -- works even if socket is missing)
    mysql -h 127.0.0.1 -P "${SLAVE_PORT}" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHUTDOWN;" 2>/dev/null || true
    # Also try via socket (in case TCP auth fails but socket auth works)
    if [[ -S /var/run/mysqld/mysqld-slave.sock ]]; then
        mysql --socket=/var/run/mysqld/mysqld-slave.sock -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHUTDOWN;" 2>/dev/null \
            || mysql --socket=/var/run/mysqld/mysqld-slave.sock -u root -e "SHUTDOWN;" 2>/dev/null \
            || true
    fi

    # Wait up to 20 seconds for graceful shutdown
    for _w in $(seq 1 20); do
        _slave_is_alive || break
        sleep 1
    done

    # 2. SIGTERM: ask the process nicely via fuser
    if _slave_is_alive; then
        warn "Slave still alive after SHUTDOWN command -- sending SIGTERM..."
        fuser -k -TERM "${SLAVE_PORT}/tcp" 2>/dev/null || true
        for _w in $(seq 1 10); do
            _slave_is_alive || break
            sleep 1
        done
    fi

    # 3. SIGKILL: force kill as last resort
    if _slave_is_alive; then
        warn "Slave still alive -- sending SIGKILL..."
        fuser -k -9 "${SLAVE_PORT}/tcp" 2>/dev/null || true
        sleep 3
    fi

    # 4. Final verification
    if _slave_is_alive; then
        fail "Could not stop the previous slave instance."
        fail "Manual fix: sudo mysql -h 127.0.0.1 -P ${SLAVE_PORT} -u root -p'${MYSQL_ROOT_PASSWORD}' -e 'SHUTDOWN;'"
        exit $EXIT_ERROR
    fi

    # Clean up stale socket/pid files
    rm -f /var/run/mysqld/mysqld-slave.sock /var/run/mysqld/mysqld-slave.pid 2>/dev/null || true
    pass "Previous slave instance stopped"
else
    info "No existing slave instance found"
fi

if [[ ! -d /var/lib/mysql-slave/mysql ]]; then
    info "Initializing slave data directory (this may take 30-60 seconds)..."
    rm -rf /var/lib/mysql-slave 2>/dev/null || true
    # MySQL rejects --defaults-file if the file is group-writable.
    # Copy to a root-owned temp file with 600 permissions to satisfy the check.
    SLAVE_CNF_TMP=$(mktemp /tmp/slave-init.cnf.XXXX)
    cp "$SCRIPT_DIR/slave.cnf" "$SLAVE_CNF_TMP"
    chmod 600 "$SLAVE_CNF_TMP"
    # Run --initialize-insecure as root so it can create /var/lib/mysql-slave.
    # Then chown everything to mysql:mysql afterward.
    mysqld --defaults-file="$SLAVE_CNF_TMP" --initialize-insecure 2>&1
    rm -f "$SLAVE_CNF_TMP"
    chown -R mysql:mysql /var/lib/mysql-slave
    chmod 750 /var/lib/mysql-slave
    # Fix ownership of any log files created by the init step (runs as root)
    chown -R mysql:mysql /var/log/mysql/
    pass "Slave data directory initialized"
else
    info "Slave data directory already exists — skipping initialization"
fi

# -----------------------------------------------------------------------
# Step 5: Start slave instance
# -----------------------------------------------------------------------
step 5 "Start MySQL slave (port $SLAVE_PORT)"

info "Starting slave mysqld..."
# Pre-create log files with correct ownership (AppArmor may block creation by mysql user)
for _logfile in /var/log/mysql/error-slave.log /var/log/mysql/slow-slave.log; do
    touch "$_logfile" 2>/dev/null || true
    chown mysql:mysql "$_logfile" 2>/dev/null || true
done
# Ensure all existing slave log/binlog files are owned by mysql
chown -R mysql:mysql /var/log/mysql/ 2>/dev/null || true
# Clean up stale socket/pid files before start
rm -f /var/run/mysqld/mysqld-slave.sock /var/run/mysqld/mysqld-slave.pid 2>/dev/null || true
# Copy config to a persistent location OUTSIDE conf.d/ (files in conf.d are
# auto-included by the system MySQL and would break the master instance).
SLAVE_CNF_RUNTIME="/etc/mysql/stack2-slave.cnf"
cp "$SCRIPT_DIR/slave.cnf" "$SLAVE_CNF_RUNTIME"
chmod 600 "$SLAVE_CNF_RUNTIME"
chown root:root "$SLAVE_CNF_RUNTIME"
mysqld --defaults-file="$SLAVE_CNF_RUNTIME" --user=mysql &
SLAVE_PID=$!
disown $SLAVE_PID

# Wait for slave to accept connections (try both with and without password)
info "Waiting for slave to accept connections (up to 60 seconds)..."
SLAVE_READY=false
for i in $(seq 1 30); do
    if mysql --socket=/var/run/mysqld/mysqld-slave.sock -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1" &>/dev/null 2>&1; then
        SLAVE_READY=true
        break
    fi
    if mysql --socket=/var/run/mysqld/mysqld-slave.sock -u root -e "SELECT 1" &>/dev/null 2>&1; then
        SLAVE_READY=true
        break
    fi
    # Check if the process is still alive (may have crashed)
    if ! kill -0 "$SLAVE_PID" 2>/dev/null && ! pgrep -f "mysqld.*mysql-slave" &>/dev/null; then
        fail "Slave mysqld process died unexpectedly."
        fail "Check: sudo tail -50 /var/log/mysql/error-slave.log"
        exit $EXIT_ERROR
    fi
    sleep 2
done

if [[ $SLAVE_READY == false ]]; then
    fail "Slave failed to accept connections within 60 seconds."
    fail "Check: sudo tail -50 /var/log/mysql/error-slave.log"
    exit $EXIT_ERROR
fi
pass "Slave is running on port $SLAVE_PORT (PID: $SLAVE_PID)"

# -----------------------------------------------------------------------
# Step 6: Configure slave replication
# -----------------------------------------------------------------------
step 6 "Configure slave -- connect to master"

# Stop any previous replication
slave_sql "STOP SLAVE;" 2>/dev/null || true
slave_sql "RESET SLAVE ALL;" 2>/dev/null || true

# Configure GTID replication
slave_sql "
CHANGE MASTER TO
    MASTER_HOST='127.0.0.1',
    MASTER_PORT=${MASTER_PORT},
    MASTER_USER='${REPLICATION_USER}',
    MASTER_PASSWORD='${REPLICATION_PASSWORD}',
    MASTER_AUTO_POSITION=1;
START SLAVE;
"
pass "Slave configured with GTID auto-positioning"

# Grant read-only access to app user on slave (replication will create the
# database and tables -- the user is needed for read queries)
# Use mysql_native_password for PHP PDO compatibility (same as master user)
slave_sql "
CREATE USER IF NOT EXISTS '${APP_USER}'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${APP_PASSWORD}';
ALTER USER '${APP_USER}'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${APP_PASSWORD}';
GRANT SELECT ON ${APP_DB}.* TO '${APP_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
" 2>/dev/null || true
pass "Read-only app user configured on slave"

# -----------------------------------------------------------------------
# Step 7: Verify replication
# -----------------------------------------------------------------------
step 7 "Verify replication status"

# Wait for replication threads to start (may take a few seconds after CHANGE MASTER)
info "Waiting for replication threads to start..."
REPL_OK=false
for _r in $(seq 1 10); do
    sleep 3
    SLAVE_STATUS=$(slave_sql "SHOW SLAVE STATUS\G" 2>/dev/null)
    SLAVE_IO=$(echo  "$SLAVE_STATUS" | grep "Slave_IO_Running:"  | awk '{print $2}')
    SLAVE_SQL_ST=$(echo "$SLAVE_STATUS" | grep "Slave_SQL_Running:" | awk '{print $2}')
    if [[ "$SLAVE_IO" == "Yes" && "$SLAVE_SQL_ST" == "Yes" ]]; then
        REPL_OK=true
        break
    fi
done

SLAVE_BEHIND=$(echo "$SLAVE_STATUS" | grep "Seconds_Behind_Master:" | awk '{print $2}')
SLAVE_ERROR=$(echo  "$SLAVE_STATUS" | grep "Last_Error:" | cut -d: -f2- | xargs)

if [[ "$REPL_OK" == true ]]; then
    pass "Replication is running"
    info "  Slave_IO_Running:      $SLAVE_IO"
    info "  Slave_SQL_Running:     $SLAVE_SQL_ST"
    info "  Seconds_Behind_Master: $SLAVE_BEHIND"
else
    warn "Replication threads not yet running:"
    warn "  Slave_IO_Running:  $SLAVE_IO"
    warn "  Slave_SQL_Running: $SLAVE_SQL_ST"
    [[ -n "$SLAVE_ERROR" ]] && warn "  Last_Error: $SLAVE_ERROR"
    warn "Check: mysql --socket=/var/run/mysqld/mysqld-slave.sock -u root -e 'SHOW SLAVE STATUS\\G'"
fi

# Write replication test: insert on master, read on slave
info "Testing replication with a write..."
master_sql "
CREATE DATABASE IF NOT EXISTS ${APP_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS ${APP_DB}._repl_test (id INT PRIMARY KEY);
INSERT IGNORE INTO ${APP_DB}._repl_test VALUES (1);
" 2>/dev/null || true
sleep 2
CHECK=$(mysql --socket=/var/run/mysqld/mysqld-slave.sock -u root \
    -Nse "SELECT COUNT(*) FROM ${APP_DB}._repl_test WHERE id=1;" 2>/dev/null || echo "0")
if [[ "$CHECK" == "1" ]]; then
    pass "Replication test passed -- data visible on slave"
else
    warn "Replication test data not visible on slave yet -- replication may still be catching up"
fi

sep
log ""
log "${GREEN}  MySQL master-slave replication setup complete.${NC}"
log "  Master socket: /var/run/mysqld/mysqld.sock (port $MASTER_PORT)"
log "  Slave  socket: /var/run/mysqld/mysqld-slave.sock (port $SLAVE_PORT)"
log ""

