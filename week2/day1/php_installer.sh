#!/bin/bash
set -euo pipefail

# Script: php_installer.sh
# Description: Installs multiple PHP versions, configures php-fpm, installs Composer
# Author: Aakash
# Date: 2026-02-18
# Usage: ./php_installer.sh

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
LOG_DIR="var/log/apps"
LOG_FILE="${LOG_DIR}/php_installer.log"

PHP_VERSIONS=("7.4" "8.1" "8.2" "8.3")
DEFAULT_PHP_VERSION="8.2"
PHP_INI_TEMPLATE_DIR="/etc/php/templates"

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
    log_info "Installing PHP dependencies"
    sudo apt update -y
    sudo apt install -y \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        lsb-release \
        curl \
        unzip
}

# Add Ondrej PHP repository
add_php_repository() {
    if ! grep -Rq "ondrej/php" /etc/apt/sources.list.d; then
        log_info "Adding Ondrej PHP repository"
        sudo add-apt-repository -y ppa:ondrej/php
        sudo apt update -y
    else
        log_info "Ondrej PHP repository already exists"
    fi
}

# Install PHP versions
install_php_versions() {
    for version in "${PHP_VERSIONS[@]}"; do
        log_info "Installing PHP ${version}"
        sudo apt install -y \
            php${version} \
            php${version}-cli \
            php${version}-fpm \
            php${version}-common \
            php${version}-curl \
            php${version}-mbstring \
            php${version}-xml \
            php${version}-zip \
            php${version}-mysql \
            php${version}-opcache
    done
}

# Set default PHP version
set_default_php() {
    log_info "Setting PHP ${DEFAULT_PHP_VERSION} as default"

    sudo update-alternatives --set php /usr/bin/php${DEFAULT_PHP_VERSION}
    sudo update-alternatives --set phar /usr/bin/phar${DEFAULT_PHP_VERSION}
    sudo update-alternatives --set phar.phar /usr/bin/phar.phar${DEFAULT_PHP_VERSION}
}

# Configure php-fpm
configure_php_fpm() {
    log_info "Configuring php-fpm for PHP ${DEFAULT_PHP_VERSION}"

    sudo systemctl enable php${DEFAULT_PHP_VERSION}-fpm
    sudo systemctl restart php${DEFAULT_PHP_VERSION}-fpm
}

# Create php.ini templates
create_php_ini_templates() {
    log_info "Creating php.ini templates"

    sudo mkdir -p "$PHP_INI_TEMPLATE_DIR"

    for version in "${PHP_VERSIONS[@]}"; do
        sudo tee "${PHP_INI_TEMPLATE_DIR}/php-${version}.ini" > /dev/null <<EOF
; PHP ${version} Template
date.timezone = UTC
memory_limit = 256M
upload_max_filesize = 50M
post_max_size = 50M
max_execution_time = 60
display_errors = Off
log_errors = On
EOF
    done
}

# Install Composer
install_composer() {
    if command -v composer &>/dev/null; then
        log_info "Composer already installed"
    else
        log_info "Installing Composer globally"
        curl -sS https://getcomposer.org/installer | php
        sudo mv composer.phar /usr/local/bin/composer
        sudo chmod +x /usr/local/bin/composer
    fi
}

# Verify installation
verify_installation() {
    log_info "Verifying PHP and Composer installation"

    php --version | tee -a "$LOG_FILE"
    composer --version | tee -a "$LOG_FILE"
}

# Main
main() {
    log_info "PHP installer started"

    install_dependencies
    add_php_repository
    install_php_versions
    set_default_php
    configure_php_fpm
    create_php_ini_templates
    install_composer
    verify_installation

    log_info "PHP installer completed successfully"
    echo "========== PHP INSTALLATION COMPLETED =========="
}

main "$@"
