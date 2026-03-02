#!/bin/bash
set -euo pipefail

# Script: collect_configs.sh
# Description: Collects all configuration files from all 3 stacks into
#              the centralized configs/ directory for easy reference.
# Author: Aakash
# Date: 2026-03-02
# Usage: ./collect_configs.sh

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
DIM='\033[2m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS="$SCRIPT_DIR/configs"

mkdir -p "$CONFIGS"/{nginx,systemd,pm2,database/{mysql,mongodb},env,ssl,redis,logging,optimization}

log() { echo -e "  ${GREEN}✓${NC} $*"; }

echo -e "${BOLD}${BLUE}Collecting configs into $CONFIGS/${NC}"
echo ""

# Nginx
for f in stack1_next_node_mongodb/nginx/stack1.conf \
         stack2_laravel_mysql_api/nginx/stack2.conf \
         stack3_next_fastapi_mysql/nginx/stack3.conf; do
    [[ -f "$SCRIPT_DIR/$f" ]] && cp "$SCRIPT_DIR/$f" "$CONFIGS/nginx/" && log "nginx/$(basename $f)"
done
[[ -f "$SCRIPT_DIR/optimization/nginx_advanced.conf" ]] && cp "$SCRIPT_DIR/optimization/nginx_advanced.conf" "$CONFIGS/nginx/" && log "nginx/nginx_advanced.conf"

# Systemd
for f in "$SCRIPT_DIR"/stack2_laravel_mysql_api/systemd/*.service \
         "$SCRIPT_DIR"/stack3_next_fastapi_mysql/systemd/*.service; do
    [[ -f "$f" ]] && cp "$f" "$CONFIGS/systemd/" && log "systemd/$(basename $f)"
done

# PM2
for f in stack1_next_node_mongodb/pm2/ecosystem.config.js; do
    [[ -f "$SCRIPT_DIR/$f" ]] && cp "$SCRIPT_DIR/$f" "$CONFIGS/pm2/" && log "pm2/$(basename $f)"
done
[[ -f "$SCRIPT_DIR/stack3_next_fastapi_mysql/pm2/nextjs-ecosystem.config.js" ]] && \
    cp "$SCRIPT_DIR/stack3_next_fastapi_mysql/pm2/nextjs-ecosystem.config.js" "$CONFIGS/pm2/nextjs-ecosystem.config.js" && \
    log "pm2/nextjs-ecosystem.config.js"

# MySQL
for f in stack2_laravel_mysql_api/mysql/master.cnf \
         stack2_laravel_mysql_api/mysql/slave.cnf \
         stack3_next_fastapi_mysql/mysql/optimization.cnf; do
    [[ -f "$SCRIPT_DIR/$f" ]] && cp "$SCRIPT_DIR/$f" "$CONFIGS/database/mysql/" && log "database/mysql/$(basename $f)"
done

# MongoDB
for f in "$SCRIPT_DIR"/stack1_next_node_mongodb/mongodb-replicaset/config/*.conf; do
    [[ -f "$f" ]] && cp "$f" "$CONFIGS/database/mongodb/" && log "database/mongodb/$(basename $f)"
done

# Environment files
for f in stack1_next_node_mongodb/.env.production \
         stack1_next_node_mongodb/backend/.env.production \
         stack2_laravel_mysql_api/.env.example \
         stack3_next_fastapi_mysql/.env.production; do
    if [[ -f "$SCRIPT_DIR/$f" ]]; then
        local_name=$(echo "$f" | tr '/' '_')
        cp "$SCRIPT_DIR/$f" "$CONFIGS/env/$local_name" && log "env/$local_name"
    fi
done

# Redis
[[ -f "$SCRIPT_DIR/caching/redis.conf" ]] && cp "$SCRIPT_DIR/caching/redis.conf" "$CONFIGS/redis/" && log "redis/redis.conf"

# Logging
for f in logging/rsyslog.conf logging/logrotate.conf; do
    [[ -f "$SCRIPT_DIR/$f" ]] && cp "$SCRIPT_DIR/$f" "$CONFIGS/logging/" && log "logging/$(basename $f)"
done

# Optimization
for f in optimization/sysctl.conf optimization/nginx_advanced.conf; do
    [[ -f "$SCRIPT_DIR/$f" ]] && cp "$SCRIPT_DIR/$f" "$CONFIGS/optimization/" && log "optimization/$(basename $f)"
done

echo ""
echo -e "${GREEN}${BOLD}Config collection complete.${NC}"
echo -e "Total files: $(find "$CONFIGS" -type f | wc -l)"
