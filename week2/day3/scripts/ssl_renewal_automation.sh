#!/bin/bash
set -euo pipefail
# Script: ssl_renewal_automation.sh
# Description: Automates Let's Encrypt certificate renewal, checks expiry, reloads Nginx, and logs operations
# Author: Aakash
# Date: 2026-02-23
# Usage: ./ssl_renewal_automation.sh [options]
# Cron: 0 3 * * 1 /path/to/ssl_renewal_automation.sh

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="var/log/apps/ssl_renewal_automation.log"
RENEWAL_LOG="var/log/apps/ssl_renewal_$(date '+%Y-%m-%d').log"
VERBOSE=false
ALERT_EMAIL=""
EXPIRY_THRESHOLD_DAYS=30

# Logging functions
log_info()    { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" | tee -a "$LOG_FILE" | tee -a "$RENEWAL_LOG"; }
log_error()   { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" | tee -a "$RENEWAL_LOG" >&2; }
log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK]    $1" | tee -a "$LOG_FILE" | tee -a "$RENEWAL_LOG"; }
log_verbose() { [[ "$VERBOSE" == true ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" | tee -a "$LOG_FILE"; }

# Help function
show_usage() {
    cat << EOF
Usage: $(basename $0) [OPTIONS]

Automates Let's Encrypt certificate renewal.
Checks expiry dates, renews certificates expiring within ${EXPIRY_THRESHOLD_DAYS} days,
tests Nginx configuration, and reloads Nginx on success.

Recommended cron (weekly, Monday 3 AM):
    0 3 * * 1 /path/to/ssl_renewal_automation.sh

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -e, --email ADDR    Send notification to this email on renewal
    -t, --threshold N   Renew if expiry within N days (default: 30)

Examples:
    $(basename $0)
    $(basename $0) --threshold 14
    $(basename $0) --email admin@example.com
EOF
}

# Ensure log directory exists
init_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    touch "$RENEWAL_LOG"
}

# Check root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit $EXIT_ERROR
    fi
}

# Check certbot is installed
check_certbot() {
    if ! command -v certbot &>/dev/null; then
        log_error "certbot is not installed. Install with: apt-get install -y certbot python3-certbot-nginx"
        exit $EXIT_ERROR
    fi
    log_verbose "certbot found: $(certbot --version 2>&1)"
}

# Check individual certificate expiry
check_cert_expiry() {
    local domain="$1"
    local cert_path="/etc/letsencrypt/live/${domain}/fullchain.pem"

    if [[ ! -f "$cert_path" ]]; then
        log_verbose "Certificate not found for ${domain}"
        return 1
    fi

    local expiry_date days_left
    expiry_date=$(openssl x509 -enddate -noout -in "$cert_path" 2>/dev/null | cut -d= -f2)
    days_left=$(( ($(date -d "$expiry_date" +%s) - $(date +%s)) / 86400 ))

    log_info "Domain: ${domain} | Expires: ${expiry_date} | Days left: ${days_left}"

    if [[ $days_left -lt $EXPIRY_THRESHOLD_DAYS ]]; then
        log_info "Certificate for ${domain} expires in ${days_left} days — renewal needed"
        return 0
    else
        log_verbose "Certificate for ${domain} is valid for ${days_left} more days"
        return 1
    fi
}

# Run certbot renew
run_renewal() {
    log_info "Running certbot renewal..."
    local renewal_output
    renewal_output=$(certbot renew --quiet --no-random-sleep-on-renew 2>&1)
    local renewal_exit=$?

    echo "$renewal_output" >> "$RENEWAL_LOG"

    if [[ $renewal_exit -eq 0 ]]; then
        log_success "Certificate renewal completed successfully"
        return 0
    else
        log_error "certbot renewal failed. Output logged to ${RENEWAL_LOG}"
        return 1
    fi
}

# Test Nginx configuration after renewal
test_nginx() {
    if command -v nginx &>/dev/null; then
        log_info "Testing Nginx configuration after renewal..."
        if nginx -t 2>&1; then
            log_success "Nginx configuration test passed"
            return 0
        else
            log_error "Nginx configuration test failed after renewal"
            return 1
        fi
    fi
    return 0
}

# Reload Nginx
reload_nginx() {
    if systemctl is-active --quiet nginx; then
        systemctl reload nginx
        log_success "Nginx reloaded successfully"
    else
        log_info "Nginx is not running — skipping reload"
    fi
}

# Send notification email
send_notification() {
    local status="$1"
    if [[ -n "$ALERT_EMAIL" ]] && command -v mail &>/dev/null; then
        echo "SSL certificate renewal status: ${status} on $(hostname) at $(date)" | \
            mail -s "[SSL Renewal] ${status} - $(hostname)" "$ALERT_EMAIL"
        log_info "Notification email sent to ${ALERT_EMAIL}"
    fi
}

# List all Let's Encrypt certificates
list_certificates() {
    log_info "Current Let's Encrypt certificates:"
    certbot certificates 2>/dev/null | tee -a "$RENEWAL_LOG" || echo "No certificates found"
}

# Setup auto-renewal cron if not already configured
ensure_cron() {
    if ! crontab -l 2>/dev/null | grep -q "ssl_renewal_automation.sh"; then
        (crontab -l 2>/dev/null; echo "0 3 * * 1 $(realpath "$0") >> ${RENEWAL_LOG} 2>&1") | crontab -
        log_success "Cron job added: every Monday at 3:00 AM"
    else
        log_verbose "Cron job already configured"
    fi
}

# Main function
main() {
    init_logging
    log_info "=== ssl_renewal_automation.sh started ==="
    check_root
    check_certbot
    list_certificates

    local renewal_needed=false
    local renewed=false

    # Check each certificate
    if [[ -d "/etc/letsencrypt/live" ]]; then
        for domain_dir in /etc/letsencrypt/live/*/; do
            domain=$(basename "$domain_dir")
            if check_cert_expiry "$domain"; then
                renewal_needed=true
            fi
        done
    fi

    if [[ "$renewal_needed" == true ]]; then
        log_info "Renewal required — starting certbot renew..."
        if run_renewal; then
            renewed=true
            if test_nginx; then
                reload_nginx
                send_notification "SUCCESS - Certificates renewed and Nginx reloaded"
            else
                send_notification "WARNING - Certificates renewed but Nginx test failed"
                log_error "Manual review required"
                exit $EXIT_ERROR
            fi
        else
            send_notification "FAILED - Certificate renewal failed"
            exit $EXIT_ERROR
        fi
    else
        log_info "No certificates require renewal at this time"
        send_notification "INFO - No renewal required, all certificates valid"
    fi

    ensure_cron

    echo ""
    echo "===== SSL Renewal Summary ====="
    echo "  Date:      $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  Renewal:   $([ "$renewed" == true ] && echo "Completed" || echo "Not required")"
    echo "  Log:       ${RENEWAL_LOG}"
    echo "==============================="

    log_info "=== ssl_renewal_automation.sh completed ==="
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)       show_usage; exit $EXIT_SUCCESS ;;
        -v|--verbose)    VERBOSE=true ;;
        -e|--email)      ALERT_EMAIL="$2"; shift ;;
        -t|--threshold)  EXPIRY_THRESHOLD_DAYS="$2"; shift ;;
        *) echo "Unknown option: $1"; show_usage; exit $EXIT_ERROR ;;
    esac
    shift
done

main "$@"
