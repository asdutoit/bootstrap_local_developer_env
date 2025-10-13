# Minikube CentOS/RHEL/Fedora Fixes

## Overview

The bootstrap scripts have been updated to automatically fix Minikube compatibility issues on CentOS, RHEL, and Fedora systems. These fixes ensure that Minikube works out-of-the-box with rootless Podman.

## Issues Addressed

### 1. cgroup v2 CPU Controller Delegation
**Problem**: Rootless Podman containers (including Minikube) require the CPU controller to be delegated to user services, but this isn't configured by default on CentOS/RHEL/Fedora.

**Error**: `ERROR: UserNS: cpu controller needs to be delegated`

**Solution**: Automatically configure systemd user service delegation by:
- Creating `/etc/systemd/system/user@.service.d/delegate.conf`
- Enabling delegation for: `cpu cpuset io memory pids`
- Reloading systemd and restarting the user service

### 2. Minikube Configuration for Rootless Podman
**Problem**: Minikube defaults to requiring sudo/root access for Podman, but we want rootless operation.

**Solution**: Automatically configure Minikube with:
- `minikube config set rootless true`
- `minikube config set driver podman`

## Changes Made

### Bootstrap Script (`bootstrap-dev-env.sh`)

Added two new functions:

#### `configure_kubernetes_centos()`
- Checks and configures cgroup v2 delegation
- Configures Minikube for rootless Podman
- Calls `install_kubernetes_tools()`

#### `install_kubernetes_tools()`
- Downloads and installs kubectl and Minikube if not present
- Uses latest stable versions with proper architecture detection
- Configures Minikube after installation

#### Integration
- Called automatically for CentOS/RHEL/Fedora after container runtime installation
- Detects distribution using existing `$DISTRO` variable pattern matching

### Ansible Playbook (`setup.yml`)

Added new task block: **"Configure Kubernetes for CentOS/RHEL/Fedora"**

Tasks include:
- Check current cgroup controller delegation status
- Create systemd drop-in directory if needed
- Configure delegation file
- Reload systemd daemon
- Restart user service
- Verify delegation worked
- Configure Minikube settings
- Display usage instructions

## Usage

### Automatic (Recommended)
The fixes are applied automatically when running:
```bash
./bootstrap-dev-env.sh
```

On CentOS/RHEL/Fedora systems, the script will:
1. Install Podman and container tools
2. Configure cgroup delegation
3. Install and configure kubectl/Minikube
4. Set up Minikube for rootless operation

### Manual Verification
After the script runs, verify the setup:

```bash
# Check cgroup delegation
cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/cgroup.controllers

# Should include 'cpu' in the output

# Check Minikube configuration
minikube config get rootless  # Should return 'true'
minikube config get driver    # Should return 'podman'

# Start Kubernetes cluster
minikube start

# Verify cluster
minikube status
kubectl get nodes
```

## Compatibility

### Tested On
- CentOS Stream 9 (ARM64)
- Fedora (ARM64)

### Should Work On
- RHEL 8+
- CentOS Stream 8+
- Fedora 35+
- Any systemd-based distribution using cgroup v2

### Architecture Support
- x86_64 (amd64)
- aarch64 (arm64)
- armv7l (arm)

## Troubleshooting

### CPU Delegation Still Not Working
If CPU delegation doesn't work immediately:
1. Reboot the system: `sudo reboot`
2. Verify after reboot: Check the cgroup controllers again
3. If still failing, check systemd logs: `journalctl -u "user@$(id -u).service"`

### Minikube Still Asking for Sudo
1. Check configuration: `minikube config list`
2. Reset if needed: `minikube delete --all && minikube start`
3. Verify Podman works rootlessly: `podman ps`

### Volume Conflicts
If you see volume already exists errors:
```bash
minikube delete --all
podman volume rm minikube
minikube start
```

## Technical Details

### Why These Fixes Are Needed

1. **cgroup v2**: Modern distributions use cgroup v2 by default, but don't delegate the CPU controller to user services
2. **Rootless Containers**: For security, we want containers to run without root privileges
3. **Minikube Assumptions**: Minikube assumes either root access or proper cgroup delegation

### Security Benefits
- No sudo required for container operations
- Containers run in user namespace
- Better isolation and security posture
- Follows container security best practices

## References

- [Podman rootless documentation](https://docs.podman.io/en/latest/markdown/podman.1.html#rootless-mode)
- [systemd resource control](https://systemd.io/CGROUP_DELEGATION/)
- [Minikube drivers](https://minikube.sigs.k8s.io/docs/drivers/)