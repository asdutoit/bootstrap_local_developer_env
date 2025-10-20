# CentOS Stream 9 Bootstrap - Installed Tools

Complete list of tools installed by `bootstrap-dev-env-centos.sh` and `setup-centos.yml`

## ✅ Verified Installations

### Core System Tools
- **Python 3** - Programming language and pip package manager
- **curl** - Data transfer tool
- **git** - Version control system
- **GitHub CLI (gh)** - GitHub command-line interface

### Container Runtime
- **Podman** - Docker-compatible container runtime (rootless, daemonless)
- **podman-docker** - Docker CLI compatibility layer
- **podman-compose** - Docker Compose compatibility
- **Podman Desktop** - GUI for Podman (via Flatpak, desktop environments only)

### Kubernetes Tools
- **k3s** - Lightweight production Kubernetes (PRIMARY, auto-starts on boot)
- **kubectl** - Kubernetes command-line tool
- **k9s** - Terminal UI for Kubernetes management ⭐ NEW
- **Minikube** - Local Kubernetes (OPTIONAL, may have issues on CentOS VMs)

### GitOps & Workflow Tools
- **Argo CD CLI (argocd)** - GitOps continuous delivery
- **Argo Workflows CLI (argo)** - Container-native workflow engine

### Shell & Prompt
- **zsh** - Z shell (set as default shell) ✅ VERIFIED
- **Oh My Zsh** - Zsh framework with themes and plugins
- **Starship** - Cross-shell prompt with customization ✅ VERIFIED

### Fonts
- **FiraCode Nerd Font** - Monospace font with ligatures and icons

### Editor
- **VS Code** - Code editor (with FiraCode font configured)

## 🎯 Kubernetes Tool Comparison

| Tool | Purpose | When to Use |
|------|---------|-------------|
| **k3s** | Production Kubernetes | Default, reliable, auto-starts |
| **kubectl** | K8s CLI | Managing any K8s cluster |
| **k9s** | K8s TUI | Visual cluster management, monitoring |
| **Minikube** | Dev K8s | Testing VM-based scenarios (may struggle on CentOS) |

## 📊 k9s Features

k9s is a terminal-based UI for Kubernetes that provides:

- **Real-time monitoring** - Live cluster state updates
- **Easy navigation** - Arrow keys + Enter to drill into resources
- **Resource management** - View, edit, delete pods/deployments/services
- **Log viewing** - Stream logs from any container
- **Shell access** - Exec into running pods
- **Port forwarding** - Quick port-forward setup
- **Resource metrics** - CPU/Memory usage visualization
- **Search** - Quick filtering with `/`
- **Help** - Press `?` for command reference

### k9s Quick Commands
```bash
# Launch k9s
k9s

# k9s keyboard shortcuts (inside k9s):
# :pods       - View pods
# :svc        - View services
# :deploy     - View deployments
# /           - Search/filter
# d           - Describe resource
# l           - View logs
# s           - Shell into pod
# Ctrl+d      - Delete resource
# ?           - Help
# :quit       - Exit
```

## 🚀 Quick Start After Installation

### 1. Verify zsh (must log out/in first)
```bash
echo $0          # Should show: zsh or -zsh
echo $SHELL      # Should show: /usr/bin/zsh
```

### 2. Verify Starship
```bash
starship --version
# Prompt should have custom styling
```

### 3. Test k3s Cluster
```bash
kubectl get nodes
kubectl get pods -A
```

### 4. Launch k9s
```bash
k9s
# Navigate with arrow keys
# Press ? for help
# Press :quit to exit
```

### 5. Deploy Test App
```bash
kubectl create deployment nginx --image=nginx
kubectl get deployments
kubectl get pods

# View in k9s
k9s
# Type: :deploy (Enter)
# Arrow down to nginx
# Press Enter to see pods
```

### 6. Test Podman
```bash
podman run hello-world
docker run hello-world  # Same thing (aliased)
```

### 7. Test Argo CLIs
```bash
argocd version
argo version
```

## 🔧 Troubleshooting

### zsh Not Active After Script
**Issue:** `echo $0` shows `bash` instead of `zsh`

**Solution:**
```bash
# Run diagnostic script
./verify-zsh.sh

# Or manually verify and fix
getent passwd $USER | cut -d: -f7  # Check shell
sudo chsh -s $(which zsh) $USER    # Change shell
exit                                # Log out
# Then log back in
```

### k3s Cluster Not Ready
```bash
# Check k3s service
sudo systemctl status k3s

# Restart k3s
sudo systemctl restart k3s

# View logs
sudo journalctl -u k3s -f
```

### k9s Can't Connect to Cluster
```bash
# Verify kubeconfig
ls -la ~/.kube/config

# Test kubectl first
kubectl get nodes

# If kubectl works but k9s doesn't, try:
k9s --kubeconfig ~/.kube/config
```

## 📝 Additional Tools (Installed by Ansible)

The `setup-centos.yml` playbook also installs:

### Languages
- Node.js and npm
- Go (golang)
- Rust and Cargo

### Modern CLI Tools
- **fzf** - Fuzzy finder
- **ripgrep (rg)** - Fast grep alternative
- **bat** - Cat with syntax highlighting
- **eza** - Modern ls replacement
- **ncdu** - Disk usage analyzer

### Databases
- SQLite
- Redis (from EPEL)

### Cloud Tools
- Azure CLI
- Terraform

### VCS Tools
- git-lfs
- meld (diff viewer)

## 🎓 Learning Resources

### k9s
- Documentation: https://k9scli.io/
- GitHub: https://github.com/derailed/k9s
- Video tutorial: Search "k9s kubernetes" on YouTube

### k3s
- Documentation: https://docs.k3s.io/
- Quick start: https://docs.k3s.io/quick-start

### Argo CD
- Getting started: https://argo-cd.readthedocs.io/
- Examples: https://github.com/argoproj/argocd-example-apps

### Argo Workflows
- Documentation: https://argoproj.github.io/argo-workflows/
- Examples: https://github.com/argoproj/argo-workflows/tree/master/examples

## 🎉 Success Indicators

After a successful bootstrap, you should be able to run:

```bash
# All should return version info or success
echo $0                    # zsh or -zsh
starship --version         # ✅
k3s --version             # ✅
kubectl get nodes          # Shows master node
k9s version               # ✅
podman --version          # ✅
argocd version            # ✅
argo version              # ✅
gh --version              # ✅
code --version            # ✅
```

---

**Pro Tip:** Use `k9s` as your primary Kubernetes management tool. It's much faster and more intuitive than running multiple `kubectl` commands! 🚀
