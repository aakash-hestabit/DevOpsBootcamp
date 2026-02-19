#!/bin/bash
set -euo pipefail

# Script: performance_tuning.sh
# Description: Applies production performance tuning for Node.js, Python, and PHP
# Author: Aakash
# Date: 2026-02-19
# Usage: sudo ./performance_tuning.sh

readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

LOG_DIR="var/log/apps"
LOG_FILE="${LOG_DIR}/performance_tuning.log"
BACKUP_DIR="/var/backups/runtime-performance"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

RUNTIME_USER="${SUDO_USER:-$USER}"
RUNTIME_HOME="$(getent passwd "$RUNTIME_USER" | cut -d: -f6)"

# Logging
log_info() {
    echo "[$(date '+%F %T')] [INFO] $1" | tee -a "$LOG_FILE"
}

# Backup helper
backup_file() {
    local file="$1"
    [[ -f "$file" ]] && cp "$file" "$BACKUP_DIR/$(basename "$file").$(date '+%Y%m%d%H%M%S').bak"
}

# NODE.JS
tune_node() {
    log_info "Applying Node.js performance tuning"

    local node_env="/etc/profile.d/node-options.sh"
    backup_file "$node_env"

    cat <<EOF > "$node_env"
# Node.js performance tuning
export NODE_OPTIONS="--max-old-space-size=4096 --max-http-header-size=16384"
EOF

    chmod 644 "$node_env"
    log_info "NODE_OPTIONS exported system-wide via $node_env"
}

#  PYTHON 
tune_python() {
    log_info "Applying Python performance tuning for user: $RUNTIME_USER"

    local bashrc="${RUNTIME_HOME}/.bashrc"
    backup_file "$bashrc"

    grep -q "Python performance tuning" "$bashrc" || cat <<EOF >> "$bashrc"

# >>> Python performance tuning >>>
export PYTHONOPTIMIZE=1
export PYTHONUNBUFFERED=1
# <<< Python performance tuning <<<
EOF

    log_info "Python environment variables added to $bashrc"
}

# PHP
tune_php() {
    log_info "Applying PHP performance tuning"

    for sapi in cli fpm; do
        for dir in /etc/php/*/$sapi/conf.d; do
            [[ -d "$dir" ]] || continue

            local ini="$dir/99-performance.ini"
            backup_file "$ini"

            cat <<EOF > "$ini"
; PHP Performance Tuning
memory_limit = 256M
max_execution_time = 300

opcache.enable = 1
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 10000
opcache.validate_timestamps = 1
EOF
        done
    done

    systemctl restart php*-fpm 2>/dev/null || true
    log_info "PHP performance tuning applied and PHP-FPM restarted"
}

#  MAIN 
main() {
    log_info "Performance tuning started"

    tune_node
    tune_python
    tune_php

    log_info "Performance tuning completed successfully"
    echo "Performance tuning applied. Backups stored in $BACKUP_DIR"
}

main "$@"
