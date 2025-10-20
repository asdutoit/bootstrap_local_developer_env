#!/bin/bash

# CentOS Stream 9 Development Environment Bootstrap Script
# Streamlined version - CentOS Stream 9 only
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

# Parse command line arguments
SKIP_ANSIBLE=false
INSTALL_DESKTOP=false
ENSURE_TASKBAR=false
INSTALL_DEV_TOOLS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-ansible)
            SKIP_ANSIBLE=true
            shift
            ;;
        --install-desktop)
            INSTALL_DESKTOP=true
            shift
            ;;
        --ensure-taskbar)
            ENSURE_TASKBAR=true
            shift
            ;;
        --install-dev-tools)
            INSTALL_DEV_TOOLS=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Usage: $0 [--skip-ansible] [--install-desktop] [--ensure-taskbar] [--install-dev-tools]"
            exit 1
            ;;
    esac
done

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        DOWNLOAD_ARCH="amd64"
        ;;
    aarch64|arm64)
        DOWNLOAD_ARCH="arm64"
        ;;
    *)
        log_warning "Unknown architecture: $ARCH, defaulting to amd64"
        DOWNLOAD_ARCH="amd64"
        ;;
esac

log "CentOS Stream 9 Bootstrap Starting..."
log "Architecture: $ARCH ($DOWNLOAD_ARCH)"

# Clean up any problematic repository files
log "Cleaning up problematic repositories..."
sudo rm -f /etc/yum.repos.d/azure-cli.repo 2>/dev/null || true
sudo dnf config-manager --set-disabled hashicorp 2>/dev/null || true
sudo dnf config-manager --set-disabled docker-ce-stable 2>/dev/null || true
sudo dnf config-manager --set-disabled packages.microsoft.com_yumrepos_azurecli 2>/dev/null || true

# Update package manager
log "Updating package manager..."
if ! sudo dnf update -y 2>/dev/null; then
    log_warning "Standard dnf update failed, trying with skip-broken..."
    sudo dnf update -y --skip-broken || error_exit "Failed to update dnf packages"
fi
log_success "Package manager updated successfully"

# Install curl
if ! command_exists curl; then
    log "Installing curl..."
    sudo dnf install -y curl || error_exit "Failed to install curl"
    log_success "curl installed successfully"
else
    log_success "curl is already installed"
fi

# Install Python 3
if command_exists python3; then
    log_success "Python3 is already installed"
    PYTHON_CMD="python3"
else
    log "Installing Python3..."
    sudo dnf install -y python3 python3-pip || error_exit "Failed to install Python3"
    PYTHON_CMD="python3"
    log_success "Python3 installed successfully"
fi

# Install pip if not present
if ! command_exists pip3; then
    log "Installing pip..."
    sudo dnf install -y python3-pip || error_exit "Failed to install pip"
    log_success "pip installed successfully"
fi

# Install git
if command_exists git; then
    log_success "git is already installed"
else
    log "Installing git..."
    sudo dnf install -y git || error_exit "Failed to install git"
    log_success "git installed successfully"
fi

# Install GitHub CLI
if command_exists gh; then
    log_success "GitHub CLI is already installed"
else
    log "Installing GitHub CLI..."
    sudo dnf install -y 'dnf-command(config-manager)'
    sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
    sudo dnf install -y gh || error_exit "Failed to install GitHub CLI"
    log_success "GitHub CLI installed successfully"
fi

# Install Azure CLI
if ! command_exists az; then
    log "Installing Azure CLI..."

    # Use the universal installation script (works on all architectures)
    log "Using Microsoft's universal installation script..."
    if curl -sL https://aka.ms/InstallAzureCli | sudo bash; then
        log_success "Azure CLI installed successfully"

        # Verify installation
        if command_exists az; then
            AZ_VERSION=$(az version --output json 2>/dev/null | grep -o '"azure-cli": "[^"]*"' | cut -d'"' -f4 || echo "installed")
            log "Azure CLI version: $AZ_VERSION"
        fi
    else
        log_warning "Azure CLI installation failed"
        log "You can try manually later with: curl -L https://aka.ms/InstallAzureCli | bash"
        log "Or use containerized version: podman run -it mcr.microsoft.com/azure-cli"
    fi
