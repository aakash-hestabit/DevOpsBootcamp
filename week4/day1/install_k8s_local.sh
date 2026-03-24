#!/usr/bin/env bash

set -euo pipefail

# Defaults

CPUS=2
MEMORY=2048
DISK_SIZE="10g"
DRIVER="docker"
K8S_VERSION=""


# Logging

log_info()    { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $*"; }
log_error()   { echo -e "\033[1;31m[ERROR]\033[0m $*"; }


# Help

show_help() {
cat <<EOF
Kubernetes Local Environment Setup Script

USAGE:
  ./install_k8s_local.sh [OPTIONS]

OPTIONS:
  -c, --cpus <num>        CPUs for Minikube (default: 2)
  -m, --memory <mb>       Memory in MB (default: 2048)
  -d, --disk <size>       Disk size (default: 10g)
  -v, --version <ver>     Install specific kubectl version (e.g. v1.35.0)
  -h, --help              Show this help message

DESCRIPTION:
  Installs:
    - kubectl (with checksum verification)
    - Minikube

  Then:
    - Starts a Kubernetes cluster using Docker
    - Verifies cluster health

EXAMPLES:
  ./install_k8s_local.sh
  ./install_k8s_local.sh --cpus 4 --memory 4096
  ./install_k8s_local.sh --version v1.35.0

REQUIREMENTS:
  - Docker must be installed and running
  - sudo privileges

EOF
}


# Argument Parsing

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--cpus)
            CPUS="$2"; shift 2 ;;
        -m|--memory)
            MEMORY="$2"; shift 2 ;;
        -d|--disk)
            DISK_SIZE="$2"; shift 2 ;;
        -v|--version)
            K8S_VERSION="$2"; shift 2 ;;
        -h|--help)
            show_help; exit 0 ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1 ;;
    esac
done


# Install kubectl

install_kubectl() {
    log_info "Installing kubectl..."

    if command -v kubectl &>/dev/null; then
        log_success "kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client | head -1)"
        return
    fi

    # Detect architecture
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *)
            log_error "Unsupported architecture: $ARCH"
            exit 1 ;;
    esac

    # Get version
    if [[ -z "$K8S_VERSION" ]]; then
        VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    else
        VERSION="$K8S_VERSION"
    fi

    log_info "Version: $VERSION | Arch: $ARCH"

    # Download
    curl -LO "https://dl.k8s.io/release/${VERSION}/bin/linux/${ARCH}/kubectl"
    curl -LO "https://dl.k8s.io/release/${VERSION}/bin/linux/${ARCH}/kubectl.sha256"

    # Verify checksum
    log_info "Verifying checksum..."
    if echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check; then
        log_success "Checksum verified"
    else
        log_error "Checksum verification failed!"
        rm -f kubectl kubectl.sha256
        exit 1
    fi

    # Install
    chmod +x kubectl
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

    # Cleanup
    rm -f kubectl kubectl.sha256

    log_success "kubectl installed"
}


# Install Minikube

install_minikube() {
    log_info "Installing Minikube..."

    if command -v minikube &>/dev/null; then
        log_success "Minikube already installed: $(minikube version --short)"
        return
    fi

    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    rm minikube-linux-amd64

    log_success "Minikube installed"
}


# Check Docker

check_docker() {
    log_info "Checking Docker..."
    if ! docker info &>/dev/null; then
        log_error "Docker is not running. Start Docker first."
        exit 1
    fi
    log_success "Docker is running"
}


# Start Cluster

start_cluster() {
    log_info "Starting Minikube cluster..."
    echo "  CPUs: $CPUS | Memory: ${MEMORY}MB | Disk: $DISK_SIZE"

    if minikube status &>/dev/null; then
        log_info "Minikube already running. Skipping..."
        return
    fi

    minikube start \
        --driver="$DRIVER" \
        --cpus="$CPUS" \
        --memory="$MEMORY" \
        --disk-size="$DISK_SIZE"
}


# Verify Cluster

verify_cluster() {
    log_info "Verifying cluster..."
    kubectl cluster-info
    echo ""
    kubectl get nodes
}


# Main

echo "============================================"
echo "  Kubernetes Local Environment Setup"
echo "============================================"
echo ""

check_docker
install_kubectl
install_minikube
start_cluster
verify_cluster

echo ""
echo "============================================"
log_success "Kubernetes is ready!"
echo "============================================"
echo ""
echo "Quick commands:"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo "  minikube dashboard"
echo "  minikube stop"
echo "  minikube delete"
echo ""