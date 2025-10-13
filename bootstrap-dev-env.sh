#!/bin/bash

# Development Environment Bootstrap Script
# Supports: Ubuntu, CentOS/RHEL, macOS
# Installs: Python, Curl, Git, GitHub CLI, zsh, Nerd Fonts, Starship, Ansible, Container Runtime, VS Code
# Optional: Additional Development Tools, Desktop Environment
# Author: Development Team

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Detect operating system and architecture
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        DISTRO="macos"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "${WINDIR:-}" ]]; then
        OS="windows"
        DISTRO="windows"
        log_warning "Windows environment detected!"
        log "This bash script is designed for Unix-like systems."
        log "For Windows 11, please use the PowerShell version instead:"
        log "  .\\bootstrap-dev-env.ps1"
        log ""
        log "Windows 11 PowerShell script features:"
        log "  - Native Windows package managers (Chocolatey/Scoop)"
        log "  - Windows-specific tool installation"
        log "  - Docker Desktop + WSL2 integration"
        log "  - PowerShell profile configuration"
        log ""
        log "If you prefer to continue with bash (Git Bash/WSL), press Enter."
        log "Otherwise, exit and use bootstrap-dev-env.ps1"
        read -p "Continue with bash version? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Please use the Windows PowerShell script: .\\bootstrap-dev-env.ps1"
            exit 0
        fi
        log "Continuing with bash version (limited Windows support)..."
    elif [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS="linux"
        DISTRO=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
    elif [[ -f /etc/redhat-release ]]; then
        OS="linux"
        if grep -qi "centos" /etc/redhat-release; then
            DISTRO="centos"
        elif grep -qi "red hat" /etc/redhat-release; then
            DISTRO="rhel"
        else
            DISTRO="unknown"
        fi
    else
        error_exit "Unable to detect operating system"
    fi
    
    # Detect system architecture
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
            log_warning "Unknown architecture: $ARCH, defaulting to amd64"
            DOWNLOAD_ARCH="amd64"
            ;;
    esac
    
    log "Detected OS: $OS, Distribution: $DISTRO, Architecture: $ARCH ($DOWNLOAD_ARCH)"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate system compatibility
validate_system() {
    log "Validating system compatibility..."
    
    # Check for common architecture-specific issues
    if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
        log "ARM64 architecture detected - using ARM64 binaries for Kubernetes tools"
        if command_exists docker; then
            log "Note: Some Docker images may not be available for ARM64. Use --platform linux/amd64 if needed."
        fi
    fi
    
    # Check for required tools that may have architecture dependencies
    local missing_tools=()
    
    # These tools are essential and should be available on all platforms
    for tool in "curl" "tar" "gzip"; do
        if ! command_exists "$tool"; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_warning "Missing required tools: ${missing_tools[*]}"
        log "The bootstrap script will attempt to install these dependencies."
    fi
    
    log_success "System validation completed"
}

# Update package manager
update_package_manager() {
    log "Updating package manager..."
    
    case "$DISTRO" in
        ubuntu|debian)
            sudo apt-get update -y || error_exit "Failed to update apt package list"
            ;;
        centos|rhel)
            if command_exists dnf; then
                # Try regular update first, if it fails due to repo issues, try with skip-broken
                if ! sudo dnf update -y 2>/dev/null; then
                    log_warning "Standard dnf update failed, trying with problematic repositories disabled..."
                    # Try to update with skip-broken to handle repository issues
                    if ! sudo dnf update -y --skip-broken; then
                        # Try to disable known problematic repositories for new OS versions
                        log_warning "Attempting to disable problematic third-party repositories..."
                        sudo dnf config-manager --set-disabled hashicorp 2>/dev/null || true
                        sudo dnf config-manager --set-disabled docker-ce-stable 2>/dev/null || true
                        sudo dnf update -y --skip-broken || error_exit "Failed to update dnf packages after handling repository issues"
                    fi
                fi
            elif command_exists yum; then
                sudo yum update -y || error_exit "Failed to update yum packages"
            else
                error_exit "Neither dnf nor yum found"
            fi
            ;;
        macos)
            if ! command_exists brew; then
                log "Installing Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || error_exit "Failed to install Homebrew"
            fi
            brew update || error_exit "Failed to update Homebrew"
            ;;
        *)
            error_exit "Unsupported distribution: $DISTRO"
            ;;
    esac
    
    log_success "Package manager updated successfully"
}

# Install curl
install_curl() {
    if command_exists curl; then
        log_success "curl is already installed"
        return 0
    fi
    
    log "Installing curl..."
    
    case "$DISTRO" in
        ubuntu|debian)
            sudo apt-get install -y curl || error_exit "Failed to install curl"
            ;;
        centos|rhel)
            if command_exists dnf; then
                sudo dnf install -y curl || error_exit "Failed to install curl"
            else
                sudo yum install -y curl || error_exit "Failed to install curl"
            fi
            ;;
        macos)
            # curl is typically pre-installed on macOS, but let's ensure it's available
            if ! command_exists curl; then
                brew install curl || error_exit "Failed to install curl"
            fi
            ;;
        *)
            error_exit "Unsupported distribution for curl installation: $DISTRO"
            ;;
    esac
    
    log_success "curl installed successfully"
}

# Install Python
install_python() {
    if command_exists python3; then
        log_success "Python3 is already installed"
        PYTHON_CMD="python3"
    elif command_exists python; then
        # Check if it's Python 2 or 3
        PYTHON_VERSION=$(python --version 2>&1)
        if [[ "$PYTHON_VERSION" == *"Python 3"* ]]; then
            log_success "Python3 is already installed (as 'python')"
            PYTHON_CMD="python"
        else
            log_warning "Python 2 detected, installing Python 3..."
            install_python3_package
        fi
    else
        log "Installing Python3..."
        install_python3_package
    fi
    
    # Install pip if not present
    if ! command_exists pip3 && ! command_exists pip; then
        install_pip
    fi
}

install_python3_package() {
    case "$DISTRO" in
        ubuntu|debian)
            sudo apt-get install -y python3 python3-pip python3-venv || error_exit "Failed to install Python3"
            PYTHON_CMD="python3"
            ;;
        centos|rhel)
            if command_exists dnf; then
                sudo dnf install -y python3 python3-pip || error_exit "Failed to install Python3"
            else
                sudo yum install -y python3 python3-pip || error_exit "Failed to install Python3"
            fi
            PYTHON_CMD="python3"
            ;;
        macos)
            brew install python || error_exit "Failed to install Python3"
            PYTHON_CMD="python3"
            ;;
        *)
            error_exit "Unsupported distribution for Python installation: $DISTRO"
            ;;
    esac
    
    log_success "Python3 installed successfully"
}

install_pip() {
    log "Installing pip..."
    
    case "$DISTRO" in
        ubuntu|debian)
            sudo apt-get install -y python3-pip || error_exit "Failed to install pip"
            ;;
        centos|rhel)
            if command_exists dnf; then
                sudo dnf install -y python3-pip || error_exit "Failed to install pip"
            else
                sudo yum install -y python3-pip || error_exit "Failed to install pip"
            fi
            ;;
        macos)
            # pip should be installed with Python via Homebrew
            if ! command_exists pip3; then
                $PYTHON_CMD -m ensurepip --upgrade || error_exit "Failed to install pip"
            fi
            ;;
    esac
    
    log_success "pip installed successfully"
}

# Install git and GitHub CLI
install_git_and_github_cli() {
    log "Installing git and GitHub CLI..."
    
    # Install git first
    if command_exists git; then
        log_success "git is already installed"
        GIT_VERSION=$(git --version)
        log "Current git version: $GIT_VERSION"
    else
        log "Installing git..."
        
        case "$DISTRO" in
            ubuntu|debian)
                sudo apt-get install -y git || error_exit "Failed to install git"
                ;;
            centos|rhel)
                if command_exists dnf; then
                    sudo dnf install -y git || error_exit "Failed to install git"
                else
                    sudo yum install -y git || error_exit "Failed to install git"
                fi
                ;;
            macos)
                # git is typically pre-installed on macOS, but ensure we have the latest
                if ! command_exists git; then
                    brew install git || error_exit "Failed to install git"
                fi
                ;;
            *)
                error_exit "Unsupported distribution for git installation: $DISTRO"
                ;;
        esac
        
        log_success "git installed successfully"
    fi
    
    # Install GitHub CLI
    if command_exists gh; then
        log_success "GitHub CLI is already installed"
        GH_VERSION=$(gh --version | head -n 1)
        log "Current GitHub CLI version: $GH_VERSION"
    else
        log "Installing GitHub CLI..."
        
        case "$DISTRO" in
            ubuntu|debian)
                # Add GitHub CLI repository and install
                type -p curl >/dev/null || (sudo apt update && sudo apt install curl -y)
                curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
                sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                sudo apt update
                sudo apt install gh -y || error_exit "Failed to install GitHub CLI"
                ;;
            centos|rhel)
                # Install GitHub CLI via dnf/yum
                if command_exists dnf; then
                    sudo dnf install -y 'dnf-command(config-manager)'
                    sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
                    sudo dnf install -y gh || error_exit "Failed to install GitHub CLI"
                else
                    # For older systems, use yum
                    sudo yum install -y yum-utils
                    sudo yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
                    sudo yum install -y gh || error_exit "Failed to install GitHub CLI"
                fi
                ;;
            macos)
                # Use Homebrew for macOS
                brew install gh || error_exit "Failed to install GitHub CLI"
                ;;
            *)
                # Fallback to manual installation for other distributions
                log "Installing GitHub CLI via manual download..."
                GH_VERSION=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | grep '"tag_name"' | cut -d'"' -f4 | sed 's/v//')
                
                case "$DOWNLOAD_ARCH" in
                    amd64)
                        GH_ARCH="linux_amd64"
                        ;;
                    arm64)
                        GH_ARCH="linux_arm64"
                        ;;
                    *)
                        error_exit "Unsupported architecture for GitHub CLI: $DOWNLOAD_ARCH"
                        ;;
                esac
                
                curl -L "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_${GH_ARCH}.tar.gz" -o "/tmp/gh.tar.gz"
                tar -xzf "/tmp/gh.tar.gz" -C "/tmp"
                sudo mv "/tmp/gh_${GH_VERSION}_${GH_ARCH}/bin/gh" "/usr/local/bin/"
                sudo chmod +x "/usr/local/bin/gh"
                rm -rf "/tmp/gh.tar.gz" "/tmp/gh_${GH_VERSION}_${GH_ARCH}"
                ;;
        esac
        
        log_success "GitHub CLI installed successfully"
    fi
    
    # Provide usage hints
    log "Git and GitHub CLI installation completed!"
    log "To authenticate with GitHub, run: gh auth login"
    log "To configure git, run: git config --global user.name \"Your Name\" && git config --global user.email \"your.email@example.com\""
}

