#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MANIFESTS_DIR="${PROJECT_ROOT}/manifests"
LOG_FILE="${PROJECT_ROOT}/cleanup.log"
NAMESPACE="${KUBE_NAMESPACE:-default}"

log_info() { echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*" | tee -a "$LOG_FILE"; }
log_warning() { echo -e "${YELLOW}[⚠]${NC} $*" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[✗]${NC} $*" | tee -a "$LOG_FILE"; }

confirm_action() {
    read -r -p "$(echo -e ${YELLOW}$1${NC}) (yes/no): " response
    [[ "$response" =~ ^([Yy][Ee][Ss]|[Yy])$ ]]
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    command -v kubectl >/dev/null || { log_error "kubectl not found"; exit 1; }
    kubectl cluster-info >/dev/null || { log_error "Cannot connect to cluster"; exit 1; }
    [ -d "$MANIFESTS_DIR" ] || { log_error "Missing manifests dir"; exit 1; }

    log_success "Prerequisites OK"
}

get_resource_count() {
    kubectl get all -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l
}

show_resources() {
    log_info "Resources in $NAMESPACE:"
    kubectl get all,ingress -n "$NAMESPACE" 2>/dev/null || true
}

cleanup_resources() {
    log_info "Removing resources..."

    # FIXED label selector
    kubectl delete ingress -l 'app in (frontend,backend,assets)' -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true

    for svc in frontend-service backend-service assets-service db-service; do
        kubectl delete svc "$svc" -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 && log_success "svc $svc removed"
    done

    for dep in frontend backend assets postgres-db; do
        kubectl delete deploy "$dep" -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 && log_success "deploy $dep removed"
    done

    # FIXED label selector
    kubectl delete all -n "$NAMESPACE" -l 'app in (frontend,backend,assets,postgres)' --ignore-not-found >/dev/null 2>&1 || true

    sleep 5
    log_success "Cleanup done"
}

cleanup_manifests() {
    log_info "Deleting manifests..."

    for f in "$MANIFESTS_DIR"/*.yaml; do
        [ -f "$f" ] || continue
        kubectl delete -f "$f" -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1 || true
    done

    log_success "Manifests deleted"
}

main() {
    > "$LOG_FILE"

    log_info "Starting cleanup..."
    log_info "Namespace: $NAMESPACE"

    check_prerequisites

    kubectl get ns "$NAMESPACE" >/dev/null 2>&1 || {
        log_warning "Namespace not found"
        exit 0
    }

    show_resources

    local count=$(get_resource_count)
    [ "$count" -eq 0 ] && { log_info "Nothing to cleanup"; exit 0; }

    log_warning "This will delete resources"
    confirm_action "Proceed?" || { log_warning "Cancelled"; exit 1; }

    cleanup_manifests
    cleanup_resources

    sleep 3
    show_resources

    local final=$(get_resource_count)
    [ "$final" -eq 0 ] \
        && log_success "All cleaned" \
        || log_warning "Remaining: $final"

    log_info "Logs: $LOG_FILE"
}

main "$@"