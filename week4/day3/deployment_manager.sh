#!/bin/bash
# deployment_manager.sh - Deployment management helper

set -euo pipefail

NAMESPACE="${NAMESPACE:-default}"

show_help() {
    cat << 'EOF'
Deployment Manager

Usage: ./deployment_manager.sh <command> [options]

Commands:
    list                List all deployments
    status <name>       Show deployment status
    scale <name> <n>    Scale deployment to n replicas
    update <name> <img> Update deployment image
    rollback <name>     Rollback to previous version
    history <name>      Show deployment history
    restart <name>      Restart all pods

Examples:
    ./deployment_manager.sh list
    ./deployment_manager.sh status nginx-deployment
    ./deployment_manager.sh scale nginx-deployment 5
    ./deployment_manager.sh update nginx-deployment nginx:1.26-alpine
    ./deployment_manager.sh rollback nginx-deployment
EOF
}

list_deployments() {
    echo "=== Deployments in ${NAMESPACE} ==="
    kubectl get deployments -n "${NAMESPACE}" -o wide
    echo ""
    echo "=== Pods ==="
    kubectl get pods -n "${NAMESPACE}" -o wide
}

show_status() {
    local name="${1:?Deployment name required}"
    
    echo "=== Deployment: ${name} ==="
    kubectl get deployment "${name}" -n "${NAMESPACE}" -o wide
    echo ""
    
    echo "=== ReplicaSets ==="
    kubectl get rs -n "${NAMESPACE}" -l "app=${name}" 2>/dev/null || \
        kubectl get rs -n "${NAMESPACE}" | grep "${name}" || echo "No ReplicaSets found"
    echo ""
    
    echo "=== Pods ==="
    kubectl get pods -n "${NAMESPACE}" -l "app=${name}" 2>/dev/null || \
        kubectl get pods -n "${NAMESPACE}" | grep "${name}" || echo "No pods found"
    echo ""
    
    echo "=== Rollout Status ==="
    kubectl rollout status deployment/"${name}" -n "${NAMESPACE}" --timeout=5s 2>/dev/null || echo "Rollout in progress or deployment not found"
}

scale_deployment() {
    local name="${1:?Deployment name required}"
    local replicas="${2:?Replica count required}"
    
    echo "Scaling ${name} to ${replicas} replicas..."
    kubectl scale deployment "${name}" -n "${NAMESPACE}" --replicas="${replicas}"
    
    echo "Waiting for rollout..."
    kubectl rollout status deployment/"${name}" -n "${NAMESPACE}"
    
    echo ""
    echo "Current state:"
    kubectl get deployment "${name}" -n "${NAMESPACE}"
}

update_image() {
    local name="${1:?Deployment name required}"
    local image="${2:?Image required}"
    
    # Get container name
    local container=$(kubectl get deployment "${name}" -n "${NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].name}')
    
    echo "Updating ${name} container '${container}' to image: ${image}"
    kubectl set image deployment/"${name}" "${container}=${image}" -n "${NAMESPACE}"
    
    echo "Watching rollout..."
    kubectl rollout status deployment/"${name}" -n "${NAMESPACE}"
}

rollback_deployment() {
    local name="${1:?Deployment name required}"
    local revision="${2:-}"
    
    echo "Current history:"
    kubectl rollout history deployment/"${name}" -n "${NAMESPACE}"
    echo ""
    
    if [ -z "${revision}" ]; then
        echo "Rolling back to previous version..."
        kubectl rollout undo deployment/"${name}" -n "${NAMESPACE}"
    else
        echo "Rolling back to revision ${revision}..."
        kubectl rollout undo deployment/"${name}" -n "${NAMESPACE}" --to-revision="${revision}"
    fi
    
    kubectl rollout status deployment/"${name}" -n "${NAMESPACE}"
}

show_history() {
    local name="${1:?Deployment name required}"
    
    echo "=== Deployment History: ${name} ==="
    kubectl rollout history deployment/"${name}" -n "${NAMESPACE}"
}

restart_deployment() {
    local name="${1:?Deployment name required}"
    
    echo "Restarting deployment ${name}..."
    kubectl rollout restart deployment/"${name}" -n "${NAMESPACE}"
    
    kubectl rollout status deployment/"${name}" -n "${NAMESPACE}"
}

# Main
case "${1:-help}" in
    list)
        list_deployments
        ;;
    status)
        show_status "${2:-}"
        ;;
    scale)
        scale_deployment "${2:-}" "${3:-}"
        ;;
    update)
        update_image "${2:-}" "${3:-}"
        ;;
    rollback)
        rollback_deployment "${2:-}" "${3:-}"
        ;;
    history)
        show_history "${2:-}"
        ;;
    restart)
        restart_deployment "${2:-}"
        ;;
    help|--help|-h|*)
        show_help
        ;;
esac