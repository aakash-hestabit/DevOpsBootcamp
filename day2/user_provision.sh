#!/bin/bash
set -euo pipefail

# Script: user_provision.sh
# Description: Creates users from CSV file with secure configuration
# Author: Aakash
# Date: 2026-02-12
# Usage: sudo ./user_provision.sh [OPTIONS] users.txt

readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="var/log/apps"
LOG_FILE="$LOG_DIR/$(basename "$0" .sh).log"
VERBOSE=false
USER_PASS_FILE="var/log/user_pass.log"

# Ensure log directory exists
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
touch "$USER_PASS_FILE"
chmod 640 "$LOG_FILE"

# Logging functions
log_info() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
    echo "$message" >> "$LOG_FILE"
    if [[ "$VERBOSE" == true ]]; then
        echo "$message"
    fi
}

log_error() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    echo "$message" | tee -a "$LOG_FILE" >&2
}

# Help function
show_usage() {
    cat << EOF
Usage: sudo $(basename "$0") [OPTIONS] users.txt

Creates users from CSV file securely.

OPTIONS:
    -h, --help        Show this help message
    -v, --verbose     Enable verbose console output

CSV Format:
username,fullname,group,role

Example:
jdoe,John Doe,developers,developer
asmith,Alice Smith,ops,sysadmin
EOF
}

# Ensure script is run as root
if [[ "$EUID" -ne 0 ]]; then
    log_error "This script must be run as root"
    exit $EXIT_ERROR
fi

main() {

    log_info "Script started"

    local input_file="$1"

    if [[ ! -f "$input_file" ]]; then
        log_error "Input file not found: $input_file"
        exit $EXIT_ERROR
    fi

    {
        read -r header
        while IFS=',' read -r username fullname group role; do

            username=$(echo "$username" | xargs)
            group=$(echo "$group" | xargs)
            role=$(echo "$role" | xargs)

            if [[ -z "$username" || -z "$group" ]]; then
                log_error "Invalid entry detected. Skipping..."
                continue
            fi

            if ! getent group "$group" >/dev/null; then
                groupadd "$group"
                log_info "Created group: $group"
            fi

            if id "$username" &>/dev/null; then
                log_info "User $username already exists. Skipping."
                continue
            fi

            password=$(openssl rand -base64 14)

            useradd -m -c "$fullname" -g "$group" -s /bin/bash "$username"

            echo "$username:$password" | chpasswd
            echo "$username:$password" >> "$USER_PASS_FILE"
            chage -d 0 "$username"

            home_dir=$(getent passwd "$username" | cut -d: -f6)

            chmod 750 "$home_dir"
            chown "$username:$group" "$home_dir"

            mkdir -p "$home_dir/.ssh"
            chmod 700 "$home_dir/.ssh"
            chown "$username:$group" "$home_dir/.ssh"

            if [[ "$role" == "sysadmin" || "$role" == "admin" ]]; then
                usermod -aG sudo "$username"
                log_info "Granted sudo access to $username"
            fi

            log_info "User created: $username (Group: $group)"

        done
    } < "$input_file"

    log_info "Script completed successfully"
}

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
