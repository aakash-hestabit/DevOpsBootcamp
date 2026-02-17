#!/bin/bash
set -euo pipefail

# Script: security_hardening.sh
# Description: Applies security hardening from config files (sshd_config.hardened,
#              jail.local, sysctl hardening), validates before deploying
# Author: Aakash
# Date: 2026-02-17
# Usage: sudo ./security_hardening.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_FILE="../reports/security_hardening_report_$(date +%Y%m%d).txt"
LOG_FILE="var/log/apps/$(basename "$0" .sh).log"

# Source config files
SSH_CONFIG_SRC="${SCRIPT_DIR}/sshd_config.hardened"
FAIL2BAN_SRC="${SCRIPT_DIR}/jail.local"
SYSCTL_SRC="${SCRIPT_DIR}/99-custom-performance.conf"

# Deploy targets
SSH_CONFIG_DEST="/etc/ssh/sshd_config"
FAIL2BAN_DEST="/etc/fail2ban/jail.local"
SYSCTL_DEST="/etc/sysctl.d/99-custom-performance.conf"

# Globals
COMPLETED_TASKS=()
FAILED_TASKS=()

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$REPORT_FILE")"

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"
    logger -t "$(basename "$0")" -p local0.info "$1" 2>/dev/null || true
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2
    logger -t "$(basename "$0")" -p local0.err "$1" 2>/dev/null || true
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" | tee -a "$LOG_FILE"
    logger -t "$(basename "$0")" -p local0.warning "$1" 2>/dev/null || true
}

# Help function
show_usage() {
    cat << EOF
Usage: sudo $(basename "$0") [OPTIONS]

Applies security hardening from config files in server-provision_scripts/:
  - sshd_config.hardened    → /etc/ssh/sshd_config
  - jail.local              → /etc/fail2ban/jail.local
  - 99-custom-performance.conf → /etc/sysctl.d/

All configs are validated before deployment.

OPTIONS:
    -h, --help      Show this help message
    -n, --dry-run   Validate only, do not deploy

Examples:
    sudo $(basename "$0")
    sudo $(basename "$0") --dry-run
EOF
}

DRY_RUN=false

# Validate source files exist
validate_sources() {
    log_info "Validating source config files"
    local missing=false

    for f in "$SSH_CONFIG_SRC" "$FAIL2BAN_SRC" "$SYSCTL_SRC"; do
        if [[ ! -f "$f" ]]; then
            log_error "Missing required config file: $f"
            missing=true
        fi
    done

    [[ "$missing" == true ]] && exit $EXIT_ERROR
    log_info "All source config files found"
}

# Validate SSH config syntax
validate_ssh_config() {
    log_info "Validating SSH config: $SSH_CONFIG_SRC"

    # Must have PermitRootLogin no
    if ! grep -q "^PermitRootLogin no" "$SSH_CONFIG_SRC"; then
        log_warn "sshd_config.hardened: PermitRootLogin is not set to 'no'"
    fi

    # Must have PasswordAuthentication no
    if ! grep -q "^PasswordAuthentication no" "$SSH_CONFIG_SRC"; then
        log_warn "sshd_config.hardened: PasswordAuthentication is not set to 'no'"
    fi

    # Validate with sshd if available
    if command -v sshd &>/dev/null; then
        if ! sshd -t -f "$SSH_CONFIG_SRC" 2>&1 | tee -a "$LOG_FILE"; then
            log_error "SSH config failed sshd syntax check"
            return 1
        fi
    fi

    log_info "SSH config validation passed"
}

# Validate fail2ban config
validate_fail2ban() {
    log_info "Validating Fail2Ban config: $FAIL2BAN_SRC"

    if ! grep -q "\[sshd\]" "$FAIL2BAN_SRC"; then
        log_error "jail.local: [sshd] section not found"
        return 1
    fi

    if ! grep -q "^enabled = true" "$FAIL2BAN_SRC"; then
        log_warn "jail.local: sshd jail not explicitly enabled"
    fi

    log_info "Fail2Ban config validation passed"
}

# Validate sysctl config
validate_sysctl() {
    log_info "Validating sysctl config: $SYSCTL_SRC"

    # Verify each key is a valid sysctl key (skip comments/blanks)
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        local key
        key=$(echo "$line" | cut -d= -f1 | xargs)
        if ! sysctl -n "$key" &>/dev/null; then
            log_warn "Unknown sysctl key (may be kernel-version specific): $key"
        fi
    done < "$SYSCTL_SRC"

    log_info "sysctl config validation passed"
}

# Harden SSH from file
deploy_ssh_config() {
    log_info "Deploying SSH hardening config"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would copy: $SSH_CONFIG_SRC → $SSH_CONFIG_DEST"
        COMPLETED_TASKS+=("[DRY-RUN] SSH config would be deployed")
        return
    fi

    # Backup existing
    cp "$SSH_CONFIG_DEST" "${SSH_CONFIG_DEST}.bak.$(date +%Y%m%d_%H%M%S)"
    log_info "Backed up existing sshd_config"

    cp "$SSH_CONFIG_SRC" "$SSH_CONFIG_DEST"
    chmod 600 "$SSH_CONFIG_DEST"

    systemctl restart ssh
    COMPLETED_TASKS+=("SSH hardening applied from sshd_config.hardened")
    log_info "SSH config deployed and service restarted"
}