# Install Docker/Podman for container support
install_container_runtime() {
    log "Installing container runtime..."
    
    case "$DISTRO" in
        centos|rhel)
            # CentOS Stream/RHEL prefer Podman
            log "Checking for existing container runtime..."
            
            # Check what's currently installed
            local podman_installed=false
            local docker_installed=false
            
            if command_exists podman; then
                podman_installed=true
                PODMAN_VERSION=$(podman --version 2>/dev/null || echo "version unknown")
                log "Found existing Podman: $PODMAN_VERSION"
            fi
            
            if command_exists docker; then
                docker_installed=true
                DOCKER_VERSION=$(docker --version 2>/dev/null || echo "version unknown")
                log "Found existing Docker: $DOCKER_VERSION"
            fi
            
            if [ "$podman_installed" = false ]; then
                log "Installing Podman with Docker compatibility..."
                if command_exists dnf; then
                    if sudo dnf install -y podman podman-docker podman-compose; then
                        log_success "Podman packages installed successfully"
                        podman_installed=true
                    else
                        error_exit "Failed to install Podman packages"
                    fi
                    
                    # Check if we should install Podman Desktop
                    local has_desktop=false
                    
                    # Check for desktop environment indicators
                    if [ "$INSTALL_DESKTOP" = true ]; then
                        has_desktop=true
                        log "Desktop installation forced via --install-desktop flag"
                    elif [ -n "${DISPLAY:-}" ]; then
                        has_desktop=true
                        log "Desktop environment detected via DISPLAY variable"
                    elif [ -n "${WAYLAND_DISPLAY:-}" ]; then
                        has_desktop=true
                        log "Desktop environment detected via WAYLAND_DISPLAY"
                    elif systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
                        has_desktop=true
                        log "Desktop environment detected via systemctl graphical-session"
                    elif [ -n "${XDG_CURRENT_DESKTOP:-}" ]; then
                        has_desktop=true
                        log "Desktop environment detected: $XDG_CURRENT_DESKTOP"
                    elif command_exists gnome-shell || command_exists plasma-desktop || command_exists xfce4-session; then
                        has_desktop=true
                        log "Desktop environment detected via DE binaries"
                    fi
                    
                    if [ "$has_desktop" = true ]; then
                        log "Setting up Flatpak for Podman Desktop installation..."

                        # Install Flatpak if not present
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

                        # Add Flathub repository
                        if command_exists flatpak; then
                            log "Adding Flathub repository..."
                            if flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; then
                                log_success "Flathub repository added successfully"
                            else
                                log_warning "Failed to add Flathub repository or already exists"
                            fi

                            # Install Podman Desktop
                            if flatpak list 2>/dev/null | grep -q "io.podman_desktop.PodmanDesktop"; then
                                log_success "Podman Desktop is already installed"
                            else
                                log "Installing Podman Desktop via Flatpak..."
                                if flatpak install -y flathub io.podman_desktop.PodmanDesktop; then
                                    log_success "Podman Desktop installed successfully"
                                else
                                    log_warning "Failed to install Podman Desktop via Flatpak"
                                    log "You can try installing manually: flatpak install flathub io.podman_desktop.PodmanDesktop"
                                fi
                            fi
                        else
                            log_warning "Flatpak not available - cannot install Podman Desktop"
                        fi
                    else
                        log "No desktop environment detected, skipping Podman Desktop installation"
                        log "To force desktop installation, run with --install-desktop flag"
                    fi
                    
                    # Enable Podman socket for docker-compose compatibility
                    log "Enabling Podman sockets for Docker compatibility..."
                    systemctl --user enable --now podman.socket 2>/dev/null || log_warning "Could not enable user Podman socket"
                    sudo systemctl enable --now podman.socket 2>/dev/null || log_warning "Could not enable system Podman socket"
                else
                    if sudo yum install -y podman; then
                        log_success "Podman installed successfully via yum"
                        podman_installed=true
                    else
                        error_exit "Failed to install Podman via yum"
                    fi
                fi
            else
                log "Podman is already installed"
            fi
            
            # Always check for Podman Desktop installation on CentOS, regardless of Podman install status
            log "Checking for Podman Desktop installation..."
            local has_desktop=false
            
            # Check for desktop environment indicators
            if [ "$INSTALL_DESKTOP" = true ]; then
                has_desktop=true
                log "Desktop installation forced via --install-desktop flag"
            elif [ -n "${DISPLAY:-}" ]; then
                has_desktop=true
                log "Desktop environment detected via DISPLAY variable"
            elif [ -n "${WAYLAND_DISPLAY:-}" ]; then
                has_desktop=true
                log "Desktop environment detected via WAYLAND_DISPLAY"
            elif systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
                has_desktop=true
                log "Desktop environment detected via systemctl graphical-session"
            elif [ -n "${XDG_CURRENT_DESKTOP:-}" ]; then
                has_desktop=true
                log "Desktop environment detected: $XDG_CURRENT_DESKTOP"
            elif command_exists gnome-shell || command_exists plasma-desktop || command_exists xfce4-session; then
                has_desktop=true
                log "Desktop environment detected via DE binaries"
            fi
            
            if [ "$has_desktop" = true ]; then
                log "Setting up Flatpak for Podman Desktop installation..."

                # Install Flatpak if not present
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

                # Add Flathub repository
                if command_exists flatpak; then
                    log "Adding Flathub repository..."
                    if flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; then
                        log_success "Flathub repository added successfully"
                    else
                        log_warning "Failed to add Flathub repository or already exists"
                    fi

                    # Install Podman Desktop
                    if flatpak list 2>/dev/null | grep -q "io.podman_desktop.PodmanDesktop"; then
                        log_success "Podman Desktop is already installed"
                    else
                        log "Installing Podman Desktop via Flatpak..."
                        if flatpak install -y flathub io.podman_desktop.PodmanDesktop; then
                            log_success "Podman Desktop installed successfully"
                        else
                            log_warning "Failed to install Podman Desktop via Flatpak"
                            log "You can try installing manually: flatpak install flathub io.podman_desktop.PodmanDesktop"
                        fi
                    fi
                else
                    log_warning "Flatpak not available - cannot install Podman Desktop"
                fi
            else
                log "No desktop environment detected, skipping Podman Desktop installation"
                log "To force desktop installation, run with --install-desktop flag"
            fi
            
            # Final verification
            if command_exists podman; then
                FINAL_PODMAN_VERSION=$(podman --version)
                log_success "Podman verified: $FINAL_PODMAN_VERSION"
            elif command_exists docker; then
                log_success "Docker command available via compatibility layer"
            else
                error_exit "Container runtime installation verification failed"
            fi
            ;;
        ubuntu|debian)
            # Ubuntu/Debian - install Podman with proper Flatpak setup
            log "Installing container runtime for Ubuntu/Debian..."
            
            # Step 1: Install Podman
            if ! command_exists podman; then
                log "Installing Podman..."
                sudo apt-get update
                if sudo apt-get install -y podman; then
                    log_success "Podman installed successfully"
                else
                    error_exit "Failed to install Podman"
                fi
            else
                PODMAN_VERSION=$(podman --version 2>/dev/null || echo "version unknown")
                log_success "Podman already installed: $PODMAN_VERSION"
            fi
            
            # Step 2: Check for desktop environment
            local has_desktop=false
            
            if [ "$INSTALL_DESKTOP" = true ]; then
                has_desktop=true
                log "Desktop installation forced via --install-desktop flag"
            elif [ -n "${DISPLAY:-}" ]; then
                has_desktop=true
                log "Desktop environment detected via DISPLAY variable"
            elif [ -n "${WAYLAND_DISPLAY:-}" ]; then
                has_desktop=true
                log "Desktop environment detected via WAYLAND_DISPLAY"
            elif systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
                has_desktop=true
                log "Desktop environment detected via systemctl graphical-session"
            elif [ -n "${XDG_CURRENT_DESKTOP:-}" ]; then
                has_desktop=true
                log "Desktop environment detected: $XDG_CURRENT_DESKTOP"
            elif command_exists gnome-shell || command_exists plasma-desktop || command_exists xfce4-session; then
                has_desktop=true
                log "Desktop environment detected via DE binaries"
            fi
            
            if [ "$has_desktop" = true ]; then
                # Step 3: Setup Flatpak properly
                log "Setting up Flatpak for Podman Desktop installation..."
                
                # Install Flatpak core
                if ! command_exists flatpak; then
                    log "Installing Flatpak..."
                    if sudo apt-get install -y flatpak; then
                        log_success "Flatpak installed successfully"
                    else
                        error_exit "Failed to install Flatpak"
                    fi
                else
                    log_success "Flatpak already installed"
                fi
                
                # Install GNOME Software Flatpak plugin
                log "Installing GNOME Software Flatpak plugin..."
                if sudo apt-get install -y gnome-software-plugin-flatpak; then
                    log_success "GNOME Software Flatpak plugin installed"
                else
                    log_warning "Failed to install GNOME Software Flatpak plugin (may not be available)"
                fi
                
                # Add Flathub repository
                log "Adding Flathub repository..."
                if flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; then
                    log_success "Flathub repository added successfully"
                else
                    log_warning "Failed to add Flathub repository or already exists"
                fi
                
                # Step 4: Check if system restart is needed
                log_warning "IMPORTANT: Flatpak setup complete, but a system restart may be required."
                log "If this is the first time installing Flatpak, please restart your system before using Flatpak applications."
                log "After restart, Podman Desktop can be installed with:"
                log "  flatpak install flathub io.podman_desktop.PodmanDesktop"
                
                # Step 5: Attempt Podman Desktop installation (may work without restart)
                log "Attempting Podman Desktop installation (may require restart if this fails)..."
                
                # Check if already installed first
                if flatpak list 2>/dev/null | grep -q "io.podman_desktop.PodmanDesktop"; then
                    log_success "Podman Desktop is already installed"
                else
                    if flatpak install -y flathub io.podman_desktop.PodmanDesktop 2>/dev/null; then
                        log_success "Podman Desktop installed successfully!"
                    else
                        log_warning "Podman Desktop installation failed - this is normal on first Flatpak setup"
                        log "After restarting your system, install Podman Desktop with:"
                        log "  flatpak install flathub io.podman_desktop.PodmanDesktop"
                    fi
                fi
            else
                log "No desktop environment detected, skipping Podman Desktop installation"
                log "To force desktop installation, run with --install-desktop flag"
            fi
            
            # Step 6: Final verification
            if command_exists podman; then
                FINAL_PODMAN_VERSION=$(podman --version)
                log_success "Podman verified: $FINAL_PODMAN_VERSION"
            else
                error_exit "Podman installation verification failed"
            fi
            ;;
        macos)
            if ! command_exists docker; then
                log "Installing Docker Desktop..."
                brew install --cask docker || log_warning "Failed to install Docker Desktop"
                log "Please start Docker Desktop manually and complete the setup"
            else
                log_success "Docker already installed"
            fi
            ;;
        *)
            log_warning "Container runtime installation not configured for $DISTRO"
            ;;
    esac
    
    # Configure Kubernetes tools for CentOS/RHEL after container runtime installation
    if [[ "$DISTRO" =~ ^(centos|rhel|fedora)$ ]]; then
        configure_kubernetes_centos
    fi
}

# Configure Kubernetes tools specifically for CentOS/RHEL/Fedora
configure_kubernetes_centos() {
    log "Configuring Kubernetes tools for CentOS/RHEL/Fedora..."
    
    # Step 1: Enable CPU delegation for rootless containers (required for Minikube)
    log "Setting up cgroup v2 delegation for rootless containers..."
    
    # Check if CPU controller is already delegated
    local user_id=$(id -u)
    if [ -f "/sys/fs/cgroup/user.slice/user-${user_id}.slice/user@${user_id}.service/cgroup.controllers" ]; then
        local controllers=$(cat "/sys/fs/cgroup/user.slice/user-${user_id}.slice/user@${user_id}.service/cgroup.controllers")
        if [[ "$controllers" == *"cpu"* ]]; then
            log_success "CPU controller already delegated for user containers"
        else
            log "CPU controller not delegated, configuring systemd user service delegation..."
            
            # Create systemd drop-in directory
            sudo mkdir -p /etc/systemd/system/user@.service.d/ || log_warning "Failed to create systemd drop-in directory"
            
            # Create delegation configuration
            sudo tee /etc/systemd/system/user@.service.d/delegate.conf > /dev/null <<EOF || log_warning "Failed to create delegation config"
[Service]
Delegate=cpu cpuset io memory pids
EOF
            
            if [ -f "/etc/systemd/system/user@.service.d/delegate.conf" ]; then
                log_success "Systemd user service delegation configured"
                
                # Reload systemd and restart user service
                log "Reloading systemd configuration..."
                sudo systemctl daemon-reload || log_warning "Failed to reload systemd daemon"
                sudo systemctl restart "user@${user_id}.service" || log_warning "Failed to restart user service"
                
                # Wait a moment for the service to restart
                sleep 2
                
                # Verify CPU delegation is now working
                if [ -f "/sys/fs/cgroup/user.slice/user-${user_id}.slice/user@${user_id}.service/cgroup.controllers" ]; then
                    local new_controllers=$(cat "/sys/fs/cgroup/user.slice/user-${user_id}.slice/user@${user_id}.service/cgroup.controllers")
                    if [[ "$new_controllers" == *"cpu"* ]]; then
                        log_success "✓ CPU controller delegation enabled successfully"
                    else
                        log_warning "⚠ CPU controller delegation may not be active yet. A reboot may be required."
                    fi
                else
                    log_warning "⚠ Unable to verify CPU controller delegation"
                fi
            else
                log_warning "Failed to create delegation configuration file"
            fi
        fi
    else
        log_warning "Unable to check cgroup controllers (user service may not be running)"
    fi
    
    # Step 2: Configure Minikube for rootless Podman
    if command_exists minikube; then
        log "Configuring Minikube for rootless Podman..."
        
        # Set Minikube to use rootless mode
        minikube config set rootless true 2>/dev/null || log_warning "Failed to set Minikube rootless mode"
        
        # Set Podman as the default driver
        minikube config set driver podman 2>/dev/null || log_warning "Failed to set Minikube Podman driver"
        
        # Set containerd as container runtime to avoid Docker service conflicts
        minikube config set container-runtime containerd 2>/dev/null || log_warning "Failed to set Minikube container runtime"
        
        log_success "Minikube configured for rootless Podman with containerd runtime"
        
        # Provide usage instructions
        log "Minikube configuration completed!"
        log "To start your Kubernetes cluster (avoiding Docker service conflicts):"
        log "  minikube start --force-systemd=false"
        log "To check cluster status:"
        log "  minikube status"
        log "  kubectl get nodes"
        log "Note: The --force-systemd=false flag prevents Docker service modification conflicts"
    else
        log "Minikube not found - it will be installed by Ansible later"
    fi
    
    # Step 3: Install kubectl and Minikube if not already present
    install_kubernetes_tools
}

