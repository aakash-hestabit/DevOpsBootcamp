#!/usr/bin/env bash

set -Eeuo pipefail

# Defaults
NAMESPACE="${NAMESPACE:-default}"
INGRESS_NS="ingress-nginx"
CONTEXT=""
TIMEOUT=3
RETRIES=3

# Usage
usage() {
    cat <<EOF
Ingress Test Script - Kubernetes ingress validation tool

Usage:
  $0 [options]

Options:
  -n, --namespace       Target namespace (default: default)
  -i, --ingress-ns      Ingress controller namespace (default: ingress-nginx)
  -c, --context         Kubernetes context
  -t, --timeout         Curl timeout in seconds (default: 3)
  -r, --retries         Number of retries (default: 3)
  -h, --help            Show this help message

Examples:
  $0
  $0 -n prod
  $0 -c minikube
  $0 -t 5 -r 5
EOF
}

# Logging
log() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
err() { echo "[ERROR] $*" >&2; }

# Argument Parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -i|--ingress-ns)
            INGRESS_NS="$2"
            shift 2
            ;;
        -c|--context)
            CONTEXT="--context=$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -r|--retries)
            RETRIES="$2"
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
for cmd in kubectl curl; do
    if ! command -v "$cmd" &>/dev/null; then
        err "$cmd not found"
        exit 1
    fi
done

# Header
echo "=========================================="
echo "   INGRESS TEST SUITE"
echo "   Namespace: $NAMESPACE"
echo "   Time: $(date)"
echo "=========================================="
echo ""

# Controller Check
log "INGRESS CONTROLLER"
kubectl $CONTEXT get pods -n "$INGRESS_NS" \
    -l app.kubernetes.io/component=controller \
    || warn "Ingress controller not found"
echo ""

# Ingress Resources
log "INGRESS RESOURCES"
kubectl $CONTEXT get ingress -n "$NAMESPACE" || warn "No ingress found"
echo ""

# Detect Cluster IP
CLUSTER_IP=$(kubectl $CONTEXT get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "localhost")

echo "Cluster IP: $CLUSTER_IP"
echo ""

# Test Function
test_url() {
    local url="$1"
    local host_header="${2:-}"
    
    local curl_opts=("-s" "-o" "/dev/null" "-w" "%{http_code}" "--max-time" "$TIMEOUT" "-L")
    
    if [[ -n "$host_header" ]]; then
        curl_opts+=("-H" "Host: $host_header")
    fi

    for ((i=1; i<=RETRIES; i++)); do
        STATUS=$(curl "${curl_opts[@]}" "$url" || echo "000")
        
        if [[ "$STATUS" =~ ^[0-9]{3}$ ]] && [[ "$STATUS" != "000" ]]; then
            echo "$STATUS"
            return
        fi
        sleep 1
    done

    echo "FAIL"
}

# Test Ingress Rules
log "TESTING INGRESS RULES"

INGRESSES=$(kubectl $CONTEXT get ingress -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')

if [[ -z "$INGRESSES" ]]; then
    warn "No ingress resources found"
    exit 0
fi

for INGRESS in $INGRESSES; do
    echo ""
    echo "--- Ingress: $INGRESS ---"

    HOSTS=$(kubectl $CONTEXT get ingress "$INGRESS" -n "$NAMESPACE" \
        -o jsonpath='{.spec.rules[*].host}')

    PATHS=$(kubectl $CONTEXT get ingress "$INGRESS" -n "$NAMESPACE" \
        -o jsonpath='{.spec.rules[*].http.paths[*].path}')

    if [[ -z "$HOSTS" ]]; then
        for PATH_ITEM in $PATHS; do
            URL="http://$CLUSTER_IP$PATH_ITEM"
            echo -n "  $URL -> "
            test_url "$URL"
        done
    else
        for HOST in $HOSTS; do
            URL="http://$CLUSTER_IP/"
            echo -n "  $HOST -> "
            test_url "$URL" "$HOST"
        done
    fi
done

# Controller Logs
echo ""
log "INGRESS CONTROLLER LOGS"
kubectl $CONTEXT logs -n "$INGRESS_NS" \
    -l app.kubernetes.io/component=controller \
    --tail=10 2>/dev/null || warn "Cannot fetch logs"

echo ""
echo "=========================================="
echo "Done"
echo "=========================================="