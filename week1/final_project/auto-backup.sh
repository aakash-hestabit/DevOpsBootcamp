#!/bin/bash
set -euo pipefail

# Script: auto-backup.sh
# Description: Comprehensive backup system for all server configurations, DNS zones, and user data
# Author: Aakash
# Date: 2026-02-17
# Usage: sudo ./auto-backup.sh [options]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPTS_DIR="${SCRIPT_DIR}/backup_scripts"
LOG_FILE="var/log/apps/$(basename "$0" .sh).log"
BACKUP_ROOT="/backup"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
RETENTION_DAYS=7

# Backup directories
BACKUP_CONFIG="${BACKUP_ROOT}/configurations"
BACKUP_DNS="${BACKUP_ROOT}/dns"
BACKUP_USER="${BACKUP_ROOT}/user_data"

mkdir -p "$(dirname "$LOG_FILE")"

# Logging functions
log_info() { 
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"
}

log_error() { 
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" | tee -a "$LOG_FILE"
}

# Help function
show_usage() {
    cat << EOF
Usage: sudo $(basename "$0") [OPTIONS]

Comprehensive backup system that backs up:
  - All system configuration files
  - DNS zones and BIND configuration
  - User data from /home
  - Network and firewall settings

OPTIONS:
    -h, --help      Show this help message
    --test          Test restore procedures
    --skip-dns      Skip DNS backup

Examples:
    sudo $(basename "$0")
    sudo $(basename "$0") --test

EOF
}

# Root check
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root"
        exit $EXIT_ERROR
    fi
}

