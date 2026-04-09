#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MANIFESTS_DIR="${PROJECT_ROOT}/manifests"
LOG_FILE="${PROJECT_ROOT}/deployment.log"
NAMESPACE="${KUBE_NAMESPACE:-default}"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}${NC} $*" | tee -a "$LOG_FILE"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    if [ ! -d "$MANIFESTS_DIR" ]; then
        log_error "Manifests directory not found: $MANIFESTS_DIR"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

wait_for_rollout() {
    local deployment=$1
    local timeout=${2:-300}
    
    log_info "Waiting for rollout of deployment: $deployment..."
    
    if kubectl rollout status deployment/"$deployment" \
        -n "$NAMESPACE" --timeout="${timeout}s" 2>/dev/null; then
        log_success "$deployment rolled out successfully"
        return 0
    else
        log_warning "Rollout timeout for $deployment (this may be normal)"
        return 1
    fi
}

apply_manifest() {
    local manifest=$1
    local name=$(basename "$manifest")
    
    log_info "Applying $name..."
    
    if kubectl apply -f "$manifest" -n "$NAMESPACE" >> "$LOG_FILE" 2>&1; then
        log_success "$name applied successfully"
        return 0
    else
        log_error "Failed to apply $name"
        return 1
    fi
}


main() {
    
    > "$LOG_FILE"
    
    log_info "Starting K8S Bootcamp deployment..."
    log_info "Namespace: $NAMESPACE"
    log_info "Manifests directory: $MANIFESTS_DIR"
    
    check_prerequisites
    
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        log_info "Creating namespace: $NAMESPACE"
        kubectl create namespace "$NAMESPACE" >> "$LOG_FILE" 2>&1
        log_success "Namespace created"
    fi

    declare -a manifests=(
        "db.yaml"
        "db-service.yaml"
        "backend-deployment.yaml"
        "backend-service.yaml"
        "frontend-deployment.yaml"
        "frontend-service.yaml"
        "assets-deployment.yaml"
        "assets-service.yaml"
        "ingress.yaml"
    )
    
    local failed_manifests=()
    
    for manifest in "${manifests[@]}"; do
        if apply_manifest "$MANIFESTS_DIR/$manifest"; then
            sleep 2
        else
            failed_manifests+=("$manifest")
        fi
    done
    
    log_info "Waiting for deployments to be ready..."
    sleep 5
    
    local deployments=("postgres-db" "backend" "frontend" "assets")
    for dep in "${deployments[@]}"; do
        wait_for_rollout "$dep" 180 || true
    done
    
    log_info "Deployment completed!"
    
    log_info "Deployment status:"
    kubectl get deployments -n "$NAMESPACE" >> "$LOG_FILE" 2>&1
    kubectl get deployments -n "$NAMESPACE"
    
    log_info "Service status:"
    kubectl get services -n "$NAMESPACE" >> "$LOG_FILE" 2>&1
    kubectl get services -n "$NAMESPACE"
    
    # Ingress info
    log_info "Ingress status:"
    kubectl get ingress -n "$NAMESPACE" >> "$LOG_FILE" 2>&1
    kubectl get ingress -n "$NAMESPACE"
    
    if [ ${#failed_manifests[@]} -eq 0 ]; then
        log_success "All manifests deployed successfully!"
        log_info "  - Add hosts entries: <cluster ip> www.bootcamp.local api.bootcamp.local assets.bootcamp.local"
        log_info "  - Access frontend: http://www.bootcamp.local"
        log_info "  - Access API: http://api.bootcamp.local"
        log_info "  - Access assets: http://assets.bootcamp.local"
        log_info "Logs saved to: $LOG_FILE"
        return 0
    else
        log_error "Failed to deploy manifests: ${failed_manifests[*]}"
        log_info "Check logs: $LOG_FILE"
        return 1
    fi
}

main "$@"
