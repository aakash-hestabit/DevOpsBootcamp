#!/bin/bash
set -euo pipefail

# Script: ufw_setup.sh
# Description: Configures UFW firewall rules from a CSV input file
# Author: Aakash
# Date: 2026-02-17
# Usage: sudo ./ufw_setup.sh [OPTIONS]

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="../var/log/apps/$(basename "$0" .sh).log"
RULES_FILE="${SCRIPT_DIR}/firewall_rules.csv"

DRY_RUN=false

mkdir -p "$(dirname "$LOG_FILE")"

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

Configures UFW firewall from firewall_rules.csv.
Sets default deny-incoming / allow-outgoing before applying rules.

OPTIONS:
    -h, --help          Show this help message
    -f, --file FILE     Path to rules CSV (default: ./firewall_rules.csv)
    -n, --dry-run       Print rules without applying

Examples:
    sudo $(basename "$0")
    sudo $(basename "$0") --dry-run
    sudo $(basename "$0") --file /path/to/rules.csv
EOF
}

# Validate environment
validate_env() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root"
        exit $EXIT_ERROR
    fi

    if ! command -v ufw &>/dev/null; then
        log_error "ufw is not installed. Install with: apt install ufw"
        exit $EXIT_ERROR
    fi

    if [[ ! -f "$RULES_FILE" ]]; then
        log_error "Rules file not found: $RULES_FILE"
        exit $EXIT_ERROR
    fi
}

# Apply a single firewall rule
apply_rule() {
    local type="$1"
    local rule="$2"
    local from="$3"
    local comment="$4"

    case "$type" in
        port)
            if [[ -n "$from" ]]; then
                local cmd="ufw allow from $from to any port ${rule%%/*} comment '$comment'"
            elif [[ -n "$comment" ]]; then
                local cmd="ufw allow $rule comment '$comment'"
            else
                local cmd="ufw allow $rule"
            fi
            ;;
        app)
            local cmd="ufw allow '$rule'"
            ;;
        limit)
            if [[ -n "$comment" ]]; then
                local cmd="ufw limit $rule comment '$comment'"
            else
                local cmd="ufw limit $rule"
            fi
            ;;
        *)
            log_warn "Unknown rule type '$type' — skipping"
            return
            ;;
    esac

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would run: $cmd"
        return
    fi

    eval "$cmd" 2>&1 | tee -a "$LOG_FILE" || log_warn "Rule may already exist: $cmd"
    log_info "Applied [$type]: $rule${from:+ from $from}${comment:+ ($comment)}"
}

# Main function
main() {
    validate_env

    log_info "========================================"
    log_info "UFW setup started"
    log_info "Rules file: $RULES_FILE"
    log_info "========================================"

    # Set defaults
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would set: ufw default deny incoming"
        log_info "[DRY-RUN] Would set: ufw default allow outgoing"
    else
        ufw --force reset 2>&1 | tee -a "$LOG_FILE" || true
        ufw default deny incoming  2>&1 | tee -a "$LOG_FILE"
        ufw default allow outgoing 2>&1 | tee -a "$LOG_FILE"
        log_info "Set defaults: deny incoming, allow outgoing"
    fi

    # Read and apply rules from CSV (skip header and comments)
    local rule_count=0
    while IFS=',' read -r type rule from comment; do
        # Skip comments and blank lines
        [[ "$type" =~ ^#.*$ || -z "$type" ]] && continue
        # Skip header row
        [[ "$type" == "type" ]] && continue

        # Trim whitespace
        type="${type// /}"
        rule="${rule// /}"
        from="${from// /}"
        comment="${comment//$'\r'/}"  # strip carriage return

        apply_rule "$type" "$rule" "$from" "$comment"
        ((rule_count++))
    done < "$RULES_FILE"

    # Enable UFW
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would enable ufw"
    else
        ufw --force enable 2>&1 | tee -a "$LOG_FILE"
        log_info "UFW enabled"
    fi

    log_info "========================================"
    log_info "UFW setup completed — $rule_count rule(s) processed"
    log_info "========================================"

    if [[ "$DRY_RUN" == false ]]; then
        log_info "Current UFW status:"
        ufw status numbered 2>&1 | tee -a "$LOG_FILE"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage
            exit $EXIT_SUCCESS
            ;;
        -f|--file)
            RULES_FILE="$2"
            shift 2
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