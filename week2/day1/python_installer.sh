#!/bin/bash
set -euo pipefail

# Script: python_installer.sh
# Description: Install pyenv, multiple Python versions, and virtual environment tooling
# Author: Aakash
# Date: 2026-02-18
# Usage: ./python_installer.sh

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="var/log/apps"
LOG_FILE="${LOG_DIR}/python_installer.log"

PYTHON_VERSIONS=("3.9.18" "3.10.13" "3.11.7" "3.12.1")
DEFAULT_PYTHON_VERSION="3.11.7"
VENV_TEMPLATE_DIR="$HOME/python-venvs"

mkdir -p "$LOG_DIR"

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2
}

# Install system dependencies
install_dependencies() {
    log_info "Installing Python build dependencies"
    sudo apt update -y
    sudo apt install -y \
        make build-essential \
        libssl-dev \
        zlib1g-dev \
        libbz2-dev \
        libreadline-dev \
        libsqlite3-dev \
        curl git \
        libncursesw5-dev \
        xz-utils \
        tk-dev \
        libxml2-dev \
        libxmlsec1-dev \
        libffi-dev \
        liblzma-dev
}

# Install pyenv
install_pyenv() {
    if [[ -d "$HOME/.pyenv" ]]; then
        log_info "pyenv already installed"
    else
        log_info "Installing pyenv"
        curl -fsSL https://pyenv.run | bash
    fi
}

# Configure ~/.profile (login shells)
configure_profile() {
    log_info "Configuring ~/.profile for pyenv"

    grep -q 'pyenv initialization' ~/.profile 2>/dev/null || cat << 'EOF' >> ~/.profile

# >>> pyenv initialization >>>
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - bash)"
# <<< pyenv initialization <<<
EOF
}

# Configure ~/.bashrc (interactive shells, guarded)
configure_bashrc() {
    log_info "Configuring ~/.bashrc for pyenv (guarded)"

    grep -q 'pyenv initialization' ~/.bashrc 2>/dev/null || cat << 'EOF' >> ~/.bashrc

# >>> pyenv initialization >>>
if [[ $- == *i* ]] && [[ -z "${PYENV_SHELL_INITIALIZED:-}" ]]; then
    export PYENV_SHELL_INITIALIZED=1
    export PYENV_ROOT="$HOME/.pyenv"
    [[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init - bash)"
fi
# <<< pyenv initialization <<<
EOF
}

# Load pyenv into current shell
load_pyenv() {
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init - bash)"
}

# Install Python versions
install_python_versions() {
    for version in "${PYTHON_VERSIONS[@]}"; do
        if pyenv versions --bare | grep -q "^${version}$"; then
            log_info "Python ${version} already installed"
        else
            log_info "Installing Python ${version}"
            pyenv install "$version"
        fi
    done
}

# Set global Python version
set_global_python() {
    log_info "Setting Python ${DEFAULT_PYTHON_VERSION} as global default"
    pyenv global "$DEFAULT_PYTHON_VERSION"
}

# Install Python tools
install_python_tools() {
    log_info "Installing pip, virtualenv, pipenv"
    python -m pip install --upgrade pip
    python -m pip install virtualenv pipenv
    pyenv rehash
}

# Create virtual environment template   
create_venv_template() {
    log_info "Creating virtual environment template"
    mkdir -p "$VENV_TEMPLATE_DIR"
    python -m venv "${VENV_TEMPLATE_DIR}/base"
}

# Verify installation
verify_installation() {
    log_info "Verifying installation"
    python --version | tee -a "$LOG_FILE"
    pip --version | tee -a "$LOG_FILE"
}

# Main
main() {
    log_info "Python installer started"

    install_dependencies
    install_pyenv
    configure_profile
    configure_bashrc
    load_pyenv
    install_python_versions
    set_global_python
    install_python_tools
    create_venv_template
    verify_installation

    log_info "Python installer completed successfully"
}

main "$@"
