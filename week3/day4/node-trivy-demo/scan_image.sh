#!/bin/bash
# scan_image.sh — Trivy vulnerability scanner for express-basic:1.0
# Scans for HIGH and CRITICAL severities only, reports fixability
# Usage: ./scan_image.sh

IMAGE="express-basic:1.0"
REPORT_DIR="reports"
SCAN_DATE=$(date "+%Y-%m-%d %H:%M:%S")
TRIVY_VERSION=$(trivy --version 2>&1 | head -1 | awk '{print $2}')
REPORT_FILE="${REPORT_DIR}/vuln-report-$(date +%Y%m%d-%H%M%S).txt"

# helpers 
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_banner() {
  echo ""
  echo -e "${BOLD}${CYAN}========== VULNERABILITY SCAN REPORT ==========${NC}"
}

print_footer() {
  echo -e "${BOLD}${CYAN}================================================${NC}"
  echo ""
}

# pre-flight checks 
if ! command -v trivy &>/dev/null; then
  echo -e "${RED}ERROR: Trivy is not installed or not in PATH.${NC}"
  echo "Install: https://trivy.dev/latest/getting-started/installation/"
  exit 1
fi

if ! command -v docker &>/dev/null; then
  echo -e "${RED}ERROR: Docker is not installed or not in PATH.${NC}"
  exit 1
fi

if ! docker image inspect "${IMAGE}" &>/dev/null 2>&1; then
  echo -e "${RED}ERROR: Image '${IMAGE}' not found.${NC}"
  echo "Build it first with:  docker build -t ${IMAGE} ."
  exit 1
fi

mkdir -p "${REPORT_DIR}"

# run trivy (JSON for parsing) 
echo -e "${CYAN}[*] Scanning image: ${IMAGE} — severity HIGH,CRITICAL ...${NC}"
JSON_OUT=$(trivy image \
  --severity HIGH,CRITICAL \
  --format json \
  --quiet \
  "${IMAGE}" 2>/dev/null)

if [[ $? -ne 0 ]]; then
  echo -e "${RED}ERROR: Trivy scan failed.${NC}"
  exit 1
fi

# parse counts 
CRITICAL_TOTAL=$(echo "${JSON_OUT}" | jq '[.Results[]? | .Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length')
HIGH_TOTAL=$(echo "${JSON_OUT}"     | jq '[.Results[]? | .Vulnerabilities[]? | select(.Severity=="HIGH")]     | length')

CRITICAL_FIXABLE=$(echo "${JSON_OUT}" | jq '[.Results[]? | .Vulnerabilities[]? | select(.Severity=="CRITICAL" and (.FixedVersion // "" | . != ""))] | length')
CRITICAL_UNFIXED=$(echo "${JSON_OUT}" | jq '[.Results[]? | .Vulnerabilities[]? | select(.Severity=="CRITICAL" and (.FixedVersion // "" | . == ""))] | length')

HIGH_FIXABLE=$(echo "${JSON_OUT}" | jq '[.Results[]? | .Vulnerabilities[]? | select(.Severity=="HIGH" and (.FixedVersion // "" | . != ""))] | length')
HIGH_UNFIXED=$(echo "${JSON_OUT}" | jq '[.Results[]? | .Vulnerabilities[]? | select(.Severity=="HIGH" and (.FixedVersion // "" | . == ""))] | length')

TOTAL=$((CRITICAL_TOTAL + HIGH_TOTAL))

# build report text 
REPORT_TEXT=$(cat <<EOF
========== VULNERABILITY SCAN REPORT ==========
Image:      ${IMAGE}
Scan Date:  ${SCAN_DATE}
Scanner:    Trivy v${TRIVY_VERSION}

Severity Summary (HIGH + CRITICAL only):
  CRITICAL: ${CRITICAL_TOTAL}
  HIGH:     ${HIGH_TOTAL}
  TOTAL:    ${TOTAL}

Fixability Breakdown:
  CRITICAL fixable  : ${CRITICAL_FIXABLE}
  CRITICAL unfixed  : ${CRITICAL_UNFIXED}
  HIGH     fixable  : ${HIGH_FIXABLE}
  HIGH     unfixed  : ${HIGH_UNFIXED}

EOF
)

# top CRITICAL CVEs 
TOP_CRITICAL=$(echo "${JSON_OUT}" | jq -r '
  [.Results[]? | .Vulnerabilities[]? | select(.Severity=="CRITICAL")]
  | to_entries
  | map("  \(.key+1). \(.value.VulnerabilityID) — \(.value.PkgName) \(.value.InstalledVersion)  [\(if (.value.FixedVersion // "") != "" then "FIXABLE --> " + .value.FixedVersion else "NO FIX AVAILABLE" end)]")
  | .[:10]
  | .[]
' 2>/dev/null)

TOP_HIGH=$(echo "${JSON_OUT}" | jq -r '
  [.Results[]? | .Vulnerabilities[]? | select(.Severity=="HIGH")]
  | to_entries
  | map("  \(.key+1). \(.value.VulnerabilityID) — \(.value.PkgName) \(.value.InstalledVersion)  [\(if (.value.FixedVersion // "") != "" then "FIXABLE --> " + .value.FixedVersion else "NO FIX AVAILABLE" end)]")
  | .[:10]
  | .[]
' 2>/dev/null)

if [[ -n "${TOP_CRITICAL}" ]]; then
  REPORT_TEXT+="Top CRITICAL Vulnerabilities (up to 10):
${TOP_CRITICAL}

"
else
  REPORT_TEXT+="Top CRITICAL Vulnerabilities:
  None found.

"
fi

if [[ -n "${TOP_HIGH}" ]]; then
  REPORT_TEXT+="Top HIGH Vulnerabilities (up to 10):
${TOP_HIGH}

"
else
  REPORT_TEXT+="Top HIGH Vulnerabilities:
  None found.

"
fi

REPORT_TEXT+="================================================"

# print to terminal 
print_banner
echo "${REPORT_TEXT}" | while IFS= read -r line; do
  if echo "${line}" | grep -q "CRITICAL:"; then
    echo -e "${RED}${line}${NC}"
  elif echo "${line}" | grep -q "HIGH:"; then
    echo -e "${YELLOW}${line}${NC}"
  elif echo "${line}" | grep -q "FIXABLE"; then
    echo -e "${GREEN}${line}${NC}"
  elif echo "${line}" | grep -q "NO FIX"; then
    echo -e "${RED}${line}${NC}"
  else
    echo "${line}"
  fi
done
print_footer

# save report 
echo "${REPORT_TEXT}" > "${REPORT_FILE}"
echo -e "${GREEN}[✓] Report saved --> ${REPORT_FILE}${NC}"
echo ""

# raw trivy human-readable output 
echo -e "${CYAN}[*] Full Trivy table output:${NC}"
trivy image --severity HIGH,CRITICAL --quiet "${IMAGE}"
