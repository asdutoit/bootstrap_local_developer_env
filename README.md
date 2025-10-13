# Universal Development Environment Bootstrap

This repository contains scripts for setting up a comprehensive development environment that automatically detects and supports multiple operating systems and architectures.

## 🌍 **Supported Systems**

- **Ubuntu/Debian** (x86_64, ARM64, ARMv7)
- **CentOS/RHEL** (x86_64, ARM64, ARMv7)  
- **macOS** (Intel, Apple Silicon)
- **Windows 11** (x64, ARM64) - **NEW!**

## 🚀 **Quick Start**

### **Linux/macOS:**
```bash
# One command to rule them all
./bootstrap-dev-env.sh
```

### **Windows 11:**
```powershell
# PowerShell (recommended)
.\bootstrap-dev-env.ps1

# With Scoop package manager
.\bootstrap-dev-env.ps1 -UseScoop

# Skip Ansible automation
.\bootstrap-dev-env.ps1 -SkipAnsible
```

## 📁 **Main Files**

### `bootstrap-dev-env.sh`
**Universal bootstrap script** - Detects your OS and sets up everything automatically.

**What it does:**
- Detects OS (Ubuntu/CentOS/macOS) and architecture (x86_64/ARM64/ARMv7) automatically
- Installs: curl, Python3, Ansible
- Runs the unified Ansible playbook (`setup.yml`) for complete environment setup
- No manual configuration needed!

### `bootstrap-dev-env.ps1` (Windows)
**Windows PowerShell bootstrap script** - Native Windows 11 setup using PowerShell.

**What it does:**
- Detects Windows version and architecture automatically
- Installs package managers (Chocolatey/Scoop)
- Installs: curl, Python3, Ansible
- Runs the Windows-specific Ansible playbook (`setup-windows.yml`)
- Configures PowerShell profile with useful aliases

### `setup.yml`
**Unified Ansible playbook** - Single playbook that handles Linux and macOS.

### `setup-windows.yml`
**Windows-specific Ansible playbook** - Comprehensive Windows 11 development environment.

**What it installs:**

### 💻 **Core Development Tools**
- **Editors**: VS Code, vim, neovim (Ubuntu)
- **Version Control**: git, git-lfs, meld (Ubuntu)
- **System Tools**: htop, tree, jq, curl, wget, tar
- **Build Tools**: gcc/build-essential, make
- **Terminal**: tmux (Ubuntu), zsh (Ubuntu)

### 🔥 **Languages & Runtimes**
- **JavaScript**: Node.js, npm
- **Go**: golang  
- **Rust**: rust, cargo
- **Python**: Available system-wide

### ☁️ **Cloud & DevOps Tools**
- **Cloud CLIs**: GitHub CLI (`gh`), Azure CLI (`az`), AWS CLI (Ubuntu)
- **Infrastructure**: Terraform
- **Kubernetes**: kubectl, minikube
- **API Testing**: Bruno (macOS)

### 🐳 **Container Runtimes** (OS-specific)
- **macOS**: Docker Desktop + Docker Compose (native)
- **Linux**: Podman + Podman Desktop GUI (Docker CLI compatible, rootless)

### 📡 **Modern CLI Tools** (Ubuntu)
- **Search**: fzf (fuzzy finder), ripgrep (fast grep)
- **File Tools**: bat (better cat), exa (better ls), ncdu (disk usage)
- **Databases**: sqlite3, redis-tools
- **Network**: netcat-openbsd

**Usage:**
```bash
ansible-playbook setup.yml
```

## 🌍 **OS-Specific Container Strategy**

### **macOS**
- **Docker Desktop**: Full native macOS experience
- **Docker Compose**: Included with Docker Desktop
- **Commands**: `docker` and `docker-compose` work natively
- **GUI**: Docker Desktop provides full container management

### **Ubuntu/Debian & CentOS/RHEL**
- **Podman**: Rootless, daemonless, Docker CLI compatible
- **Podman Desktop**: GUI application via Flatpak
- **Docker Aliases**: `docker` commands work via podman-docker package + aliases
- **Security**: Containers run rootless by default (more secure)
- **Launch GUI**: `flatpak run io.podman_desktop.PodmanDesktop`

### **Windows 11**
- **Docker Desktop**: Native Windows experience with WSL2 backend
- **WSL2 Integration**: Linux containers run efficiently on Windows
- **Windows Containers**: Support for both Linux and Windows containers
- **GUI**: Docker Desktop provides full container management
- **Commands**: `docker` and `docker-compose` work natively

