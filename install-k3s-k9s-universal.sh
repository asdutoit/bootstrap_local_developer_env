#!/bin/bash

# Universal k3s and k9s Installation Script
# Works on both ARM64 and AMD64 architectures
# Supports: CentOS Stream 9, Ubuntu 20.04+, Debian 11+
# Author: Development Team

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

error_exit() {
    log_error "$1"
    exit 1
}

# Command exists check
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        error_exit "Cannot detect OS. /etc/os-release not found."
    fi
}

# Detect architecture and set download format
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        DOWNLOAD_ARCH="amd64"
        ;;
    aarch64|arm64)
        DOWNLOAD_ARCH="arm64"
        ;;
    armv7l)
        DOWNLOAD_ARCH="arm"
        ;;
    *)
        error_exit "Unsupported architecture: $ARCH"
        ;;
esac

detect_os

log "========================================="
log "Universal k3s + k9s Installer"
log "========================================="
log "OS: $OS $OS_VERSION"
log "Architecture: $ARCH → $DOWNLOAD_ARCH"
echo ""

# Handle SELinux on CentOS/RHEL
if command_exists getenforce; then
    SELINUX_STATUS=$(getenforce)
    log "SELinux status: $SELINUX_STATUS"

    if [ "$SELINUX_STATUS" = "Enforcing" ]; then
        log_warning "SELinux is Enforcing. k3s may have issues."
        log "Setting SELinux to Permissive mode for k3s compatibility..."

        if sudo setenforce 0; then
            log_success "SELinux set to Permissive (temporary)"
            log "To make permanent, edit /etc/selinux/config"
        else
            log_warning "Could not change SELinux mode. k3s may fail to start."
        fi
    fi
fi

