#!/bin/bash
# scan-images.sh
# Scans all local Docker images for CRITICAL and HIGH CVEs
# using Trivy and generates ONE consolidated report.
#
# Usage:
#   ./scan-images.sh
#   ./scan-images.sh --help

# help function 
show_help() {
cat << EOF
Docker Image Vulnerability Scanner

This script scans ALL local Docker images using Trivy and reports
CRITICAL and HIGH vulnerabilities.

Features:
- Scans every local Docker image
- Filters CRITICAL and HIGH severity
- Shows fixable vs non-fixable vulnerabilities
- Generates a single consolidated report

Usage:
  ./scan-images.sh

Options:
  --help      Show this help message

Requirements:
  - docker
  - trivy
  - jq

Output:
  ./trivy-reports/scan-report-<timestamp>.txt
EOF
}

# check for help flag
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
    exit 0
fi

# config 
REPORT_DIR="$(dirname "$0")/trivy-reports"
DATE=$(date +%Y%m%d-%H%M%S)
REPORT_FILE="${REPORT_DIR}/scan-report-${DATE}.txt"
SEVERITY="CRITICAL,HIGH"

# colours 
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# pre-flight checks 
for cmd in trivy docker jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "${RED}ERROR: '$cmd' not found in PATH.${NC}"
    exit 1
  fi
done

mkdir -p "$REPORT_DIR"

TRIVY_VER=$(trivy --version 2>&1 | head -1 | awk '{print $2}')

# collect docker images 
mapfile -t IMAGES < <(docker images --format "{{.Repository}}:{{.Tag}}" \
  | grep -v "<none>" | sort -u)

if [[ ${#IMAGES[@]} -eq 0 ]]; then
  echo -e "${YELLOW}No local images found.${NC}"
  exit 0
fi

echo -e "${CYAN}[*] Found ${#IMAGES[@]} image(s) to scan.${NC}"
echo ""

# report header 
{
echo "=========================================="
echo "     DOCKER IMAGE SECURITY SCAN REPORT"
echo "=========================================="
echo "Scan Date : $(date '+%Y-%m-%d %H:%M:%S')"
echo "Scanner   : Trivy v${TRIVY_VER}"
echo "Severity  : ${SEVERITY}"
echo "Images    : ${#IMAGES[@]}"
echo "=========================================="
echo ""
} > "$REPORT_FILE"

# totals
TOTAL_CRITICAL=0
TOTAL_HIGH=0
TOTAL_CRITICAL_FIXABLE=0
TOTAL_CRITICAL_NOFIX=0
TOTAL_HIGH_FIXABLE=0
TOTAL_HIGH_NOFIX=0

# scanning loop 
for IMAGE in "${IMAGES[@]}"; do

  echo -e "${CYAN}[*] Scanning ${IMAGE}${NC}"

  JSON=$(trivy image \
    --severity "$SEVERITY" \
    --format json \
    --quiet \
    "$IMAGE" 2>/dev/null)

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

{
echo "Image : ${IMAGE}"
echo "------------------------------------------"
printf "CRITICAL : %d (fixable: %d | no-fix: %d)\n" "$CRITICAL" "$CRITICAL_FIXABLE" "$CRITICAL_NOFIX"
printf "HIGH     : %d (fixable: %d | no-fix: %d)\n" "$HIGH" "$HIGH_FIXABLE" "$HIGH_NOFIX"
printf "TOTAL    : %d\n" $((CRITICAL + HIGH))
echo ""

if [[ $CRITICAL -gt 0 ]]; then
  echo "CRITICAL Vulnerabilities:"
  echo "$JSON" | jq -r '
    [.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")]
    | .[]
    | "  \(.VulnerabilityID) | pkg=\(.PkgName) | installed=\(.InstalledVersion) | fix=\(.FixedVersion // "NO FIX")"
  '
  echo ""
fi

if [[ $HIGH -gt 0 ]]; then
  echo "HIGH Vulnerabilities:"
  echo "$JSON" | jq -r '
    [.Results[]?.Vulnerabilities[]? | select(.Severity=="HIGH")]
    | .[]
    | "  \(.VulnerabilityID) | pkg=\(.PkgName) | installed=\(.InstalledVersion) | fix=\(.FixedVersion // "NO FIX")"
  '
  echo ""
fi

echo "=========================================="
echo ""

} >> "$REPORT_FILE"

done

# summary 
{
echo "============== SUMMARY ==================="
printf "Total CRITICAL : %d\n" "$TOTAL_CRITICAL"
printf "   Fixable     : %d\n" "$TOTAL_CRITICAL_FIXABLE"
printf "   No Fix      : %d\n" "$TOTAL_CRITICAL_NOFIX"
echo ""

printf "Total HIGH     : %d\n" "$TOTAL_HIGH"
printf "   Fixable     : %d\n" "$TOTAL_HIGH_FIXABLE"
printf "   No Fix      : %d\n" "$TOTAL_HIGH_NOFIX"
echo ""

printf "Total Fixable Vulnerabilities : %d\n" $((TOTAL_CRITICAL_FIXABLE + TOTAL_HIGH_FIXABLE))
printf "Grand Total Vulnerabilities   : %d\n" $((TOTAL_CRITICAL + TOTAL_HIGH))
echo "=========================================="
} >> "$REPORT_FILE"

echo -e "${GREEN}[#] Scan completed${NC}"
echo -e "${GREEN}[#] Report generated: ${REPORT_FILE}${NC}"