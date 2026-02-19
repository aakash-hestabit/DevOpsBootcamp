#!/bin/bash
set -euo pipefail

# Script: runtime_audit.sh
# Description: Audits installed runtime versions and generates a report
# Author: Aakash
# Date: 2026-02-18
# Usage: ./runtime_audit.sh

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
LOG_DIR="var/log/apps"
LOG_FILE="${LOG_DIR}/runtime_audit.log"
REPORT_DIR="reports"
REPORT_FILE="${REPORT_DIR}/runtime_audit_report.txt"

mkdir -p "$REPORT_DIR"
mkdir -p "$LOG_DIR"

# Latest LTS baseline
LATEST_NODE_LTS="20.11.0"
LATEST_PYTHON_LTS="3.11.7"
LATEST_PHP_LTS="8.2.15"

# Logging
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"
}

# Load nvm
load_nvm() {
    export NVM_DIR="$HOME/.nvm"
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
}

# Load pyenv
load_pyenv() {
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init - bash)"
}

# Version status helper
version_status() {
    local current="$1"
    local lts="$2"

    if [[ "$current" == "$lts" ]]; then
        echo "OK"
    elif [[ "$(printf '%s\n%s\n' "$current" "$lts" | sort -V | head -n1)" == "$current" ]]; then
        echo "OUTDATED"
    else
        echo "NEWER"
    fi
}

# Audit Node.js
audit_node() {
    load_nvm 2>/dev/null || true
    NODE_VERSIONS=$(nvm ls node --no-colors 2>/dev/null | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+' | sed 's/^v//' | tr '\n' ',' | sed 's/,$//')
    NODE_DEFAULT=$(node --version 2>/dev/null | sed 's/^v//' || echo "N/A")
    NODE_PATH="$HOME/.nvm/versions"
    NODE_STATUS=$(version_status "$NODE_DEFAULT" "$LATEST_NODE_LTS")
}

# Audit Python
audit_python() {
    load_pyenv 2>/dev/null || true
    PYTHON_VERSIONS=$(pyenv versions --bare 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    PYTHON_DEFAULT=$(python --version 2>/dev/null | awk '{print $2}' || echo "N/A")
    PYTHON_PATH="$HOME/.pyenv/versions"
    PYTHON_STATUS=$(version_status "$PYTHON_DEFAULT" "$LATEST_PYTHON_LTS")
}

# Audit PHP (PATCH-AWARE)
audit_php() {
    PHP_VERSIONS=$(
        for bin in /usr/bin/php[0-9]*.[0-9]*; do
            [[ -x "$bin" ]] || continue
            "$bin" -v | head -n1 | awk '{print $2}'
        done | tr '\n' ',' | sed 's/,$//'
    )

    PHP_DEFAULT=$(php --version 2>/dev/null | head -n1 | awk '{print $2}' || echo "N/A")
    PHP_PATH="/usr/bin/php*"
    PHP_STATUS=$(version_status "$PHP_DEFAULT" "$LATEST_PHP_LTS")
}

# Generate report
generate_report() {
    {
        echo "RUNTIME AUDIT REPORT"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "=============================================================="
        printf "%-8s | %-30s | %-10s | %-10s | %s\n" "RUNTIME" "INSTALLED VERSIONS" "DEFAULT" "STATUS" "PATH"
        echo "---------|--------------------------------|------------|------------|------------------"
        printf "%-8s | %-30s | %-10s | %-10s | %s\n" "Node.js" "$NODE_VERSIONS" "$NODE_DEFAULT" "$NODE_STATUS" "$NODE_PATH"
        printf "%-8s | %-30s | %-10s | %-10s | %s\n" "Python"  "$PYTHON_VERSIONS" "$PYTHON_DEFAULT" "$PYTHON_STATUS" "$PYTHON_PATH"
        printf "%-8s | %-30s | %-10s | %-10s | %s\n" "PHP"     "$PHP_VERSIONS" "$PHP_DEFAULT" "$PHP_STATUS" "$PHP_PATH"
        echo
        echo "LTS BASELINE"
        echo "Node.js  : $LATEST_NODE_LTS"
        echo "Python   : $LATEST_PYTHON_LTS"
        echo "PHP      : $LATEST_PHP_LTS"
    } | tee "$REPORT_FILE"
}

# Main
main() {
    log_info "Runtime audit started"

    audit_node
    audit_python
    audit_php
    generate_report

    log_info "Runtime audit completed"
    log_info "Report generated: $REPORT_FILE"
}

main "$@"
