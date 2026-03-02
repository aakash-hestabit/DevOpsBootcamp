#!/bin/bash
set -euo pipefail

# Script: install-nginx-config.sh
# Description: Install and configure Nginx for Stack 3 load balancer
# Author: Aakash
# Date: 2026-03-02
# Usage: sudo ./install-nginx-config.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NGINX_CONF="$SCRIPT_DIR/stack3.conf"

echo "Installing Nginx configuration for Stack 3..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (sudo)"
    exit 1
fi

# Install Nginx if not present
if ! command -v nginx &>/dev/null; then
    echo "Installing Nginx..."
    apt-get update -qq
    apt-get install -y nginx
fi

# Create cache directory
mkdir -p /var/cache/nginx/stack3
chown www-data:www-data /var/cache/nginx/stack3

# Copy configuration
cp "$NGINX_CONF" /etc/nginx/sites-available/stack3.conf

# Enable site (create symlink)
ln -sf /etc/nginx/sites-available/stack3.conf /etc/nginx/sites-enabled/stack3.conf

# Test configuration
echo "Testing Nginx configuration..."
if nginx -t; then
    echo "Configuration valid"
else
    echo "Error: Nginx configuration test failed"
    exit 1
fi

# Reload Nginx
systemctl reload nginx 2>/dev/null || systemctl restart nginx

# Add to /etc/hosts if not present
if ! grep -q "stack3.devops.local" /etc/hosts; then
    echo "127.0.0.1  stack3.devops.local" >> /etc/hosts
    echo "Added stack3.devops.local to /etc/hosts"
fi

echo ""
echo "Nginx configuration installed successfully"
echo "  Site available: /etc/nginx/sites-available/stack3.conf"
echo "  Site enabled:   /etc/nginx/sites-enabled/stack3.conf"
echo "  Access URL:     https://stack3.devops.local"
