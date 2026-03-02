#!/bin/bash
set -euo pipefail

# Script: install-nginx-config.sh
# Description: Install Nginx and deploy the Stack 1 load balancer configuration.
#              Enables the site, disables the Nginx default, validates the config,
#              and reloads (or starts) Nginx. Requires root (sudo).
# Author: Aakash
# Date: 2026-03-01
# Usage: sudo ./install-nginx-config.sh [--help]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/nginx/install-nginx-config.log"
NGINX_AVAILABLE="/etc/nginx/sites-available/stack1.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/stack1.conf"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info()  { mkdir -p "$(dirname "$LOG_FILE")"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE"; }
log_error() { mkdir -p "$(dirname "$LOG_FILE")"; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2; }

# Help function
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Install Nginx and deploy the Stack 1 load balancer configuration.

OPTIONS:
    -h, --help    Show this help message

EXAMPLES:
    sudo $(basename "$0")

WHAT IT DOES:
    1. Installs Nginx (skips if already installed)
    2. Copies stack1.conf to /etc/nginx/sites-available/
    3. Enables the site and disables the default
    4. Tests the configuration with nginx -t
    5. Reloads or starts Nginx
EOF
}

# Main function
main() {
    log_info "Nginx setup started"

    echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║    Nginx Setup — Stack 1 Load Balancer               ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Nginx writes config to /etc/nginx/ so root is required
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root. Use: sudo $0"
        exit $EXIT_ERROR
    fi

    # Step 1: Install Nginx if not already present
    echo -e "${YELLOW}[1/5] Installing Nginx...${NC}"
    if ! command -v nginx &>/dev/null; then
        apt-get update -q
        apt-get install -y nginx
        log_info "Nginx installed: $(nginx -v 2>&1)"
        echo -e "${GREEN}  Nginx installed: $(nginx -v 2>&1)${NC}"
    else
        log_info "Nginx already installed: $(nginx -v 2>&1)"
        echo -e "${GREEN}  Nginx already installed: $(nginx -v 2>&1)${NC}"
    fi

    # Step 2: Copy our stack1.conf to sites-available
    echo -e "${YELLOW}[2/5] Deploying stack1.conf...${NC}"
    cp "$SCRIPT_DIR/stack1.conf" "$NGINX_AVAILABLE"
    log_info "Config copied to $NGINX_AVAILABLE"
    echo -e "${GREEN}  Config copied to $NGINX_AVAILABLE${NC}"

    # Step 3: Enable the site and remove the default welcome page
    echo -e "${YELLOW}[3/5] Enabling site...${NC}"
    ln -sf "$NGINX_AVAILABLE" "$NGINX_ENABLED"
    if [[ -L /etc/nginx/sites-enabled/default ]]; then
        rm /etc/nginx/sites-enabled/default
        log_info "Default Nginx site disabled"
        echo -e "${GREEN}  Default site disabled${NC}"
    fi
    echo -e "${GREEN}  stack1.conf enabled${NC}"

    # Step 4: Validate the config before reloading — fail fast on syntax errors
    echo -e "${YELLOW}[4/5] Testing Nginx configuration...${NC}"
    if nginx -t; then
        log_info "Nginx config test passed"
        echo -e "${GREEN}  Configuration is valid${NC}"
    else
        log_error "Nginx configuration test failed — see output above"
        exit $EXIT_ERROR
    fi

    # Step 5: Reload if Nginx is running; otherwise start and enable it
    echo -e "${YELLOW}[5/5] Starting / Reloading Nginx...${NC}"
    if systemctl is-active --quiet nginx; then
        systemctl reload nginx
        log_info "Nginx reloaded"
        echo -e "${GREEN}  Nginx reloaded${NC}"
    else
        systemctl enable --now nginx
        log_info "Nginx started and enabled"
        echo -e "${GREEN}  Nginx started and enabled${NC}"
    fi

    # Pre-provision log files to avoid 403 on first access
    mkdir -p /var/log/nginx
    touch /var/log/nginx/stack1-access.log /var/log/nginx/stack1-error.log

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   Nginx Load Balancer Configured!                    ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  HTTP  --> https://stack1.devops.local  (redirect)"
    echo "  HTTPS --> https://stack1.devops.local"
    echo "  API   --> https://stack1.devops.local/api/"
    echo "  Docs  --> https://stack1.devops.local/api-docs"
    echo ""
    echo -e "${YELLOW}[TIP] If you haven't generated SSL certificates yet, run:${NC}"
    echo "  sudo $SCRIPT_DIR/setup-ssl.sh"
    echo ""
    echo -e "${YELLOW}Useful Nginx commands:${NC}"
    echo "  sudo nginx -t                           # test config"
    echo "  sudo systemctl reload nginx             # apply config changes"
    echo "  sudo systemctl status nginx             # service status"
    echo "  sudo tail -f /var/log/nginx/stack1-access.log"
    echo ""

    log_info "Nginx setup completed successfully"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_usage; exit $EXIT_SUCCESS ;;
        *) log_error "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
