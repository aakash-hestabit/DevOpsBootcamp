#!/bin/bash

# Docker Performance Analysis Script
# Analyses image sizes, container startup times, resource usage, and disk usage
# Generates a timestamped performance report

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPORT_DIR="$SCRIPT_DIR/reports"
REPORT_FILE="$REPORT_DIR/performance-report-$(date +%Y%m%d).txt"

mkdir -p "$REPORT_DIR"

log() { echo "$*" | tee -a "$REPORT_FILE"; }
separator() { log ""; log "-----------------------------------------------"; log ""; }

# Header 
{
echo "========== Docker Performance Analysis =========="
echo "Analysis Date : $(date)"
echo "Hostname      : $(hostname)"
echo "Docker Version: $(docker --version 2>/dev/null || echo 'N/A')"
echo "================================================="
echo ""
} | tee "$REPORT_FILE"

#  Image Size Analysis 
log "IMAGE SIZE ANALYSIS"
log "-------------------"

if docker images --format "{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -qv "<none>"; then
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}" >> "$REPORT_FILE"

    separator

    log "TOP 10 LARGEST IMAGES"
    log "---------------------"
    docker images --format "{{.Size}}\t{{.Repository}}:{{.Tag}}" \
        | grep -v "<none>" \
        | sort -rh \
        | head -n 10 \
        | awk -F'\t' '{printf "  %-12s %s\n", $1, $2}' >> "$REPORT_FILE"
else
    log "  No Docker images found."
fi

separator

#  Container Resource Usage 
log "CONTAINER RESOURCE USAGE"
log "------------------------"

if docker ps -q 2>/dev/null | grep -q .; then
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" \
        >> "$REPORT_FILE"
else
    log "  No running containers found."
fi

separator

# Container Startup Time Analysis 
log "CONTAINER STARTUP TIMES"
log "-----------------------"

if docker ps -q 2>/dev/null | grep -q .; then
    printf "  %-35s %-30s %s\n" "CONTAINER" "STARTED_AT" "STATUS" >> "$REPORT_FILE"
    for CONTAINER in $(docker ps -q); do
        NAME=$(docker inspect --format='{{.Name}}' "$CONTAINER" | sed 's/\///')
        STARTED=$(docker inspect --format='{{.State.StartedAt}}' "$CONTAINER")
        STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER")
        HEALTH=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$CONTAINER" 2>/dev/null || echo "N/A")
        printf "  %-35s %-30s %s (health: %s)\n" "$NAME" "$STARTED" "$STATUS" "$HEALTH" >> "$REPORT_FILE"
    done

    separator

    # Measure response times for containers exposing common ports
    log "APPLICATION RESPONSE TIMES"
    log "-------------------------"
    TESTED=0
    for PORT in 80 443 3000 3001 5000 8080 8443 9090 9091; do
        if curl -sf --max-time 3 "http://localhost:$PORT" &>/dev/null; then
            RESPONSE_TIME=$(curl -o /dev/null -sf -w "%{time_total}" --max-time 5 "http://localhost:$PORT" 2>/dev/null || echo "timeout")
            log "  localhost:$PORT  -->  ${RESPONSE_TIME}s"
            TESTED=$((TESTED + 1))
        fi
    done
    if [[ $TESTED -eq 0 ]]; then
        log "  No HTTP endpoints found on common ports (80, 443, 3000, 3001, 5000, 8080, 8443, 9090, 9091)."
    fi
else
    log "  No running containers."
fi

separator

# Volume Disk Usage 
log "VOLUME DISK USAGE"
log "-----------------"

if docker volume ls -q 2>/dev/null | grep -q .; then
    docker system df -v 2>/dev/null | sed -n '/Local Volumes/,/^$/p' >> "$REPORT_FILE"
else
    log "  No Docker volumes found."
fi

separator

# Docker System Overview 
log "DOCKER SYSTEM OVERVIEW"
log "----------------------"
docker system df 2>/dev/null >> "$REPORT_FILE" || log "  Unable to retrieve system disk usage."

separator

# Network Overview 
log "DOCKER NETWORKS"
log "---------------"
docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}" 2>/dev/null >> "$REPORT_FILE" || log "  N/A"

separator

#  Optimisation Recommendations 
log "OPTIMISATION RECOMMENDATIONS"
log "----------------------------"

# Check for images using :latest tag
LATEST_COUNT=$(docker images --format "{{.Tag}}" 2>/dev/null | grep -c "^latest$" || true)
if [[ $LATEST_COUNT -gt 0 ]]; then
    log "  - $LATEST_COUNT image(s) using :latest tag - pin to specific versions for reproducibility."
fi

# Check for dangling images
DANGLING=$(docker images -f "dangling=true" -q 2>/dev/null | wc -l)
if [[ $DANGLING -gt 0 ]]; then
    log "  - $DANGLING dangling image(s) - run 'docker image prune' to reclaim disk space."
fi

# Check for stopped containers
STOPPED=$(docker ps -a --filter "status=exited" -q 2>/dev/null | wc -l)
if [[ $STOPPED -gt 0 ]]; then
    log "  - $STOPPED stopped container(s) - run 'docker container prune' to clean up."
fi

# Check images over 1GB
LARGE_IMAGES=$(docker images --format "{{.Size}}\t{{.Repository}}:{{.Tag}}" 2>/dev/null | grep -i "gb" | wc -l || true)
if [[ $LARGE_IMAGES -gt 0 ]]; then
    log "  - $LARGE_IMAGES image(s) larger than 1 GB - consider multi-stage builds or smaller base images."
fi

# Check containers without health checks
if docker ps -q 2>/dev/null | grep -q .; then
    NO_HEALTH=0
    for C in $(docker ps -q); do
        HC=$(docker inspect --format='{{if .State.Health}}yes{{else}}no{{end}}' "$C" 2>/dev/null || echo "no")
        [[ "$HC" == "no" ]] && NO_HEALTH=$((NO_HEALTH + 1))
    done
    if [[ $NO_HEALTH -gt 0 ]]; then
        log "  - $NO_HEALTH running container(s) without HEALTHCHECK - add HEALTHCHECK to Dockerfiles."
    fi
fi

if [[ $LATEST_COUNT -eq 0 && $DANGLING -eq 0 && $STOPPED -eq 0 && $LARGE_IMAGES -eq 0 ]]; then
    log "  ✓ No major optimisation issues detected."
fi

separator

# Footer 
{
echo "================================================="
echo "Performance analysis completed at: $(date)"
echo "Report saved to: $REPORT_FILE"
echo "================================================="
} | tee -a "$REPORT_FILE"
