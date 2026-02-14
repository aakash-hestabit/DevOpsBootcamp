#!/bin/bash
set -euo pipefail

# Script: zone_generator.sh
# Description: Generates forward and reverse BIND DNS zone files from CSV input
# Author: Aakash
# Date: 2026-02-14
# Usage: ./zone_generator.sh [OPTIONS]

readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1
readonly EXIT_CSV_ERROR=2
readonly EXIT_ZONE_ERROR=3
readonly EXIT_BACKUP_ERROR=4

LOG_FILE="logs/$(basename "$0" .sh).log"

mkdir -p "logs"

touch "$LOG_FILE"
chmod 777 "$LOG_FILE"

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE" >&2
}

log_debug() {
    if $VERBOSE; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1" | tee -a "$LOG_FILE"
    fi
}


 # Root check
if [[ "$EUID" -ne 0 ]]; then
    log_error "This script must be run as root"
    exit $EXIT_ERROR
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DATA_DIR="$SCRIPT_DIR"
CSV_FILE="$DATA_DIR/hosts.csv"

ZONE_DIR="/etc/bind/zones"
BACKUP_DIR="/backup/dns"

FORWARD_ZONE="devops.lab"
REVERSE_ZONE="1.168.192.in-addr.arpa"

FORWARD_ZONE_FILE="$ZONE_DIR/db.devops.lab"
REVERSE_ZONE_FILE="$ZONE_DIR/db.192.168.1"

PRIMARY_NS="ns1.devops.lab."
ADMIN_EMAIL="admin.devops.lab."

TTL_DEFAULT=86400
SUBNET_PREFIX="192.168.1"

VERBOSE=false
DRY_RUN=false

mkdir -p "$BACKUP_DIR" "$(dirname "$LOG_FILE")"



# Help
show_usage() {
cat << EOF
Usage: sudo $(basename "$0") [OPTIONS]

Description:
  Generates forward and reverse DNS zone files from a CSV source.
  Performs validation, backups existing zones, and deploys atomically.

OPTIONS:
  -c, --csv FILE         CSV input file (default: ./hosts.csv)
  -f, --forward ZONE     Forward zone name (default: devops.lab)
  -r, --reverse ZONE     Reverse zone name
  -n, --dry-run          Generate zones but do not deploy
  -v, --verbose          Enable verbose logging
  -h, --help             Show this help message

Example:
  sudo $(basename "$0") -c hosts.csv -v
  sudo $(basename "$0") --dry-run
EOF
}

# Argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--csv)
            CSV_FILE="$2"
            shift 2
            ;;
        -f|--forward)
            FORWARD_ZONE="$2"
            FORWARD_ZONE_FILE="$ZONE_DIR/db.${FORWARD_ZONE}"
            shift 2
            ;;
        -r|--reverse)
            REVERSE_ZONE="$2"
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit $EXIT_SUCCESS
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit $EXIT_ERROR
            ;;
    esac
done

valid_ip() {
    [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

generate_serial() {
    local current_serial="$1"
    local today
    today=$(date +%Y%m%d)

    if [[ "$current_serial" =~ ^$today ]]; then
        printf "%d" "$((current_serial + 1))"
    else
        printf "%s01" "$today"
    fi
}

backup_zones() {
    local ts
    ts=$(date +%Y%m%d_%H%M%S)

    tar -czf "${BACKUP_DIR}/dns_backup_${ts}.tar.gz" \
        "$FORWARD_ZONE_FILE" "$REVERSE_ZONE_FILE" 2>/dev/null || {
        log_error "Zone backup failed"
        exit $EXIT_BACKUP_ERROR
    }

    log_info "Backup created: dns_backup_${ts}.tar.gz"
}

main() {
    log_info "Zone generation started"


    [[ -f "$CSV_FILE" ]] || {
        log_error "CSV file not found: $CSV_FILE"
        exit $EXIT_CSV_ERROR
    }

    log_debug "Using CSV file: $CSV_FILE"
    log_debug "Forward zone: $FORWARD_ZONE"
    log_debug "Reverse zone: $REVERSE_ZONE"

    backup_zones

    current_serial=$(awk '/Serial/ {print $1}' "$FORWARD_ZONE_FILE" 2>/dev/null || echo "")
    new_serial=$(generate_serial "$current_serial")

    log_debug "Generated SOA serial: $new_serial"

    tmp_forward=$(mktemp)
    tmp_reverse=$(mktemp)

    # Forward Zone Header 
    cat << EOF > "$tmp_forward"
\$TTL $TTL_DEFAULT
@   IN  SOA $PRIMARY_NS $ADMIN_EMAIL (
        $new_serial
        604800
        86400
        2419200
        300 )

@       IN  NS  $PRIMARY_NS

EOF

    # Reverse Zone Header 
    cat << EOF > "$tmp_reverse"
\$TTL $TTL_DEFAULT
@   IN  SOA $PRIMARY_NS $ADMIN_EMAIL (
        $new_serial
        604800
        86400
        2419200
        300 )

@       IN  NS  $PRIMARY_NS

EOF

    tail -n +2 "$CSV_FILE" | while IFS=',' read -r hostname ip type alias; do
        [[ -n "$hostname" && -n "$ip" && -n "$type" ]] || {
            log_error "Invalid CSV row: $hostname,$ip,$type,$alias"
            exit $EXIT_CSV_ERROR
        }

        valid_ip "$ip" || {
            log_error "Invalid IP address: $ip"
            exit $EXIT_CSV_ERROR
        }

        last_octet="${ip##*.}"

        echo "$hostname    IN  A   $ip" >> "$tmp_forward"

        if [[ -n "$alias" ]]; then
            echo "$alias       IN  CNAME $hostname" >> "$tmp_forward"
        fi

        echo "$last_octet   IN  PTR ${hostname}.${FORWARD_ZONE}." >> "$tmp_reverse"
    done

    named-checkzone "$FORWARD_ZONE" "$tmp_forward" >/dev/null || {
        log_error "Forward zone validation failed"
        exit $EXIT_ZONE_ERROR
    }

    named-checkzone "$REVERSE_ZONE" "$tmp_reverse" >/dev/null || {
        log_error "Reverse zone validation failed"
        exit $EXIT_ZONE_ERROR
    }

    if $DRY_RUN; then
        log_info "Dry-run enabled — zones generated but not deployed"
    else
        mv "$tmp_forward" "$FORWARD_ZONE_FILE"
        mv "$tmp_reverse" "$REVERSE_ZONE_FILE"
        chown root:bind "$FORWARD_ZONE_FILE" "$REVERSE_ZONE_FILE"
        chmod 640 "$FORWARD_ZONE_FILE" "$REVERSE_ZONE_FILE"

        sudo systemctl restart bind9

        log_info "Zones deployed successfully with correct permissions"
    fi

    log_info "Zone generation completed with serial $new_serial"
    exit $EXIT_SUCCESS
}

main "$@"