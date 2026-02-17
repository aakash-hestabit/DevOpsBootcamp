#!/bin/bash
set -euo pipefail

# Script: user_provision.sh
# Description: Creates users from CSV file with secure configuration
# Author: Aakash
# Date: 2026-02-17
# Usage: sudo ./user_provision.sh [OPTIONS] users.txt

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="../var/log/apps/$(basename "$0" .sh).log"
USER_PASS_FILE="../var/log/apps/user_pass.log"
VERBOSE=false

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE" "$USER_PASS_FILE"
chmod 640 "$LOG_FILE"
chmod 600 "$USER_PASS_FILE"

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
    logger -t "$(basename "$0")" -p local1.info "$1" 2>/dev/null || true
    [[ "$VERBOSE" == true ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2
    logger -t "$(basename "$0")" -p local1.err "$1" 2>/dev/null || true
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$LOG_FILE"
    logger -t "$(basename "$0")" -p local1.warning "$1" 2>/dev/null || true
    [[ "$VERBOSE" == true ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1"
}

# Help function
show_usage() {
    cat << EOF
Usage: sudo $(basename "$0") [OPTIONS] users.txt

Creates users from CSV file with secure defaults.
Skips duplicate usernames automatically.

OPTIONS:
    -h, --help        Show this help message
    -v, --verbose     Print progress to console

CSV Format (with header):
  username,fullname,group,role

Roles:
  sysadmin / admin → granted sudo access
  developer        → no sudo

Example:
  sudo $(basename "$0") users.txt
  sudo $(basename "$0") --verbose users.txt
EOF
}

# Root check
if [[ "$EUID" -ne 0 ]]; then
    log_error "This script must be run as root"
    exit $EXIT_ERROR
fi

# Validate CSV file
validate_csv() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        log_error "Input file not found: $file"
        exit $EXIT_ERROR
    fi

    # Check header
    local header
    header=$(head -n1 "$file")
    if [[ "$header" != "username,fullname,group,role" ]]; then
        log_error "Invalid CSV header. Expected: username,fullname,group,role"
        log_error "Got: $header"
        exit $EXIT_ERROR
    fi

    # Check for duplicate usernames in file
    local dupes
    dupes=$(tail -n +2 "$file" | cut -d',' -f1 | sort | uniq -d | xargs)
    if [[ -n "$dupes" ]]; then
        log_warn "Duplicate usernames in CSV (will be skipped after first): $dupes"
    fi

    log_info "CSV validation passed: $file"
}

main() {
    local input_file="$1"

    log_info "========================================"
    log_info "User provisioning started"
    log_info "Input file: $input_file"
    log_info "========================================"

    validate_csv "$input_file"

    local created=0 skipped=0 failed=0

    # Read CSV skipping header
    {
        read -r _header
        while IFS=',' read -r username fullname group role; do

            # Trim whitespace and carriage returns
            username=$(echo "$username" | tr -d '\r' | xargs)
            fullname=$(echo "$fullname" | tr -d '\r' | xargs)
            group=$(echo "$group"    | tr -d '\r' | xargs)
            role=$(echo "$role"      | tr -d '\r' | xargs)

            # Skip blank lines
            [[ -z "$username" ]] && continue

            # Validate required fields
            if [[ -z "$username" || -z "$group" ]]; then
                log_warn "Skipping invalid row: username='$username' group='$group'"
                ((failed++))
                continue
            fi

            # Create group if it doesn't exist
            if ! getent group "$group" >/dev/null 2>&1; then
                groupadd "$group"
                log_info "Created group: $group"
            fi

            # Skip if user already exists
            if id "$username" &>/dev/null; then
                log_warn "User '$username' already exists — skipping"
                ((skipped++))
                continue
            fi

            # Generate random password
            local password
            password=$(openssl rand -base64 14)

            # Create user
            useradd -m -c "$fullname" -g "$group" -s /bin/bash "$username"
            echo "$username:$password" | chpasswd
            chage -d 0 "$username"   # Force password change on first login

            # Store credentials securely
            echo "$(date '+%Y-%m-%d %H:%M:%S') $username:$password" >> "$USER_PASS_FILE"

            # Set home directory permissions
            local home_dir
            home_dir=$(getent passwd "$username" | cut -d: -f6)
            chmod 750 "$home_dir"
            chown "$username:$group" "$home_dir"

            # Set up .ssh directory
            mkdir -p "$home_dir/.ssh"
            chmod 700 "$home_dir/.ssh"
            chown "$username:$group" "$home_dir/.ssh"

            # Grant sudo if role requires it
            if [[ "$role" == "sysadmin" || "$role" == "admin" ]]; then
                usermod -aG sudo "$username"
                log_info "Granted sudo to: $username"
            fi

            log_info "Created user: $username (group: $group, role: $role)"
            ((created++))

        done
    } < "$input_file"

    log_info "========================================"
    log_info "User provisioning completed"
    log_info "Created: $created | Skipped: $skipped | Failed: $failed"
    log_info "Credentials saved to: $USER_PASS_FILE"
    log_info "========================================"
}

# Parse arguments
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit $EXIT_SUCCESS
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            show_usage
            exit $EXIT_ERROR
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

set -- "${POSITIONAL_ARGS[@]}"

if [[ $# -ne 1 ]]; then
    show_usage
    exit $EXIT_ERROR
fi

main "$1"
exit $EXIT_SUCCESS