# Install Kubernetes tools (kubectl and Minikube)
install_kubernetes_tools() {
    log "Installing Kubernetes tools..."
    
    # Install kubectl
    if ! command_exists kubectl; then
        log "Installing kubectl..."
        
        # Get latest stable version
        local kubectl_version
        kubectl_version=$(curl -L -s https://dl.k8s.io/release/stable.txt 2>/dev/null || echo "v1.31.0")
        
        # Download kubectl binary
        local kubectl_url="https://dl.k8s.io/release/${kubectl_version}/bin/linux/${DOWNLOAD_ARCH}/kubectl"
        
        if curl -L "$kubectl_url" -o "/tmp/kubectl" 2>/dev/null; then
            sudo mv "/tmp/kubectl" "/usr/local/bin/kubectl"
            sudo chmod +x "/usr/local/bin/kubectl"
            
            if command_exists kubectl; then
                local installed_version=$(kubectl version --client --output=yaml 2>/dev/null | grep gitVersion || echo "unknown")
                log_success "kubectl installed successfully: $installed_version"
            else
                log_warning "kubectl installation verification failed"
            fi
        else
            log_warning "Failed to download kubectl"
        fi
    else
        local kubectl_version=$(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null || echo "version unknown")
        log_success "kubectl already installed: $kubectl_version"
    fi
    
    # Install Minikube
    if ! command_exists minikube; then
        log "Installing Minikube..."
        
        # Get latest Minikube version
        local minikube_version="v1.34.0"  # Known stable version
        local minikube_url="https://github.com/kubernetes/minikube/releases/download/${minikube_version}/minikube-linux-${DOWNLOAD_ARCH}"
        
        if curl -L "$minikube_url" -o "/tmp/minikube" 2>/dev/null; then
            sudo mv "/tmp/minikube" "/usr/local/bin/minikube"
            sudo chmod +x "/usr/local/bin/minikube"
            
            if command_exists minikube; then
                local installed_version=$(minikube version --short 2>/dev/null || echo "unknown")
                log_success "Minikube installed successfully: $installed_version"
                
                # Now configure Minikube since it's installed
                log "Configuring newly installed Minikube..."
                minikube config set rootless true 2>/dev/null || log_warning "Failed to set Minikube rootless mode"
                minikube config set driver podman 2>/dev/null || log_warning "Failed to set Minikube Podman driver"
                minikube config set container-runtime containerd 2>/dev/null || log_warning "Failed to set Minikube container runtime"
                log_success "Minikube configured for rootless Podman with containerd runtime"
            else
                log_warning "Minikube installation verification failed"
            fi
        else
            log_warning "Failed to download Minikube"
        fi
    else
        local minikube_version=$(minikube version --short 2>/dev/null || echo "version unknown")
        log_success "Minikube already installed: $minikube_version"
    fi
}

# Install and configure zsh
install_zsh() {
    log "Installing and configuring zsh..."
    
    # Check if zsh is already installed
    if command_exists zsh; then
        log_success "zsh is already installed"
        ZSH_VERSION=$(zsh --version)
        log "Current zsh version: $ZSH_VERSION"
    else
        log "Installing zsh..."
        
        case "$DISTRO" in
            ubuntu|debian)
                sudo apt-get install -y zsh || error_exit "Failed to install zsh"
                ;;
            centos|rhel)
                if command_exists dnf; then
                    sudo dnf install -y zsh || error_exit "Failed to install zsh"
                else
                    sudo yum install -y zsh || error_exit "Failed to install zsh"
                fi
                ;;
            macos)
                # zsh is typically pre-installed on macOS, but ensure we have the latest
                if ! command_exists zsh; then
                    brew install zsh || error_exit "Failed to install zsh"
                fi
                ;;
            *)
                error_exit "Unsupported distribution for zsh installation: $DISTRO"
                ;;
        esac
        
        log_success "zsh installed successfully"
    fi
    
    # Check current shell and set zsh as default if it's not already
    CURRENT_SHELL=$(echo $SHELL)
    ZSH_PATH=$(which zsh)
    
    if [ "$CURRENT_SHELL" != "$ZSH_PATH" ]; then
        log "Current shell is $CURRENT_SHELL, setting zsh as default shell..."
        
        # Add zsh to /etc/shells if not already present
        if ! grep -q "$ZSH_PATH" /etc/shells 2>/dev/null; then
            log "Adding $ZSH_PATH to /etc/shells..."
            echo "$ZSH_PATH" | sudo tee -a /etc/shells > /dev/null || log_warning "Could not add zsh to /etc/shells"
        fi
        
        # Change default shell for current user
        log "Attempting to change default shell to zsh..."
        
        # First try without password prompt (works on some systems)
        if chsh -s "$ZSH_PATH" 2>/dev/null; then
            log_success "Default shell changed to zsh for user $USER"
            log "Note: You may need to restart your terminal or log out and back in for the change to take effect"
        else
            # Try with sudo (some systems require this)
            log "Standard chsh failed, trying with sudo..."
            if sudo chsh -s "$ZSH_PATH" "$USER" 2>/dev/null; then
                log_success "Default shell changed to zsh for user $USER (via sudo)"
                log "Note: You may need to restart your terminal or log out and back in for the change to take effect"
            else
                # Try with usermod as last resort
                log "Sudo chsh failed, trying usermod..."
                if sudo usermod -s "$ZSH_PATH" "$USER" 2>/dev/null; then
                    log_success "Default shell changed to zsh for user $USER (via usermod)"
                    log "Note: You may need to restart your terminal or log out and back in for the change to take effect"
                else
                    log_warning "All automatic methods failed to change default shell."
                    log "Please change it manually after the script completes:"
                    log "  Method 1: chsh -s $ZSH_PATH"
                    log "  Method 2: sudo chsh -s $ZSH_PATH $USER"
                    log "  Method 3: sudo usermod -s $ZSH_PATH $USER"
                    log "Then restart your terminal or log out and back in."
                fi
            fi
        fi
    else
        log_success "zsh is already the default shell"
    fi
    
    # Final check and user guidance
    log "Checking final shell configuration..."
    FINAL_SHELL_CHECK=$(getent passwd "$USER" | cut -d: -f7)
    if [ "$FINAL_SHELL_CHECK" = "$ZSH_PATH" ]; then
        log_success "✓ User shell is properly set to zsh in /etc/passwd"
    else
        log_warning "⚠ User shell in /etc/passwd is still: $FINAL_SHELL_CHECK"
        log "To change it manually after the script completes:"
        log "  sudo chsh -s $ZSH_PATH $USER"
        log "  # OR"
        log "  sudo usermod -s $ZSH_PATH $USER"
    fi
    
    # Check current session
    if [ "$SHELL" != "$ZSH_PATH" ]; then
        log "Note: Current session is still using $SHELL"
        log "To start using zsh immediately: exec zsh"
        log "Or restart your terminal/SSH session"
    fi
    
    # Optional: Install oh-my-zsh for better zsh experience (only if not already installed)
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        log "Installing Oh My Zsh for enhanced zsh experience..."
        # Download and install oh-my-zsh non-interactively
        sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || log_warning "Failed to install Oh My Zsh"
        
        if [ -d "$HOME/.oh-my-zsh" ]; then
            log_success "Oh My Zsh installed successfully"
        fi
    else
        log_success "Oh My Zsh is already installed"
    fi
}

# Install Nerd Fonts (FiraCode for ligatures and icons)
install_nerd_fonts() {
    log "Installing Nerd Fonts (FiraCode) for better terminal experience..."
    
    case "$DISTRO" in
        ubuntu|debian)
            # For consistency, always use manual installation to ensure fonts go to /usr/share/fonts/firacode
            log "Installing FiraCode Nerd Font manually for Ubuntu/Debian for consistent directory structure..."
            install_firacode_nerd_font_manual
            ;;
        centos|rhel)
            # CentOS/RHEL usually need manual installation
            log "Installing FiraCode Nerd Font manually for CentOS/RHEL..."
            install_firacode_nerd_font_manual
            ;;
        macos)
            # Use Homebrew cask for macOS
            log "Installing FiraCode Nerd Font via Homebrew..."
            if brew tap homebrew/cask-fonts 2>/dev/null; then
                brew install --cask font-fira-code-nerd-font || log_warning "Failed to install FiraCode Nerd Font via Homebrew"
                log_success "FiraCode Nerd Font installed via Homebrew"
            else
                log_warning "Failed to tap homebrew/cask-fonts, trying manual installation"
                install_firacode_nerd_font_manual
            fi
            ;;
        *)
            # Fallback to manual installation for other distributions
            log "Installing FiraCode Nerd Font manually for unknown distribution..."
            install_firacode_nerd_font_manual
            ;;
    esac
    
    # Provide configuration guidance
    log "Font installation completed!"
    
    # Try to auto-configure terminal fonts where possible
    configure_terminal_font
    
    # Configure VS Code if available
    configure_vscode_font
    
    # Install development tools if requested
    if [ "$INSTALL_DEV_TOOLS" = true ]; then
        install_development_tools
    fi
    
    # Configure desktop environment if GUI detected
    configure_desktop_environment
}