# Install and configure Fail2Ban from file
deploy_fail2ban() {
    log_info "Installing and deploying Fail2Ban config"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would install fail2ban and deploy: $FAIL2BAN_SRC → $FAIL2BAN_DEST"
        COMPLETED_TASKS+=("[DRY-RUN] Fail2Ban config would be deployed")
        return
    fi

    apt-get install -y fail2ban 2>&1 | tee -a "$LOG_FILE"

    cp "$FAIL2BAN_SRC" "$FAIL2BAN_DEST"
    chmod 644 "$FAIL2BAN_DEST"

    systemctl enable fail2ban
    systemctl restart fail2ban

    COMPLETED_TASKS+=("Fail2Ban installed and configured from jail.local")
    log_info "Fail2Ban deployed and service restarted"
}

# Apply sysctl from file
deploy_sysctl() {
    log_info "Deploying sysctl performance/security config"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would deploy: $SYSCTL_SRC → $SYSCTL_DEST"
        log_info "[DRY-RUN] Would run: sysctl -p $SYSCTL_DEST"
        COMPLETED_TASKS+=("[DRY-RUN] sysctl config would be deployed")
        return
    fi

    cp "$SYSCTL_SRC" "$SYSCTL_DEST"
    chmod 644 "$SYSCTL_DEST"

    sysctl -p "$SYSCTL_DEST" 2>&1 | tee -a "$LOG_FILE" || {
        log_warn "Some sysctl values may not have applied — check kernel compatibility"
    }

    COMPLETED_TASKS+=("Kernel parameters applied from 99-custom-performance.conf")
    log_info "sysctl config deployed"
}

# Remove unnecessary packages
remove_unnecessary_packages() {
    log_info "Removing unnecessary packages"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would purge: telnet ftp rsh-server xinetd"
        COMPLETED_TASKS+=("[DRY-RUN] Unnecessary packages would be removed")
        return
    fi

    apt-get purge -y telnet ftp rsh-server xinetd 2>/dev/null || true
    apt-get autoremove -y 2>&1 | tee -a "$LOG_FILE"

    COMPLETED_TASKS+=("Unnecessary legacy packages removed (telnet, ftp, rsh-server, xinetd)")
}

# Disable unused services
disable_unused_services() {
    log_info "Disabling unused services"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would disable: avahi-daemon cups"
        COMPLETED_TASKS+=("[DRY-RUN] Unused services would be disabled")
        return
    fi

    for svc in avahi-daemon cups; do
        systemctl disable --now "$svc" 2>/dev/null || true
    done

    COMPLETED_TASKS+=("Unused services disabled (avahi-daemon, cups)")
}

# Password policy
set_password_policy() {
    log_info "Setting password policies in /etc/login.defs"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would set PASS_MAX_DAYS=90, PASS_MIN_DAYS=1, PASS_WARN_AGE=7"
        COMPLETED_TASKS+=("[DRY-RUN] Password policy would be applied")
        return
    fi

    sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
    sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/'  /etc/login.defs
    sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   7/'  /etc/login.defs

    COMPLETED_TASKS+=("Password aging policies enforced")
}

# Automatic security updates
enable_auto_updates() {
    log_info "Enabling automatic security updates"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would install and configure unattended-upgrades"
        COMPLETED_TASKS+=("[DRY-RUN] Auto-updates would be enabled")
        return
    fi

    apt-get install -y unattended-upgrades 2>&1 | tee -a "$LOG_FILE"
    dpkg-reconfigure -f noninteractive unattended-upgrades

    COMPLETED_TASKS+=("Automatic security updates enabled")
}

# Audit logging
setup_auditd() {
    log_info "Setting up audit logging (auditd)"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would install and start auditd"
        COMPLETED_TASKS+=("[DRY-RUN] auditd would be configured")
        return
    fi

    apt-get install -y auditd audispd-plugins 2>&1 | tee -a "$LOG_FILE"
    systemctl enable auditd
    systemctl restart auditd

    COMPLETED_TASKS+=("Audit logging enabled via auditd")
}

# Generate report
generate_report() {
    mkdir -p "$(dirname "$REPORT_FILE")"

    {
        echo "========== SECURITY HARDENING REPORT =========="
        echo "Date: $(date)"
        echo ""
        echo "----- Completed Tasks -----"
        for task in "${COMPLETED_TASKS[@]}"; do
            echo "[OK] $task"
        done
        echo ""
        if [[ "${#FAILED_TASKS[@]}" -gt 0 ]]; then
            echo "----- Failed Tasks -----"
            for task in "${FAILED_TASKS[@]}"; do
                echo "[FAILED] $task"
            done
            echo ""
        fi
        echo "Hardening Status: COMPLETED"
        echo "================================================"
    } | tee -a "$LOG_FILE"

    log_info "Report saved to: $REPORT_FILE"
}

# Main function
main() {
    log_info "========================================"
    log_info "Security hardening started"
    log_info "========================================"

    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root"
        exit $EXIT_ERROR
    fi

    # Validate all source files before touching anything live
    validate_sources
    validate_ssh_config   || FAILED_TASKS+=("SSH config validation failed")
    validate_fail2ban     || FAILED_TASKS+=("Fail2Ban config validation failed")
    validate_sysctl       || true  # sysctl warns but doesn't abort

    if [[ ${#FAILED_TASKS[@]} -gt 0 ]]; then
        log_error "Validation failed — aborting deployment"
        generate_report
        exit $EXIT_ERROR
    fi

    log_info "All validations passed — deploying"

    # Deploy configs
    deploy_ssh_config
    deploy_fail2ban
    deploy_sysctl
    remove_unnecessary_packages
    disable_unused_services
    set_password_policy
    enable_auto_updates
    setup_auditd

    generate_report

    log_info "========================================"
    log_info "Security hardening completed"
    log_info "========================================"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit $EXIT_SUCCESS
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit $EXIT_ERROR
            ;;
    esac
done

main "$@"