#!/bin/bash
set -euo pipefail

# Script: docker_installer.sh
# Description: Installs Docker Engine from official repository, configures non-root access,
#              sets logging limits, and verifies installation.
# Author: Aakash
# Date: 2026-03-03
# Usage: ./docker_installer.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/$(basename $0 .sh).log"
DOCKER_DAEMON_FILE="/etc/docker/daemon.json"
DOCKER_USER="${SUDO_USER:-$USER}"

mkdir -p "var/log/apps"
chown -R aakash:aakash "var"

# Logging functions
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }

# Help function
show_usage() {
    cat << EOF
Usage: $(basename $0) [OPTIONS]

Installs Docker Engine from official repository and configures:
- Non-root docker access
- json-file logging with size limits
- Service verification

OPTIONS:
    -h, --help      Show this help message

Example:
    sudo ./$(basename $0)
EOF
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root."
        exit $EXIT_ERROR
    fi
}

install_dependencies() {
    log_info "Installing required packages..."
    apt update -y
    apt install -y ca-certificates curl
}

setup_repository() {
    log_info "Setting up Docker official repository..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    apt update -y
}

install_docker() {
    log_info "Installing Docker Engine..."
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

configure_user_access() {
    log_info "Adding user '$DOCKER_USER' to docker group..."
    groupadd -f docker
    usermod -aG docker "$DOCKER_USER"
}

configure_logging() {
    log_info "Configuring Docker daemon logging..."

    mkdir -p /etc/docker

    cat > "$DOCKER_DAEMON_FILE" <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

    systemctl restart docker
}

verify_installation() {
    log_info "Verifying Docker service..."
    systemctl enable docker
    systemctl start docker

    if systemctl is-active --quiet docker; then
        log_info "Docker service is active and running"
    else
        log_error "Docker service failed to start"
        exit $EXIT_ERROR
    fi

    DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
}

print_summary() {
    echo
    echo "========== DOCKER INSTALLATION =========="
    echo " Docker Engine installed (version $DOCKER_VERSION)"
    echo " User '$DOCKER_USER' added to docker group"
    echo " Docker service is active and running"
    echo " Docker daemon configured with json-file logging"
    echo
    echo "Docker Version:"
    docker version
    echo "=========================================="
}

# Main function
main() {
    require_root
    mkdir -p /var/log/apps

    log_info "Docker installation started"

    install_dependencies
    setup_repository
    install_docker
    configure_user_access
    configure_logging
    verify_installation
    print_summary

    log_info "Docker installation completed successfully"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit $EXIT_SUCCESS
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit $EXIT_ERROR
            ;;
    esac
    shift
done

main "$@"
exit $EXIT_SUCCESS