#!/usr/bin/env bash

set -Eeuo pipefail

# Defaults
SERVICE=""
NAMESPACE="${NAMESPACE:-default}"
CONTEXT=""
ATTEMPTS=5
TIMEOUT=3


# Usage

usage() {
    cat <<EOF
Service Debug Script - Kubernetes service connectivity tester

Usage:
  $0 --service <name> [options]

Options:
  -s, --service       Service name (required)
  -n, --namespace     Namespace (default: default)
  -c, --context       Kubernetes context
  -a, --attempts      Number of test attempts (default: 5)
  -t, --timeout       Request timeout in seconds (default: 3)
  -h, --help          Show this help message

Examples:
  $0 -s nginx-service
  $0 -s api-service -n prod
  $0 -s web -a 10 -t 5
EOF
}


# Logging

log() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
err() { echo "[ERROR] $*" >&2; }


# Argument Parsing

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--service)
            SERVICE="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -c|--context)
            CONTEXT="--context=$2"
            shift 2
            ;;
        -a|--attempts)
            ATTEMPTS="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            err "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done


# Validation

if [[ -z "$SERVICE" ]]; then
    err "Service name is required"
    usage
    exit 1
fi

if ! command -v kubectl &>/dev/null; then
    err "kubectl not found"
    exit 1
fi

if ! kubectl $CONTEXT get svc "$SERVICE" -n "$NAMESPACE" &>/dev/null; then
    err "Service '$SERVICE' not found in namespace '$NAMESPACE'"
    echo ""
    kubectl $CONTEXT get svc -n "$NAMESPACE"
    exit 1
fi


# Header

echo "=========================================="
echo "   SERVICE TEST: $SERVICE"
echo "   Namespace: $NAMESPACE"
echo "   Time: $(date)"
echo "=========================================="
echo ""


# Service Details

log "SERVICE DETAILS"
kubectl $CONTEXT get svc "$SERVICE" -n "$NAMESPACE" -o wide
echo ""


# Endpoints

log "ENDPOINTS"
kubectl $CONTEXT get endpoints "$SERVICE" -n "$NAMESPACE" -o wide || warn "No endpoints found"
echo ""

ENDPOINT_COUNT=$(kubectl $CONTEXT get endpoints "$SERVICE" -n "$NAMESPACE" \
    -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)

echo "Active endpoints: $ENDPOINT_COUNT"
echo ""

if [[ "$ENDPOINT_COUNT" -eq 0 ]]; then
    warn "No active endpoints - service likely broken"
    exit 1
fi


# Connectivity Test

log "CONNECTIVITY TEST"

TEST_POD="svc-test-$(date +%s)"

kubectl $CONTEXT run "$TEST_POD" \
    --restart=Never \
    --image=busybox:1.36 \
    -n "$NAMESPACE" \
    --command -- sh -c "
echo 'DNS Resolution:'
nslookup $SERVICE 2>/dev/null | grep -A2 'Name:' || echo 'DNS failed'
echo ''

echo 'HTTP Test ($ATTEMPTS attempts):'
for i in \$(seq 1 $ATTEMPTS); do
  RESPONSE=\$(wget -qO- -T $TIMEOUT http://$SERVICE 2>/dev/null | head -1)
  echo \"  Attempt \$i: \${RESPONSE:-FAILED}\"
done
"

# Wait for pod completion
kubectl $CONTEXT wait --for=condition=Ready pod/"$TEST_POD" -n "$NAMESPACE" --timeout=10s 2>/dev/null || true
kubectl $CONTEXT logs "$TEST_POD" -n "$NAMESPACE" || warn "Failed to fetch logs"

# Cleanup
kubectl $CONTEXT delete pod "$TEST_POD" -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1

echo ""
echo "=========================================="
echo "Done"
echo "=========================================="