else
    log_success "Azure CLI is already installed"
    AZ_VERSION=$(az version --output json 2>/dev/null | grep -o '"azure-cli": "[^"]*"' | cut -d'"' -f4 || echo "unknown")
    log "Azure CLI version: $AZ_VERSION"
fi

# Install Podman and related tools
log "Installing Podman with Docker compatibility..."
if command_exists podman; then
    PODMAN_VERSION=$(podman --version 2>/dev/null || echo "version unknown")
    log_success "Podman already installed: $PODMAN_VERSION"
else
    if sudo dnf install -y podman podman-docker podman-compose; then
        log_success "Podman packages installed successfully"
    else
        error_exit "Failed to install Podman packages"
    fi
fi

# Check for desktop environment and install Podman Desktop if present
has_desktop=false

if [ "$INSTALL_DESKTOP" = true ]; then
    has_desktop=true
    log "Desktop installation forced via --install-desktop flag"
elif [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${XDG_CURRENT_DESKTOP:-}" ]; then
    has_desktop=true
    log "Desktop environment detected"
fi

if [ "$has_desktop" = true ]; then
    log "Setting up Flatpak for Podman Desktop installation..."

    if ! command_exists flatpak; then
        log "Installing Flatpak..."
        if sudo dnf install -y flatpak; then
            log_success "Flatpak installed successfully"
        else
            log_warning "Failed to install Flatpak"
        fi
    else
        log_success "Flatpak already installed"
    fi

    if command_exists flatpak; then
        log "Adding Flathub repository..."
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true

        if flatpak list 2>/dev/null | grep -q "io.podman_desktop.PodmanDesktop"; then
            log_success "Podman Desktop is already installed"
        else
            log "Installing Podman Desktop via Flatpak..."
            if flatpak install -y flathub io.podman_desktop.PodmanDesktop; then
                log_success "Podman Desktop installed successfully"
            else
                log_warning "Failed to install Podman Desktop via Flatpak"
            fi
        fi
    fi
else
    log "No desktop environment detected, skipping Podman Desktop installation"
fi

# Enable Podman sockets
log "Enabling Podman sockets for Docker compatibility..."
systemctl --user enable --now podman.socket 2>/dev/null || log_warning "Could not enable user Podman socket"
sudo systemctl enable --now podman.socket 2>/dev/null || log_warning "Could not enable system Podman socket"

# Configure cgroup v2 delegation for rootless containers
log "Setting up cgroup v2 delegation for rootless containers..."
user_id=$(id -u)
if [ -f "/sys/fs/cgroup/user.slice/user-${user_id}.slice/user@${user_id}.service/cgroup.controllers" ]; then
    controllers=$(cat "/sys/fs/cgroup/user.slice/user-${user_id}.slice/user@${user_id}.service/cgroup.controllers")
    if [[ "$controllers" == *"cpu"* ]]; then
        log_success "CPU controller already delegated for user containers"
    else
        sudo mkdir -p /etc/systemd/system/user@.service.d/
        sudo tee /etc/systemd/system/user@.service.d/delegate.conf > /dev/null <<EOF
[Service]
Delegate=cpu cpuset io memory pids
EOF
        sudo systemctl daemon-reload
        sudo systemctl restart "user@${user_id}.service"
        sleep 2
        log_success "CPU controller delegation configured"
    fi
fi

# Install kubectl
if ! command_exists kubectl; then
    log "Installing kubectl..."
    kubectl_version=$(curl -L -s https://dl.k8s.io/release/stable.txt 2>/dev/null || echo "v1.31.4")
    kubectl_url="https://dl.k8s.io/release/${kubectl_version}/bin/linux/${DOWNLOAD_ARCH}/kubectl"

    if curl -L "$kubectl_url" -o "/tmp/kubectl" 2>/dev/null; then
        sudo mv "/tmp/kubectl" "/usr/local/bin/kubectl"
        sudo chmod +x "/usr/local/bin/kubectl"
        log_success "kubectl installed successfully"
    else
        log_warning "Failed to download kubectl"
    fi
else
    log_success "kubectl already installed"
fi

# Install Minikube (optional - k3s is recommended for CentOS)
if ! command_exists minikube; then
    log "Installing Minikube (optional)..."
    minikube_version="v1.34.0"
    minikube_url="https://github.com/kubernetes/minikube/releases/download/${minikube_version}/minikube-linux-${DOWNLOAD_ARCH}"

    if curl -L "$minikube_url" -o "/tmp/minikube" 2>/dev/null; then
        sudo mv "/tmp/minikube" "/usr/local/bin/minikube"
        sudo chmod +x "/usr/local/bin/minikube"
        log_success "Minikube installed successfully"

        # Configure Minikube for rootless Podman
        minikube config set rootless true 2>/dev/null || true
        minikube config set driver podman 2>/dev/null || true
        minikube config set container-runtime containerd 2>/dev/null || true
    else
        log_warning "Failed to download Minikube"
    fi
else
    log_success "Minikube already installed"
    minikube config set rootless true 2>/dev/null || true
    minikube config set driver podman 2>/dev/null || true
    minikube config set container-runtime containerd 2>/dev/null || true
fi

# Install Argo CD CLI
if ! command_exists argocd; then
    log "Installing Argo CD CLI..."
    argocd_version=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$argocd_version" ]; then
        argocd_version="v2.10.0"  # Fallback version
    fi

    argocd_url="https://github.com/argoproj/argo-cd/releases/download/${argocd_version}/argocd-linux-${DOWNLOAD_ARCH}"

    if curl -L "$argocd_url" -o "/tmp/argocd" 2>/dev/null; then
        sudo mv "/tmp/argocd" "/usr/local/bin/argocd"
        sudo chmod +x "/usr/local/bin/argocd"
        log_success "Argo CD CLI installed successfully: $argocd_version"
    else
        log_warning "Failed to download Argo CD CLI"
    fi
else
    log_success "Argo CD CLI already installed"
fi

# Install Argo Workflows CLI
if ! command_exists argo; then
    log "Installing Argo Workflows CLI..."
    argo_version=$(curl -s https://api.github.com/repos/argoproj/argo-workflows/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$argo_version" ]; then
        argo_version="v3.5.0"  # Fallback version
    fi

    argo_url="https://github.com/argoproj/argo-workflows/releases/download/${argo_version}/argo-linux-${DOWNLOAD_ARCH}.gz"

    if curl -L "$argo_url" -o "/tmp/argo.gz" 2>/dev/null; then
        gunzip "/tmp/argo.gz"
        sudo mv "/tmp/argo" "/usr/local/bin/argo"
        sudo chmod +x "/usr/local/bin/argo"
        log_success "Argo Workflows CLI installed successfully: $argo_version"
    else
        log_warning "Failed to download Argo Workflows CLI"
    fi
else
    log_success "Argo Workflows CLI already installed"
fi

# Install k3s (lightweight Kubernetes)
if ! command_exists k3s; then
    log "Installing k3s (lightweight Kubernetes)..."

    # k3s installation script automatically detects architecture and installs
    # By default, k3s starts automatically as a systemd service
    if curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644; then
        log_success "k3s installed successfully"

        # Wait for k3s to be ready
        log "Waiting for k3s to be ready..."
        sleep 5

        # Create symlink for kubectl to use k3s
        if ! command_exists kubectl; then
            sudo ln -s /usr/local/bin/k3s /usr/local/bin/kubectl
            log_success "kubectl symlinked to k3s"
        fi

        # Set up kubeconfig for current user
        mkdir -p "$HOME/.kube"
        sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
        sudo chown "$USER:$USER" "$HOME/.kube/config"
        chmod 600 "$HOME/.kube/config"

        log_success "k3s kubeconfig configured for user $USER"
        log "k3s service status: $(sudo systemctl is-active k3s)"
    else
        log_warning "Failed to install k3s"
    fi
else
    log_success "k3s is already installed"

    # Ensure kubeconfig is set up
    if [ -f "/etc/rancher/k3s/k3s.yaml" ]; then
        mkdir -p "$HOME/.kube"
        if [ ! -f "$HOME/.kube/config" ]; then
            sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
            sudo chown "$USER:$USER" "$HOME/.kube/config"
            chmod 600 "$HOME/.kube/config"
            log_success "k3s kubeconfig configured"
        fi
    fi
fi

# Install k9s (Kubernetes TUI management tool)
if ! command_exists k9s; then
    log "Installing k9s (Kubernetes management tool)..."
    k9s_version=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$k9s_version" ]; then
        k9s_version="v0.32.5"  # Fallback version
    fi

    k9s_url="https://github.com/derailed/k9s/releases/download/${k9s_version}/k9s_Linux_${DOWNLOAD_ARCH}.tar.gz"

    if curl -L "$k9s_url" -o "/tmp/k9s.tar.gz" 2>/dev/null; then
        tar -xzf "/tmp/k9s.tar.gz" -C /tmp
        sudo mv "/tmp/k9s" "/usr/local/bin/k9s"
        sudo chmod +x "/usr/local/bin/k9s"
        rm -f "/tmp/k9s.tar.gz" "/tmp/LICENSE" "/tmp/README.md"
        log_success "k9s installed successfully: $k9s_version"
    else
        log_warning "Failed to download k9s"
    fi
else
    log_success "k9s already installed"
fi

# Install zsh
if command_exists zsh; then
    log_success "zsh is already installed"
else
    log "Installing zsh..."
    sudo dnf install -y zsh || error_exit "Failed to install zsh"
    log_success "zsh installed successfully"
fi

# Set zsh as default shell
ZSH_PATH=$(which zsh)
CURRENT_SHELL=$(echo $SHELL)

if [ "$CURRENT_SHELL" != "$ZSH_PATH" ]; then
    log "Setting zsh as default shell..."

    # Ensure zsh is in /etc/shells
    if ! grep -q "$ZSH_PATH" /etc/shells 2>/dev/null; then
        log "Adding $ZSH_PATH to /etc/shells..."
        echo "$ZSH_PATH" | sudo tee -a /etc/shells > /dev/null
    fi

    # Try to change shell
    SHELL_CHANGED=false

    if sudo chsh -s "$ZSH_PATH" "$USER" 2>/dev/null; then
        SHELL_CHANGED=true
        log_success "Default shell changed to zsh (via chsh)"
    elif sudo usermod -s "$ZSH_PATH" "$USER" 2>/dev/null; then
        SHELL_CHANGED=true
        log_success "Default shell changed to zsh (via usermod)"
    else
        log_warning "Failed to change default shell automatically"
        log "Please run manually after the script completes:"
        log "  sudo chsh -s $ZSH_PATH $USER"
    fi

    # Verify the change
    if [ "$SHELL_CHANGED" = true ]; then
        PASSWD_SHELL=$(getent passwd "$USER" | cut -d: -f7)
        if [ "$PASSWD_SHELL" = "$ZSH_PATH" ]; then
            log_success "✓ Verified: Default shell is now zsh in /etc/passwd"
            log "You must LOG OUT and LOG BACK IN for the change to take effect"
        else
            log_warning "Shell change may not have taken effect"
            log "Current shell in /etc/passwd: $PASSWD_SHELL"
        fi
    fi
else
    log_success "zsh is already the default shell"
fi

# Install Oh My Zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    log "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || log_warning "Failed to install Oh My Zsh"
    if [ -d "$HOME/.oh-my-zsh" ]; then
        log_success "Oh My Zsh installed successfully"
    fi
else
    log_success "Oh My Zsh is already installed"
fi

# Install FiraCode Nerd Font
log "Installing FiraCode Nerd Font..."
FONT_DIR="/usr/share/fonts/firacode"
if sudo mkdir -p "$FONT_DIR" 2>/dev/null; then
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    if curl -L "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip" -o "FiraCode.zip"; then
        if command_exists unzip || sudo dnf install -y unzip; then
            if unzip -q "FiraCode.zip" && find . -name "*.ttf" -exec sudo cp {} "$FONT_DIR/" \;; then
                sudo fc-cache -fv "$FONT_DIR" 2>/dev/null || true
                log_success "FiraCode Nerd Font installed successfully"
            fi
        fi
    fi

    cd - > /dev/null
    rm -rf "$TEMP_DIR"
else
    log_warning "Could not create system font directory"
fi

# Install Starship prompt
if command_exists starship; then
    log_success "Starship is already installed"
else
    log "Installing Starship prompt..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y || log_warning "Failed to install Starship"
    if command_exists starship; then
        log_success "Starship installed successfully"
    fi
fi

# Configure Starship in zsh
if command_exists starship && [ -f "$HOME/.zshrc" ]; then
    if ! grep -q "starship init zsh" "$HOME/.zshrc"; then
        echo 'eval "$(starship init zsh)"' >> "$HOME/.zshrc"
        log_success "Starship configured in zsh"
    fi
fi

# Install direnv (environment variable manager)
if command_exists direnv; then
    log_success "direnv is already installed"
else
    log "Installing direnv..."

    # Try installing from dnf first
    if sudo dnf install -y direnv 2>/dev/null; then
        log_success "direnv installed via dnf"
    else
        # Fallback to manual installation
        log "dnf installation failed, installing direnv manually..."
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64)
                DIRENV_ARCH="linux-amd64"
                ;;
            aarch64|arm64)
                DIRENV_ARCH="linux-arm64"
                ;;
            *)
                log_warning "Unknown architecture for direnv: $ARCH"
                DIRENV_ARCH="linux-amd64"
                ;;
        esac

        direnv_version=$(curl -s https://api.github.com/repos/direnv/direnv/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
        if [ -z "$direnv_version" ]; then
            direnv_version="v2.34.0"  # Fallback version
        fi

        direnv_url="https://github.com/direnv/direnv/releases/download/${direnv_version}/direnv.${DIRENV_ARCH}"

        if curl -L "$direnv_url" -o "/tmp/direnv" 2>/dev/null; then
            sudo mv "/tmp/direnv" "/usr/local/bin/direnv"
            sudo chmod +x "/usr/local/bin/direnv"
            log_success "direnv installed successfully: $direnv_version"
        else
            log_warning "Failed to download direnv"
        fi
    fi
fi

# Configure direnv in zsh
if command_exists direnv && [ -f "$HOME/.zshrc" ]; then
    if ! grep -q "direnv hook zsh" "$HOME/.zshrc"; then
        echo 'eval "$(direnv hook zsh)"' >> "$HOME/.zshrc"
        log_success "direnv configured in zsh"
    fi
fi

# Configure direnv in bash (fallback)
if command_exists direnv && [ -f "$HOME/.bashrc" ]; then
    if ! grep -q "direnv hook bash" "$HOME/.bashrc"; then
        echo 'eval "$(direnv hook bash)"' >> "$HOME/.bashrc"
        log_success "direnv configured in bash"
    fi
fi

# Install VS Code
if command_exists code; then
    log_success "VS Code is already installed"
else
    log "Installing VS Code..."
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    cat << 'EOF' | sudo tee /etc/yum.repos.d/vscode.repo
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
    sudo dnf install -y code || log_warning "Failed to install VS Code"
    if command_exists code; then
        log_success "VS Code installed successfully"
    fi
fi

# Configure VS Code to use FiraCode Nerd Font
if command_exists code; then
    VSCODE_CONFIG_DIR="$HOME/.config/Code/User"
    mkdir -p "$VSCODE_CONFIG_DIR"
    SETTINGS_FILE="$VSCODE_CONFIG_DIR/settings.json"

    if [ ! -f "$SETTINGS_FILE" ]; then
        cat > "$SETTINGS_FILE" << 'VSCODE_SETTINGS_EOF'
{
    "editor.fontFamily": "'FiraCode Nerd Font', Consolas, 'Courier New', monospace",
    "terminal.integrated.fontFamily": "'FiraCode Nerd Font', monospace",
    "terminal.integrated.fontLigatures": true,
    "editor.fontLigatures": true,
    "editor.fontSize": 13,
    "terminal.integrated.fontSize": 13
}
VSCODE_SETTINGS_EOF
        log_success "VS Code font configuration created"
    fi
fi

# Install Ansible if not skipped
if [ "$SKIP_ANSIBLE" = false ]; then
    log "Installing Ansible..."
    if ! command_exists ansible; then
        sudo dnf install -y ansible-core || error_exit "Failed to install Ansible"
        log_success "Ansible installed successfully"
    else
        log_success "Ansible is already installed"
    fi

    # Run Ansible playbook
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PLAYBOOK="$SCRIPT_DIR/setup-centos.yml"

    if [ -f "$PLAYBOOK" ]; then
        log "Running Ansible playbook: $PLAYBOOK"
        if ansible-playbook "$PLAYBOOK"; then
            log_success "Ansible playbook completed successfully"
        else
            log_warning "Ansible playbook completed with some errors (this is often normal)"
        fi
    else
        log_warning "Ansible playbook not found: $PLAYBOOK"
    fi
else
    log "Skipping Ansible automation (--skip-ansible flag provided)"
fi

# Final summary
log ""
log_success "========================================="
log_success "CentOS Stream 9 Bootstrap Complete!"
log_success "========================================="
log ""
log "Installed components:"
log "  ✓ Python 3 and pip"
log "  ✓ curl and git"
log "  ✓ GitHub CLI (gh)"
log "  ✓ Azure CLI (az)"
log "  ✓ Podman with Docker compatibility"
log "  ✓ k3s (lightweight production Kubernetes)"
log "  ✓ kubectl CLI"
log "  ✓ k9s (Kubernetes management TUI)"
log "  ✓ Minikube (optional - k3s recommended for CentOS)"
log "  ✓ Argo CD CLI (argocd)"
log "  ✓ Argo Workflows CLI (argo)"
log "  ✓ zsh and Oh My Zsh"
log "  ✓ FiraCode Nerd Font"
log "  ✓ Starship prompt"
log "  ✓ direnv (environment variable manager)"
log "  ✓ VS Code"
if [ "$has_desktop" = true ]; then
    log "  ✓ Podman Desktop (GUI)"
fi
log ""
log "Next steps:"
log "  1. TO USE ZSH: You MUST log out and log back in (not just restart terminal)"
log "     - For SSH: exit and reconnect"
log "     - For console: logout and login"
log "     - Quick test (current session only): exec zsh"
log "  2. Verify zsh: echo \$0 (should show 'zsh' or '-zsh')"
log "  3. Test Podman: podman run hello-world"
log "  4. Test Docker compatibility: docker run hello-world"
log "  5. Check k3s cluster: kubectl get nodes"
log "  6. Launch k9s (Kubernetes TUI): k9s"
log "  7. Deploy something: kubectl create deployment nginx --image=nginx"
log "  8. Authenticate with GitHub: gh auth login"
log "  9. Authenticate with Azure: az login"
log ""
log "Note: k3s is the recommended Kubernetes for CentOS (Minikube may have issues)"
log ""
log "Configuration files:"
log "  - Shell config: ~/.zshrc"
log "  - VS Code settings: ~/.config/Code/User/settings.json"
log "  - k3s kubeconfig: ~/.kube/config (or /etc/rancher/k3s/k3s.yaml)"
log "  - Minikube config: ~/.minikube/config/config.json"
log ""
log_success "Happy coding!"
