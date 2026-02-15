#!/bin/bash
set -euo pipefail

# Script: security_hardening.sh
# Description: Automates system security hardening (SSH, Fail2Ban, packages, updates, auditing)
# Author: Aakash
# Date: 2026-02-15
# Usage: sudo ./security_hardening.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="reports"
REPORT_FILE="$REPORT_DIR/security_hardening_report_$(date +%Y%m%d).txt"
LOG_FILE="var/log/apps/$(basename "$0" .sh).log"

# Ensure directories exist
mkdir -p "$REPORT_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

# Globals
COMPLETED_TASKS=()
FAILED_TASKS=()

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2
}

# Help function
show_usage() {
    cat << EOF
Usage: sudo $(basename "$0") [OPTIONS]

Automates SSH hardening, Fail2Ban setup, system hardening,
and generates a security hardening report.

OPTIONS:
    -h, --help      Show this help message

Examples:
    sudo $(basename "$0")
EOF
}

# SSH Hardening
harden_ssh() {
    log_info "Applying SSH hardening"

    sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#Port 22/Port 2222/' /etc/ssh/sshd_config

    systemctl restart ssh

    COMPLETED_TASKS+=("SSH hardening applied (root login disabled, key-based auth enforced, port changed to 2222)")
}

# Fail2Ban setup
setup_fail2ban() {
    log_info "Installing and configuring Fail2Ban"

    apt install -y fail2ban

    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

    cat > /etc/fail2ban/jail.local << EOF
[sshd]
enabled = true
port = 2222
maxretry = 3
bantime = 3600
findtime = 600
EOF

    systemctl enable fail2ban
    systemctl restart fail2ban

    COMPLETED_TASKS+=("Fail2Ban installed and SSH jail configured")
}

# Remove unnecessary packages
remove_unnecessary_packages() {
    log_info "Removing unnecessary packages"

    apt purge -y telnet ftp rsh-server xinetd || true
    apt autoremove -y

    COMPLETED_TASKS+=("Unnecessary legacy packages removed (telnet ftp rsh-server xinetd)")
}

# Disable unused services
disable_unused_services() {
    log_info "Disabling unused services"

    for svc in avahi-daemon cups ; do
        systemctl disable --now "$svc" 2>/dev/null || true
    done

    COMPLETED_TASKS+=("Unused services disabled")
}

# Password policy hardening
set_password_policy() {
    log_info "Setting password policies"

    sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
    sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/' /etc/login.defs
    sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   7/' /etc/login.defs

    COMPLETED_TASKS+=("Password aging policies enforced")
}

# Automatic security updates
enable_auto_updates() {
    log_info "Enabling automatic security updates"

    apt install -y unattended-upgrades
    dpkg-reconfigure -f noninteractive unattended-upgrades

    COMPLETED_TASKS+=("Automatic security updates enabled")
}

# Audit logging
setup_auditd() {
    log_info "Setting up audit logging"

    apt install -y auditd audispd-plugins
    systemctl enable auditd
    systemctl restart auditd

    COMPLETED_TASKS+=("Audit logging enabled using auditd")
}

# Generate report
generate_report() {
    {
        echo "========== SECURITY HARDENING REPORT =========="
        echo "Date: $(date)"
        echo
        echo "----- Completed Tasks -----"
        for task in "${COMPLETED_TASKS[@]}"; do
            echo "[OK] $task"
        done
        echo
        if [[ "${#FAILED_TASKS[@]}" -gt 0 ]]; then
            echo "----- Failed Tasks -----"
            for task in "${FAILED_TASKS[@]}"; do
                echo "[FAILED] $task"
            done
            echo
        fi
        echo "Hardening Status: COMPLETED"
        echo "=============================================="
    } | tee "$REPORT_FILE"
}

# Main
main() {
    log_info "Security hardening started"

    harden_ssh
    setup_fail2ban
    remove_unnecessary_packages
    disable_unused_services
    set_password_policy
    enable_auto_updates
    setup_auditd

    generate_report

    log_info "Security hardening completed successfully"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
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
