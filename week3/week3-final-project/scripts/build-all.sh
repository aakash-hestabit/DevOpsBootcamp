#!/bin/bash
set -euo pipefail

# build-all.sh — Build all Docker images for the microservices platform
#
# Features:
#   - Parallel-safe sequential build for each service
#   - Build timing per image
#   - Image size summary table
#   - Exit code reflects overall success
#
# Usage:
#   ./scripts/build-all.sh
#   ./scripts/build-all.sh --no-cache

readonly SCRIPT_NAME="$(basename "$0")"
readonly PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
readonly LOG_DIR="${PROJECT_DIR}/var/log"
readonly LOG_FILE="${LOG_DIR}/build.log"

DOCKER_BUILD_ARGS=""

# Services to build: <directory> <image-name>
declare -A SERVICES=(
  ["frontend"]="microservices-frontend"
  ["api-gateway"]="microservices-api-gateway"
  ["services/user-service"]="microservices-user-service"
  ["services/product-service"]="microservices-product-service"
  ["services/order-service"]="microservices-order-service"
)

# Logging 
mkdir -p "$LOG_DIR"
log()     { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "$LOG_FILE"; }
log_ok()  { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [OK]    $*" | tee -a "$LOG_FILE"; }
log_err() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_FILE" >&2; }

# Cleanup trap 
cleanup() {
  log "Build script finished."
}
trap cleanup EXIT

# Argument parsing 
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-cache) DOCKER_BUILD_ARGS="--no-cache" ;;
    -h|--help)
      echo "Usage: ${SCRIPT_NAME} [--no-cache]"
      echo "Build all Docker images for the microservices platform."
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

# Pre-flight checks 
if ! command -v docker &>/dev/null; then
  log_err "docker is not installed"
  exit 1
fi

# Build each image 
TOTAL=0
FAILED=0
SUCCEEDED=0
declare -a FAILED_SERVICES=()

cd "$PROJECT_DIR"

log "=== Building all Docker images ==="
echo ""

for svc_dir in "${!SERVICES[@]}"; do
  image_name="${SERVICES[$svc_dir]}"
  TOTAL=$((TOTAL + 1))

  if [[ ! -d "${PROJECT_DIR}/${svc_dir}" ]]; then
    log_err "${svc_dir}: directory not found — skipped"
    FAILED=$((FAILED + 1))
    FAILED_SERVICES+=("$svc_dir")
    continue
  fi

  log "Building ${image_name} from ./${svc_dir} ..."
  start_time=$(date +%s)

  # shellcheck disable=SC2086
  if docker build $DOCKER_BUILD_ARGS -t "${image_name}:latest" "./${svc_dir}" >> "$LOG_FILE" 2>&1; then
    elapsed=$(( $(date +%s) - start_time ))
    log_ok "${image_name}: built in ${elapsed}s"
    SUCCEEDED=$((SUCCEEDED + 1))
  else
    elapsed=$(( $(date +%s) - start_time ))
    log_err "${image_name}: FAILED after ${elapsed}s (see ${LOG_FILE})"
    FAILED=$((FAILED + 1))
    FAILED_SERVICES+=("$svc_dir")
  fi
done

# Summary 
echo ""
echo "========================================"
echo "Build Summary"
echo "========================================"
echo "  Total  : ${TOTAL}"
echo "  Success: ${SUCCEEDED}"
echo "  Failed : ${FAILED}"

if [[ ${#FAILED_SERVICES[@]} -gt 0 ]]; then
  echo ""
  echo "  Failed services:"
  for f in "${FAILED_SERVICES[@]}"; do
    echo "    - ${f}"
  done
fi

echo ""
echo "Image Sizes:"
docker images --filter "reference=microservices-*" --format "  {{.Repository}}:{{.Tag}}\t{{.Size}}" 2>/dev/null || true
echo "========================================"

if [[ "$FAILED" -gt 0 ]]; then
  exit 1
fi
