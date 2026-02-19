#!/bin/bash
set -euo pipefail

# Script: performance_tuning.sh
# Description: Applies performance tuning for Node.js, Python, and PHP runtimes
# Author: Aakash
# Date: 2026-02-19
# Usage: sudo ./performance_tuning.sh

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
LOG_DIR="var/log/apps"
LOG_FILE="${LOG_DIR}/performance_tuning.log"
BACKUP_DIR="/var/backups/runtime-performance"

NODE_OPTIONS_FILE="/etc/node-options"
PYTHON_BASHRC="$HOME/.bashrc"
PHP_INI_TUNED="/etc/php/performance-tuned.ini"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

# Logging
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2
}

# Backup helper
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp "$file" "$BACKUP_DIR/$(basename "$file").$(date '+%Y%m%d%H%M%S').bak"
        log_info "Backup created for $file"
    fi
}

# ===== NODE.JS TUNING =====
tune_node() {
    log_info "Applying Node.js performance tuning"

    backup_file "$NODE_OPTIONS_FILE"

    sudo tee "$NODE_OPTIONS_FILE" > /dev/null <<EOF
--max-old-space-size=4096
--max-http-header-size=16384
EOF

    log_info "Node.js options written to $NODE_OPTIONS_FILE"
}

# ===== PYTHON TUNING =====
tune_python() {
    log_info "Applying Python performance tuning"

    backup_file "$PYTHON_BASHRC"

    grep -q "PYTHONOPTIMIZE" "$PYTHON_BASHRC" || cat << 'EOF' >> "$PYTHON_BASHRC"

# >>> Python performance tuning >>>
export PYTHONOPTIMIZE=1
export PYTHONUNBUFFERED=1
# <<< Python performance tuning <<<
EOF

    log_info "Python environment variables configured in ~/.bashrc"
}

# ===== PHP TUNING =====
tune_php() {
    log_info "Applying PHP performance tuning"

    backup_file "$PHP_INI_TUNED"

    sudo tee "$PHP_INI_TUNED" > /dev/null <<EOF
; PHP Performance Tuning
memory_limit = 256M
max_execution_time = 300

opcache.enable = 1
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 10000
opcache.validate_timestamps = 1
EOF

    log_info "Optimized PHP configuration written to $PHP_INI_TUNED"
    log_info "You may include this file in active php.ini configurations"
}

# ===== MAIN =====
main() {
    log_info "Performance tuning started"

    tune_node
    tune_python
    tune_php

    log_info "Performance tuning completed successfully"
    echo "Performance tuning applied. Backups stored in $BACKUP_DIR"
}

main "$@"
