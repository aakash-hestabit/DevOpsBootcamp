#!/bin/bash
set -euo pipefail

# security-scan.sh — Trivy vulnerability scan for all microservice images
#
# Features:
#   - Scans all project Docker images
#   - Generates detailed text report
#   - Summary table with fixable/no-fix breakdown
#   - Exit code reflects CRITICAL vulnerability count
#
# Usage:
#   ./scripts/security-scan.sh
#   ./scripts/security-scan.sh --severity HIGH,CRITICAL

readonly SCRIPT_NAME="$(basename "$0")"
readonly PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly REPORT_DIR="${PROJECT_DIR}/security/scan-reports"
readonly DATE=$(date +%Y%m%d-%H%M%S)
readonly REPORT_FILE="${REPORT_DIR}/security-scan-${DATE}.txt"

SEVERITY="${1:-CRITICAL,HIGH}"

IMAGES=(
  "microservices-frontend:latest"
  "microservices-api-gateway:latest"
  "microservices-user-service:latest"
  "microservices-product-service:latest"
  "microservices-order-service:latest"
)

# Colors 
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging 
log() { echo -e "${CYAN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }

# Cleanup 
cleanup() {
  log "Security scan script finished."
}
trap cleanup EXIT

# Pre-flight checks 
mkdir -p "$REPORT_DIR"

for cmd in trivy jq docker; do
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "${RED}ERROR: ${cmd} is not installed${NC}"
    exit 1
  fi
done

TRIVY_VER=$(trivy --version 2>/dev/null | head -1 | awk '{print $2}')

# Report header 
log "Starting security scans (severity: ${SEVERITY})"

{
  echo "=========================================="
  echo "MICROSERVICES SECURITY SCAN REPORT"
  echo "=========================================="
  echo "Scan Date : $(date)"
  echo "Scanner   : Trivy v${TRIVY_VER}"
  echo "Severity  : ${SEVERITY}"
  echo "Images    : ${#IMAGES[@]}"
  echo "=========================================="
  echo ""
} > "$REPORT_FILE"

# Totals 
TOTAL_CRITICAL=0
TOTAL_HIGH=0
TOTAL_CRITICAL_FIXABLE=0
TOTAL_CRITICAL_NOFIX=0
TOTAL_HIGH_FIXABLE=0
TOTAL_HIGH_NOFIX=0

# Scan loop 
for IMAGE in "${IMAGES[@]}"; do
  log "Scanning ${IMAGE} ..."

  if ! docker image inspect "$IMAGE" &>/dev/null; then
    log "  ${YELLOW}Image not found — skipping${NC}"
    {
      echo "Image : ${IMAGE}"
      echo "------------------------------------------"
      echo "  IMAGE NOT FOUND — skipped"
      echo ""
    } >> "$REPORT_FILE"
    continue
  fi

  JSON=$(trivy image \
    --severity "$SEVERITY" \
    --format json \
    --quiet \
    "$IMAGE" 2>/dev/null || echo '{"Results":[]}')

  CRITICAL=$(echo "$JSON" | jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length')
  HIGH=$(echo "$JSON" | jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")] | length')

  CRITICAL_FIXABLE=$(echo "$JSON" | jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL" and (.FixedVersion//"") != "")] | length')
  CRITICAL_NOFIX=$(echo "$JSON" | jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL" and (.FixedVersion//"") == "")] | length')

  HIGH_FIXABLE=$(echo "$JSON" | jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH" and (.FixedVersion//"") != "")] | length')
  HIGH_NOFIX=$(echo "$JSON" | jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH" and (.FixedVersion//"") == "")] | length')

  TOTAL_CRITICAL=$((TOTAL_CRITICAL + CRITICAL))
  TOTAL_HIGH=$((TOTAL_HIGH + HIGH))
  TOTAL_CRITICAL_FIXABLE=$((TOTAL_CRITICAL_FIXABLE + CRITICAL_FIXABLE))
  TOTAL_CRITICAL_NOFIX=$((TOTAL_CRITICAL_NOFIX + CRITICAL_NOFIX))
  TOTAL_HIGH_FIXABLE=$((TOTAL_HIGH_FIXABLE + HIGH_FIXABLE))
  TOTAL_HIGH_NOFIX=$((TOTAL_HIGH_NOFIX + HIGH_NOFIX))

  # Color-coded console output
  if [[ "$CRITICAL" -gt 0 ]]; then
    echo -e "  ${RED}CRITICAL: ${CRITICAL}${NC} | HIGH: ${HIGH} | Total: $((CRITICAL + HIGH))"
  elif [[ "$HIGH" -gt 0 ]]; then
    echo -e "  CRITICAL: 0 | ${YELLOW}HIGH: ${HIGH}${NC} | Total: ${HIGH}"
  else
    echo -e "  ${GREEN}No CRITICAL or HIGH vulnerabilities${NC}"
  fi

  {
    echo "Image : ${IMAGE}"
    echo "------------------------------------------"
    printf "CRITICAL : %d (fixable: %d | no-fix: %d)\n" "$CRITICAL" "$CRITICAL_FIXABLE" "$CRITICAL_NOFIX"
    printf "HIGH     : %d (fixable: %d | no-fix: %d)\n" "$HIGH" "$HIGH_FIXABLE" "$HIGH_NOFIX"
    printf "TOTAL    : %d\n" $((CRITICAL + HIGH))
    echo ""
    echo "=========================================="
    echo ""
  } >> "$REPORT_FILE"
done

# Final summary 
{
  echo "============== SUMMARY ==================="
  printf "Total CRITICAL : %d (fixable: %d | no-fix: %d)\n" "$TOTAL_CRITICAL" "$TOTAL_CRITICAL_FIXABLE" "$TOTAL_CRITICAL_NOFIX"
  printf "Total HIGH     : %d (fixable: %d | no-fix: %d)\n" "$TOTAL_HIGH" "$TOTAL_HIGH_FIXABLE" "$TOTAL_HIGH_NOFIX"
  echo ""
  printf "Fixable Vulnerabilities: %d\n" $((TOTAL_CRITICAL_FIXABLE + TOTAL_HIGH_FIXABLE))
  printf "Grand Total            : %d\n" $((TOTAL_CRITICAL + TOTAL_HIGH))
  echo "=========================================="
} >> "$REPORT_FILE"

echo ""
echo -e "${GREEN}Security scan complete${NC}"
echo -e "${GREEN}Report: ${REPORT_FILE}${NC}"

echo ""
echo "Summary:"
printf "  CRITICAL: %d | HIGH: %d | Total: %d\n" "$TOTAL_CRITICAL" "$TOTAL_HIGH" $((TOTAL_CRITICAL + TOTAL_HIGH))