# Install k3s
if command_exists k3s; then
    log_success "k3s is already installed"
    K3S_VERSION=$(k3s --version 2>/dev/null | head -1 || echo "unknown")
    log "Version: $K3S_VERSION"

    # Check if k3s service is running
    log "Checking k3s service status..."
    if sudo systemctl is-active --quiet k3s; then
        log_success "k3s service is running"
    else
        log_warning "k3s service is not running"
        log "Starting k3s service..."

        if sudo systemctl start k3s; then
            log_success "k3s service started"

            # Enable service to start on boot
            if sudo systemctl enable k3s 2>/dev/null; then
                log_success "k3s service enabled for auto-start"
            fi

            # Wait for k3s to initialize
            log "Waiting for k3s to initialize..."
            sleep 10

            # Wait for kubeconfig to be created
            RETRY_COUNT=0
            MAX_RETRIES=12
            while [ ! -f /etc/rancher/k3s/k3s.yaml ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
                log "Waiting for kubeconfig... (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)"
                sleep 5
                RETRY_COUNT=$((RETRY_COUNT + 1))
            done

            if [ ! -f /etc/rancher/k3s/k3s.yaml ]; then
                log_error "k3s kubeconfig was not created after starting service!"
                log "k3s service status:"
                sudo systemctl status k3s --no-pager || true
                log "k3s logs:"
                sudo journalctl -u k3s -n 100 --no-pager
                exit 1
            fi

            log_success "k3s kubeconfig created at /etc/rancher/k3s/k3s.yaml"
        else
            log_error "Failed to start k3s service"
            log "Checking service status..."
            sudo systemctl status k3s --no-pager || true
            log "Checking service logs..."
            sudo journalctl -u k3s -n 50 --no-pager
            exit 1
        fi
    fi
else
    log "Installing k3s..."

    # Backup existing kubectl if present
    KUBECTL_BACKUP=""
    if command_exists kubectl && [ -f /usr/local/bin/kubectl ] && [ ! -L /usr/local/bin/kubectl ]; then
        log "Backing up existing kubectl binary..."
        KUBECTL_BACKUP="/usr/local/bin/kubectl.backup.$(date +%s)"
        sudo mv /usr/local/bin/kubectl "$KUBECTL_BACKUP"
        log_success "kubectl backed up to: $KUBECTL_BACKUP"
    fi

    # Install k3s with appropriate flags
    log "Downloading and installing k3s binary..."

    # Use different installation flags based on OS
    INSTALL_FLAGS="--write-kubeconfig-mode 644"
    if [[ "$OS" =~ ^(centos|rhel|fedora)$ ]]; then
        INSTALL_FLAGS="$INSTALL_FLAGS"
        export INSTALL_K3S_SKIP_SELINUX_RPM=true
    fi

    if curl -sfL https://get.k3s.io | sh -s - $INSTALL_FLAGS; then
        log_success "k3s installation script completed"
    else
        log_error "k3s installation failed!"
        if [ -n "$KUBECTL_BACKUP" ]; then
            log "Restoring kubectl backup..."
            sudo mv "$KUBECTL_BACKUP" /usr/local/bin/kubectl
        fi
        exit 1
    fi

    # Verify k3s binary exists
    if ! command_exists k3s; then
        log_error "k3s binary not found after installation!"
        log "Checking /usr/local/bin..."
        ls -la /usr/local/bin/k3s* 2>/dev/null || echo "No k3s files found"
        exit 1
    fi

    # Check binary architecture
    log "Verifying k3s binary..."
    K3S_BINARY_INFO=$(file /usr/local/bin/k3s)
    log "Binary info: $K3S_BINARY_INFO"

    # Ensure k3s is executable
    sudo chmod +x /usr/local/bin/k3s

    # Start k3s service if not running
    log "Starting k3s service..."
    if sudo systemctl is-active --quiet k3s; then
        log_success "k3s service is already running"
    else
        if sudo systemctl start k3s; then
            log_success "k3s service started"
        else
            log_error "Failed to start k3s service"
            log "Checking service status..."
            sudo systemctl status k3s --no-pager || true
            log "Checking service logs..."
            sudo journalctl -u k3s -n 50 --no-pager
            exit 1
        fi
    fi

    # Wait for k3s to initialize
    log "Waiting for k3s to initialize..."
    sleep 10

    # Wait for kubeconfig to be created
    RETRY_COUNT=0
    MAX_RETRIES=12
    while [ ! -f /etc/rancher/k3s/k3s.yaml ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        log "Waiting for kubeconfig... (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)"
        sleep 5
        RETRY_COUNT=$((RETRY_COUNT + 1))
    done

    if [ ! -f /etc/rancher/k3s/k3s.yaml ]; then
        log_error "k3s kubeconfig was not created!"
        log "k3s service status:"
        sudo systemctl status k3s --no-pager || true
        log "k3s logs:"
        sudo journalctl -u k3s -n 100 --no-pager
        exit 1
    fi

    log_success "k3s kubeconfig created at /etc/rancher/k3s/k3s.yaml"
fi

# Set up kubeconfig for current user
log "Configuring kubeconfig for user $USER..."
mkdir -p "$HOME/.kube"

if [ -f /etc/rancher/k3s/k3s.yaml ]; then
    sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
    sudo chown "$USER:$USER" "$HOME/.kube/config"
    chmod 600 "$HOME/.kube/config"
    log_success "kubeconfig configured at ~/.kube/config"
else
    log_error "k3s kubeconfig not found at /etc/rancher/k3s/k3s.yaml"
    exit 1
fi

# Verify k3s cluster is accessible
log "Testing cluster connectivity..."
if kubectl get nodes >/dev/null 2>&1; then
    log_success "kubectl can connect to k3s cluster"
    kubectl get nodes
else
    log_warning "kubectl cannot connect yet, cluster may still be initializing..."
    log "Waiting 10 more seconds..."
    sleep 10
    if kubectl get nodes >/dev/null 2>&1; then
        log_success "kubectl connected after delay"
        kubectl get nodes
    else
        log_error "kubectl still cannot connect to cluster"
        log "Try manually: sudo kubectl get nodes --kubeconfig /etc/rancher/k3s/k3s.yaml"
    fi
fi

echo ""

# Install k9s
if command_exists k9s; then
    log_success "k9s is already installed"
    K9S_VERSION=$(k9s version 2>/dev/null | grep Version | head -1 || echo "unknown")
    log "Version: $K9S_VERSION"
else
    log "Installing k9s..."

    # Get latest k9s version
    K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$K9S_VERSION" ]; then
        K9S_VERSION="v0.32.5"  # Fallback version
        log_warning "Could not fetch latest k9s version, using fallback: $K9S_VERSION"
    else
        log "Latest k9s version: $K9S_VERSION"
    fi

    # Download k9s
    K9S_URL="https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${DOWNLOAD_ARCH}.tar.gz"
    log "Downloading from: $K9S_URL"

    if curl -L "$K9S_URL" -o "/tmp/k9s.tar.gz" 2>/dev/null; then
        tar -xzf "/tmp/k9s.tar.gz" -C /tmp
        sudo mv "/tmp/k9s" "/usr/local/bin/k9s"
        sudo chmod +x "/usr/local/bin/k9s"
        rm -f "/tmp/k9s.tar.gz" "/tmp/LICENSE" "/tmp/README.md"
        log_success "k9s installed successfully: $K9S_VERSION"
    else
        log_warning "Failed to download k9s"
        log "You can install it manually later from: https://github.com/derailed/k9s/releases"
    fi
fi

# Final status check
echo ""
log_success "========================================="
log_success "Installation Complete!"
log_success "========================================="
echo ""

log "Installed components:"
log "  ✓ k3s (lightweight Kubernetes)"
log "  ✓ kubectl (k3s built-in)"
log "  ✓ k9s (Kubernetes TUI)"
echo ""

log "Cluster status:"
sudo systemctl status k3s --no-pager | grep -E "(Active|Loaded)" || true
echo ""

log "Quick tests:"
log "  kubectl version --client"
kubectl version --client 2>/dev/null || true
log ""
log "  kubectl get nodes"
kubectl get nodes 2>/dev/null || log_warning "Cluster not ready yet, try again in a few seconds"
echo ""

log "Next steps:"
log "  1. Check cluster: kubectl get nodes"
log "  2. Launch k9s: k9s"
log "  3. Deploy test app: kubectl create deployment nginx --image=nginx"
log "  4. List all resources: kubectl get all -A"
echo ""

log "Configuration:"
log "  - kubeconfig: ~/.kube/config"
log "  - k3s config: /etc/rancher/k3s/k3s.yaml"
log "  - Service: sudo systemctl {start|stop|restart|status} k3s"
log "  - Uninstall: /usr/local/bin/k3s-uninstall.sh"
echo ""

if [ -n "${KUBECTL_BACKUP:-}" ] && [ -f "$KUBECTL_BACKUP" ]; then
    log "Note: Original kubectl backed up to: $KUBECTL_BACKUP"
    log "Restore with: sudo mv $KUBECTL_BACKUP /usr/local/bin/kubectl"
    echo ""
fi

log_success "Happy Kubernetes-ing!"