# Manual installation of FiraCode Nerd Font
install_firacode_nerd_font_manual() {
    log "Downloading and installing FiraCode Nerd Font manually..."
    
    # Create fonts directory
    case "$DISTRO" in
        macos)
            FONT_DIR="$HOME/Library/Fonts"
            mkdir -p "$FONT_DIR" || error_exit "Failed to create font directory"
            ;;
        *)
            # Linux systems - try system-wide fonts first, fallback to user fonts
            FONT_DIR="/usr/share/fonts/firacode"
            # Try to create the directory with sudo
            if sudo mkdir -p "$FONT_DIR" 2>/dev/null; then
                log "Using system-wide font directory: $FONT_DIR"
            else
                log_warning "Cannot create system font directory, using user directory"
                FONT_DIR="$HOME/.local/share/fonts"
                mkdir -p "$FONT_DIR" || error_exit "Failed to create user font directory"
                log "Using user font directory: $FONT_DIR"
            fi
            ;;
    esac
    
    log "Font directory: $FONT_DIR"
    
    # Download FiraCode Nerd Font
    TEMP_DIR=$(mktemp -d)
    log "Using temporary directory: $TEMP_DIR"
    cd "$TEMP_DIR" || error_exit "Failed to change to temporary directory"
    
    log "Downloading FiraCode Nerd Font..."
    if ! curl -L "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip" -o "FiraCode.zip"; then
        log_warning "Failed to download fonts - continuing without ligatures support"
        log "You can install fonts manually later from: https://www.nerdfonts.com/font-downloads"
        cd - > /dev/null || true
        rm -rf "$TEMP_DIR"
        return 0
    fi

    # Verify download succeeded
    if [ ! -f "FiraCode.zip" ] || [ ! -s "FiraCode.zip" ]; then
        log_warning "Downloaded font file is empty - continuing without fonts"
        log "You can install fonts manually later from: https://www.nerdfonts.com/font-downloads"
        cd - > /dev/null || true
        rm -rf "$TEMP_DIR"
        return 0
    fi

    log "Downloaded $(du -h FiraCode.zip | cut -f1) font archive"

    # Continue with extraction
    log "Extracting font files..."
    if command_exists unzip; then
        if ! unzip -q "FiraCode.zip"; then
            log_warning "Failed to extract font archive - continuing without fonts"
            log "Archive may be corrupted. You can install fonts manually later."
            cd - > /dev/null || true
            rm -rf "$TEMP_DIR"
            return 0
        fi
    else
        # Install unzip if not available
        log "Installing unzip..."
        local unzip_installed=false
        case "$DISTRO" in
            ubuntu|debian)
                sudo apt-get install -y unzip && unzip_installed=true || log_warning "Failed to install unzip"
                ;;
            centos|rhel)
                if command_exists dnf; then
                    sudo dnf install -y unzip && unzip_installed=true || log_warning "Failed to install unzip"
                else
                    sudo yum install -y unzip && unzip_installed=true || log_warning "Failed to install unzip"
                fi
                ;;
            macos)
                # unzip should be available on macOS
                log_warning "unzip command not found on macOS"
                ;;
        esac

        if [ "$unzip_installed" = false ]; then
            log_warning "Could not install unzip - continuing without fonts"
            log "Install unzip manually and re-run font installation if needed"
            cd - > /dev/null || true
            rm -rf "$TEMP_DIR"
            return 0
        fi

        if ! unzip -q "FiraCode.zip"; then
            log_warning "Failed to extract font archive after installing unzip - continuing without fonts"
            cd - > /dev/null || true
            rm -rf "$TEMP_DIR"
            return 0
        fi
    fi
        
        # Check what was extracted
        log "Extracted files:"
        find . -name "*.ttf" | head -5 || true
        FONT_COUNT_BEFORE=$(find . -name "*.ttf" | wc -l)
        log "Found $FONT_COUNT_BEFORE TTF font files to install"
        
        if [ "$FONT_COUNT_BEFORE" -eq 0 ]; then
            log_error "No TTF font files found in extracted archive"
            log "All extracted files:"
            find . -type f | head -10 || true
            error_exit "No font files to install"
        fi
        
        # Install font files (only TrueType fonts)
        log "Installing font files to $FONT_DIR..."
        case "$DISTRO" in
            macos)
                if find . -name "*.ttf" -exec cp {} "$FONT_DIR/" \; ; then
                    log "Font files copied successfully"
                else
                    error_exit "Failed to copy font files"
                fi
                ;;
            *)
                # Check if we're using system or user directory
                if [[ "$FONT_DIR" == "/usr/share/fonts/"* ]]; then
                    # System-wide installation requires sudo
                    if find . -name "*.ttf" -exec sudo cp {} "$FONT_DIR/" \; ; then
                        log "Font files copied successfully to system directory"
                        # Set proper permissions for system fonts
                        if sudo chmod 644 "$FONT_DIR"/*.ttf 2>/dev/null; then
                            log "Font permissions set successfully"
                        else
                            log_warning "Failed to set font permissions"
                        fi
                    else
                        error_exit "Failed to copy font files to system directory"
                    fi
                else
                    # User directory installation
                    if find . -name "*.ttf" -exec cp {} "$FONT_DIR/" \; ; then
                        log "Font files copied successfully to user directory"
                        # Set proper permissions for user fonts
                        chmod 644 "$FONT_DIR"/*.ttf 2>/dev/null || log_warning "Failed to set font permissions"
                    else
                        error_exit "Failed to copy font files to user directory"
                    fi
                fi
                ;;
        esac
        
        # Verify installation
        FONT_COUNT_AFTER=$(find "$FONT_DIR" -name "*FiraCode*" -name "*.ttf" | wc -l)
        if [ "$FONT_COUNT_AFTER" -eq 0 ]; then
            log_error "No FiraCode fonts found in target directory after installation"
            log "Checking directory contents:"
            ls -la "$FONT_DIR" 2>/dev/null || true
            error_exit "Font installation verification failed"
        fi
        
        # Update font cache on Linux
        if [[ "$DISTRO" != "macos" ]]; then
            if command_exists fc-cache; then
                log "Updating font cache..."
                
                # Update cache based on installation location
                if [[ "$FONT_DIR" == "/usr/share/fonts/"* ]]; then
                    # System fonts - update system cache
                    if sudo fc-cache -fv "$FONT_DIR" 2>/dev/null; then
                        log "System font cache updated successfully"
                    else
                        log_warning "Failed to update system font cache"
                    fi
                    
                    # Also update user cache to ensure immediate availability
                    if fc-cache -fv 2>/dev/null; then
                        log "User font cache updated successfully"
                    else
                        log_warning "Failed to update user font cache"
                    fi
                else
                    # User fonts - update user cache
                    if fc-cache -fv "$FONT_DIR" 2>/dev/null; then
                        log "User font cache updated successfully"
                    else
                        log_warning "Failed to update user font cache"
                    fi
                fi
            else
                log "Installing fontconfig to update font cache..."
                case "$DISTRO" in
                    ubuntu|debian)
                        sudo apt-get install -y fontconfig
                        ;;
                    centos|rhel)
                        if command_exists dnf; then
                            sudo dnf install -y fontconfig
                        else
                            sudo yum install -y fontconfig
                        fi
                        ;;
                esac
                
                log "Updating font cache after installing fontconfig..."
                if [[ "$FONT_DIR" == "/usr/share/fonts/"* ]]; then
                    sudo fc-cache -fv "$FONT_DIR" 2>/dev/null || log_warning "Failed to update system font cache"
                    fc-cache -fv 2>/dev/null || log_warning "Failed to update user font cache"
                else
                    fc-cache -fv "$FONT_DIR" 2>/dev/null || log_warning "Failed to update user font cache"
                fi
            fi
        fi
        
        # Clean up
        cd - > /dev/null || true
        rm -rf "$TEMP_DIR"
        
        log_success "FiraCode Nerd Font installed successfully to $FONT_DIR"
        log "Installed $FONT_COUNT_AFTER FiraCode font files"
        
        # List some installed fonts for verification
        log "Sample installed fonts:"
        find "$FONT_DIR" -name "*FiraCode*" -name "*.ttf" | head -3 | while read -r font; do
            log "  $(basename "$font")"
        done
}

# Configure terminal font automatically where possible
configure_terminal_font() {
    log "Configuring terminal font settings..."
    
    case "$DISTRO" in
        macos)
            configure_macos_terminal_font
            ;;
        ubuntu|debian)
            configure_ubuntu_terminal_font
            ;;
        centos|rhel)
            configure_centos_terminal_font
            ;;
        *)
            log "Manual font configuration required for $DISTRO"
            show_manual_font_instructions
            ;;
    esac
}

# Configure macOS Terminal and iTerm2
configure_macos_terminal_font() {
    log "Configuring macOS terminal fonts..."
    
    # Check if we're running in Terminal.app
    if [[ "$TERM_PROGRAM" == "Apple_Terminal" ]]; then
        log "Detected macOS Terminal.app"
        log "To set FiraCode Nerd Font in Terminal.app:"
        log "  1. Terminal → Preferences → Profiles → Text"
        log "  2. Click 'Change' next to Font"
        log "  3. Select 'FiraCode Nerd Font' or 'FiraCode NF'"
        log "  4. Set size to 12-14pt for best experience"
        
        # Try to create a new Terminal profile with FiraCode
        if command_exists osascript; then
            log "Creating Terminal profile with FiraCode Nerd Font..."
            osascript <<EOF 2>/dev/null || log_warning "Failed to create Terminal profile automatically"
tell application "Terminal"
    -- Create a new settings set based on Basic
    set newSettings to duplicate settings set "Basic"
    set name of newSettings to "FiraCode Dev"
    
    -- Try to set the font (this may not work on all macOS versions)
    try
        set font name of newSettings to "FiraCode Nerd Font"
        set font size of newSettings to 13
    end try
    
    -- Set as default
    set default settings to newSettings
end tell
EOF
            if [ $? -eq 0 ]; then
                log_success "Created 'FiraCode Dev' Terminal profile and set as default"
            fi
        fi
        
    elif [[ "$TERM_PROGRAM" == "iTerm.app" ]]; then
        log "Detected iTerm2"
        log "To set FiraCode Nerd Font in iTerm2:"
        log "  1. iTerm2 → Preferences → Profiles → Text"
        log "  2. Change Font to 'FiraCode Nerd Font'"
        log "  3. Enable 'Use ligatures'"
        log "  4. Set size to 12-14pt"
        
        # iTerm2 configuration via plist (if not running)
        if ! pgrep -f "iTerm" > /dev/null; then
            log "Attempting to configure iTerm2 default font..."
            defaults write com.googlecode.iterm2 "Normal Font" -string "FiraCodeNerdFont-Regular 13" 2>/dev/null || log_warning "Could not set iTerm2 font via defaults"
            defaults write com.googlecode.iterm2 "Use Ligatures" -bool true 2>/dev/null
        fi
        
    else
        log "Unknown macOS terminal. General instructions:"
        log "  1. Open terminal preferences/settings"
        log "  2. Look for Font or Text settings"
        log "  3. Set font to 'FiraCode Nerd Font' or 'FiraCode NF'"
        log "  4. Enable ligatures if available"
    fi
}

# Configure Ubuntu/Debian terminal fonts
configure_ubuntu_terminal_font() {
    log "Configuring Ubuntu/Debian terminal fonts..."
    
    # Check for GNOME Terminal
    if command_exists gnome-terminal; then
        log "Detected GNOME Terminal"
        
        # Try to set font via gsettings (GNOME Terminal)
        if command_exists gsettings; then
            log "Setting GNOME Terminal font to FiraCode Nerd Font..."
            
            # Get the default profile UUID
            PROFILE_ID=$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d "'")
            
            if [ -n "$PROFILE_ID" ]; then
                # Set font for the default profile
                gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE_ID/ use-system-font false
                gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE_ID/ font 'FiraCode Nerd Font 12'
                log_success "GNOME Terminal font set to FiraCode Nerd Font"
            else
                log_warning "Could not detect GNOME Terminal profile ID"
                show_gnome_terminal_manual_instructions
            fi
        else
            show_gnome_terminal_manual_instructions
        fi
        
    # Check for other terminals
    elif command_exists konsole; then
        log "Detected Konsole (KDE)"
        log "To set FiraCode Nerd Font in Konsole:"
        log "  1. Settings → Edit Current Profile → Appearance"
        log "  2. Click 'Choose' next to Font"
        log "  3. Select 'FiraCode Nerd Font'"
        log "  4. Set size to 11-13pt"
        
    elif command_exists xfce4-terminal; then
        log "Detected XFCE Terminal"
        log "To set FiraCode Nerd Font in XFCE Terminal:"
        log "  1. Edit → Preferences → Appearance"
        log "  2. Uncheck 'Use system font'"
        log "  3. Select 'FiraCode Nerd Font'"
        
    else
        log "Terminal auto-detection failed. Manual configuration required:"
        show_manual_font_instructions
    fi
}

# Configure CentOS/RHEL terminal fonts
configure_centos_terminal_font() {
    log "Configuring CentOS/RHEL terminal fonts..."
    
    # Most CentOS/RHEL systems use GNOME Terminal
    if command_exists gnome-terminal; then
        log "Detected GNOME Terminal"
        configure_ubuntu_terminal_font  # Same process as Ubuntu
        
    elif command_exists konsole; then
        log "Detected Konsole (KDE)"
        log "To set FiraCode Nerd Font in Konsole:"
        log "  1. Settings → Edit Current Profile → Appearance"
        log "  2. Click 'Choose' next to Font"
        log "  3. Select 'FiraCode Nerd Font'"
        log "  4. Set size to 11-13pt"
        
    else
        log "Terminal auto-detection failed. Manual configuration required:"
        show_manual_font_instructions
    fi
}

# Manual instructions for GNOME Terminal
show_gnome_terminal_manual_instructions() {
    log "Manual GNOME Terminal configuration:"
    log "  1. Right-click in terminal → Preferences"
    log "  2. Select your profile (usually 'Unnamed' or 'Default')"
    log "  3. Go to Text tab"
    log "  4. Uncheck 'Use the system fixed width font'"
    log "  5. Click the font button and select 'FiraCode Nerd Font'"
    log "  6. Set size to 11-13pt"
}

# General manual instructions
show_manual_font_instructions() {
    log "Manual terminal font configuration:"
    log "  1. Open your terminal's preferences/settings"
    log "  2. Look for Font, Text, or Appearance settings"
    log "  3. Set font to 'FiraCode Nerd Font' or 'FiraCode NF'"
    log "  4. Set size to 11-14pt depending on preference"
    log "  5. Enable font ligatures if available"
    log "  6. Restart terminal to see changes"
}

# Configure VS Code font and ligatures
configure_vscode_font() {
    log "Configuring VS Code font and ligatures..."
    
    # Check if VS Code is installed
    local vscode_installed=false
    
    case "$DISTRO" in
        macos)
            # Check for VS Code on macOS
            if [ -d "/Applications/Visual Studio Code.app" ] || command_exists code; then
                vscode_installed=true
                VSCODE_CONFIG_DIR="$HOME/Library/Application Support/Code/User"
            fi
            ;;
        *)
            # Check for VS Code on Linux
            if command_exists code || command_exists code-oss || command_exists codium; then
                vscode_installed=true
                # VS Code settings location on Linux
                VSCODE_CONFIG_DIR="$HOME/.config/Code/User"
                
                # Also check for other VS Code variants
                if [ -d "$HOME/.config/Code - OSS/User" ]; then
                    VSCODE_CONFIG_DIR="$HOME/.config/Code - OSS/User"
                elif [ -d "$HOME/.config/VSCodium/User" ]; then
                    VSCODE_CONFIG_DIR="$HOME/.config/VSCodium/User"
                fi
            fi
            ;;
    esac
    
    if [ "$vscode_installed" = false ]; then
        log "VS Code not detected, skipping VS Code font configuration"
        return 0
    fi
    
    log "VS Code detected, configuring FiraCode Nerd Font and ligatures..."
    
    # Create VS Code user settings directory if it doesn't exist
    mkdir -p "$VSCODE_CONFIG_DIR"
    
    local SETTINGS_FILE="$VSCODE_CONFIG_DIR/settings.json"
    
    # Create or update settings.json
    if [ -f "$SETTINGS_FILE" ]; then
        log "Updating existing VS Code settings.json..."

        # Create a backup
        cp "$SETTINGS_FILE" "${SETTINGS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

        # Use Python to merge JSON settings (safer than manual editing)
        if command_exists python3; then
            # Export the variable so Python can access it
            export SETTINGS_FILE
            python3 << 'PYTHON_EOF'
import json
import sys
import os

settings_file = os.environ.get('SETTINGS_FILE')
if not settings_file:
    print("Error: SETTINGS_FILE environment variable not set", file=sys.stderr)
    sys.exit(1)

try:
    # Read existing settings
    with open(settings_file, 'r') as f:
        settings = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    settings = {}

# Add/update font settings
font_settings = {
    "editor.fontFamily": "'FiraCode Nerd Font', Jomolhari, Consolas, 'Courier New', monospace",
    "terminal.integrated.fontFamily": "'FiraCode Nerd Font', monospace",
    "terminal.integrated.fontLigatures": True,
    "editor.fontLigatures": True
}

# Merge settings
for key, value in font_settings.items():
    settings[key] = value

# Write updated settings
with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=4)

print("VS Code settings updated successfully")
PYTHON_EOF
            
            if [ $? -eq 0 ]; then
                log_success "VS Code settings updated with FiraCode Nerd Font and ligatures"
            else
                log_warning "Failed to update VS Code settings with Python, trying manual method..."
                create_vscode_settings_manual "$SETTINGS_FILE"
            fi
        else
            log "Python not available, using manual method to update VS Code settings..."
            create_vscode_settings_manual "$SETTINGS_FILE"
        fi
    else
        log "Creating new VS Code settings.json..."
        create_vscode_settings_manual "$SETTINGS_FILE"
    fi
    
    log_success "VS Code font configuration completed"
    log "Restart VS Code to apply the new font and ligature settings"
}

# Create VS Code settings manually when Python method fails
create_vscode_settings_manual() {
    local settings_file="$1"
    
    # Create basic settings with FiraCode Nerd Font
    cat > "$settings_file" << 'VSCODE_SETTINGS_EOF'
{
    "editor.fontFamily": "'FiraCode Nerd Font', Jomolhari, Consolas, 'Courier New', monospace",
    "terminal.integrated.fontFamily": "'FiraCode Nerd Font', monospace",
    "terminal.integrated.fontLigatures": true,
    "editor.fontLigatures": true,
    "editor.fontSize": 13,
    "terminal.integrated.fontSize": 13
}
VSCODE_SETTINGS_EOF
    
    if [ -f "$settings_file" ]; then
        log_success "VS Code settings.json created with FiraCode Nerd Font configuration"
    else
        log_warning "Failed to create VS Code settings.json"
    fi
}

# Install development tools suite
install_development_tools() {
    log "Installing development tools suite..."
    
    # Install VS Code
    install_vscode
    
    # Install additional development tools
    install_additional_dev_tools
}

# Install additional development tools
install_additional_dev_tools() {
    log "Installing additional development tools..."
    
    case "$DISTRO" in
        macos)
            log "Installing macOS development tools..."
            
            # Install common development tools via Homebrew
            local macos_tools=(
                "jq"                    # JSON processor
                "wget"                  # File downloader
                "tree"                  # Directory tree viewer
                "htop"                  # Process monitor
                "neofetch"              # System info
                "tmux"                  # Terminal multiplexer
            )
            
            for tool in "${macos_tools[@]}"; do
                if ! command_exists "$tool"; then
                    log "Installing $tool..."
                    brew install "$tool" || log_warning "Failed to install $tool"
                else
                    log_success "$tool is already installed"
                fi
            done
            
            # Install GUI applications
            local macos_casks=(
                "firefox"               # Web browser
                "postman"               # API testing
            )
            
            for cask in "${macos_casks[@]}"; do
                if ! brew list --cask "$cask" >/dev/null 2>&1; then
                    log "Installing $cask..."
                    brew install --cask "$cask" || log_warning "Failed to install $cask"
                else
                    log_success "$cask is already installed"
                fi
            done
            ;;
        ubuntu|debian)
            log "Installing Ubuntu/Debian development tools..."
            
            local ubuntu_tools=(
                "jq"                    # JSON processor
                "wget"                  # File downloader  
                "tree"                  # Directory tree viewer
                "htop"                  # Process monitor
                "neofetch"              # System info
                "tmux"                  # Terminal multiplexer
                "firefox"               # Web browser
                "build-essential"       # Build tools
                "software-properties-common" # Repository management
            )
            
            for tool in "${ubuntu_tools[@]}"; do
                if ! dpkg -l | grep -q "^ii  $tool "; then
                    log "Installing $tool..."
                    sudo apt-get install -y "$tool" || log_warning "Failed to install $tool"
                else
                    log_success "$tool is already installed"
                fi
            done
            ;;
        centos|rhel)
            log "Installing CentOS/RHEL development tools..."
            
            local centos_tools=(
                "jq"                    # JSON processor
                "wget"                  # File downloader
                "tree"                  # Directory tree viewer
                "htop"                  # Process monitor
                "neofetch"              # System info
                "tmux"                  # Terminal multiplexer
                "firefox"               # Web browser
                "@development-tools"    # Development group
            )
            
            for tool in "${centos_tools[@]}"; do
                if [[ "$tool" == "@"* ]]; then
                    # Group installation
                    log "Installing group $tool..."
                    if command_exists dnf; then
                        sudo dnf group install -y "$tool" || log_warning "Failed to install group $tool"
                    else
                        sudo yum groupinstall -y "$tool" || log_warning "Failed to install group $tool"
                    fi
                else
                    # Individual package
                    log "Installing $tool..."
                    if command_exists dnf; then
                        sudo dnf install -y "$tool" || log_warning "Failed to install $tool"
                    else
                        sudo yum install -y "$tool" || log_warning "Failed to install $tool"
                    fi
                fi
            done
            ;;
        *)
            log_warning "Additional development tools not configured for $DISTRO"
            ;;
    esac
    
    log_success "Additional development tools installation completed"
}

# Install VS Code
install_vscode() {
    log "Installing Visual Studio Code..."
    
    # Only install if we're in a graphical environment or on macOS
    if [ "$DISTRO" != "macos" ]; then
        if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && ! systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
            log "No graphical environment detected, skipping VS Code installation"
            return 0
        fi
    fi
    
    # Check if VS Code is already installed
    local vscode_installed=false
    
    case "$DISTRO" in
        macos)
            if [ -d "/Applications/Visual Studio Code.app" ] || command_exists code; then
                vscode_installed=true
            fi
            ;;
        *)
            if command_exists code || command_exists code-oss || command_exists codium; then
                vscode_installed=true
            fi
            ;;
    esac
    
    if [ "$vscode_installed" = true ]; then
        log_success "VS Code is already installed"
        return 0
    fi
    
    case "$DISTRO" in
        macos)
            log "Installing VS Code via Homebrew..."
            brew install --cask visual-studio-code || error_exit "Failed to install VS Code"
            ;;
        ubuntu|debian)
            log "Installing VS Code via official repository..."
            
            # Add Microsoft GPG key and repository
            curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
            sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
            
            echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list
            
            sudo apt-get update
            sudo apt-get install -y code || error_exit "Failed to install VS Code"
            
            # Clean up
            rm -f packages.microsoft.gpg
            ;;
        centos|rhel)
            log "Installing VS Code via official repository..."
            
            # Import Microsoft GPG key
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            
            # Add VS Code repository
            cat << 'EOF' | sudo tee /etc/yum.repos.d/vscode.repo
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
            
            # Install VS Code
            if command_exists dnf; then
                sudo dnf install -y code || error_exit "Failed to install VS Code"
            else
                sudo yum install -y code || error_exit "Failed to install VS Code"
            fi
            ;;
        *)
            log_warning "VS Code installation not configured for $DISTRO"
            log "Please install VS Code manually from: https://code.visualstudio.com/"
            return 1
            ;;
    esac
    
    # Verify installation
    if command_exists code; then
        log_success "VS Code installed successfully"
        CODE_VERSION=$(code --version 2>/dev/null | head -n 1 || echo "version check failed")
        log "VS Code version: $CODE_VERSION"
    else
        log_warning "VS Code installation may have failed - command not found"
    fi
}

# Configure desktop environment and enable dock/sidebar
configure_desktop_environment() {
    log "Checking and configuring desktop environment..."
    
    # Check if taskbar configuration is forced
    local force_taskbar=false
    if [ "$ENSURE_TASKBAR" = true ] || [ "$INSTALL_DESKTOP" = true ]; then
        force_taskbar=true
        log "Taskbar configuration forced via command line flag"
    fi
    
    # Configure even if no graphical environment if forced
    if [ "$force_taskbar" = false ]; then
        if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && ! systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
            log "No graphical environment detected, skipping desktop configuration"
            log "Use --ensure-taskbar to force desktop configuration"
            return 0
        fi
    fi
    
    case "$DISTRO" in
        centos|rhel)
            configure_centos_desktop
            ;;
        ubuntu|debian)
            configure_ubuntu_desktop
            ;;
        macos)
            log "macOS desktop environment already configured"
            ;;
        *)
            if [ "$force_taskbar" = true ]; then
                log_warning "Taskbar configuration requested but not available for $DISTRO"
                log "Supported distributions: CentOS/RHEL, Ubuntu/Debian"
            else
                log "Desktop configuration not available for $DISTRO"
            fi
            ;;
    esac
}

# Configure CentOS/RHEL desktop environment
configure_centos_desktop() {
    log "Configuring CentOS/RHEL desktop environment..."
    
    # Detect desktop environment
    local desktop_env="unknown"
    
    if [ "$XDG_CURRENT_DESKTOP" = "GNOME" ] || command_exists gnome-shell; then
        desktop_env="gnome"
    elif [ "$XDG_CURRENT_DESKTOP" = "KDE" ] || command_exists plasma-desktop; then
        desktop_env="kde"
    elif [ "$XDG_CURRENT_DESKTOP" = "XFCE" ] || command_exists xfce4-session; then
        desktop_env="xfce"
    fi
    
    log "Detected desktop environment: $desktop_env"
    
    case "$desktop_env" in
        gnome)
            configure_gnome_desktop
            ensure_gnome_taskbar
            ;;
        kde)
            configure_kde_desktop
            ensure_kde_taskbar
            ;;
        xfce)
            configure_xfce_desktop
            ensure_xfce_taskbar
            ;;
        unknown)
            log "Unknown desktop environment, installing GNOME with taskbar..."
            install_gnome_desktop_components
            # After installation, try to configure GNOME
            if command_exists gnome-shell; then
                configure_gnome_desktop
                ensure_gnome_taskbar
            fi
            ;;
    esac
    
    # Ensure desktop environment starts with GUI session
    ensure_gui_session_startup
    
    # Create manual taskbar script for post-reboot installation
    create_manual_taskbar_script
}

# Configure Ubuntu desktop environment
configure_ubuntu_desktop() {
    log "Configuring Ubuntu desktop environment..."
    
    if [ "$XDG_CURRENT_DESKTOP" = "ubuntu:GNOME" ] || [ "$XDG_CURRENT_DESKTOP" = "GNOME" ]; then
        configure_gnome_desktop
    elif [ "$XDG_CURRENT_DESKTOP" = "KDE" ]; then
        configure_kde_desktop
    elif [ "$XDG_CURRENT_DESKTOP" = "XFCE" ]; then
        configure_xfce_desktop
    else
        log "Unknown Ubuntu desktop environment: $XDG_CURRENT_DESKTOP"
        configure_gnome_desktop  # Default to GNOME configuration
    fi
}

# Configure GNOME desktop with dock and sidebar
configure_gnome_desktop() {
    log "Configuring GNOME desktop environment..."
    
    # Check if gsettings is available
    if ! command_exists gsettings; then
        log_warning "gsettings not available, cannot configure GNOME desktop"
        return 1
    fi
    
    log "Enabling GNOME dock and sidebar features..."
    
    # Enable dock (Ubuntu dock or Dash to Dock extension)
    if gsettings list-schemas | grep -q "org.gnome.shell.extensions.dash-to-dock" 2>/dev/null; then
        log "Configuring Dash to Dock extension..."
        
        # Enable the extension if it exists
        CURRENT_EXTENSIONS=$(gsettings get org.gnome.shell enabled-extensions)
        if [[ "$CURRENT_EXTENSIONS" != *"dash-to-dock@micxgx.gmail.com"* ]]; then
            # Add dash-to-dock to enabled extensions
            NEW_EXTENSIONS=$(echo "$CURRENT_EXTENSIONS" | sed "s/\]/,'dash-to-dock@micxgx.gmail.com']/")
            gsettings set org.gnome.shell enabled-extensions "$NEW_EXTENSIONS" 2>/dev/null || log_warning "Failed to enable dash-to-dock extension"
        fi
        
        # Configure dock settings
        gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'LEFT' 2>/dev/null || true
        gsettings set org.gnome.shell.extensions.dash-to-dock extend-height true 2>/dev/null || true
        gsettings set org.gnome.shell.extensions.dash-to-dock show-apps-at-top true 2>/dev/null || true
        gsettings set org.gnome.shell.extensions.dash-to-dock click-action 'cycle-windows' 2>/dev/null || true
        
        log_success "Dash to Dock configured"
    else
        log "Dash to Dock extension not found, trying to install desktop components..."
        install_gnome_desktop_components
    fi
    
    # Enable Activities Overview
    gsettings set org.gnome.desktop.interface show-battery-percentage true 2>/dev/null || true
    gsettings set org.gnome.desktop.interface clock-show-weekday true 2>/dev/null || true
    
    # Enable file manager sidebar
    gsettings set org.gnome.nautilus.preferences always-use-location-entry false 2>/dev/null || true
    gsettings set org.gnome.nautilus.preferences default-folder-viewer 'list-view' 2>/dev/null || true
    
    # Show desktop icons (if supported)
    gsettings set org.gnome.desktop.background show-desktop-icons true 2>/dev/null || log "Desktop icons setting not available"
    
    log_success "GNOME desktop environment configured"
}

# Install missing GNOME desktop components
install_gnome_desktop_components() {
    log "Installing GNOME desktop components..."
    
    case "$DISTRO" in
        centos|rhel)
            if command_exists dnf; then
                log "Installing GNOME desktop and essential components..."
                
                # Try multiple GNOME desktop group names for different CentOS versions
                if sudo dnf group list --installed 2>/dev/null | grep -i "gnome\|workstation" >/dev/null; then
                    log_success "GNOME desktop group already installed"
                else
                    log "Installing GNOME desktop group..."
                    # Try different group names based on CentOS version
                    if sudo dnf group install -y "GNOME Desktop Environment" 2>/dev/null; then
                        log_success "GNOME Desktop Environment installed"
                    elif sudo dnf group install -y "Workstation" 2>/dev/null; then
                        log_success "Workstation group installed"
                    elif sudo dnf group install -y "GNOME" 2>/dev/null; then
                        log_success "GNOME group installed"
                    else
                        log_warning "Group installation failed, trying individual packages..."
                        # Install essential GNOME packages individually
                        sudo dnf install -y gnome-shell gnome-session gdm gnome-terminal nautilus || \
                        log_warning "Failed to install basic GNOME packages"
                    fi
                fi
                
                # Install essential desktop components
                log "Installing essential GNOME components..."
                sudo dnf install -y gnome-tweaks gnome-extensions-app gnome-shell-extensions 2>/dev/null || \
                log_warning "Some GNOME tools may not be available"
                
                # Install taskbar/dock extensions
                sudo dnf install -y gnome-shell-extension-dash-to-dock gnome-shell-extension-apps-menu 2>/dev/null || \
                log_warning "Taskbar extensions not available in repositories - will configure manually"
                
                # Install additional useful extensions
                sudo dnf install -y gnome-shell-extension-top-icons gnome-shell-extension-places-menu \
                                   gnome-shell-extension-window-list 2>/dev/null || true
                
                # Ensure display manager is installed and enabled
                if ! command_exists gdm; then
                    log "Installing GDM display manager..."
                    sudo dnf install -y gdm || log_warning "Failed to install GDM"
                fi
                
            else
                # Legacy yum systems
                log "Installing GNOME desktop via yum..."
                sudo yum groupinstall -y "GNOME Desktop" 2>/dev/null || \
                sudo yum groupinstall -y "Desktop" 2>/dev/null || \
                log_warning "Failed to install GNOME desktop via yum"
                
                # Install basic components
                sudo yum install -y gnome-tweaks 2>/dev/null || log_warning "GNOME tweaks not available"
            fi
            ;;
        ubuntu|debian)
            log "Installing Ubuntu/Debian desktop components..."
            sudo apt-get install -y ubuntu-desktop-minimal gnome-shell-extensions 2>/dev/null || \
            sudo apt-get install -y gnome-shell gnome-shell-extensions gdm3 2>/dev/null || \
            log_warning "Failed to install desktop components"
            
            # Install dash-to-dock
            sudo apt-get install -y gnome-shell-extension-dashtodock 2>/dev/null || \
            log_warning "Dash-to-dock not available"
            ;;
    esac
    
    # After installation, ensure services are enabled
    if command_exists systemctl; then
        log "Enabling desktop services..."
        sudo systemctl enable gdm 2>/dev/null || sudo systemctl enable lightdm 2>/dev/null || \
        log_warning "Could not enable display manager"
        
        sudo systemctl set-default graphical.target 2>/dev/null || \
        log_warning "Could not set graphical boot target"
    fi
    
    log "Desktop components installation completed."
    log "IMPORTANT: You may need to:"
    log "  1. Reboot the system to start the graphical interface"
    log "  2. Log out and back in to see desktop changes"
    log "  3. Run 'sudo systemctl start gdm' to start the display manager now"
}

# Configure KDE desktop
configure_kde_desktop() {
    log "Configuring KDE desktop environment..."
    
    # KDE typically has a taskbar/panel by default
    log "KDE desktop usually includes a taskbar by default"
    
    # Check if plasma panel is running
    if pgrep -f plasma-desktop > /dev/null; then
        log_success "KDE Plasma desktop is running with taskbar"
    else
        log_warning "KDE Plasma desktop not detected as running"
    fi
}

# Configure XFCE desktop
configure_xfce_desktop() {
    log "Configuring XFCE desktop environment..."
    
    # XFCE typically has a panel by default
    log "XFCE desktop usually includes a panel by default"
    
    if command_exists xfce4-panel; then
        log_success "XFCE panel should be available"
    else
        log_warning "XFCE panel not found"
    fi
}

# Ensure GNOME has a visible taskbar/dock
ensure_gnome_taskbar() {
    log "Ensuring GNOME taskbar/dock is visible..."
    
    # Check if we're in a GNOME session
    if [ "$XDG_SESSION_DESKTOP" != "gnome" ] && [ "$XDG_CURRENT_DESKTOP" != "GNOME" ]; then
        log "Not in a GNOME session, skipping GNOME taskbar configuration"
        return 0
    fi
    
    # Install GNOME Shell extensions if not present
    if command_exists dnf; then
        # Install essential GNOME extensions
        sudo dnf install -y gnome-shell-extension-dash-to-dock gnome-shell-extension-apps-menu gnome-tweaks 2>/dev/null || \
        log_warning "Some GNOME extensions may not be available in repositories"
        
        # Try to install additional taskbar-related packages
        sudo dnf install -y gnome-shell-extension-top-icons gnome-shell-extension-places-menu 2>/dev/null || true
    elif command_exists yum; then
        sudo yum install -y gnome-shell-extension-dash-to-dock gnome-tweaks 2>/dev/null || \
        log_warning "GNOME extensions may not be available"
    fi
    
    # Configure GNOME to show dock/taskbar
    if command_exists gsettings; then
        log "Configuring GNOME dock and taskbar settings..."
        
        # Enable dock to be always visible
        gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed true 2>/dev/null || true
        gsettings set org.gnome.shell.extensions.dash-to-dock intellihide false 2>/dev/null || true
        gsettings set org.gnome.shell.extensions.dash-to-dock autohide false 2>/dev/null || true
        
        # Position dock at bottom for traditional taskbar feel
        gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM' 2>/dev/null || true
        gsettings set org.gnome.shell.extensions.dash-to-dock extend-height false 2>/dev/null || true
        
        # Show running applications
        gsettings set org.gnome.shell.extensions.dash-to-dock show-running true 2>/dev/null || true
        gsettings set org.gnome.shell.extensions.dash-to-dock show-favorites true 2>/dev/null || true
        
        # Enable app menu in top bar (like Windows/macOS)
        gsettings set org.gnome.shell enabled-extensions "['apps-menu@gnome-shell-extensions.gcampax.github.com', 'dash-to-dock@micxgx.gmail.com']" 2>/dev/null || true
        
        # Configure top bar to be more taskbar-like
        gsettings set org.gnome.desktop.interface show-battery-percentage true 2>/dev/null || true
        gsettings set org.gnome.desktop.interface clock-show-weekday true 2>/dev/null || true
        gsettings set org.gnome.desktop.interface clock-show-seconds false 2>/dev/null || true
        
        log_success "GNOME taskbar/dock configured for visibility"
    else
        log_warning "gsettings not available, cannot configure GNOME taskbar"
    fi
    
    # Create a startup script to ensure dock is always enabled
    create_gnome_taskbar_startup_script
}

# Ensure KDE has a visible taskbar/panel
ensure_kde_taskbar() {
    log "Ensuring KDE taskbar/panel is visible..."
    
    # KDE taskbar is called a "panel" and should be present by default
    if pgrep -f plasma-desktop > /dev/null; then
        log_success "KDE Plasma desktop is running - taskbar should be visible"
        
        # KDE panels are usually configured automatically, but let's ensure basic components are installed
        if command_exists dnf; then
            sudo dnf install -y plasma-workspace plasma-desktop kf5-plasma-framework 2>/dev/null || true
        elif command_exists yum; then
            sudo yum install -y plasma-workspace plasma-desktop 2>/dev/null || true
        fi
        
        # Restart plasma-desktop if it's not showing taskbar
        log "Restarting KDE plasma desktop to ensure taskbar visibility..."
        killall plasma-desktop 2>/dev/null || true
        nohup plasma-desktop >/dev/null 2>&1 &
        
    else
        log_warning "KDE Plasma desktop not running - installing KDE desktop"
        
        if command_exists dnf; then
            sudo dnf group install -y "KDE Plasma Workspaces" 2>/dev/null || \
            sudo dnf install -y plasma-workspace plasma-desktop 2>/dev/null || \
            log_warning "Failed to install KDE desktop components"
        elif command_exists yum; then
            sudo yum groupinstall -y "KDE Desktop" 2>/dev/null || \
            log_warning "Failed to install KDE desktop"
        fi
    fi
}

# Ensure XFCE has a visible taskbar/panel
ensure_xfce_taskbar() {
    log "Ensuring XFCE taskbar/panel is visible..."
    
    # Install XFCE panel components if missing
    if ! command_exists xfce4-panel; then
        log "Installing XFCE panel components..."
        
        if command_exists dnf; then
            sudo dnf install -y xfce4-panel xfce4-session xfce4-settings 2>/dev/null || \
            log_warning "Failed to install XFCE panel components"
        elif command_exists yum; then
            sudo yum install -y xfce4-panel xfce4-session 2>/dev/null || \
            log_warning "Failed to install XFCE panel components"
        fi
    fi
    
    # Start XFCE panel if not running
    if ! pgrep -f xfce4-panel > /dev/null; then
        log "Starting XFCE panel..."
        nohup xfce4-panel >/dev/null 2>&1 &
    else
        log_success "XFCE panel is running"
    fi
    
    # Create a startup script for XFCE panel
    create_xfce_panel_startup_script
}

# Create a startup script to ensure GNOME dock is always enabled
create_gnome_taskbar_startup_script() {
    log "Creating GNOME taskbar startup script..."
    
    local autostart_dir="$HOME/.config/autostart"
    mkdir -p "$autostart_dir"
    
    # Create a desktop file to enable dash-to-dock on login
    cat > "$autostart_dir/enable-dash-to-dock.desktop" << 'GNOME_AUTOSTART_EOF'
[Desktop Entry]
Type=Application
Exec=/usr/bin/bash -c "sleep 5 && gsettings set org.gnome.shell enabled-extensions \"['dash-to-dock@micxgx.gmail.com', 'apps-menu@gnome-shell-extensions.gcampax.github.com']\" && gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed true"
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name[en_US]=Enable Dash to Dock
Name=Enable Dash to Dock
Comment[en_US]=Ensures GNOME taskbar/dock is always visible
Comment=Ensures GNOME taskbar/dock is always visible
GNOME_AUTOSTART_EOF
    
    log_success "GNOME taskbar startup script created"
}

# Create a startup script for XFCE panel
create_xfce_panel_startup_script() {
    log "Creating XFCE panel startup script..."
    
    local autostart_dir="$HOME/.config/autostart"
    mkdir -p "$autostart_dir"
    
    # Create a desktop file to start XFCE panel on login
    cat > "$autostart_dir/xfce4-panel.desktop" << 'XFCE_AUTOSTART_EOF'
[Desktop Entry]
Type=Application
Exec=xfce4-panel
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name[en_US]=XFCE Panel
Name=XFCE Panel
Comment[en_US]=XFCE desktop panel/taskbar
Comment=XFCE desktop panel/taskbar
XFCE_AUTOSTART_EOF
    
    log_success "XFCE panel startup script created"
}

# Ensure GUI session starts properly with desktop environment
ensure_gui_session_startup() {
    log "Ensuring GUI session startup configuration..."
    
    # Set default target to graphical.target for systemd systems
    if command_exists systemctl; then
        log "Setting default systemd target to graphical..."
        if sudo systemctl get-default | grep -q "multi-user.target"; then
            sudo systemctl set-default graphical.target || log_warning "Failed to set graphical target"
            log_success "System will boot to graphical interface"
        else
            log_success "System already configured for graphical boot"
        fi
        
        # Enable display manager
        local display_manager=""
        if command_exists gdm; then
            display_manager="gdm"
        elif command_exists lightdm; then
            display_manager="lightdm"
        elif command_exists sddm; then
            display_manager="sddm"
        fi
        
        if [ -n "$display_manager" ]; then
            log "Enabling display manager: $display_manager"
            sudo systemctl enable "$display_manager" || log_warning "Failed to enable $display_manager"
        else
            log_warning "No display manager found - GUI login may not work"
        fi
    fi
    
    # For CentOS/RHEL, ensure X11 or Wayland session configuration
    if [[ "$DISTRO" =~ ^(centos|rhel)$ ]]; then
        configure_centos_gui_session
    fi
}

# Configure CentOS/RHEL specific GUI session settings
configure_centos_gui_session() {
    log "Configuring CentOS/RHEL GUI session settings..."
    
    # Install display manager if not present
    if ! command_exists gdm && ! command_exists lightdm; then
        log "Installing GDM display manager..."
        if command_exists dnf; then
            sudo dnf install -y gdm || log_warning "Failed to install GDM"
        elif command_exists yum; then
            sudo yum install -y gdm || log_warning "Failed to install GDM"
        fi
    fi
    
    # Ensure GNOME session is available
    if ! command_exists gnome-session; then
        log "Installing GNOME session manager..."
        if command_exists dnf; then
            sudo dnf install -y gnome-session || log_warning "Failed to install GNOME session"
        elif command_exists yum; then
            sudo yum install -y gnome-session || log_warning "Failed to install GNOME session"
        fi
    fi
    
    log_success "CentOS/RHEL GUI session configuration completed"
}

# Create manual taskbar installation script for users to run after reboot
create_manual_taskbar_script() {
    log "Creating manual taskbar installation script..."
    
    local script_path="$HOME/install-taskbar.sh"
    
    cat > "$script_path" << 'MANUAL_TASKBAR_EOF'
#!/bin/bash
# Manual Taskbar Installation Script
# Run this after rebooting into graphical mode

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

log "Installing and configuring desktop taskbar..."

# Check if we're in a graphical session
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    log_error "No graphical session detected. Please run this script after logging into the desktop."
    exit 1
fi

# Install GNOME extensions
if command_exists dnf; then
    log "Installing GNOME taskbar extensions..."
    sudo dnf install -y gnome-shell-extension-dash-to-dock gnome-shell-extension-apps-menu gnome-tweaks
elif command_exists yum; then
    sudo yum install -y gnome-shell-extension-dash-to-dock gnome-tweaks
fi

# Configure GNOME taskbar
if command_exists gsettings; then
    log "Configuring GNOME taskbar settings..."
    
    # Enable extensions
    gsettings set org.gnome.shell enabled-extensions "['dash-to-dock@micxgx.gmail.com', 'apps-menu@gnome-shell-extensions.gcampax.github.com']"
    
    # Configure dock
    gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed true
    gsettings set org.gnome.shell.extensions.dash-to-dock intellihide false
    gsettings set org.gnome.shell.extensions.dash-to-dock autohide false
    gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM'
    gsettings set org.gnome.shell.extensions.dash-to-dock show-running true
    gsettings set org.gnome.shell.extensions.dash-to-dock show-favorites true
    
    log_success "GNOME taskbar configured successfully!"
    log "Please log out and back in to see the changes, or restart GNOME Shell with Alt+F2, then type 'r' and press Enter."
else
    log_warning "gsettings not available - manual configuration required"
    log "Please install GNOME Tweaks and configure extensions manually"
fi

log_success "Manual taskbar installation completed!"
MANUAL_TASKBAR_EOF

    chmod +x "$script_path"
    
    log_success "Manual taskbar installation script created at: $script_path"
    log "You can run this script after rebooting into graphical mode:"
    log "  bash $script_path"
}

# Troubleshoot minikube issues
troubleshoot_minikube() {
    log "Troubleshooting minikube issues..."
    
    # Check if minikube exists
    if ! command_exists minikube; then
        log_warning "Minikube not installed"
        return 1
    fi
    
    # Clean up any failed installations
    log "Cleaning up any previous failed minikube installations..."
    minikube delete --all 2>/dev/null || true
    
    # Remove any existing volumes that might cause conflicts
    if command_exists podman; then
        log "Cleaning up Podman volumes..."
        podman volume ls -q | grep -E '^minikube' | xargs -r podman volume rm 2>/dev/null || true
    fi
    
    # Reconfigure minikube with correct settings
    log "Reconfiguring minikube..."
    minikube config set rootless true 2>/dev/null || log_warning "Failed to set rootless mode"
    minikube config set driver podman 2>/dev/null || log_warning "Failed to set Podman driver"
    minikube config set container-runtime containerd 2>/dev/null || log_warning "Failed to set container runtime"
    
    log_success "Minikube troubleshooting completed"
    log "Try starting minikube with: minikube start --force-systemd=false"
}

# Install and configure Starship prompt
install_starship() {
    log "Installing and configuring Starship prompt..."
    
    # Check if Starship is already installed
    if command_exists starship; then
        log_success "Starship is already installed"
        STARSHIP_VERSION=$(starship --version | head -n 1)
        log "Current Starship version: $STARSHIP_VERSION"
    else
        log "Installing Starship..."
        
        case "$DISTRO" in
            ubuntu|debian)
                # Install via package manager if available, otherwise use installer script
                if ! sudo apt-get install -y starship 2>/dev/null; then
                    log "Installing Starship via official installer..."
                    curl -sS https://starship.rs/install.sh | sh -s -- --yes || error_exit "Failed to install Starship"
                fi
                ;;
            centos|rhel)
                # Use official installer for CentOS/RHEL
                log "Installing Starship via official installer..."
                curl -sS https://starship.rs/install.sh | sh -s -- --yes || error_exit "Failed to install Starship"
                ;;
            macos)
                # Use Homebrew for macOS
                brew install starship || error_exit "Failed to install Starship"
                ;;
            *)
                # Fallback to official installer
                log "Installing Starship via official installer..."
                curl -sS https://starship.rs/install.sh | sh -s -- --yes || error_exit "Failed to install Starship"
                ;;
        esac
        
        log_success "Starship installed successfully"
    fi
    
    # Create Starship configuration directory
    mkdir -p "$HOME/.config"
    
    # Install Starship configuration using built-in preset
    log "Installing Starship configuration (Catppuccin Powerline preset)..."
    
    # Use the built-in Starship preset to avoid Unicode corruption issues
    if starship preset catppuccin-powerline -o "$HOME/.config/starship.toml"; then
        log_success "Starship configuration installed using built-in preset"
    else
        log_warning "Failed to install Starship preset, trying fallback method..."
        install_starship_config_fallback
    fi
    
    # Configure shell integration
    configure_starship_shell_integration
}


# Fallback function to create Starship config when preset command fails
install_starship_config_fallback() {
    log "Installing fallback Starship configuration..."
    
    # Use a simple, reliable config without complex Unicode symbols
    cat > "$HOME/.config/starship.toml" << 'FALLBACK_EOF'
"$schema" = 'https://starship.rs/config-schema.json'

format = """
[](surface0)\
$os\
$username\
[](bg:peach fg:surface0)\
$directory\
[](fg:peach bg:green)\
$git_branch\
$git_status\
[](fg:green bg:teal)\
$c\
$rust\
$golang\
$nodejs\
$php\
$java\
$kotlin\
$haskell\
$python\
[](fg:teal bg:blue)\
$docker_context\
[](fg:blue bg:purple)\
$time\
[ ](fg:purple)\
$line_break$character"""

palette = 'catppuccin_mocha'

[palettes.gruvbox_dark]
color_fg0 = '#fbf1c7'
color_bg1 = '#3c3836'
color_bg3 = '#665c54'
color_blue = '#458588'
color_aqua = '#689d6a'
color_green = '#98971a'
color_orange = '#d65d0e'
color_purple = '#b16286'
color_red = '#cc241d'
color_yellow = '#d79921'

[palettes.catppuccin_mocha]
rosewater = "#f5e0dc"
flamingo = "#f2cdcd"
pink = "#f5c2e7"
orange = "#cba6f7"
red = "#f38ba8"
maroon = "#eba0ac"
peach = "#fab387"
yellow = "#f9e2af"
green = "#a6e3a1"
teal = "#94e2d5"
sky = "#89dceb"
sapphire = "#74c7ec"
blue = "#89b4fa"
lavender = "#b4befe"
text = "#cdd6f4"
subtext1 = "#bac2de"
subtext0 = "#a6adc8"
overlay2 = "#9399b2"
overlay1 = "#7f849c"
overlay0 = "#6c7086"
surface2 = "#585b70"
surface1 = "#45475a"
surface0 = "#313244"
base = "#1e1e2e"
mantle = "#181825"
crust = "#11111b"

[os]
disabled = false
style = "bg:surface0 fg:text"

[os.symbols]
Windows = "󰍲"
Ubuntu = "󰕈"
SUSE = ""
Raspbian = "󰐿"
Mint = "󰣭"
Macos = "󰀵"
Manjaro = ""
Linux = "󰌽"
Gentoo = "󰣨"
Fedora = "󰣛"
Alpine = ""
Amazon = ""
Android = ""
Arch = "󰣇"
Artix = "󰣇"
EndeavourOS = ""
CentOS = ""
Debian = "󰣚"
Redhat = "󱄛"
RedHatEnterprise = "󱄛"
Pop = ""

[username]
show_always = true
style_user = "bg:surface0 fg:text"
style_root = "bg:surface0 fg:text"
format = '[ $user ]($style)'

[directory]
style = "fg:mantle bg:peach"
format = "[ $path ]($style)"
truncation_length = 3
truncation_symbol = "…/"

[directory.substitutions]
"Documents" = "󰈙 "
"Downloads" = " "
"Music" = "󰝚 "
"Pictures" = " "
"Developer" = "󰲋 "

[git_branch]
symbol = ""
style = "bg:teal"
format = '[[ $symbol $branch ](fg:base bg:green)]($style)'

[git_status]
style = "bg:teal"
format = '[[($all_status$ahead_behind )](fg:base bg:green)]($style)'

[nodejs]
symbol = ""
style = "bg:teal"
format = '[[ $symbol( $version) ](fg:base bg:teal)]($style)'

[c]
symbol = " "
style = "bg:teal"
format = '[[ $symbol( $version) ](fg:base bg:teal)]($style)'

[rust]
symbol = ""
style = "bg:teal"
format = '[[ $symbol( $version) ](fg:base bg:teal)]($style)'

[golang]
symbol = ""
style = "bg:teal"
format = '[[ $symbol( $version) ](fg:base bg:teal)]($style)'

[php]
symbol = ""
style = "bg:teal"
format = '[[ $symbol( $version) ](fg:base bg:teal)]($style)'

[java]
symbol = " "
style = "bg:teal"
format = '[[ $symbol( $version) ](fg:base bg:teal)]($style)'

[kotlin]
symbol = ""
style = "bg:teal"
format = '[[ $symbol( $version) ](fg:base bg:teal)]($style)'

[haskell]
symbol = ""
style = "bg:teal"
format = '[[ $symbol( $version) ](fg:base bg:teal)]($style)'

[python]
symbol = ""
style = "bg:teal"
format = '[[ $symbol( $version) ](fg:base bg:teal)]($style)'

[docker_context]
symbol = ""
style = "bg:mantle"
format = '[[ $symbol( $context) ](fg:#83a598 bg:color_bg3)]($style)'

[time]
disabled = false
time_format = "%R"
style = "bg:peach"
format = '[[  $time ](fg:mantle bg:purple)]($style)'

[line_break]
disabled = false

[character]
disabled = false
success_symbol = '[](bold fg:green)'
error_symbol = '[](bold fg:red)'
vimcmd_symbol = '[](bold fg:creen)'
vimcmd_replace_one_symbol = '[](bold fg:purple)'
vimcmd_replace_symbol = '[](bold fg:purple)'
vimcmd_visual_symbol = '[](bold fg:lavender)'
FALLBACK_EOF
    
    log_success "Fallback Starship configuration created"
}

# Configure shell integration for Starship
configure_starship_shell_integration() {
    log "Configuring shell integration for Starship..."
    
    # Configure zsh integration
    if [ -f "$HOME/.zshrc" ]; then
        # Check if Starship is already configured in .zshrc
        if ! grep -q "starship init zsh" "$HOME/.zshrc"; then
            echo '' >> "$HOME/.zshrc"
            echo '# Initialize Starship prompt' >> "$HOME/.zshrc"
            echo 'eval "$(starship init zsh)"' >> "$HOME/.zshrc"
            log_success "Added Starship initialization to ~/.zshrc"
        else
            log_success "Starship is already configured in ~/.zshrc"
        fi
    fi
    
    # Configure bash integration as fallback
    if [ -f "$HOME/.bashrc" ]; then
        if ! grep -q "starship init bash" "$HOME/.bashrc"; then
            echo '' >> "$HOME/.bashrc"
            echo '# Initialize Starship prompt' >> "$HOME/.bashrc"
            echo 'eval "$(starship init bash)"' >> "$HOME/.bashrc"
            log_success "Added Starship initialization to ~/.bashrc"
        else
            log_success "Starship is already configured in ~/.bashrc"
        fi
    fi
}

# Verify VS Code configuration
verify_vscode_config() {
    # Determine VS Code config directory
    local vscode_config_dir=""
    local vscode_detected=false
    
    case "$DISTRO" in
        macos)
            if [ -d "/Applications/Visual Studio Code.app" ] || command_exists code; then
                vscode_config_dir="$HOME/Library/Application Support/Code/User"
                vscode_detected=true
            fi
            ;;
        *)
            if command_exists code || command_exists code-oss || command_exists codium; then
                vscode_config_dir="$HOME/.config/Code/User"
                vscode_detected=true
                
                # Check for other VS Code variants
                if [ -d "$HOME/.config/Code - OSS/User" ]; then
                    vscode_config_dir="$HOME/.config/Code - OSS/User"
                elif [ -d "$HOME/.config/VSCodium/User" ]; then
                    vscode_config_dir="$HOME/.config/VSCodium/User"
                fi
            fi
            ;;
    esac
    
    if [ "$vscode_detected" = false ]; then
        log "VS Code: Not installed or not detected"
        return 0
    fi
    
    local settings_file="$vscode_config_dir/settings.json"
    
    if [ -f "$settings_file" ]; then
        # Check if FiraCode Nerd Font is configured
        if grep -q "FiraCode Nerd Font" "$settings_file" 2>/dev/null; then
            log_success "VS Code: FiraCode Nerd Font configured"
        else
            log_warning "VS Code: Settings file exists but FiraCode Nerd Font not configured"
        fi
        
        # Check if ligatures are enabled
        if grep -q '"editor.fontLigatures".*true' "$settings_file" 2>/dev/null; then
            log_success "VS Code: Font ligatures enabled"
        else
            log_warning "VS Code: Font ligatures not enabled"
        fi
    else
        log_warning "VS Code: Settings file not found at $settings_file"
    fi
}

# Verify desktop environment configuration
verify_desktop_environment() {
    # Only verify if we're in a graphical environment
    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && ! systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
        log "Desktop Environment: No GUI detected (headless system)"
        return 0
    fi
    
    case "$DISTRO" in
        macos)
            log_success "Desktop Environment: macOS (native dock and sidebar)"
            ;;
        centos|rhel|ubuntu|debian)
            if [ -n "${XDG_CURRENT_DESKTOP:-}" ]; then
                log_success "Desktop Environment: $XDG_CURRENT_DESKTOP detected"
                
                # Check for dock/taskbar based on desktop environment
                if [[ "$XDG_CURRENT_DESKTOP" =~ GNOME ]]; then
                    if command_exists gsettings; then
                        # Check if dash-to-dock is enabled (with timeout to prevent hanging)
                        if timeout 2 gsettings list-schemas 2>/dev/null | grep -q "org.gnome.shell.extensions.dash-to-dock" 2>/dev/null; then
                            ENABLED_EXTENSIONS=$(timeout 2 gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "[]")
                            if [[ "$ENABLED_EXTENSIONS" =~ dash-to-dock ]]; then
                                log_success "Desktop Environment: Dash-to-Dock enabled"
                            else
                                log_warning "Desktop Environment: Dash-to-Dock installed but not enabled"
                            fi
                        else
                            log "Desktop Environment: Dash-to-Dock check skipped (no D-Bus session or not available)"
                        fi
                    fi
                elif [[ "$XDG_CURRENT_DESKTOP" =~ KDE ]]; then
                    if pgrep -f plasma-desktop > /dev/null; then
                        log_success "Desktop Environment: KDE Plasma taskbar running"
                    else
                        log_warning "Desktop Environment: KDE Plasma not detected as running"
                    fi
                elif [[ "$XDG_CURRENT_DESKTOP" =~ XFCE ]]; then
                    if command_exists xfce4-panel; then
                        log_success "Desktop Environment: XFCE panel available"
                    else
                        log_warning "Desktop Environment: XFCE panel not found"
                    fi
                fi
            else
                log_warning "Desktop Environment: XDG_CURRENT_DESKTOP not set, unknown desktop"
            fi
            ;;
        *)
            log "Desktop Environment: Not configured for $DISTRO"
            ;;
    esac
}

# Install Ansible
install_ansible() {
    if command_exists ansible; then
        log_success "Ansible is already installed"
        return 0
    fi
    
    log "Installing Ansible..."
    
    # Use system package manager first to avoid PEP 668 issues
    case "$DISTRO" in
        ubuntu|debian)
            # Ubuntu 24.04+ enforces PEP 668, so use system packages
            sudo apt-get install -y ansible || error_exit "Failed to install Ansible"
            ;;
        centos|rhel)
            # CentOS Stream 10+ may not have Ansible in standard repos
            if command_exists dnf; then
                # Try installing EPEL first
                log "Installing EPEL repository for additional packages..."
                sudo dnf install -y epel-release 2>/dev/null || log_warning "EPEL installation failed or already installed"
                
                # Try to install Ansible from repositories
                if sudo dnf install -y ansible 2>/dev/null; then
                    log_success "Ansible installed from repository"
                else
                    log_warning "Ansible not available in repositories, installing via pip"
                    # Fallback to pip installation
                    if command_exists pip3; then
                        pip3 install --user ansible || error_exit "Failed to install Ansible via pip3"
                    elif command_exists pip; then
                        pip install --user ansible || error_exit "Failed to install Ansible via pip"
                    else
                        error_exit "Unable to install Ansible - no pip available"
                    fi
                    # Add user bin to PATH for this session
                    export PATH="$HOME/.local/bin:$PATH"
                fi
            else
                sudo yum install -y epel-release || log_warning "EPEL installation failed or already installed"
                if ! sudo yum install -y ansible 2>/dev/null; then
                    log_warning "Ansible not available in repositories, installing via pip"
                    if command_exists pip3; then
                        pip3 install --user ansible || error_exit "Failed to install Ansible via pip3"
                    elif command_exists pip; then
                        pip install --user ansible || error_exit "Failed to install Ansible via pip"
                    else
                        error_exit "Unable to install Ansible - no pip available"
                    fi
                    export PATH="$HOME/.local/bin:$PATH"
                fi
            fi
            ;;
        macos)
            brew install ansible || error_exit "Failed to install Ansible"
            ;;
        *)
            # Fallback to pip for unknown distributions
            log_warning "Unknown distribution $DISTRO, trying pip installation"
            if command_exists pip3; then
                pip3 install --user ansible || error_exit "Failed to install Ansible via pip3"
            elif command_exists pip; then
                pip install --user ansible || error_exit "Failed to install Ansible via pip"
            else
                error_exit "Unable to install Ansible on $DISTRO - no pip or package manager available"
            fi
            ;;
    esac
    
    log_success "Ansible installed successfully"
}

# Verify installations
verify_installations() {
    log "Verifying installations..."
    
    local all_good=true
    
    if command_exists curl; then
        CURL_VERSION=$(curl --version | head -n 1)
        log_success "curl: $CURL_VERSION"
    else
        log_error "curl verification failed"
        all_good=false
    fi
    
    if command_exists python3; then
        PYTHON_VERSION=$(python3 --version)
        log_success "Python: $PYTHON_VERSION"
    elif command_exists python; then
        PYTHON_VERSION=$(python --version)
        log_success "Python: $PYTHON_VERSION"
    else
        log_error "Python verification failed"
        all_good=false
    fi
    
    if command_exists pip3; then
        PIP_VERSION=$(pip3 --version)
        log_success "pip: $PIP_VERSION"
    elif command_exists pip; then
        PIP_VERSION=$(pip --version)
        log_success "pip: $PIP_VERSION"
    else
        log_error "pip verification failed"
        all_good=false
    fi
    
    if command_exists git; then
        GIT_VERSION=$(git --version)
        log_success "git: $GIT_VERSION"
    else
        log_error "git verification failed"
        all_good=false
    fi
    
    if command_exists gh; then
        GH_VERSION=$(gh --version | head -n 1)
        log_success "GitHub CLI: $GH_VERSION"
    else
        log_error "GitHub CLI verification failed"
        all_good=false
    fi
    
    if [ "$SKIP_ZSH" = false ]; then
        if command_exists zsh; then
            ZSH_VERSION=$(zsh --version)
            CURRENT_SHELL=$(echo $SHELL)
            ZSH_PATH=$(which zsh)
            log_success "zsh: $ZSH_VERSION"
            if [ "$CURRENT_SHELL" = "$ZSH_PATH" ]; then
                log_success "zsh is set as default shell"
            else
                log_warning "zsh is installed but not set as default shell (current: $CURRENT_SHELL)"
            fi
        else
            log_error "zsh verification failed"
            all_good=false
        fi
    fi
    
    # Check Nerd Fonts installation
    case "$DISTRO" in
        macos)
            FONT_DIR="$HOME/Library/Fonts"
            ;;
        *)
            # Check both system and user font directories on Linux
            SYSTEM_FONT_DIR="/usr/share/fonts/firacode"
            USER_FONT_DIR="$HOME/.local/share/fonts"
            ;;
    esac
    
    case "$DISTRO" in
        macos)
            if [ -d "$FONT_DIR" ]; then
                FIRACODE_FONTS=$(find "$FONT_DIR" -name "*FiraCode*" -name "*.ttf" 2>/dev/null | wc -l)
                if [ "$FIRACODE_FONTS" -gt 0 ]; then
                    log_success "Nerd Fonts: Found $FIRACODE_FONTS FiraCode font files"
                else
                    log_warning "Nerd Fonts: No FiraCode fonts found in $FONT_DIR"
                fi
            else
                log_warning "Nerd Fonts: Font directory $FONT_DIR not found"
            fi
            ;;
        *)
            # Check Linux font directories
            SYSTEM_FONTS=0
            USER_FONTS=0
            if [ -d "$SYSTEM_FONT_DIR" ]; then
                SYSTEM_FONTS=$(find "$SYSTEM_FONT_DIR" -name "*FiraCode*" -name "*.ttf" 2>/dev/null | wc -l)
            fi
            if [ -d "$USER_FONT_DIR" ]; then
                USER_FONTS=$(find "$USER_FONT_DIR" -name "*FiraCode*" -name "*.ttf" 2>/dev/null | wc -l)
            fi
            TOTAL_FONTS=$((SYSTEM_FONTS + USER_FONTS))
            
            if [ "$TOTAL_FONTS" -gt 0 ]; then
                if [ "$SYSTEM_FONTS" -gt 0 ]; then
                    log_success "Nerd Fonts: Found $SYSTEM_FONTS FiraCode font files (system-wide)"
                fi
                if [ "$USER_FONTS" -gt 0 ]; then
                    log_success "Nerd Fonts: Found $USER_FONTS FiraCode font files (user)"
                fi
            else
                log_warning "Nerd Fonts: No FiraCode fonts found in system or user directories"
            fi
            ;;
    esac
    
    if command_exists starship; then
        STARSHIP_VERSION=$(starship --version | head -n 1)
        log_success "Starship: $STARSHIP_VERSION"
        
        # Check if Starship is configured in shell
        if [ -f "$HOME/.zshrc" ] && grep -q "starship init zsh" "$HOME/.zshrc"; then
            log_success "Starship is configured for zsh"
        elif [ -f "$HOME/.bashrc" ] && grep -q "starship init bash" "$HOME/.bashrc"; then
            log_success "Starship is configured for bash"
        else
            log_warning "Starship is installed but may not be configured for your current shell"
        fi
    else
        log_error "Starship verification failed"
        all_good=false
    fi
    
    # Check VS Code font configuration
    verify_vscode_config
    
    # Check desktop environment configuration
    verify_desktop_environment
    
    if command_exists ansible; then
        ANSIBLE_VERSION=$(ansible --version | head -n 1)
        log_success "Ansible: $ANSIBLE_VERSION"
    else
        log_error "Ansible verification failed"
        all_good=false
    fi
    
    # Check VS Code installation
    if command_exists code; then
        CODE_VERSION=$(code --version 2>/dev/null | head -n 1 || echo "version check failed")
        log_success "VS Code: $CODE_VERSION"
    else
        # Only warn if GUI environment exists (VS Code installation was attempted)
        if [ "$DISTRO" = "macos" ] || [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ] || systemctl --user is-active --quiet graphical-session.target 2>/dev/null; then
            log_warning "VS Code: Not installed (GUI environment detected)"
        else
            log "VS Code: Skipped (no GUI environment)"
        fi
    fi
    
    if command_exists podman; then
        PODMAN_VERSION=$(podman --version)
        log_success "Podman: $PODMAN_VERSION"
    elif command_exists docker; then
        DOCKER_VERSION=$(docker --version)
        log_success "Docker: $DOCKER_VERSION"
    else
        log_warning "No container runtime found (podman/docker)"
    fi
    
    if [ "$all_good" = true ]; then
        log_success "All tools verified successfully!"
        return 0
    else
        log_warning "Some tools failed verification, but continuing with setup..."
        return 0
    fi
}

# Run secondary Ansible automation
run_ansible_automation() {
    local ansible_script="${1:-./setup.yml}"

    if [ -f "$ansible_script" ]; then
        log "Running unified development environment setup: $ansible_script"
        log "This will install packages appropriate for $OS ($DISTRO)"
        log "Note: You may be prompted for your sudo password during package installation"

        # Let Ansible handle sudo prompts naturally (removes automation barriers)
        ansible-playbook "$ansible_script" || log_warning "Ansible automation script failed or completed with warnings"
    else
        log_warning "Ansible automation script not found: $ansible_script"
        log "You can run the setup manually once it's available:"
        log "  ansible-playbook setup.yml"
    fi
}

# Main function
main() {
    log "Starting development environment bootstrap..."
    
    # Parse command line arguments
    ANSIBLE_SCRIPT=""
    SKIP_ANSIBLE=false
    SKIP_ZSH=false
    SKIP_FONTS=false
    INSTALL_DESKTOP=false
    INSTALL_DEV_TOOLS=false
    ENSURE_TASKBAR=false
    TROUBLESHOOT_MINIKUBE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ansible-script)
                ANSIBLE_SCRIPT="$2"
                shift 2
                ;;
            --skip-ansible)
                SKIP_ANSIBLE=true
                shift
                ;;
            --skip-zsh)
                SKIP_ZSH=true
                shift
                ;;
            --skip-fonts)
                SKIP_FONTS=true
                shift
                ;;
            --install-desktop)
                INSTALL_DESKTOP=true
                shift
                ;;
            --install-dev-tools)
                INSTALL_DEV_TOOLS=true
                shift
                ;;
            --ensure-taskbar)
                ENSURE_TASKBAR=true
                shift
                ;;
            --troubleshoot-minikube)
                TROUBLESHOOT_MINIKUBE=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [--ansible-script PATH] [--skip-ansible] [--skip-zsh] [--skip-fonts] [--install-desktop] [--install-dev-tools] [--ensure-taskbar] [--troubleshoot-minikube]"
                echo "  --ansible-script PATH     Path to custom Ansible playbook (default: setup.yml)"
                echo "  --skip-ansible            Skip running Ansible automation"
                echo "  --skip-zsh                Skip installing and configuring zsh as default shell"
                echo "  --skip-fonts              Skip installing FiraCode Nerd Font"
                echo "  --install-desktop          Force installation of Podman Desktop (GUI) on Linux"
                echo "  --install-dev-tools        Install additional development tools (VS Code, etc.)"
                echo "  --ensure-taskbar           Force installation and configuration of desktop taskbar/panel"
                echo "  --troubleshoot-minikube    Clean up and reconfigure minikube for proper operation"
                echo ""
                echo "The script automatically detects your OS and installs appropriate packages:"
                echo "  - macOS: Docker Desktop + Docker Compose, Homebrew packages"
                echo "  - Ubuntu/Debian: Podman (Docker CLI compatible), apt packages, modern CLI tools"
                echo "  - CentOS/RHEL/CentOS Stream 9/10: Podman (Docker CLI compatible), dnf/yum packages"
                echo "  - Windows 11: Use bootstrap-dev-env.ps1 instead (PowerShell script)"
                echo ""
                echo "For Windows 11 users:"
                echo "  .\\bootstrap-dev-env.ps1                    # Full Windows setup"
                echo "  .\\bootstrap-dev-env.ps1 -UseScoop         # Use Scoop package manager"
                echo "  .\\bootstrap-dev-env.ps1 -SkipAnsible     # Skip Ansible automation"
                exit 0
                ;;
            *)
                log_warning "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    # Detect OS and architecture
    detect_os
    
    # Run minikube troubleshooter if requested
    if [ "$TROUBLESHOOT_MINIKUBE" = true ]; then
        troubleshoot_minikube
        log_success "Minikube troubleshooting completed! You can now try 'minikube start --force-systemd=false'"
        exit 0
    fi
    
    # Validate system compatibility
    validate_system
    
    # Update package manager
    update_package_manager
    
    # Install tools
    install_curl
    install_python
    install_git_and_github_cli
    
    # Install zsh if not skipped
    if [ "$SKIP_ZSH" = false ]; then
        install_zsh
    else
        log "Skipping zsh installation as requested"
    fi
    
    # Install Nerd Fonts for better terminal experience if not skipped
    if [ "$SKIP_FONTS" = false ]; then
        install_nerd_fonts
    else
        log "Skipping Nerd Fonts installation as requested"
    fi
    
    # Install Starship after fonts and zsh for best experience
    install_starship
    
    # Install VS Code if GUI environment is detected
    install_vscode
    
    install_container_runtime
    install_ansible
    
    # Verify installations
    verify_installations
    
    # Run Ansible automation if not skipped
    if [ "$SKIP_ANSIBLE" = false ]; then
        if [ -n "$ANSIBLE_SCRIPT" ]; then
            run_ansible_automation "$ANSIBLE_SCRIPT"
        else
            # Use the unified setup playbook for all operating systems
            run_ansible_automation "./setup.yml"
        fi
    fi
    
    log_success "Development environment bootstrap completed!"
    if [ "$INSTALL_DEV_TOOLS" = true ]; then
        log "You can now use python, curl, git, gh (GitHub CLI), zsh, starship, ansible, VS Code, and additional development tools."
    else
        log "You can now use python, curl, git, gh (GitHub CLI), zsh, starship, ansible, and VS Code for your development environment."
        log "Tip: Run with --install-dev-tools to install additional development tools and utilities"
    fi
    log ""
    log "Next steps:"
    log "1. To start using zsh immediately: exec zsh"
    log "2. Restart your terminal to apply font changes (auto-configured where possible)"
    log "3. Restart VS Code to apply FiraCode Nerd Font and ligatures (auto-configured if detected)"
    
    # Add taskbar-specific instructions for CentOS/RHEL
    if [[ "$DISTRO" =~ ^(centos|rhel)$ ]]; then
        if [ "$ENSURE_TASKBAR" = true ] || [ "$INSTALL_DESKTOP" = true ]; then
            log "4. TASKBAR SETUP (CentOS/RHEL):"
            log "   a. Reboot the system: sudo reboot"
            log "   b. Log in to the graphical desktop environment"
            log "   c. Run the taskbar setup script: bash ~/install-taskbar.sh"
            log "   d. Log out and back in to see the taskbar/dock"
        else
            log "4. Log out and back in to see desktop environment changes"
        fi
    else
        log "4. Log out and back in to see desktop environment changes (GNOME dock/sidebar configured)"
    fi
    
    log "5. To see the Starship prompt: restart your terminal or run 'source ~/.zshrc'"
    log "6. To authenticate with GitHub: gh auth login"
    log "7. If zsh isn't your default shell, restart your terminal/SSH session or run:"
    log "   sudo chsh -s \$(which zsh) $USER"
    
    # Add minikube-specific instructions for Linux systems
    if [[ "$DISTRO" =~ ^(centos|rhel|ubuntu|debian)$ ]]; then
        log "8. To start Kubernetes with minikube (Podman + containerd):"
        log "   minikube start --force-systemd=false"
        log "   kubectl get nodes"
        log "   If minikube has issues, run: $0 --troubleshoot-minikube"
    fi
    
    # Additional CentOS taskbar tip
    if [[ "$DISTRO" =~ ^(centos|rhel)$ ]] && [ -f "$HOME/install-taskbar.sh" ]; then
        log ""
        log "💡 TIP: If you don't see a taskbar after logging in graphically, run:"
        log "   bash ~/install-taskbar.sh"
    fi
}

# Run main function with all arguments
main "$@"