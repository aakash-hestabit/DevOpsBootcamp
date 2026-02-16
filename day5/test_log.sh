#!/bin/bash

# Define the log file location
LOG_FILE="/var/log/apps/application.log"

# Define the functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"
    logger -t "$(basename $0)" -p local0.info "$1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2
    logger -t "$(basename $0)" -p local0.err "$1"
}

log_info "The application started successfully."
log_error "Failed to connect to the database!"