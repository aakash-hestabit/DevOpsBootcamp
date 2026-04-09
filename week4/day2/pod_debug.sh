#!/usr/bin/env bash

set -Eeuo pipefail


# Defaults

NAMESPACE="default"
TAIL_LINES=20
POD_NAME=""
CONTEXT=""
SHOW_PREVIOUS=false


# Colors

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'


# Usage

usage() {
    cat <<EOF
Pod Debug Script - Kubernetes troubleshooting helper

Usage:
  $0 --pod <pod-name> [options]

Options:
  -p, --pod           Pod name (required)
  -n, --namespace     Namespace (default: default)
  -t, --tail          Log lines to show (default: 20)
  -c, --context       Kubernetes context
      --previous      Show logs from previous container
  -h, --help          Show this help message

Examples:
  $0 --pod nginx
  $0 -p nginx -n kube-system
  $0 -p api-pod --tail 100 --previous
EOF
}


# Logging helpers

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $*${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $*${NC}"; }
err() { echo -e "${RED}[ERROR] $*${NC}" >&2; }


# Argument parsing

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--pod)
            POD_NAME="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -t|--tail)
            TAIL_LINES="$2"
            shift 2
            ;;
        -c|--context)
            CONTEXT="--context=$2"
            shift 2
            ;;
        --previous)
            SHOW_PREVIOUS=true
            shift
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

if [[ -z "$POD_NAME" ]]; then
    err "Pod name is required"
    usage
    exit 1
fi

if ! command -v kubectl &>/dev/null; then
    err "kubectl not found"
    exit 1
fi

# Check pod existence
if ! kubectl $CONTEXT get pod "$POD_NAME" -n "$NAMESPACE" &>/dev/null; then
    err "Pod '$POD_NAME' not found in namespace '$NAMESPACE'"
    echo ""
    kubectl $CONTEXT get pods -n "$NAMESPACE"
    exit 1
fi


# Header

echo "========================================"
echo "   POD DEBUG: $POD_NAME"
echo "   Namespace: $NAMESPACE"
echo "   Time: $(date)"
echo "========================================"
echo ""


# Status

log "POD STATUS"
kubectl $CONTEXT get pod "$POD_NAME" -n "$NAMESPACE" -o wide
echo ""


# Containers

log "CONTAINERS"
CONTAINERS=$(kubectl $CONTEXT get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[*].name}')
kubectl $CONTEXT get pod "$POD_NAME" -n "$NAMESPACE" \
    -o jsonpath='{range .spec.containers[*]}{.name}{"\t"}{.image}{"\n"}{end}'
echo ""


# Conditions

log "CONDITIONS"
kubectl $CONTEXT get pod "$POD_NAME" -n "$NAMESPACE" \
    -o jsonpath='{range .status.conditions[*]}{.type}{": "}{.status}{" ("}{.reason}{")"}{"\n"}{end}'
echo ""


# Events

log "RECENT EVENTS"
kubectl $CONTEXT get events -n "$NAMESPACE" \
    --field-selector "involvedObject.name=$POD_NAME" \
    --sort-by='.lastTimestamp' | tail -10 || warn "No events found"
echo ""


# Logs

log "LOGS"
for CONTAINER in $CONTAINERS; do
    echo "--- Container: $CONTAINER ---"
    kubectl $CONTEXT logs "$POD_NAME" -n "$NAMESPACE" -c "$CONTAINER" \
        --tail="$TAIL_LINES" $( $SHOW_PREVIOUS && echo "--previous" ) \
        2>/dev/null || warn "No logs available for $CONTAINER"
    echo ""
done


# Metrics

log "RESOURCE USAGE"
kubectl $CONTEXT top pod "$POD_NAME" -n "$NAMESPACE" \
    2>/dev/null || warn "Metrics server not installed"
echo ""


# Debug Commands

echo "========================================"
echo "Useful commands:"
echo "kubectl describe pod $POD_NAME -n $NAMESPACE"
echo "kubectl logs $POD_NAME -n $NAMESPACE -f"
echo "kubectl exec -it $POD_NAME -n $NAMESPACE -- /bin/sh"
echo "========================================"