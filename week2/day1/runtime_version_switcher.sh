#!/bin/bash
set -euo pipefail

# Script: runtime_version_switcher.sh
# Description: Interactive runtime version switcher for Node.js, Python, and PHP
# Author: Aakash
# Date: 2026-02-18
# Usage: ./runtime_version_switcher.sh

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
LOG_DIR="var/log/apps"
LOG_FILE="${LOG_DIR}/runtime_version_switcher.log"

mkdir -p "$LOG_DIR"

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2
}

# Load NVM
load_nvm() {
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1091
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
}

# Load pyenv
load_pyenv() {
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init - bash)"
}

# Current versions
current_node() {
    node --version 2>/dev/null || echo "not installed"
}

current_python() {
    python --version 2>/dev/null | awk '{print $2}' || echo "not installed"
}

current_php() {
    php --version 2>/dev/null | head -n1 | awk '{print $2}' || echo "not installed"
}

# Switch Node.js
switch_node() {
    load_nvm

    mapfile -t versions < <(nvm ls node --no-colors | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+' | sort -uV)
    [[ ${#versions[@]} -eq 0 ]] && { log_error "No Node.js versions found"; return; }

    echo "Available Node versions:"
    select version in "${versions[@]}"; do
        [[ -n "$version" ]] || { echo "Invalid selection"; continue; }
        nvm use "$version"
        nvm alias default "$version"
        log_info "Switched Node.js to $version (and set as default)"
        echo "Switched to Node.js $version (and set as default)"
        node --version
        break
    done
}

# Switch Python
switch_python() {
    load_pyenv

    mapfile -t versions < <(pyenv versions --bare)
    [[ ${#versions[@]} -eq 0 ]] && { log_error "No Python versions found"; return; }

    echo "Available Python versions:"
    select version in "${versions[@]}"; do
        [[ -n "$version" ]] || { echo "Invalid selection"; continue; }
        pyenv global "$version"
        log_info "Switched Python to $version"
        echo "Switched to Python $version"
        python --version
        break
    done
}

# Switch PHP
switch_php() {
    log_info "Collecting PHP patch versions..."

    mapfile -t versions < <(
        for bin in /usr/bin/php[0-9]*.[0-9]*; do
            [[ -x "$bin" ]] || continue
            "$bin" -v | head -n1 | awk '{print $2}'
        done | sort -uV
    )

    [[ ${#versions[@]} -eq 0 ]] && { log_error "No PHP versions found"; return; }

    echo "Available PHP versions:"
    select version in "${versions[@]}"; do
        [[ -n "$version" ]] || { echo "Invalid selection"; continue; }
        
        short_ver=$(echo "$version" | grep -oE '^[0-9]+\.[0-9]+')

        sudo update-alternatives --set php "/usr/bin/php${short_ver}"
        
        log_info "Switched PHP to $version (Binary: $short_ver)"
        echo "Successfully switched to PHP $version"
        php --version | head -n1
        break
    done
}

# Show all versions
show_all_versions() {
    echo "========== INSTALLED RUNTIME VERSIONS =========="

    echo "Node.js:"
    load_nvm
    nvm ls || echo "nvm not available"

    echo
    echo "Python:"
    load_pyenv
    pyenv versions || echo "pyenv not available"

    echo
    echo "PHP:"
    update-alternatives --list php 2>/dev/null || echo "PHP not available"

    echo "==============================================="
}

# Menu
show_menu() {
    echo
    echo "Select runtime to switch:"
    echo "1) Node.js (current: $(current_node))"
    echo "2) Python (current: $(current_python))"
    echo "3) PHP (current: $(current_php))"
    echo "4) Show all versions"
    echo "5) Exit"
    echo
    read -rp "Choice: " choice
}

# Main
main() {
    log_info "Runtime version switcher started"

    while true; do
        show_menu
        case "$choice" in
            1) switch_node ;;
            2) switch_python ;;
            3) switch_php ;;
            4) show_all_versions ;;
            5)
                log_info "Exiting runtime version switcher"
                exit $EXIT_SUCCESS
                ;;
            *)
                echo "Invalid option"
                ;;
        esac
    done
}

main "$@"
