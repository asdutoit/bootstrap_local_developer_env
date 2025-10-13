# Development Environment Bootstrap Script - Windows 11
# Supports: Windows 10/11 (x64, ARM64)
# Installs: Python, Curl, Ansible via Chocolatey
# Author: Development Team

param(
    [string]$AnsibleScript = "",
    [switch]$SkipAnsible = $false,
    [switch]$UseScoop = $false,
    [switch]$Help = $false
)

# Requires PowerShell 5.1+ and Administrator privileges for some operations
#Requires -Version 5.1

# Colors for output
$Colors = @{
    Red = [ConsoleColor]::Red
    Green = [ConsoleColor]::Green
    Yellow = [ConsoleColor]::Yellow
    Blue = [ConsoleColor]::Blue
    White = [ConsoleColor]::White
}

# Logging functions
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Colors.Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor $Colors.Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor $Colors.Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor $Colors.Red
}

# Error handling
function Exit-WithError {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

# Detect Windows version and architecture
function Get-SystemInfo {
    Write-Log "Detecting Windows version and architecture..."
    
    $osInfo = Get-WmiObject -Class Win32_OperatingSystem
    $procInfo = Get-WmiObject -Class Win32_Processor
    
    $global:OSVersion = $osInfo.Caption
    $global:OSBuild = $osInfo.BuildNumber
    $global:Architecture = $procInfo.AddressWidth
    $global:ProcessorArch = $env:PROCESSOR_ARCHITECTURE
    
    # Map architecture for downloads
    switch ($global:ProcessorArch) {
        "AMD64" { $global:DownloadArch = "amd64" }
        "ARM64" { $global:DownloadArch = "arm64" }
        "x86" { $global:DownloadArch = "386" }
        default { 
            Write-Warning "Unknown architecture: $global:ProcessorArch, defaulting to amd64"
            $global:DownloadArch = "amd64" 
        }
    }
    
    Write-Log "Detected OS: $global:OSVersion, Build: $global:OSBuild, Architecture: $global:ProcessorArch ($global:DownloadArch)"
    
    # Check if Windows 10/11
    if ($global:OSBuild -lt 19041) {
        Write-Warning "Windows 10 version 2004+ or Windows 11 recommended for best compatibility"
    }
}

# Check if running as Administrator
function Test-AdminPrivileges {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Test if command exists
function Test-CommandExists {
    param([string]$Command)
    try {
        Get-Command $Command -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

# Disable Windows Store Python aliases that interfere with real Python
function Disable-WindowsStorePythonAliases {
    Write-Log "Checking for Windows Store Python aliases..."
    
    try {
        # Check if python command points to Windows Store
        $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
        if ($pythonCmd -and $pythonCmd.Source -like "*WindowsApps*") {
            Write-Warning "Windows Store Python alias detected, attempting to disable..."
            
            # Try to disable app execution aliases via registry (requires admin)
            $registryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            if (Test-Path $registryPath) {
                Set-ItemProperty -Path $registryPath -Name "EnableXamlIslandViewers" -Value 0 -ErrorAction SilentlyContinue
            }
            
            Write-Warning "Please manually disable Python aliases:"
            Write-Log "1. Open Settings > Apps > Advanced app settings > App execution aliases"
            Write-Log "2. Turn OFF 'python.exe' and 'python3.exe' aliases"
            Write-Log "3. Restart PowerShell after making changes"
        }
    }
    catch {
        Write-Log "Could not check for Windows Store aliases"
    }
}

# Find actual Python installation, avoiding Windows Store aliases
function Find-RealPython {
    $pythonPaths = @(
        "py",  # Python Launcher is usually reliable
        "python3",
        "python"
    )
    
    # Also check common installation paths directly
    $directPaths = @(
        "$env:LOCALAPPDATA\Programs\Python\Python*\python.exe",
        "$env:ProgramFiles\Python*\python.exe", 
        "$env:ProgramFiles(x86)\Python*\python.exe"
    )
    
    foreach ($path in $directPaths) {
        $expanded = Get-ChildItem $path -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
        if ($expanded) {
            $pythonPaths = @($expanded.FullName) + $pythonPaths
        }
    }
    
    foreach ($pythonPath in $pythonPaths) {
        try {
            $version = & $pythonPath --version 2>$null
            if ($version -match "Python 3") {
                # Double-check it's not a Windows Store alias by testing actual functionality
                $testResult = & $pythonPath -c "print('test')" 2>$null
                if ($testResult -eq "test") {
                    return @{
                        Path = $pythonPath
                        Version = $version.Trim()
                        Works = $true
                    }
                }
            }
        }
        catch {
            continue
        }
    }
    
    return $null
}

# Validate system compatibility
function Test-SystemCompatibility {
    Write-Log "Validating system compatibility..."
    
    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Exit-WithError "PowerShell 5.1 or later is required. Current version: $($PSVersionTable.PSVersion)"
    }
    
    # Check Windows version
    if ($global:OSBuild -lt 17763) {
        Exit-WithError "Windows 10 version 1809 or later is required for full compatibility"
    }
    
    # Check for WSL2 availability (optional)
    $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
    if ($wslFeature -and $wslFeature.State -eq "Enabled") {
        Write-Log "WSL detected - containers can use WSL2 backend"
    }
    
    # Check execution policy
    $executionPolicy = Get-ExecutionPolicy
    if ($executionPolicy -eq "Restricted") {
        Write-Warning "PowerShell execution policy is Restricted. You may need to run: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
    }
    
    Write-Success "System validation completed"
}

# Install Chocolatey package manager
function Install-Chocolatey {
    if (Test-CommandExists "choco") {
        Write-Success "Chocolatey is already installed"
        return
    }
    
    Write-Log "Installing Chocolatey package manager..."
    
    # Check if we need admin privileges
    if (-not (Test-AdminPrivileges)) {
        Write-Warning "Chocolatey installation typically requires Administrator privileges"
        Write-Log "Attempting user-level installation..."
    }
    
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        Write-Success "Chocolatey installed successfully"
    }
    catch {
        Exit-WithError "Failed to install Chocolatey: $($_.Exception.Message)"
    }
}

# Install Scoop package manager (alternative)
function Install-Scoop {
    if (Test-CommandExists "scoop") {
        Write-Success "Scoop is already installed"
        return
    }
    
    Write-Log "Installing Scoop package manager..."
    
    try {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Invoke-RestMethod get.scoop.sh | Invoke-Expression
        
        # Add extras bucket for more packages
        scoop bucket add extras
        scoop bucket add versions
        
        Write-Success "Scoop installed successfully"
    }
    catch {
        Exit-WithError "Failed to install Scoop: $($_.Exception.Message)"
    }
}

# Install curl
function Install-Curl {
    if (Test-CommandExists "curl") {
        Write-Success "curl is already installed"
        return
    }
    
    Write-Log "Installing curl..."
    
    try {
        if ($UseScoop -and (Test-CommandExists "scoop")) {
            scoop install curl
        } elseif (Test-CommandExists "choco") {
            choco install curl -y
        } else {
            # Fallback: curl is built into Windows 10 1803+
            if ($global:OSBuild -ge 17134) {
                Write-Success "curl is built into Windows 10/11"
                return
            } else {
                Exit-WithError "No package manager available and curl not built into this Windows version"
            }
        }
        
        Write-Success "curl installed successfully"
    }
    catch {
        Exit-WithError "Failed to install curl: $($_.Exception.Message)"
    }
}

# Install Python
function Install-Python {
    Write-Log "Checking for Python installation..."
    
    # First, try to find a real Python installation
    $pythonInfo = Find-RealPython
    
    if ($pythonInfo) {
        Write-Success "Python 3 is already installed: $($pythonInfo.Version)"
        $global:PythonCmd = $pythonInfo.Path
        return
    }
    
    # Check for Windows Store aliases and warn user
    Disable-WindowsStorePythonAliases
    
    Write-Log "Installing Python 3..."
    
    try {
        if ($UseScoop -and (Test-CommandExists "scoop")) {
            scoop install python
        } elseif (Test-CommandExists "choco") {
            choco install python -y
        } else {
            # Fallback: Download from python.org
            Write-Log "Downloading Python installer from python.org..."
            $pythonUrl = "https://www.python.org/ftp/python/3.13.1/python-3.13.1-amd64.exe"  # Updated Jan 2025
            if ($global:DownloadArch -eq "arm64") {
                # Note: ARM64 Python availability may be limited
                Write-Warning "ARM64 Python installer may not be available, falling back to x64"
            }
            
            $installer = "$env:TEMP\python-installer.exe"
            Invoke-WebRequest -Uri $pythonUrl -OutFile $installer
            
            Write-Log "Running Python installer..."
            Start-Process -FilePath $installer -ArgumentList "/quiet", "InstallAllUsers=0", "PrependPath=1", "Include_test=0" -Wait
            
            Remove-Item $installer -Force
        }
        
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        # Verify installation
        if (Test-CommandExists "python") {
            $global:PythonCmd = "python"
        } elseif (Test-CommandExists "python3") {
            $global:PythonCmd = "python3"
        } else {
            Exit-WithError "Python installation verification failed"
        }
        
        Write-Success "Python 3 installed successfully"
    }
    catch {
        Exit-WithError "Failed to install Python: $($_.Exception.Message)"
    }
}

# Install pip (usually comes with Python)
function Install-Pip {
    # Test if pip works with our Python command
    if ($global:PythonCmd) {
        try {
            & $global:PythonCmd -m pip --version 2>$null
            Write-Success "pip is already installed"
            return
        }
        catch {
            Write-Log "pip not found, installing..."
        }
    }
    
    Write-Log "Installing pip..."
    
    try {
        if ($global:PythonCmd) {
            & $global:PythonCmd -m ensurepip --upgrade
            & $global:PythonCmd -m pip install --upgrade pip
        } else {
            # Fallback to py launcher
            py -m ensurepip --upgrade
            py -m pip install --upgrade pip
        }
        
        Write-Success "pip installed successfully"
    }
    catch {
        Write-Warning "pip installation may have failed: $($_.Exception.Message)"
        Write-Log "You may need to install pip manually after resolving Python path issues"
    }
}

# Install Ansible
function Install-Ansible {
    if (Test-CommandExists "ansible") {
        Write-Success "Ansible is already installed"
        return
    }
    
    Write-Log "Installing Ansible..."
    
    try {
        # Install Ansible via pip
        if ($global:PythonCmd) {
            & $global:PythonCmd -m pip install --user ansible
            
            # Add Python Scripts to PATH if not already there
            try {
                # Get both user scripts paths
                $userScriptsPath1 = & $global:PythonCmd -c "import site; print(site.USER_BASE + '\\Scripts')" 2>$null
                $userScriptsPath2 = & $global:PythonCmd -c "import sysconfig; print(sysconfig.get_path('scripts'))" 2>$null
                
                $pathsToAdd = @($userScriptsPath1, $userScriptsPath2) | Where-Object { $_ -and (Test-Path $_) }
                
                foreach ($pathToAdd in $pathsToAdd) {
                    if ($env:Path -notlike "*$pathToAdd*") {
                        Write-Log "Adding $pathToAdd to PATH"
                        $env:Path += ";$pathToAdd"
                        [Environment]::SetEnvironmentVariable("Path", $env:Path, [EnvironmentVariableTarget]::User)
                    }
                }
                
                # Also try the specific path from the warning message
                $roamingPythonScripts = "$env:APPDATA\Python\Python*\Scripts"
                $expandedPath = Get-ChildItem $roamingPythonScripts -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($expandedPath -and $env:Path -notlike "*$($expandedPath.FullName)*") {
                    Write-Log "Adding $($expandedPath.FullName) to PATH"
                    $env:Path += ";$($expandedPath.FullName)"
                    [Environment]::SetEnvironmentVariable("Path", $env:Path, [EnvironmentVariableTarget]::User)
                }
            }
            catch {
                Write-Warning "Could not determine Python scripts path"
            }
        } else {
            # Fallback to py launcher
            py -m pip install --user ansible
        }
        
        Write-Success "Ansible installed successfully"
    }
    catch {
        Write-Warning "Ansible installation may have failed: $($_.Exception.Message)"
        Write-Log "You may need to install Ansible manually after resolving Python path issues"
    }
}

# Verify installations
function Test-Installations {
    Write-Log "Verifying installations..."
    
    $allGood = $true
    
    # Test curl (built into Windows 10/11)
    if (Test-CommandExists "curl") {
        try {
            $curlVersion = curl --version 2>&1 | Select-Object -First 1
            Write-Success "curl: $curlVersion"
        }
        catch {
            Write-Error "curl verification failed"
            $allGood = $false
        }
    } elseif ($global:OSBuild -ge 17134) {
        # curl should be built into Windows 10 1803+
        try {
            $curlVersion = & "$env:SystemRoot\System32\curl.exe" --version 2>&1 | Select-Object -First 1
            Write-Success "curl: $curlVersion (built-in)"
        }
        catch {
            Write-Warning "curl not found - may need to be installed via package manager"
            $allGood = $false
        }
    } else {
        Write-Error "curl verification failed - command not found"
        $allGood = $false
    }
    
    # Test Python
    if ($global:PythonCmd -and (Test-Path $global:PythonCmd -ErrorAction SilentlyContinue)) {
        try {
            $pythonVersion = & $global:PythonCmd --version 2>$null
            Write-Success "Python: $pythonVersion"
        }
        catch {
            Write-Error "Python verification failed"
            $allGood = $false
        }
    } elseif (Test-CommandExists "py") {
        try {
            $pythonVersion = py --version 2>$null
            Write-Success "Python: $pythonVersion (via py launcher)"
        }
        catch {
            Write-Error "Python verification failed"
            $allGood = $false
        }
    } else {
        Write-Error "Python verification failed - command not found"
        $allGood = $false
    }
    
    # Test pip
    if (Test-CommandExists "pip") {
        try {
            $pipVersion = pip --version
            Write-Success "pip: $pipVersion"
        }
        catch {
            Write-Error "pip verification failed"
            $allGood = $false
        }
    } else {
        Write-Error "pip verification failed - command not found"
        $allGood = $false
    }
    
    # Test Ansible (may need PATH refresh)
    $ansibleFound = $false
    
    if (Test-CommandExists "ansible") {
        try {
            $ansibleVersion = ansible --version | Select-Object -First 1
            Write-Success "Ansible: $ansibleVersion"
            $ansibleFound = $true
        }
        catch {
            Write-Error "Ansible command failed"
        }
    }
    
    # Try to find Ansible in Python scripts directories if not found
    if (-not $ansibleFound) {
        $ansiblePaths = @(
            "$env:APPDATA\Python\Python*\Scripts\ansible.exe",
            "$env:LOCALAPPDATA\Programs\Python\Python*\Scripts\ansible.exe",
            "$env:ProgramFiles\Python*\Scripts\ansible.exe"
        )
        
        foreach ($pathPattern in $ansiblePaths) {
            $expandedPaths = Get-ChildItem $pathPattern -ErrorAction SilentlyContinue
            if ($expandedPaths) {
                $ansiblePath = $expandedPaths | Select-Object -First 1
                try {
                    $ansibleVersion = & $ansiblePath.FullName --version | Select-Object -First 1
                    Write-Success "Ansible: $ansibleVersion (found at $($ansiblePath.FullName))"
                    Write-Warning "Ansible is installed but not in PATH. Restart PowerShell to use 'ansible' command directly."
                    $ansibleFound = $true
                    break
                }
                catch {
                    continue
                }
            }
        }
    }
    
    if (-not $ansibleFound) {
        Write-Error "Ansible verification failed - command not found"
        $allGood = $false
    }
    
    if ($allGood) {
        Write-Success "All tools verified successfully!"
    } else {
        Exit-WithError "Some tools failed verification"
    }
}

# Run Ansible automation
function Invoke-AnsibleAutomation {
    param([string]$AnsibleScript = "")
    
    if ([string]::IsNullOrEmpty($AnsibleScript)) {
        $AnsibleScript = ".\setup-windows.yml"
    }
    
    if (Test-Path $AnsibleScript) {
        Write-Log "Running Windows development environment setup: $AnsibleScript"
        Write-Log "This will install packages appropriate for Windows 11"
        Write-Warning "You may be prompted for Administrator privileges for system-level installations"
        
        try {
            ansible-playbook $AnsibleScript
            Write-Success "Ansible automation completed"
        }
        catch {
            Write-Warning "Ansible automation failed or completed with warnings: $($_.Exception.Message)"
        }
    } else {
        Write-Warning "Ansible automation script not found: $AnsibleScript"
        Write-Log "You can run the setup manually once it's available:"
        Write-Log "  ansible-playbook setup-windows.yml"
    }
}

# Show help
function Show-Help {
    @"
Windows 11 Development Environment Bootstrap

Usage: .\bootstrap-dev-env.ps1 [OPTIONS]

Options:
  -AnsibleScript PATH   Path to custom Ansible playbook (default: setup-windows.yml)
  -SkipAnsible         Skip running Ansible automation
  -UseScoop           Use Scoop package manager instead of Chocolatey
  -Help               Show this help message

The script automatically detects your Windows version and installs:
  - Package manager (Chocolatey or Scoop)
  - Python 3, curl, Ansible
  - Runs Windows-specific Ansible playbook for complete environment setup

Examples:
  .\bootstrap-dev-env.ps1                           # Full setup with Chocolatey
  .\bootstrap-dev-env.ps1 -UseScoop                # Full setup with Scoop
  .\bootstrap-dev-env.ps1 -SkipAnsible             # Only install Python/curl/Ansible
  .\bootstrap-dev-env.ps1 -AnsibleScript custom.yml # Use custom playbook

Requirements:
  - Windows 10 version 1809+ or Windows 11
  - PowerShell 5.1 or later
  - Internet connection
  - Administrator privileges for some operations
"@
}

# Main function
function Main {
    if ($Help) {
        Show-Help
        exit 0
    }
    
    # Check if running on non-Windows system
    if ($IsMacOS -or $IsLinux -or (Test-Path "/etc/os-release") -or (Test-CommandExists "sw_vers")) {
        Write-Warning "Non-Windows system detected!"
        Write-Log "This PowerShell script is designed for Windows 11."
        Write-Log "For macOS/Linux, please use the bash version instead:"
        Write-Log "  ./bootstrap-dev-env.sh"
        Write-Log ""
        Write-Log "macOS/Linux bash script features:"
        Write-Log "  - Native package managers (Homebrew/apt/dnf)"
        Write-Log "  - Unix-specific tool installation"
        Write-Log "  - Podman on Linux, Docker Desktop on macOS"
        Write-Log "  - Shell profile configuration"
        Write-Log ""
        Write-Log "If you prefer to continue with PowerShell on this system, press Enter."
        Write-Log "Otherwise, exit and use bootstrap-dev-env.sh"
        $response = Read-Host "Continue with PowerShell version? [y/N]"
        if ($response -notmatch '^[Yy]') {
            Write-Log "Please use the bash script: ./bootstrap-dev-env.sh"
            exit 0
        }
        Write-Log "Continuing with PowerShell version (limited non-Windows support)..."
    }
    
    Write-Log "Starting Windows 11 development environment bootstrap..."
    
    # Detect system information
    Get-SystemInfo
    
    # Validate system compatibility
    Test-SystemCompatibility
    
    # Install package manager
    if ($UseScoop) {
        Install-Scoop
    } else {
        Install-Chocolatey
    }
    
    # Install core tools
    Install-Curl
    Install-Python
    Install-Pip
    Install-Ansible
    
    # Verify installations
    Test-Installations
    
    # Run Ansible automation if not skipped
    if (-not $SkipAnsible) {
        Invoke-AnsibleAutomation -AnsibleScript $AnsibleScript
    }
    
    Write-Success "Windows 11 development environment bootstrap completed!"
    Write-Log "You can now use ansible, python, and curl for further automation."
    Write-Log "For complete environment info, check the generated setup documentation."
}

# Run main function
try {
    Main
}
catch {
    Exit-WithError "Bootstrap failed: $($_.Exception.Message)"
}