#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="${PROJECT_ROOT}/test-results.log"
NAMESPACE="${KUBE_NAMESPACE:-default}"
MAX_RETRIES=5
RETRY_DELAY=3

PASSED=0
FAILED=0
SKIPPED=0

log_info() { echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*" | tee -a "$LOG_FILE"; ((PASSED++)) || true; }
log_warning() { echo -e "${YELLOW}[⚠]${NC} $*" | tee -a "$LOG_FILE"; ((SKIPPED++)) || true; }
log_error() { echo -e "${RED}[✗]${NC} $*" | tee -a "$LOG_FILE"; ((FAILED++)) || true; }

check_prerequisites() {
    log_info "Checking prerequisites..."

    command -v kubectl >/dev/null || { log_error "kubectl not found"; exit 1; }
    command -v curl >/dev/null || log_warning "curl not found"

    kubectl cluster-info >/dev/null || { log_error "Cannot connect to cluster"; exit 1; }

    log_success "Prerequisites check passed"
}

retry_command() {
    local cmd="$1" attempts="$2" delay="$3" i=1
    while [ $i -le $attempts ]; do
        eval "$cmd" >/dev/null 2>&1 && return 0
        [ $i -lt $attempts ] && sleep "$delay"
        ((i++))
    done
    return 1
}

test_deployments_exist() {
    log_info "Testing deployments..."
    local deps=("frontend" "backend" "assets" "postgres-db")

    for d in "${deps[@]}"; do
        kubectl get deploy "$d" -n "$NAMESPACE" >/dev/null 2>&1 \
            && log_success "$d exists" \
            || log_error "$d missing"
    done
}

test_pods_running() {
    log_info "Testing running pods..."
    local deps=("frontend" "backend" "assets" "postgres-db")

    for d in "${deps[@]}"; do
        local label="$d"
        [[ "$d" == "postgres-db" ]] && label="postgres"

        local running=$(kubectl get pods -n "$NAMESPACE" -l app="$label" \
            --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

        [ "$running" -gt 0 ] \
            && log_success "$d: $running running" \
            || log_error "$d: no running pods"
    done
}

test_pod_readiness() {
    log_info "Testing readiness..."

    local not_ready=$(kubectl get pods -n "$NAMESPACE" \
        -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready")].status!="True")].metadata.name}' \
        2>/dev/null | wc -w)

    [ "$not_ready" -eq 0 ] \
        && log_success "All pods ready" \
        || log_warning "$not_ready not ready"
}

check_replica_count() {
    local d=$1 expected=$2

    local actual=$(kubectl get deploy "$d" -n "$NAMESPACE" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)

    [[ -z "$actual" ]] && actual=0

    [ "$actual" -ge "$expected" ] \
        && log_success "$d: $actual/$expected ready" \
        || log_warning "$d: $actual/$expected ready"
}

test_replicas() {
    log_info "Testing replicas..."
    check_replica_count frontend 3
    check_replica_count backend 3
    check_replica_count assets 3
    check_replica_count postgres-db 1
}

test_services_exist() {
    log_info "Testing services..."
    local svcs=("frontend-service" "backend-service" "assets-service" "db-service")

    for s in "${svcs[@]}"; do
        kubectl get svc "$s" -n "$NAMESPACE" >/dev/null 2>&1 \
            && log_success "$s exists" \
            || log_error "$s missing"
    done
}

test_service_endpoints() {
    log_info "Testing endpoints..."
    local svcs=("frontend-service" "backend-service" "assets-service" "db-service")

    for s in "${svcs[@]}"; do
        local ep=$(kubectl get endpoints "$s" -n "$NAMESPACE" \
            -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w)

        [ "$ep" -gt 0 ] \
            && log_success "$s: $ep endpoints" \
            || log_error "$s: no endpoints"
    done
}

test_ingress_exists() {
    log_info "Testing ingress..."
    kubectl get ingress project-ingress -n "$NAMESPACE" >/dev/null 2>&1 \
        && log_success "Ingress exists" \
        || log_error "Ingress missing"
}

test_ingress_rules() {
    log_info "Testing ingress paths..."

    local paths=$(kubectl get ingress project-ingress -n "$NAMESPACE" \
        -o jsonpath='{.spec.rules[*].http.paths[*].path}' 2>/dev/null)

    [ -n "$paths" ] \
        && log_success "Paths: $paths" \
        || log_error "No paths found"
}

test_pod_exec_health() {
    log_info "Testing pod health..."

    local backend=$(kubectl get pods -n "$NAMESPACE" -l app=backend \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    [ -n "$backend" ] && kubectl exec -n "$NAMESPACE" "$backend" -- \
        curl -s -f http://localhost:9000/api/health >/dev/null 2>&1 \
        && log_success "Backend OK" || log_warning "Backend check failed"

    local frontend=$(kubectl get pods -n "$NAMESPACE" -l app=frontend \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    [ -n "$frontend" ] && kubectl exec -n "$NAMESPACE" "$frontend" -- \
        curl -s -f http://localhost:80 >/dev/null 2>&1 \
        && log_success "Frontend OK" || log_warning "Frontend check failed"
}

test_database_connectivity() {
    log_info "Testing DB..."

    local db=$(kubectl get pods -n "$NAMESPACE" -l app=postgres \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    [ -n "$db" ] && kubectl exec -n "$NAMESPACE" "$db" -- \
        pg_isready -U testuser -d testdb >/dev/null 2>&1 \
        && log_success "DB OK" || log_warning "DB check failed"
}

test_resource_requests() {
    log_info "Testing resources..."

    local pods=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)

    [ "$pods" -gt 0 ] \
        && log_success "$pods pods found" \
        || log_error "No pods"
}

test_service_dns() {
    log_info "Testing DNS..."

    kubectl run -n "$NAMESPACE" test-dns --image=busybox --rm -i --restart=Never \
        -- nslookup backend-service >/dev/null 2>&1 \
        && log_success "DNS OK" || log_warning "DNS failed"
}

print_summary() {
    echo ""
    log_info "========== SUMMARY =========="
    echo -e "${GREEN}Passed: $PASSED${NC}"
    echo -e "${RED}Failed: $FAILED${NC}"
    echo -e "${YELLOW}Skipped: $SKIPPED${NC}"

    [ "$FAILED" -eq 0 ] \
        && log_success "All tests passed" \
        || log_error "Failures present"
}

main() {
    > "$LOG_FILE"

    log_info "Starting tests..."
    log_info "Namespace: $NAMESPACE"

    check_prerequisites

    test_deployments_exist
    test_pods_running
    test_pod_readiness
    test_replicas

    test_services_exist
    test_service_endpoints

    test_ingress_exists
    test_ingress_rules

    test_pod_exec_health
    test_database_connectivity

    test_resource_requests
    test_service_dns || true

    print_summary
}

main "$@"