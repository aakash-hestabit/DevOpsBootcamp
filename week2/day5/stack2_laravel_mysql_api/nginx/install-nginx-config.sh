#!/bin/bash
set -euo pipefail

# Script: install-nginx-config.sh
# Description: Installs Nginx (if not present), deploys the stack2.conf
#              virtual host, and enables the site.
# Author: Aakash
# Date: 2026-03-01
# Usage: sudo bash nginx/install-nginx-config.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_SRC="$SCRIPT_DIR/stack2.conf"
CONF_DEST="/etc/nginx/sites-available/stack2.conf"
LINK_DEST="/etc/nginx/sites-enabled/stack2.conf"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "$1"; }
pass() { log "${GREEN}  [OK]   $1${NC}"; }
info() { log "${BLUE}  [INFO] $1${NC}"; }
fail() { log "${RED}  [FAIL] $1${NC}"; }

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (sudo)."
    exit 1
fi

# Step 1: Install Nginx if not present
if ! command -v nginx &>/dev/null; then
    info "Installing Nginx..."
    apt-get update -qq && apt-get install -y -qq nginx
    pass "Nginx installed"
else
    pass "Nginx already installed: $(nginx -v 2>&1)"
fi

# Step 2: Create required directories
mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

# Step 3: Copy config
info "Installing stack2.conf..."
cp "$CONF_SRC" "$CONF_DEST"
pass "Config copied to $CONF_DEST"

# Step 4: Enable site (symlink)
if [[ -L "$LINK_DEST" ]]; then
    rm "$LINK_DEST"
fi
ln -s "$CONF_DEST" "$LINK_DEST"
pass "Site enabled via symlink"

# Step 5: Remove default site (if it exists and conflicts)
if [[ -L /etc/nginx/sites-enabled/default ]]; then
    rm /etc/nginx/sites-enabled/default
    info "Removed default site to avoid port 80 conflict"
fi

# Step 6: Test configuration
info "Testing Nginx configuration..."
if nginx -t 2>&1; then
    pass "Nginx config test passed"
else
    fail "Nginx config test FAILED — check syntax"
    exit 1
fi

# Step 7: Reload or start Nginx
if systemctl is-active --quiet nginx; then
    systemctl reload nginx
    pass "Nginx reloaded"
else
    systemctl start nginx
    systemctl enable nginx
    pass "Nginx started and enabled"
fi

log ""
pass "Nginx is serving stack2 at https://stack2.devops.local"
log ""