### 📖 **Documentation**

#### `ARCHITECTURE_SUPPORT.md`
Documents the architecture-awareness improvements:
- Fixes for kubectl/minikube ARM64 compatibility
- Architecture detection and mapping
- Supported architectures (x86_64, ARM64, ARMv7)

#### `PYTHON_SETUP_FIX.md`
Documents the Python PEP 668 compliance solution:
- Multi-layered Python package management
- System packages, pipx tools, virtual environments
- Usage examples and verification tests

#### `AZURE_AUTH_GUIDE.md`
Comprehensive guide for Azure authentication automation:
- Interactive and automated authentication methods
- Service Principal setup and security best practices
- Environment configuration and troubleshooting
- CI/CD integration examples

## Architecture Support

All scripts automatically detect your system architecture and download the correct binaries:

| Architecture | Download Format | Status |
|-------------|----------------|--------|
| x86_64 | amd64 | ✅ Supported |
| aarch64 (ARM64) | arm64 | ✅ Supported |
| armv7l | arm | ✅ Supported |

## Python Development Setup

The bootstrap creates a **PEP 668 compliant** Python environment:

### 🔧 **System Packages** (Global)
```bash
# Available immediately
python3 -c "import requests; print('Works!')"
```

### 🛠️ **CLI Tools** (pipx)
```bash
# Code formatting and linting
black --version
flake8 --version

# HTTP testing and development
httpie https://api.github.com/user

# Dependency management
poetry new my-project

# Interactive Python
ipython
jupyter notebook
```

### 🧪 **Development Environment** (Virtual)
```bash
# Isolated development environment
source ~/venv/dev-env/bin/activate
pip install your-package
```

### 🚀 **Modern CLI Tools**
```bash
# Fuzzy finding
fzf  # Interactive file/command finder
Ctrl+R  # Fuzzy search command history

# Fast searching
rg "search-term" .  # Faster than grep
rg "function.*main" --type py  # Search Python files

# Better file viewing
bat README.md  # Syntax highlighted cat
exa -la  # Better ls with colors and icons

# Disk usage
ncdu  # Interactive disk usage analyzer
```

### ☁️ **Azure Development**
```bash
# Authenticate to Azure
~/scripts/azure-auth.sh

# Basic Azure operations
az account show
az group list
az resource list

# Azure + GitHub workflow
gh repo clone your-org/your-repo
az webapp create --resource-group myRG --plan myPlan --name myApp
```

## Quick Start

### **Linux/macOS:**
```bash
# Complete setup (automatically detects your OS)
./bootstrap-dev-env.sh

# Skip Ansible automation (only install Python/curl/Ansible)
./bootstrap-dev-env.sh --skip-ansible

# Use a custom Ansible playbook
./bootstrap-dev-env.sh --ansible-script /path/to/your-playbook.yml
```

### **Windows 11:**
```powershell
# Complete setup with Chocolatey (recommended)
.\bootstrap-dev-env.ps1

# Use Scoop package manager instead
.\bootstrap-dev-env.ps1 -UseScoop

# Skip Ansible automation (only install Python/curl/Ansible)
.\bootstrap-dev-env.ps1 -SkipAnsible

# Use a custom Ansible playbook
.\bootstrap-dev-env.ps1 -AnsibleScript custom-windows.yml
```

## What Gets Installed Automatically

### **All Operating Systems:**
- Python 3, curl, Ansible (via bootstrap script)
- Git, vim, htop, tree, jq
- Node.js for JavaScript development
- kubectl, minikube for Kubernetes
- GitHub CLI, Azure CLI for cloud operations
- Development directories: ~/projects, ~/scripts

### **Ubuntu/Debian Specific:**
- Docker Engine with full Docker Compose
- Modern CLI tools: fzf, ripgrep, bat, exa, ncdu
- Database tools: SQLite, Redis
- Build tools: build-essential
- Additional: neovim, tmux, zsh, git-lfs, meld

### **Ubuntu/Debian Specific:**
- **Podman** (Docker CLI compatible)
- Modern CLI tools: fzf, ripgrep, bat, exa, ncdu
- Database tools: SQLite, Redis
- Build tools: build-essential
- Additional: neovim, tmux, zsh, git-lfs, meld
- Docker commands work via alias (docker=podman)

### **CentOS/RHEL Specific:**
- **Podman** (Docker CLI compatible)
- Build tools: gcc, gcc-c++, make
- Docker commands work via alias (docker=podman)
- Rootless containers by default (more secure)