# Backup system configurations
backup_system_configs() {
    log_info "========================================"
    log_info "Starting system configuration backup"
    log_info "========================================"
    
    mkdir -p "$BACKUP_CONFIG"
    local archive="${BACKUP_CONFIG}/system_configs_${TIMESTAMP}.tar.gz"
    
    # List of configuration directories and files to backup
    local configs=(
        # Core System Configuration
        "/etc/hostname"
        "/etc/hosts"
        "/etc/fstab"
        "/etc/sysctl.conf"
        "/etc/sysctl.d"
        "/etc/login.defs"
        "/etc/security/limits.conf"
        
        # User, Group & Privileges
        "/etc/passwd"
        "/etc/shadow"
        "/etc/group"
        "/etc/gshadow"
        "/etc/sudoers"
        "/etc/sudoers.d"
        
        # SSH & Authentication
        "/etc/ssh/sshd_config"
        "/etc/ssh/ssh_config"
        "/etc/fail2ban"
        
        # Firewall
        "/etc/ufw"
        
        # Network Configuration
        "/etc/netplan"
        
        # Application Logs Configuration
        "/etc/rsyslog.conf"
        "/etc/rsyslog.d"
        "/etc/logrotate.conf"
        "/etc/logrotate.d"
    )
    
    # Filter out non-existent paths
    local existing_configs=()
    for config in "${configs[@]}"; do
        if [[ -e "$config" ]]; then
            existing_configs+=("$config")
        else
            log_info "Skipping non-existent: $config"
        fi
    done
    
    if [[ ${#existing_configs[@]} -eq 0 ]]; then
        log_error "No configuration files found to backup"
        return 1
    fi
    
    log_info "Creating archive: $archive"
    tar -czpf "$archive" "${existing_configs[@]}" 2>/dev/null || {
        log_error "Failed to create system config archive"
        return 1
    }
    
    # Set secure permissions
    chmod 600 "$archive"
    
    # Verify integrity
    if tar -tzf "$archive" > /dev/null 2>&1; then
        log_success "System configs backup completed: $archive"
        log_info "Archive size: $(du -h "$archive" | cut -f1)"
    else
        log_error "Integrity check failed for system configs"
        return 1
    fi
}

# Backup DNS zones using dns_backup.sh
backup_dns_zones() {
    log_info "========================================"
    log_info "Starting DNS backup"
    log_info "========================================"
    
    if [[ ! -x "${BACKUP_SCRIPTS_DIR}/dns_backup.sh" ]]; then
        log_error "DNS backup script not found or not executable: ${BACKUP_SCRIPTS_DIR}/dns_backup.sh"
        return 1
    fi
    
    # Run DNS backup script
    "${BACKUP_SCRIPTS_DIR}/dns_backup.sh" || {
        log_error "DNS backup failed"
        return 1
    }
    
    log_success "DNS backup completed"
}

# Backup user data
backup_user_data() {
    log_info "========================================"
    log_info "Starting user data backup"
    log_info "========================================"
    
    mkdir -p "$BACKUP_USER"
    local archive="${BACKUP_USER}/user_data_${TIMESTAMP}.tar.gz"
    
    # Backup /home directory
    if [[ -d "/home/jdoe" ]]; then
        log_info "Creating archive: $archive"
        tar -czpf "$archive" /home/jdoe 2>/dev/null || {
            log_error "Failed to create user data archive"
            return 1
        }
        
        # Set secure permissions
        chmod 600 "$archive"
        
        # Verify integrity
        if tar -tzf "$archive" > /dev/null 2>&1; then
            log_success "User data backup completed: $archive"
            log_info "Archive size: $(du -h "$archive" | cut -f1)"
        else
            log_error "Integrity check failed for user data"
            return 1
        fi
    else
        log_info "No /home directory found to backup"
    fi
}

# Backup application logs
backup_logs() {
    log_info "========================================"
    log_info "Starting logs backup"
    log_info "========================================"
    
    mkdir -p "$BACKUP_ROOT/logs"
    local archive="${BACKUP_ROOT}/logs/logs_${TIMESTAMP}.tar.gz"
    
    if [[ -d "/var/log/apps" ]]; then
        log_info "Creating archive: $archive"
        tar -czpf "$archive" /var/log/apps 2>/dev/null || {
            log_error "Failed to create logs archive"
            return 1
        }
        
        chmod 600 "$archive"
        
        if tar -tzf "$archive" > /dev/null 2>&1; then
            log_success "Logs backup completed: $archive"
            log_info "Archive size: $(du -h "$archive" | cut -f1)"
        else
            log_error "Integrity check failed for logs"
            return 1
        fi
    else
        log_info "No /var/log/apps directory found to backup"
    fi
}

# Test restore procedure
test_restore() {
    log_info "========================================"
    log_info "Testing restore procedures"
    log_info "========================================"
    
    local test_dir="/tmp/restore_test_$$"
    mkdir -p "$test_dir"
    
    local all_ok=true
    
    # Test system config restore
    local latest_config=$(ls -t "${BACKUP_CONFIG}"/system_configs_*.tar.gz 2>/dev/null | head -n1)
    if [[ -n "$latest_config" ]]; then
        log_info "Testing system config restore: $latest_config"
        if tar -xzf "$latest_config" -C "$test_dir" 2>/dev/null; then
            log_success "System config restore test: PASSED"
        else
            log_error "System config restore test: FAILED"
            all_ok=false
        fi
    fi
    
    # Test DNS restore
    local latest_dns=$(ls -t "${BACKUP_DNS}"/dns_backup_*.tar.gz 2>/dev/null | head -n1)
    if [[ -n "$latest_dns" ]]; then
        log_info "Testing DNS restore: $latest_dns"
        if tar -tzf "$latest_dns" > /dev/null 2>&1; then
            log_success "DNS restore test: PASSED"
        else
            log_error "DNS restore test: FAILED"
            all_ok=false
        fi
    fi
    
    # Test user data restore
    local latest_user=$(ls -t "${BACKUP_USER}"/user_data_*.tar.gz 2>/dev/null | head -n1)
    if [[ -n "$latest_user" ]]; then
        log_info "Testing user data restore: $latest_user"
        if tar -tzf "$latest_user" > /dev/null 2>&1; then
            log_success "User data restore test: PASSED"
        else
            log_error "User data restore test: FAILED"
            all_ok=false
        fi
    fi
    
    # Cleanup test directory
    rm -rf "$test_dir"
    
    if [[ "$all_ok" == true ]]; then
        log_success "All restore tests PASSED"
    else
        log_error "Some restore tests FAILED"
        return 1
    fi
}

# Apply retention policy across all backup types
apply_retention() {
    log_info "========================================"
    log_info "Applying retention policy (${RETENTION_DAYS} days)"
    log_info "========================================"
    
    local total_deleted=0
    
    for backup_dir in "$BACKUP_CONFIG" "$BACKUP_DNS" "$BACKUP_USER" "${BACKUP_ROOT}/logs"; do
        if [[ -d "$backup_dir" ]]; then
            local deleted
            deleted=$(find "$backup_dir" -type f -name "*.tar.gz" -mtime +${RETENTION_DAYS} -delete -print | wc -l)
            total_deleted=$((total_deleted + deleted))
            
            if [[ $deleted -gt 0 ]]; then
                log_info "Deleted $deleted old backup(s) from $(basename "$backup_dir")"
            fi
        fi
    done
    
    if [[ $total_deleted -gt 0 ]]; then
        log_success "Retention policy applied: $total_deleted old backup(s) removed"
    else
        log_info "No old backups to remove"
    fi
}

# Generate backup summary
generate_summary() {
    log_info "========================================"
    log_info "BACKUP SUMMARY"
    log_info "========================================"
    
    local total_size=0
    local backup_count=0
    
    for backup_dir in "$BACKUP_CONFIG" "$BACKUP_DNS" "$BACKUP_USER" "${BACKUP_ROOT}/logs"; do
        if [[ -d "$backup_dir" ]]; then
            local dir_name=$(basename "$backup_dir")
            local count=$(find "$backup_dir" -type f -name "*.tar.gz" | wc -l)
            local size=$(du -sh "$backup_dir" 2>/dev/null | cut -f1)
            
            log_info "$dir_name: $count archive(s), Total: $size"
            backup_count=$((backup_count + count))
        fi
    done
    
    log_info "----------------------------------------"
    log_info "Total backups: $backup_count"
    log_info "Backup location: $BACKUP_ROOT"
    log_info "Retention period: ${RETENTION_DAYS} days"
    log_info "========================================"
}

# Main function
main() {
    log_info "=========================================="
    log_info "AUTO-BACKUP SYSTEM STARTED"
    log_info "=========================================="
    log_info "Timestamp: $TIMESTAMP"
    
    check_root
    
    # Create backup root directory
    mkdir -p "$BACKUP_ROOT"
    chmod 700 "$BACKUP_ROOT"
    
    local status=0
    
    # Run all backup operations
    backup_system_configs || status=1
    
    if [[ "${SKIP_DNS:-false}" != true ]]; then
        backup_dns_zones || status=1
    fi
    
    backup_user_data || status=1
    backup_logs || status=1
    
    # Test restore if requested
    if [[ "${TEST_RESTORE:-false}" == true ]]; then
        test_restore || status=1
    fi
    
    # Apply retention policy
    apply_retention
    
    # Generate summary
    generate_summary
    
    if [[ $status -eq 0 ]]; then
        log_success "=========================================="
        log_success "AUTO-BACKUP COMPLETED SUCCESSFULLY"
        log_success "=========================================="
        logger -p user.info "auto-backup.sh: Backup completed successfully"
    else
        log_error "=========================================="
        log_error "AUTO-BACKUP COMPLETED WITH ERRORS"
        log_error "=========================================="
        logger -p user.err "auto-backup.sh: Backup completed with errors"
    fi
    
    exit $status
}

# Parse arguments
SKIP_DNS=false
TEST_RESTORE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit $EXIT_SUCCESS
            ;;
        --skip-dns)
            SKIP_DNS=true
            shift
            ;;
        --test)
            TEST_RESTORE=true
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