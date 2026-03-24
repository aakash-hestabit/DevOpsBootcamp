#!/usr/bin/env bash
# cluster_status.sh - Production-ready Kubernetes cluster health check

set -euo pipefail

SCRIPT_NAME=$(basename "$0")

# Defaults

NAMESPACE="all"
SHOW_WARNINGS=5


# Help Function

usage() {
    cat <<EOF
${SCRIPT_NAME} - Kubernetes Cluster Health Check

USAGE:
  ${SCRIPT_NAME} [OPTIONS]

OPTIONS:
  -n, --namespace <ns>   Check specific namespace (default: all)
  -w, --warnings <num>   Number of recent warnings to show (default: 5)
  -h, --help             Show this help message and exit

DESCRIPTION:
  This script provides a quick overview of Kubernetes cluster health:
  - Cluster connectivity
  - Node status
  - Resource usage (if metrics-server available)
  - Pod summary (Running, Pending, Failed)
  - Recent warning events
  - Minikube status (if available)

EXAMPLES:
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} --namespace default
  ${SCRIPT_NAME} --warnings 10

EOF
}


# Argument Parsing

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -w|--warnings)
            SHOW_WARNINGS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done


# Logging helpers

log() { echo -e "$*"; }
error() { echo -e "❌ $*" >&2; }
success() { echo -e "✓ $*"; }


# Header

log "========================================"
log "   KUBERNETES CLUSTER STATUS"
log "   $(date)"
log "========================================"
log ""


# Check dependencies

if ! command -v kubectl &>/dev/null; then
    error "kubectl is not installed"
    exit 1
fi


# Cluster connectivity

if ! kubectl cluster-info &>/dev/null; then
    error "Cannot connect to cluster!"
    log "   Try: minikube start OR check kubeconfig"
    exit 1
fi

success "Cluster is reachable"
log ""


# Node status

log "=== NODES ==="
kubectl get nodes -o custom-columns=\
'NAME:.metadata.name,STATUS:.status.conditions[-1].type,VERSION:.status.nodeInfo.kubeletVersion,OS:.status.nodeInfo.osImage' \
|| error "Failed to fetch nodes"
log ""


# Node resources

log "=== NODE RESOURCES ==="
if kubectl top nodes &>/dev/null; then
    kubectl top nodes
else
    log "Metrics not available (install metrics-server)"
fi
log ""


# Pod Summary

log "=== POD SUMMARY ==="

if [[ "$NAMESPACE" == "all" ]]; then
    POD_CMD="kubectl get pods -A --no-headers"
else
    POD_CMD="kubectl get pods -n ${NAMESPACE} --no-headers"
fi

TOTAL=$($POD_CMD 2>/dev/null | wc -l | tr -d ' ')
RUNNING=$($POD_CMD 2>/dev/null | awk '$4=="Running"' | wc -l | tr -d ' ')
PENDING=$($POD_CMD 2>/dev/null | awk '$4=="Pending"' | wc -l | tr -d ' ')
FAILED=$($POD_CMD 2>/dev/null | awk '$4 ~ /Error|CrashLoopBackOff|Failed/' | wc -l | tr -d ' ')

log "Total Pods: ${TOTAL:-0}"
log "  Running:  ${RUNNING:-0}"
log "  Pending:  ${PENDING:-0}"
log "  Failed:   ${FAILED:-0}"
log ""


# Recent warnings

log "=== RECENT WARNINGS (last ${SHOW_WARNINGS}) ==="

if kubectl get events -A &>/dev/null; then
    kubectl get events -A \
        --field-selector type=Warning \
        --sort-by='.lastTimestamp' \
        | tail -n "${SHOW_WARNINGS}"
else
    log "Unable to fetch events"
fi
log ""


# Minikube status

if command -v minikube &>/dev/null; then
    log "=== MINIKUBE STATUS ==="
    minikube status || log "Minikube not running"
    log ""
fi


# Footer

log "========================================"
success "Cluster check completed"