### **macOS Specific:**
- **Docker Desktop + Docker Compose** (native macOS experience)
- All packages via Homebrew
- Zsh configuration (default shell)
- Native Docker commands (no aliases needed)

### **Windows 11 Specific:**
- **Package Manager**: Chocolatey (default) or Scoop (alternative)
- **Containers**: Docker Desktop with WSL2 backend
- **Languages**: Node.js, Go, Rust, Python via package manager
- **Modern CLI**: PowerShell profile with aliases and shortcuts
- **Development Tools**: VS Code, Visual Studio Build Tools, Windows SDK
- **Cloud Tools**: GitHub CLI, Azure CLI, Terraform
- **WSL2**: Optional Linux subsystem integration

**Test everything works:**
```bash
./test-python-setup.sh
```

3. **Start developing:**
   ```bash
   # Activate virtual environment
   source ~/venv/dev-env/bin/activate
   
   # Install project dependencies
   pip install flask fastapi pytest
   
   # Use CLI tools
   black your_code.py
   flake8 your_code.py
   ```

## Created Directories

- `~/projects` - Your code projects
- `~/scripts` - Your utility scripts  
- `~/venv/dev-env` - Python virtual environment
- `~/.local/bin` - User binaries (pipx tools)

## Next Steps After Bootstrap

1. **Logout/login** to apply Docker group changes
2. **Test Docker:** `docker run hello-world`
3. **Start Minikube:** `minikube start`
4. **Test Kubernetes:** `kubectl cluster-info`

## Troubleshooting

### "sudo: a password is required" Error

This is the most common issue when running on CentOS/RHEL. The Ansible playbook needs sudo access to install system packages.

**Solutions:**

1. **Use the updated script** (recommended):
   ```bash
   ./bootstrap-dev-env.sh --full-setup
   # You'll be prompted for your sudo password when needed
   ```

2. **Use safe setup** (minimal sudo usage):
   ```bash
   ./bootstrap-dev-env.sh
   # Uses ansible-setup-safe.yml by default
   ```

3. **Run Ansible manually**:
   ```bash
   ansible-playbook --ask-become-pass ansible-setup.yml
   ```

4. **Configure passwordless sudo** (not recommended for security):
   ```bash
   echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER
   ```

### CentOS/RHEL Specific Issues

- Some packages may not be available in default repositories
- The script automatically installs EPEL repository when needed
- Package installation failures are set to `ignore_errors: yes`

### Docker Installation Fails on CentOS

Docker installation commonly fails on CentOS due to dependency issues (especially `libcgroup` on ARM64). This is a known problem with Docker CE on CentOS systems.

**Quick Solutions (try in order):**

1. **Use the unified setup** (recommended):
   ```bash
   ./bootstrap-dev-env.sh
   # Automatically installs Podman on CentOS (no Docker issues!)
   ```

2. **Diagnose the problem** (if still having issues):
   ```bash
   ./diagnose-centos-docker.sh
   # This will tell you exactly what's wrong
   ```

3. **Install Podman instead** (recommended for CentOS):
   ```bash
   ./install-podman-centos.sh
   # Podman is more reliable on CentOS and 100% Docker-compatible
   ```

4. **Manual Docker installation**:
   ```bash
   ./manual-docker-centos.sh
   # Tries multiple installation strategies
   ```

5. **Direct dnf installation** (like your old working script):
   ```bash
   sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
   ```

6. **Skip Ansible entirely** (just get Python/curl/Ansible):
   ```bash
   ./bootstrap-dev-env.sh --skip-ansible
   ```

**Why Podman is better for CentOS:**
- ✅ No dependency issues (libcgroup not needed)
- ✅ Rootless by default (more secure)
- ✅ No daemon required
- ✅ 100% Docker CLI compatible
- ✅ Officially supported by Red Hat

### General Issues

1. **Check architecture compatibility:**
   ```bash
   uname -m  # Should match binary architecture
   file /usr/local/bin/kubectl  # Should show correct arch
   ```

2. **Test Python setup:**
   ```bash
   ./test-python-setup.sh
   ```

3. **Check PATH:**
   ```bash
   echo $PATH  # Should include ~/.local/bin
   ```

## Benefits

- ✅ **Architecture-aware:** Works on ARM64 and x86_64
- ✅ **PEP 668 compliant:** No system Python conflicts
- ✅ **Comprehensive:** Full development environment
- ✅ **Tested:** Validation scripts included
- ✅ **Documented:** Clear usage instructions