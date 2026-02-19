#!/bin/bash
set -euo pipefail

# Script: node_installer.sh
# Description: Installs NVM and multiple Node.js versions and sets default
# Author: Aakash 
# Date: 2026-02-18
# Usage: ./node_installer.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="var/log/apps"
LOG_FILE="${LOG_DIR}/node_installer.log"

# Node versions
NODE_VERSIONS=("18.19.0" "20.11.0" "22.0.0")
DEFAULT_NODE_VERSION="20.11.0"
NVM_VERSION="v0.40.4"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2
}

# Help function
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Installs NVM and Node.js versions:
  - v18.19.0
  - v20.11.0 (default)
  - v22.0.0

OPTIONS:
  -h, --help      Show this help message

Examples:
  ./$(basename "$0")
EOF
}

# Load NVM into current shell
load_nvm() {
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1091
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
}

# Install NVM
install_nvm() {
    if [[ -d "$HOME/.nvm" ]]; then
        log_info "nvm already installed"
    else
        log_info "Installing nvm..."
        echo "Installing nvm..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash
        log_info "nvm installed successfully"
        echo "nvm installed successfully"
    fi
}

# Install Node versions
install_node_versions() {
    for version in "${NODE_VERSIONS[@]}"; do
        log_info "Installing Node.js v${version}..."
        echo "Installing Node.js v${version}..."
        nvm install "$version"
        log_info "Node.js v${version} installed"
        echo "Node.js v${version} installed"
    done
}

# Set default Node version
set_default_node() {
    log_info "Setting Node.js v${DEFAULT_NODE_VERSION} as default..."
    nvm alias default "$DEFAULT_NODE_VERSION"
    nvm use default
}

# Create .nvmrc
create_nvmrc() {
    echo "v${DEFAULT_NODE_VERSION}" > "$HOME/.nvmrc"
    log_info ".nvmrc created with default version v${DEFAULT_NODE_VERSION}"
}

# Verify installation
verify_installation() {
    log_info "Verifying Node.js installation..."
    node --version | tee -a "$LOG_FILE"
    npm --version | tee -a "$LOG_FILE"
}

# Pretty output
print_versions() {
    cat << EOF

Node versions available:
$(nvm ls | sed 's/^/  /')
EOF
}

# Main function
main() {
    log_info "Script started"
    echo "========== NODE.JS INSTALLATION =========="
    install_nvm
    load_nvm
    install_node_versions
    set_default_node
    create_nvmrc
    verify_installation
    echo "=========================================="
    print_versions
    

    log_info "Script completed successfully"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit $EXIT_SUCCESS
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit $EXIT_ERROR
            ;;
    esac
    shift
done

main "$@"
