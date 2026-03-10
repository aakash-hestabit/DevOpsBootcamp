#!/bin/bash
set -euo pipefail

# trust-ssl-cert.sh — Add the self-signed SSL certificate to the system
# trust store so Chrome/Chromium accepts it without warnings.
#
# Works on Debian/Ubuntu with libnss3-tools (certutil).
#
# Usage:
#   sudo ./scripts/trust-ssl-cert.sh

readonly SCRIPT_NAME="$(basename "$0")"
readonly PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly CERT_FILE="${PROJECT_DIR}/ssl/server.crt"
readonly CERT_NAME="Microservices-DevOps-Bootcamp"

log()     { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
log_ok()  { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [OK]    $*"; }
log_err() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; }

if [[ ! -f "$CERT_FILE" ]]; then
  log_err "Certificate not found: ${CERT_FILE}"
  log "  Generate it first: cd ${PROJECT_DIR} && mkdir -p ssl && openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ssl/server.key -out ssl/server.crt -subj '/CN=localhost'"
  exit 1
fi

echo ""
echo "This script will add the self-signed certificate to:"
echo "  1. System CA trust store (/usr/local/share/ca-certificates/)"
echo "  2. Chrome/Chromium NSS database (~/.pki/nssdb)"
echo ""

# System trust store (requires root) 
log "Adding certificate to system trust store ..."

if [[ $EUID -ne 0 ]]; then
  log_err "Root required for system trust store. Run with sudo."
  log "  Example: sudo ${SCRIPT_NAME}"
  exit 1
fi

cp "$CERT_FILE" "/usr/local/share/ca-certificates/${CERT_NAME}.crt"
update-ca-certificates 2>/dev/null
log_ok "System trust store updated"

# Chrome NSS database 
log "Adding certificate to Chrome/Chromium NSS database ..."

if ! command -v certutil &>/dev/null; then
  log "  certutil not found — installing libnss3-tools ..."
  apt-get update -qq && apt-get install -y libnss3-tools
fi

# Add to each user's NSS DB that exists
for nssdb in /home/*/.pki/nssdb; do
  if [[ -d "$nssdb" ]]; then
    local_user=$(basename "$(dirname "$(dirname "$nssdb")")")
    certutil -d sql:"$nssdb" -D -n "$CERT_NAME" 2>/dev/null || true
    certutil -d sql:"$nssdb" -A -t "CT,C,C" -n "$CERT_NAME" -i "$CERT_FILE"
    log_ok "  Added to ${local_user}'s Chrome NSS database"
  fi
done

# Also try for root
if [[ -d "$HOME/.pki/nssdb" ]]; then
  certutil -d sql:"$HOME/.pki/nssdb" -D -n "$CERT_NAME" 2>/dev/null || true
  certutil -d sql:"$HOME/.pki/nssdb" -A -t "CT,C,C" -n "$CERT_NAME" -i "$CERT_FILE"
  log_ok "  Added to root's Chrome NSS database"
fi

echo ""
log_ok "Certificate trusted! Restart Chrome for changes to take effect."
echo ""
echo "  To verify: open https://localhost in Chrome — no warning should appear."
echo "  To remove: sudo certutil -d sql:~/.pki/nssdb -D -n '${CERT_NAME}'"
echo ""
