#!/bin/bash

# === Configuration ===
REPO_URL="https://github.com/dismaster/refurbminer"
INSTALL_DIR="$HOME/refurbminer"
LOG_FILE="$HOME/refurbminer_install.log"

# === Color definitions ===
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ANSI color codes for banner formatting
R='\033[0;31m'   # Red
G='\033[1;32m'   # Light Green
Y='\033[1;33m'   # Yellow
LY='\033[1;33m'  # Light Yellow (same as Y)
LC='\033[1;36m'  # Light Cyan
LG='\033[1;32m'  # Light Green
LB='\033[1;34m'  # Light Blue
P='\033[0;35m'   # Purple
LP='\033[1;35m'  # Light Purple

# === Helper Functions ===
# Logging function that writes to log file and optionally displays to user
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Display function for user-facing messages
display() {
    echo -e "${BLUE}$1${NC}"
    log "$1"
}

# Display steps with numbering
step() {
    echo -e "\n${GREEN}[$1/${TOTAL_STEPS}] $2${NC}"
    log "STEP $1/$TOTAL_STEPS: $2"
}

# Display success messages
success() {
    echo -e "${GREEN}✓ $1${NC}"
    log "SUCCESS: $1"
}

# Display warning messages
warn() {
    echo -e "${YELLOW}⚠️ $1${NC}"
    log "WARNING: $1"
}

# Display error messages
error() {
    echo -e "${RED}❌ $1${NC}"
    log "ERROR: $1"
}

# Run commands silently and log them
run_silent() {
    log "Running command: $*"
    if ! "$@" >> "$LOG_FILE" 2>&1; then
        return 1
    fi
    return 0
}

# Define total number of steps
TOTAL_STEPS=6

# Create log file
touch "$LOG_FILE"
log "Starting installation at $(date)"

# Add a function to display the banner and clear the screen at each step
display_banner() {
    clear
    echo -e "${LC} ___             __         __ __${NC}"
    echo -e "${LC}|   .-----.-----|  |_.---.-|  |  .-----.----.${NC}"
    echo -e "${LC}|.  |     |__ --|   _|  _  |  |  |  -__|   _|${NC}"
    echo -e "${LC}|.  |__|__|_____|____|___._|__|__|_____|__|${NC}  "
    echo -e "${LC}|:  | Developer ~ ${LP}@Ch3ckr${NC}"
    echo -e "${LC}|::.| Tool      ~ ${LG}RefurbMiner Installer${NC}"
    echo -e "${LC}'---' For More  ~ ${LY}https://gui.refurbminer.de${NC}"
    echo  # New line for spacing
    
    # If a step title is provided, display it
    if [ -n "$1" ]; then
        echo -e "\n${GREEN}[$2/${TOTAL_STEPS}] $1${NC}"
        echo -e "${R}->${NC} ${LC}$3${NC}"
        echo  # New line for spacing
    else
        echo -e "${R}->${NC} ${LC}This process may take a while...${NC}"
        echo  # New line for spacing
    fi
}

# Modify the step function to use the banner
step() {
    # Log the step
    log "STEP $1/$TOTAL_STEPS: $2"
    
    # Display the banner with step information
    display_banner "$2" "$1" "Processing..."
}

display_banner

# Check for running instances and stop them if needed
display "Checking for running instances..."
if screen -ls | grep -q "refurbminer"; then
    display "Found running RefurbMiner instance. Stopping it before continuing..."
    run_silent screen -S refurbminer -X quit || true
    sleep 2 # Give it time to shut down properly
    if screen -ls | grep -q "refurbminer"; then
        warn "Failed to stop RefurbMiner instance automatically."
        echo -ne "${YELLOW}Do you want to proceed with installation anyway? (y/n): ${NC}"
        read -r PROCEED
        if [[ ! "$PROCEED" =~ ^[Yy]$ ]]; then
            error "Installation aborted by user."
            exit 1
        fi
    else
        success "Successfully stopped running RefurbMiner instance."
    fi
fi

# Check for other mining sessions that might conflict
if screen -ls | grep -q "miner"; then
    warn "Found other mining sessions that might conflict:"
    screen -ls | grep "miner" | sed 's/^\s*/  /'
    echo -ne "${YELLOW}Do you want to stop these sessions before continuing? (y/n): ${NC}"
    read -r STOP_OTHERS
    if [[ "$STOP_OTHERS" =~ ^[Yy]$ ]]; then
        for SESSION in $(screen -ls | grep "miner" | awk '{print $1}' | cut -d. -f1); do
            display "Stopping session: $SESSION"
            run_silent screen -S "$SESSION" -X quit || true
        done
        success "Attempted to stop all mining sessions."
    else
        display "Continuing with installation without stopping other mining sessions."
    fi
fi

# === Step 1: Check CPU Compatibility ===
step 1 "Checking CPU compatibility"

check_cpu_compatibility() {
    # Check if lscpu is available
    if ! command -v lscpu &>/dev/null; then
        display "Installing required utilities..."
        
        # Try to install lscpu based on detected package manager
        if command -v apt-get &>/dev/null; then
            run_silent sudo apt-get update
            run_silent sudo apt-get install -y util-linux
        elif command -v dnf &>/dev/null; then
            run_silent sudo dnf install -y util-linux
        elif command -v pkg &>/dev/null; then
            run_silent pkg install -y util-linux
        else
            error "Cannot install required utilities. Please install 'util-linux' manually."
            return 1
        fi
    fi
    
    # Get CPU information
    CPU_INFO=$(lscpu 2>/dev/null)
    if [ -z "$CPU_INFO" ]; then
        error "Failed to retrieve CPU information."
        return 1
    fi
    
    # Check for 64-bit support
    if ! echo "$CPU_INFO" | grep -q "64-bit"; then
        error "Your CPU does not support 64-bit operations which is required for mining."
        return 1
    fi
    
    # Get CPU flags - try different approaches to be comprehensive
    CPU_FLAGS=""
    
    # Method 1: Try lscpu output directly for flags
    if echo "$CPU_INFO" | grep -q "Flags:"; then
        CPU_FLAGS=$(echo "$CPU_INFO" | grep "Flags:" | sed 's/Flags://g' | xargs)
        log "Found flags in lscpu output"
    # Method 2: Try lscpu -J for JSON output
    elif lscpu -J 2>/dev/null | grep -q "flags"; then
        CPU_FLAGS=$(lscpu -J 2>/dev/null | grep "flags" | sed 's/.*"data"://g' | tr -d '",')
        log "Found flags in lscpu -J output"
    # Method 3: Check /proc/cpuinfo
    elif grep -q "flags" /proc/cpuinfo 2>/dev/null; then
        CPU_FLAGS=$(grep "flags" /proc/cpuinfo | head -1 | sed 's/.*: //g')
        log "Found flags in /proc/cpuinfo"
    # Method 4: Check Features in ARM cpuinfo
    elif grep -q "Features" /proc/cpuinfo 2>/dev/null; then
        CPU_FLAGS=$(grep "Features" /proc/cpuinfo | head -1 | sed 's/.*: //g')
        log "Found features in /proc/cpuinfo (ARM format)"
    fi
    
    log "CPU flags: $CPU_FLAGS"
    
    # Check for essential CPU features (aes and pmull)
    if ! echo "$CPU_FLAGS" | grep -qi "aes"; then
        error "Your CPU does not support the AES instruction set which is required for mining."
        return 1
    fi
    
    if ! echo "$CPU_FLAGS" | grep -qi "pmull"; then
        # For x86_64 architectures, pmull might be called pclmul or pclmulqdq
        if ! echo "$CPU_FLAGS" | grep -qi "pclmul"; then
            error "Your CPU does not support the PMULL/PCLMUL instruction set which is required for mining."
            return 1
        fi
    fi
    
    success "CPU compatibility verified successfully"
    return 0
}

if ! check_cpu_compatibility; then
    error "Installation aborted: Your CPU is not compatible with mining operations."
    error "Required features: 64-bit support, AES and PMULL/PCLMUL instructions."
    echo -e "\nCheck $LOG_FILE for details."
    exit 1
fi

success "CPU compatibility check passed. Your CPU supports all required features."

# === Step 2: Detect Operating System and Install Packages ===
step 2 "Installing system dependencies"

# Handle Termux-specific setup with enhanced checks
termux_setup() {
    display "Setting up Termux environment..."
    
    # Check for root access
    HAS_ROOT=false
    if command -v su &>/dev/null; then
        if su -c "id -u" 2>/dev/null | grep -q "^0$"; then
            HAS_ROOT=true
            success "Root access detected (device is rooted)"
            log "Device has root access"
        fi
    fi
    
    if [ "$HAS_ROOT" = false ]; then
        warn "Root access not detected. Mining performance may be limited."
        log "Device does not have root access"
        display "For optimal performance, consider rooting your device."
    fi
    
    # Check for ADB connectivity
    HAS_ADB=false
    if command -v adb &>/dev/null; then
        if adb devices 2>/dev/null | grep -q "device$"; then
            HAS_ADB=true
            success "ADB connection detected"
            log "ADB connection is available"
        fi
    fi
    
    if [ "$HAS_ADB" = false ]; then
        warn "ADB connection not detected. Some features may be limited."
        log "ADB connection is not available"
        display "To enable ADB, install Android Debug Bridge and enable USB debugging in developer options."
    fi
    
    # Update the Termux package installation line with the complete set of packages
    run_silent pkg update -y
    run_silent pkg upgrade -y
    display "Installing Termux packages..."
    run_silent pkg install -y openssl cronie termux-services termux-auth libjansson wget nano git screen openssh termux-services libjansson netcat-openbsd jq termux-api iproute2 tsu android-tools nodejs
    
    # Verify critical installations with better error handling for Termux
    if ! command -v git &>/dev/null || ! command -v node &>/dev/null; then
        if [ "$OS" = "termux" ]; then
            warn "Node.js not detected. Attempting to install nodejs specifically..."
            run_silent pkg install -y nodejs
            
            # Check again after explicit installation
            if ! command -v node &>/dev/null; then
                error "Node.js installation failed! Please try manually with: pkg install nodejs"
                return 1
            else
                success "Node.js installed successfully."
            fi
        else
            error "Git or Node.js installation failed! Please install manually."
            return 1
        fi
    fi

    # Install ADB if not present and user has root
    if [ "$HAS_ROOT" = true ] && ! command -v adb &>/dev/null; then
        display "Installing ADB for enhanced functionality..."
        run_silent pkg install -y android-tools
    fi
    
    # Start Termux services if available
    if command -v sv &>/dev/null; then
        run_silent sv-enable crond
        run_silent sv up crond
    fi
    
    # If we have root, try to set optimal CPU governor
    if [ "$HAS_ROOT" = true ]; then
        display "Setting optimal CPU governor for mining..."
        # Find all CPU governor files
        CPU_GOVS=$(su -c "find /sys/devices/system/cpu/ -name scaling_governor")
        # Set to performance if available
        for gov in $CPU_GOVS; do
            GOVERNORS=$(su -c "cat ${gov%/*}/scaling_available_governors")
            if echo "$GOVERNORS" | grep -q "performance"; then
                su -c "echo performance > $gov" 2>/dev/null || true
                log "Set CPU governor to performance: $gov"
            elif echo "$GOVERNORS" | grep -q "schedutil"; then
                su -c "echo schedutil > $gov" 2>/dev/null || true
                log "Set CPU governor to schedutil: $gov"
            fi
        done
    fi
    
    # Return success
    return 0
}

detect_os_and_setup_packages() {
    display "Detecting operating system..."
    
    OS="unknown"
    if grep -qEi "termux" <<< "$PREFIX"; then
        OS="termux"
    elif [ -f "/etc/os-release" ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian) OS="debian";;
            fedora) OS="fedora";;
            raspbian) OS="raspberrypi";;
            *) OS="other-linux";;
        esac
    fi
    export OS
    
    display "Detected OS: $OS"
    
    # Determine if sudo is available and if user has direct root privileges
    HAS_SUDO=false
    IS_ROOT=false
    
    # Check if user is root
    if [ "$(id -u)" = "0" ]; then
        IS_ROOT=true
        log "Running as root user"
    else
        log "Running as non-root user"
        # Check if sudo is available
        if command -v sudo &>/dev/null; then
            # Verify sudo works without asking for password
            if sudo -n true 2>/dev/null; then
                HAS_SUDO=true
                log "Sudo is available and configured for passwordless use"
            else
                # Try with a fake command to see if sudo prompts for password or fails
                sudo_output=$(sudo -l 2>&1)
                if echo "$sudo_output" | grep -q "password"; then
                    HAS_SUDO=true
                    log "Sudo is available but requires password"
                    display "Note: You may be prompted for your password during installation"
                else
                    log "Sudo is not available or user doesn't have sudo privileges"
                    warn "No sudo privileges detected. Some features may not work properly."
                fi
            fi
        else
            log "Sudo command not found"
            warn "The 'sudo' command is not available on this system."
        fi
    fi
    
    # Function to execute commands with appropriate privilege level
    exec_pkg_cmd() {
        local cmd_args=("$@")
        
        if [ "$IS_ROOT" = true ]; then
            # Already root, execute directly
            log "Executing as root: ${cmd_args[*]}"
            run_silent "${cmd_args[@]}"
        elif [ "$HAS_SUDO" = true ]; then
            # Use sudo
            log "Executing with sudo: ${cmd_args[*]}"
            run_silent sudo "${cmd_args[@]}"
        else
            # No sudo, no root - try direct execution and hope it works
            # (useful for user-level package managers or containers)
            log "Attempting execution without root privileges: ${cmd_args[*]}"
            if run_silent "${cmd_args[@]}"; then
                return 0
            else
                error "Failed to execute: ${cmd_args[*]}"
                error "This command may require root privileges."
                error "Try running this script as root or with sudo."
                return 1
            fi
        fi
    }
    
    # Check if the system is ARM-based
    IS_ARM=false
    ARCH=$(uname -m)
    if [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]] || [[ "$ARCH" == arm* ]]; then
        IS_ARM=true
        log "ARM architecture detected: $ARCH"
    fi
    
    # Check if the system is an SBC
    IS_SBC=false
    if [ -f "/proc/device-tree/model" ]; then
        # Use tr to strip null bytes from the output
        SBC_MODEL=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')
        if [ ! -z "$SBC_MODEL" ]; then
            IS_SBC=true
            log "SBC detected: $SBC_MODEL"
        fi
    fi
    
    # Update system and install required packages
    display "Updating system packages... (this may take a while)"
    
    case "$OS" in
        termux)
            termux_setup
            ;;
            
        debian|raspberrypi)
            display "Setting up Debian/Raspberry Pi environment..."
            # Update repositories
            if ! exec_pkg_cmd apt-get update; then
                error "Failed to update package repositories. Check your network connection."
                error "If you're not running as root, try using 'sudo' or running as root user."
                return 1
            fi
            
            display "Installing common packages..."
            if ! exec_pkg_cmd apt-get install -y screen git nodejs npm build-essential wget; then
                error "Failed to install required packages."
                error "Please install git, nodejs, npm, build-essential, and wget manually."
                return 1
            fi
            ;;
            
        fedora)
            display "Setting up Fedora environment..."
            # Update repositories
            if ! exec_pkg_cmd dnf update -y; then
                error "Failed to update package repositories."
                return 1
            fi
            
            display "Installing required packages..."
            if ! exec_pkg_cmd dnf install -y screen git nodejs npm; then
                error "Failed to install required packages."
                return 1
            fi
            ;;
            
        *)
            warn "Unknown OS detected: $OS"
            display "Attempting generic Linux setup..."
            
            # Try with apt-get if available
            if command -v apt-get &>/dev/null; then
                display "Using apt-get package manager..."
                exec_pkg_cmd apt-get update
                exec_pkg_cmd apt-get install -y screen git nodejs npm
            # Try with yum if available
            elif command -v yum &>/dev/null; then
                display "Using yum package manager..."
                exec_pkg_cmd yum update -y
                exec_pkg_cmd yum install -y screen git nodejs npm
            # Try with dnf if available
            elif command -v dnf &>/dev/null; then
                display "Using dnf package manager..."
                exec_pkg_cmd dnf update -y
                exec_pkg_cmd dnf install -y screen git nodejs npm
            else
                error "Unsupported OS. Please install required packages manually."
                error "Required packages: screen, git, nodejs, npm"
                return 1
            fi
            ;;
    esac
    
    # Verify critical installations
    if ! command -v git &>/dev/null || ! command -v node &>/dev/null; then
        if [ "$OS" = "termux" ]; then
            warn "Node.js not detected. Attempting to install nodejs specifically..."
            run_silent pkg install -y nodejs
            
            # Check again after explicit installation
            if ! command -v node &>/dev/null; then
                error "Node.js installation failed! Please try manually with: pkg install nodejs"
                return 1
            else
                success "Node.js installed successfully."
            fi
        else
            error "Git or Node.js installation failed! Please install manually:"
            if [ "$IS_ROOT" = true ]; then
                error "apt-get install -y git nodejs npm"
            elif [ "$HAS_SUDO" = true ]; then
                error "sudo apt-get install -y git nodejs npm"
            else
                error "You need to install as root: git nodejs npm"
            fi
            return 1
        fi
    fi
    
    # Update the exec_cmd function to be available throughout the script
    exec_cmd() {
        if [ "$IS_ROOT" = true ]; then
            run_silent "$@"
        elif [ "$HAS_SUDO" = true ]; then
            run_silent sudo "$@"
        else
            # Try without sudo as last resort
            run_silent "$@"
        fi
    }
    
    # Export the variables for use in other functions
    export IS_ROOT HAS_SUDO
    export -f exec_cmd
    
    return 0
}

if ! detect_os_and_setup_packages; then
    error "Failed to set up the environment. Please check the errors above."
    echo -e "\nCheck $LOG_FILE for details."
    exit 1
fi

# Add this after the detect_os_and_setup_packages function

check_and_update_nodejs() {
    display "Checking Node.js version..."
    
    if ! command -v node &>/dev/null; then
        warn "Node.js not found. Will attempt to install it."
        return 1
    fi
    
    # Get current Node.js version
    NODE_VERSION=$(node -v | sed 's/v//')
    log "Current Node.js version: $NODE_VERSION"
    
    # Parse major version number
    NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)
    
    # Minimum recommended version is Node.js 16
    MIN_VERSION=16
    
    # Check if version is sufficient
    if [ "$NODE_MAJOR" -lt "$MIN_VERSION" ]; then
        warn "Node.js version $NODE_VERSION is too old. RefurbMiner requires at least version $MIN_VERSION."
        warn "Will attempt to install a newer version of Node.js."
        
        # Ask user if they want to update Node.js
        echo -ne "${YELLOW}Do you want to install a newer version of Node.js? (y/n): ${NC}"
        read -r UPDATE_NODE
        
        if [[ ! "$UPDATE_NODE" =~ ^[Yy]$ ]]; then
            warn "Continuing with current Node.js version. Some features may not work correctly."
            return 0
        fi
        
        # Install NVM (Node Version Manager) for better version control
        display "Installing NVM (Node Version Manager)..."
        
        # Create a temporary directory for NVM installation
        NVM_TMP_DIR=$(mktemp -d)
        log "Created temporary directory for NVM installation: $NVM_TMP_DIR"
        
        # Download and run NVM installer
        run_silent curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
        
        # Source NVM
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        
        # Check if NVM is available
        if ! command -v nvm &>/dev/null; then
            warn "Failed to install NVM. Will try alternative Node.js upgrade method."
            
            # Alternative approach based on OS
            case "$OS" in
                debian|raspberrypi)
                    display "Trying to update Node.js via package manager..."
                    run_silent exec_cmd curl -fsSL https://deb.nodesource.com/setup_18.x | exec_cmd bash -
                    run_silent exec_cmd apt-get install -y nodejs
                    ;;
                fedora)
                    display "Trying to update Node.js via package manager..."
                    run_silent exec_cmd dnf module install -y nodejs:18/common
                    ;;
                termux)
                    display "Trying to update Node.js for Termux..."
                    run_silent pkg install -y nodejs
                    ;;
                *)
                    warn "Unable to update Node.js automatically on this system."
                    display "Please manually install Node.js v$MIN_VERSION or higher from https://nodejs.org/"
                    return 1
                    ;;
            esac
        else
            # Install the latest LTS version using NVM
            display "Installing Node.js 18 (LTS) using NVM..."
            run_silent nvm install 18
            run_silent nvm use 18
            run_silent nvm alias default 18
            
            # Update PATH to include the new Node.js version
            export PATH="$NVM_DIR/versions/node/v18.*/bin:$PATH"
        fi
        
        # Verify the new version
        if command -v node &>/dev/null; then
            NEW_VERSION=$(node -v | sed 's/v//')
            log "Updated Node.js version: $NEW_VERSION"
            
            # Parse new major version number
            NEW_MAJOR=$(echo "$NEW_VERSION" | cut -d. -f1)
            
            if [ "$NEW_MAJOR" -ge "$MIN_VERSION" ]; then
                success "Successfully upgraded Node.js to version $NEW_VERSION"
                
                # Update npm to latest version
                display "Updating npm to the latest version..."
                run_silent npm install -g npm
                
                return 0
            else
                warn "Node.js upgrade partially successful, but version $NEW_VERSION is still below recommended $MIN_VERSION."
                warn "Some features may not work correctly."
                return 0
            fi
        else
            error "Failed to upgrade Node.js. Please install version $MIN_VERSION or higher manually."
            return 1
        fi
    else
        success "Node.js version $NODE_VERSION is compatible with RefurbMiner."
        return 0
    fi
}

# Check and update Node.js if necessary
if ! check_and_update_nodejs; then
    warn "Node.js version check or update failed. Continuing anyway, but you may encounter issues."
    # We don't exit here, give it a chance to work with current version
fi

success "System dependencies successfully installed"

# === Step 3: Get RIG Token from User ===
step 3 "Setting up RIG Token"

echo -ne "${YELLOW}Please enter your RIG Token (e.g., xyz9876543210abcdef34): ${NC}"
read -r RIG_TOKEN

if [ -z "$RIG_TOKEN" ]; then
    error "RIG Token cannot be empty. Exiting."
    exit 1
fi

log "RIG Token received: $RIG_TOKEN"
success "RIG Token received"

# === Step 4: Clone Repository and Setup ===
step 4 "Setting up RefurbMiner software"

# Clone Repository
if [ -d "$INSTALL_DIR" ]; then
    display "Installation directory already exists. Updating..."
    
    # Backup important configuration files
    display "Backing up configuration files..."
    
    # Backup .env file if it exists
    if [ -f "$INSTALL_DIR/.env" ]; then
        run_silent cp "$INSTALL_DIR/.env" "$INSTALL_DIR/.env.backup"
        log "Backed up .env file"
    fi
    
    # Backup config/config.json if it exists
    if [ -f "$INSTALL_DIR/config/config.json" ]; then
        # Make sure the backup directory exists
        run_silent mkdir -p "$INSTALL_DIR/config.backup"
        run_silent cp "$INSTALL_DIR/config/config.json" "$INSTALL_DIR/config.backup/config.json"
        log "Backed up config/config.json file"
    fi
    
    # Update the repository
    run_silent cd "$INSTALL_DIR" && run_silent git pull origin master
    
    # Restore configuration files from backups
    display "Restoring configuration files..."
    
    # Restore .env file if backup exists
    if [ -f "$INSTALL_DIR/.env.backup" ]; then
        run_silent mv "$INSTALL_DIR/.env.backup" "$INSTALL_DIR/.env"
        log "Restored .env file from backup"
    fi
    
    # Restore config/config.json if backup exists
    if [ -f "$INSTALL_DIR/config.backup/config.json" ]; then
        # Make sure the config directory exists
        run_silent mkdir -p "$INSTALL_DIR/config"
        run_silent mv "$INSTALL_DIR/config.backup/config.json" "$INSTALL_DIR/config/config.json"
        run_silent rm -rf "$INSTALL_DIR/config.backup"
        log "Restored config/config.json file from backup"
    fi
else
    display "Downloading RefurbMiner..."
    run_silent git clone "$REPO_URL" "$INSTALL_DIR"
    run_silent cd "$INSTALL_DIR" || { error "Cloning failed!"; exit 1; }
fi

# Update .env file with RIG Token - only if it doesn't already exist or needs updating
display "Configuring RIG Token..."
if [ -f "$INSTALL_DIR/.env" ]; then
    # Check if RIG_TOKEN already exists in the file
    if grep -q "^RIG_TOKEN=" "$INSTALL_DIR/.env"; then
        # Check if the existing token matches the provided one
        EXISTING_TOKEN=$(grep "^RIG_TOKEN=" "$INSTALL_DIR/.env" | cut -d '=' -f 2)
        if [ "$EXISTING_TOKEN" != "$RIG_TOKEN" ]; then
            # Token has changed, update it
            display "Updating RIG Token..."
            run_silent sed -i "s/^RIG_TOKEN=.*/RIG_TOKEN=$RIG_TOKEN/" "$INSTALL_DIR/.env"
        else
            display "RIG Token already configured. Keeping existing configuration."
        fi
    else
        # Append RIG_TOKEN line
        echo "RIG_TOKEN=$RIG_TOKEN" >> "$INSTALL_DIR/.env"
    fi
else
    # Create new .env file
    cat > "$INSTALL_DIR/.env" << EOF
##### Logging Module
LOG_LEVEL=DEBUG 
LOG_TO_CONSOLE=true

##### API settings
API_URL=https://api.refurbminer.de
RIG_TOKEN=$RIG_TOKEN
EOF
fi

# Install Node Dependencies
display "Installing dependencies..."
cd "$INSTALL_DIR" || { error "Failed to change directory!"; exit 1; }
if ! run_silent npm install; then
    error "NPM install failed! Check $LOG_FILE for details."
    exit 1
fi

# Build Project
display "Building RefurbMiner..."
if ! run_silent npm run build; then
    error "Build failed! Check $LOG_FILE for details."
    exit 1
fi

success "RefurbMiner software setup completed"

# === Step 5: Configure Mining Software ===
step 5 "Setting up mining software"

mkdir -p "$INSTALL_DIR/apps/ccminer"

# Function to build ccminer from source for SBCs
build_ccminer_sbc() {
    display "Setting up ccminer for SBC device..."
    
    run_silent wget http://ports.ubuntu.com/pool/main/o/openssl/libssl1.1_1.1.0g-2ubuntu4_arm64.deb
    exec_cmd dpkg -i libssl1.1_1.1.0g-2ubuntu4_arm64.deb
    run_silent rm libssl1.1_1.1.0g-2ubuntu4_arm64.deb
   
    # After build, create ccminer folder and copy ccminer executable
    display "Downloading optimized ccminer for ARM devices..."
    run_silent mkdir -p "$INSTALL_DIR/apps/ccminer"
    run_silent wget -q -O "$INSTALL_DIR/apps/ccminer/ccminer" https://raw.githubusercontent.com/Oink70/CCminer-ARM-optimized/main/ccminer
    run_silent chmod +x "$INSTALL_DIR/apps/ccminer/ccminer"

    # Install default config for DONATION
    run_silent wget -q -O "$INSTALL_DIR/apps/ccminer/config.json" https://raw.githubusercontent.com/dismaster/RG3DUI/main/config.json
}

# Function to build ccminer from source for UNIX
build_ccminer_unix() {
    display "Setting up ccminer for standard PC..."
    
    run_silent wget http://ports.ubuntu.com/pool/main/o/openssl/libssl1.1_1.1.0g-2ubuntu4_arm64.deb
    exec_cmd dpkg -i libssl1.1_1.1.0g-2ubuntu4_arm64.deb
    run_silent rm libssl1.1_1.1.0g-2ubuntu4_arm64.deb
    
    # Clone CCminer repository and rename folder to ccminer_build
    display "Downloading and building ccminer from source..."
    run_silent git clone --single-branch -b Verus2.2 https://github.com/monkins1010/ccminer.git "$HOME/ccminer_build"
    
    display "Compiling ccminer... (this will take a while)"
    (cd "$HOME/ccminer_build" && ./build.sh) >> "$LOG_FILE" 2>&1
    
    # After build, create ccminer folder and copy ccminer executable
    run_silent mkdir -p "$INSTALL_DIR/apps/ccminer"
    run_silent mv "$HOME/ccminer_build/ccminer" "$INSTALL_DIR/apps/ccminer/ccminer"
    
    # Clean up ccminer_build folder
    run_silent rm -rf "$HOME/ccminer_build"

    # Install default config for DONATION
    run_silent wget -q -O "$INSTALL_DIR/apps/ccminer/config.json" https://raw.githubusercontent.com/dismaster/RG3DUI/main/config.json
}

# Function to select the right ccminer version for Termux and ARM devices
select_ccminer_version() {
    display "Detecting CPU architecture..."

    # Use lscpu for CPU detection
    CPU_INFO=$(lscpu)
    
    # Extract relevant architecture information
    CPU_MODEL=$(echo "$CPU_INFO" | grep "Model name" | cut -d ':' -f 2 | xargs)
    CPU_ARCH=$(echo "$CPU_INFO" | grep "Architecture" | cut -d ':' -f 2 | xargs)
    
    log "CPU model: $CPU_MODEL"
    log "CPU architecture: $CPU_ARCH"

    # Parse complex CPU model names like "Cortex-A55 exynos-m3"
    # Check for Exynos custom cores
    if echo "$CPU_MODEL" | grep -q "exynos-m3"; then
        if echo "$CPU_MODEL" | grep -q "A55"; then
            CC_BRANCH="em3-a55"
            log "Detected Exynos M3 with Cortex-A55"
        else
            CC_BRANCH="em3" 
            log "Detected Exynos M3"
        fi
    elif echo "$CPU_MODEL" | grep -q "exynos-m4"; then
        if echo "$CPU_MODEL" | grep -q "A75" && echo "$CPU_MODEL" | grep -q "A55"; then
            CC_BRANCH="em4-a75-a55"
            log "Detected Exynos M4 with Cortex-A75 and A55"
        else
            CC_BRANCH="em4"
            log "Detected Exynos M4"
        fi
    elif echo "$CPU_MODEL" | grep -q "exynos-m5"; then
        if echo "$CPU_MODEL" | grep -q "A76" && echo "$CPU_MODEL" | grep -q "A55"; then
            CC_BRANCH="em5-a76-a55"
            log "Detected Exynos M5 with Cortex-A76 and A55"
        else
            CC_BRANCH="em5"
            log "Detected Exynos M5"
        fi
    # Prioritize combined CPU configurations first, and then fallback to single core types
    elif echo "$CPU_MODEL" | grep -q "A76" && echo "$CPU_MODEL" | grep -q "A55"; then
        CC_BRANCH="a76-a55"
    elif echo "$CPU_MODEL" | grep -q "A75" && echo "$CPU_MODEL" | grep -q "A55"; then
        CC_BRANCH="a75-a55"
    elif echo "$CPU_MODEL" | grep -q "A72" && echo "$CPU_MODEL" | grep -q "A53"; then
        CC_BRANCH="a72-a53"
    elif echo "$CPU_MODEL" | grep -q "A73" && echo "$CPU_MODEL" | grep -q "A53"; then
        CC_BRANCH="a73-a53"
    elif echo "$CPU_MODEL" | grep -q "A57" && echo "$CPU_MODEL" | grep -q "A53"; then
        CC_BRANCH="a57-a53"
    elif echo "$CPU_MODEL" | grep -q "X1" && echo "$CPU_MODEL" | grep -q "A78" && echo "$CPU_MODEL" | grep -q "A55"; then
        CC_BRANCH="x1-a78-a55"
    # Now check for single-core architectures if no combinations match
    elif echo "$CPU_MODEL" | grep -q "A35"; then
        CC_BRANCH="a35"
    elif echo "$CPU_MODEL" | grep -q "A53"; then
        CC_BRANCH="a53"
    elif echo "$CPU_MODEL" | grep -q "A55"; then
        CC_BRANCH="a55"
    elif echo "$CPU_MODEL" | grep -q "A57"; then
        CC_BRANCH="a57"
    elif echo "$CPU_MODEL" | grep -q "A65"; then
        CC_BRANCH="a65"
    elif echo "$CPU_MODEL" | grep -q "A72"; then
        CC_BRANCH="a72"
    elif echo "$CPU_MODEL" | grep -q "A73"; then
        CC_BRANCH="a73"
    elif echo "$CPU_MODEL" | grep -q "A75"; then
        CC_BRANCH="a75"
    elif echo "$CPU_MODEL" | grep -q "A76"; then
        CC_BRANCH="a76"
    elif echo "$CPU_MODEL" | grep -q "A77"; then
        CC_BRANCH="a77"
    elif echo "$CPU_MODEL" | grep -q "A78"; then
        CC_BRANCH="a78"
    elif echo "$CPU_MODEL" | grep -q "A78C"; then
        CC_BRANCH="a78c"
    # Check architecture as a fallback if model name doesn't have ARM core info
    elif [ "$CPU_ARCH" = "aarch64" ] || [ "$CPU_ARCH" = "arm64" ]; then
        # Determine a reasonable fallback for ARM64 architectures
        if grep -q "bcm" /proc/cpuinfo || grep -q "Raspberry" /proc/device-tree/model 2>/dev/null; then
            CC_BRANCH="a72-a53" # Common for Raspberry Pi 4 and similar
        else
            CC_BRANCH="a55" # Most common newer ARM core
        fi
    elif [[ "$CPU_ARCH" =~ ^arm ]]; then
        # For older 32-bit ARM
        CC_BRANCH="a53"
    else
        CC_BRANCH="generic"
    fi

    log "Selected ccminer branch: $CC_BRANCH"
    
    # Add a fallback check if the selected branch doesn't exist or isn't accessible
    display "Downloading optimal ccminer version for your CPU..."
    if ! wget -q --spider "https://raw.githubusercontent.com/Darktron/pre-compiled/$CC_BRANCH/ccminer" 2>/dev/null; then
        warn "Selected version not available. Falling back to generic version..."
        log "Branch $CC_BRANCH not available, falling back to generic"
        CC_BRANCH="generic"
    fi
    
    run_silent wget -q -O "$INSTALL_DIR/apps/ccminer/ccminer" "https://raw.githubusercontent.com/Darktron/pre-compiled/$CC_BRANCH/ccminer"
    run_silent chmod +x "$INSTALL_DIR/apps/ccminer/ccminer"
    
    # Install default config
    run_silent wget -q -O "$INSTALL_DIR/apps/ccminer/config.json" "https://raw.githubusercontent.com/dismaster/RG3DUI/main/config.json"
}

# Setup ccminer based on detected environment
case "$OS" in
    termux)
        display "Setting up ccminer for Termux..."
        
        # If we have root, optimize system for mining
        if [ "$HAS_ROOT" = true ]; then
            display "Applying system optimizations for mining..."
            # Disable thermal throttling if possible
            if [ -f "/sys/class/thermal/thermal_zone0/mode" ]; then
                su -c "echo disabled > /sys/class/thermal/thermal_zone0/mode" 2>/dev/null || true
                log "Attempted to disable thermal throttling"
            fi
            
            # Set process priority
            display "Setting process priority for better mining performance..."
            run_silent su -c "echo -17 > /proc/self/oom_adj" 2>/dev/null || true
        fi
        
        select_ccminer_version
        ;;
        
    debian|raspberrypi)
        # Check if the system is an SBC (e.g., Raspberry Pi, Orange Pi) or ARM-based
        if grep -q "Raspberry" /proc/device-tree/model 2>/dev/null || grep -q "Orange" /proc/device-tree/model 2>/dev/null || grep -q "Rockchip" /proc/device-tree/model 2>/dev/null || lscpu | grep -q "ARM"; then
            display "Detected ARM-based device. Installing necessary packages..."
            
            # Install packages silently
            exec_cmd apt-get update
            exec_cmd apt-get install -y openssl android-tools-adb android-tools-fastboot cron libomp5 git libcurl4-openssl-dev libssl-dev libjansson-dev
            
            # Build ccminer with basic configuration
            build_ccminer_sbc
        else
            display "Detected general Linux device. Installing necessary packages..."
            
            # Install packages silently
            exec_cmd apt-get update
            exec_cmd apt-get install -y openssl cron git libcurl4-openssl-dev libssl-dev libjansson-dev automake autotools-dev build-essential
            
            # Build ccminer with basic configuration
            build_ccminer_unix
        fi
        ;;
    fedora)
        display "Setting up ccminer for Fedora..."
        # Install necessary packages
        exec_cmd dnf install -y openssl cron git libcurl-devel openssl-devel jansson-devel automake libtool gcc-c++ make
        # Build ccminer with basic configuration
        build_ccminer_unix
        ;;
    *)
        error "Unsupported OS for ccminer. Please install manually."
        warn "You can still use RefurbMiner, but may need to configure mining software separately."
        ;;
esac

success "Mining software setup completed"

# === Step 6: Final Configuration ===
step 6 "Finalizing installation"

display "Checking system configuration..."
# Set executable permissions for ccminer
run_silent chmod +x "$INSTALL_DIR/apps/ccminer/ccminer"

# Setup autostart based on detected environment
display "Setting up auto-start capability..."

case "$OS" in
    termux)
        display "Configuring Termux auto-start..."
        
        # Create Termux boot directory if it doesn't exist
        run_silent mkdir -p "$HOME/.termux/boot"
        
        # Create custom boot script with optimizations if we have root
        if [ "$HAS_ROOT" = true ]; then
            display "Creating optimized boot script with root capabilities..."
            
            cat > "$HOME/.termux/boot/boot_start" << EOF
#!/data/data/com.termux/files/usr/bin/bash
# RefurbMiner autostart script with root optimizations

# Source the environment (if needed)
source /data/data/com.termux/files/usr/etc/profile

# Acquire wake lock to prevent device sleep
if command -v termux-wake-lock &>/dev/null; then
    termux-wake-lock
fi

# Start SSH daemon if available
if command -v sshd &>/dev/null; then
    sshd
fi

# Start cron daemon if available
if command -v crond &>/dev/null; then
    crond
fi

# Clean up any stale screen sessions
screen -wipe

# Set CPU governor to performance if available
if su -c "id -u" 2>/dev/null | grep -q "^0$"; then
    # Find all CPU governor files
    CPU_GOVS=\$(su -c "find /sys/devices/system/cpu/ -name scaling_governor")
    # Set to performance or schedutil if available
    for gov in \$CPU_GOVS; do
        GOVERNORS=\$(su -c "cat \${gov%/*}/scaling_available_governors")
        if echo "\$GOVERNORS" | grep -q "performance"; then
            su -c "echo performance > \$gov" 2>/dev/null || true
        elif echo "\$GOVERNORS" | grep -q "schedutil"; then
            su -c "echo schedutil > \$gov" 2>/dev/null || true
        fi
    done
    
    # Disable thermal throttling if possible
    if [ -f "/sys/class/thermal/thermal_zone0/mode" ]; then
        su -c "echo disabled > /sys/class/thermal/thermal_zone0/mode" 2>/dev/null || true
    fi
    
    # Set process priority
    su -c "echo -17 > /proc/self/oom_adj" 2>/dev/null || true
fi

# Apply ADB optimizations if available
if command -v adb &>/dev/null; then
    # Set battery level to 100% in Android's eyes
    adb shell dumpsys battery set level 100 2>/dev/null || true
    # Keep screen on (prevents throttling on some devices)
    adb shell svc power stayon true 2>/dev/null || true
    # Add Termux apps to battery optimization whitelist
    adb shell dumpsys deviceidle whitelist +com.termux.boot 2>/dev/null || true
    adb shell dumpsys deviceidle whitelist +com.termux 2>/dev/null || true
    adb shell dumpsys deviceidle whitelist +com.termux.api 2>/dev/null || true
    # Improve system responsiveness
    adb shell settings put global system_capabilities 100 2>/dev/null || true
    adb shell settings put global sem_enhanced_cpu_responsiveness 1 2>/dev/null || true
    # Keep WiFi on during sleep
    adb shell settings put global wifi_sleep_policy 2 2>/dev/null || true
fi

# Start mining in background
cd $INSTALL_DIR && screen -dmS refurbminer npm start

# Flash LED 3 times to indicate successful startup
if command -v termux-torch &>/dev/null; then
    sleep 2
    termux-torch on
    sleep 0.5
    termux-torch off
    sleep 0.5
    termux-torch on
    sleep 0.5
    termux-torch off
    sleep 0.5
    termux-torch on
    sleep 0.5
    termux-torch off
fi

exit 0
EOF
        else
            # For non-root devices, create a more basic but still enhanced boot script
            display "Creating boot script..."
            
            cat > "$HOME/.termux/boot/boot_start" << EOF
#!/data/data/com.termux/files/usr/bin/bash
# RefurbMiner autostart script

# Source the environment
source /data/data/com.termux/files/usr/etc/profile

# Acquire wake lock to prevent device sleep
if command -v termux-wake-lock &>/dev/null; then
    termux-wake-lock
fi

# Start SSH daemon if available
if command -v sshd &>/dev/null; then
    sshd
fi

# Start cron daemon if available
if command -v crond &>/dev/null; then
    crond
fi

# Clean up any stale screen sessions
screen -wipe

# Start mining in background
cd $INSTALL_DIR && screen -dmS refurbminer npm start

# Flash LED 3 times to indicate successful startup
if command -v termux-torch &>/dev/null; then
    termux-torch on
    termux-torch off
    termux-torch on
    termux-torch off
    termux-torch on
    termux-torch off
fi

exit 0
EOF
        fi
        
        # Make boot script executable
        run_silent chmod +x "$HOME/.termux/boot/boot_start"
        
        # Check if boot script was installed successfully
        if [ -f "$HOME/.termux/boot/boot_start" ] && [ -x "$HOME/.termux/boot/boot_start" ]; then
            success "Auto-start for Termux configured successfully"
            log "Termux boot script installed at $HOME/.termux/boot/boot_start"
            
            if [ "$HAS_ROOT" = true ]; then
                success "Enhanced boot script with root optimizations installed"
            fi
        else
            warn "Failed to set up auto-start for Termux"
            log "Failed to set up Termux boot script at $HOME/.termux/boot/boot_start"
        fi
        
        # Inform about Termux boot
        display "Note: For auto-start to work, you need to enable 'Boot' permission for Termux in Android settings."
        display "You may need to install the Termux:Boot add-on from F-Droid or Google Play."
        ;;
        
    debian|raspberrypi|*)
        display "Configuring crontab for auto-start..."
        
        # Create a temporary crontab file
        TEMP_CRON=$(mktemp)
        
        # Export current crontab
        crontab -l > "$TEMP_CRON" 2>/dev/null || true
        
        # Check if the crontab already has our autostart entry
        if ! grep -q "$INSTALL_DIR && screen -dmS refurbminer npm start" "$TEMP_CRON"; then
            # Add our reboot startup line
            echo -e "\n## Start RefurbMiner app" >> "$TEMP_CRON"
            echo "@reboot cd $INSTALL_DIR && screen -dmS refurbminer npm start" >> "$TEMP_CRON"
            
            # Install new crontab
            run_silent crontab "$TEMP_CRON"
            
            # Check if crontab was installed successfully
            if crontab -l | grep -q "refurbminer npm start"; then
                success "Auto-start configured successfully via crontab"
                log "Crontab entry added for auto-starting RefurbMiner on reboot"
            else
                warn "Failed to update crontab for auto-start"
                log "Failed to add crontab entry for auto-starting RefurbMiner"
                
                display "To manually set up auto-start, add the following line to your crontab:"
                echo -e "${YELLOW}@reboot cd $INSTALL_DIR && screen -dmS refurbminer npm start${NC}"
                echo -e "${BLUE}You can edit your crontab with:${NC} ${YELLOW}crontab -e${NC}"
            fi
        else
            log "Auto-start crontab entry already exists"
            success "Auto-start already configured"
        fi
        
        # Clean up temporary file
        rm -f "$TEMP_CRON"
        ;;
esac

# Create convenient start/stop scripts
display "Creating utility scripts..."

# Make all scripts executable
run_silent chmod +x "$INSTALL_DIR/start.sh" "$INSTALL_DIR/stop.sh" "$INSTALL_DIR/status.sh"

# Verify scripts were downloaded successfully
if [ -f "$INSTALL_DIR/start.sh" ] && [ -f "$INSTALL_DIR/stop.sh" ] && [ -f "$INSTALL_DIR/status.sh" ]; then
    success "Utility scripts installed successfully"
    log "Utility scripts installed in $INSTALL_DIR"
else
    warn "Failed to download one or more utility scripts"
    log "Issues downloading utility scripts from repository"
fi

# Download update script to the user's home directory, not the app folder
display "Setting up automatic updater..."
run_silent wget -q -O "$HOME/update_refurbminer.sh" "https://raw.githubusercontent.com/dismaster/refurbminer_tools/refs/heads/main/update_refurbminer.sh"
run_silent chmod +x "$HOME/update_refurbminer.sh"

if [ -f "$HOME/update_refurbminer.sh" ] && [ -x "$HOME/update_refurbminer.sh" ]; then
    success "Auto-updater script installed successfully"
    log "Update script installed at $HOME/update_refurbminer.sh"
else
    warn "Failed to install auto-updater script"
    log "Failed to install update script at $HOME/update_refurbminer.sh"
fi

# Make all scripts executable
run_silent chmod +x "$INSTALL_DIR/start.sh" "$INSTALL_DIR/stop.sh" "$INSTALL_DIR/status.sh"

# === Finished ===
success "RefurbMiner installation complete!"
echo
echo -e "${LC} _____               _     _       ${NC}"
echo -e "${LC}|     |___ _____ ___| |___| |_ ___ ${NC}"
echo -e "${LC}|   --| . |     | . | | -_|  _| -_|${NC}"
echo -e "${LC}|_____|___|_|_|_|  _|_|___|_| |___|${NC}"
echo -e "${LC}                |_|                ${NC}"
echo
echo -e "${BLUE}Management commands:${NC}"
echo -e "  ${YELLOW}$INSTALL_DIR/start.sh${NC}  - Start the mining process"
echo -e "  ${YELLOW}$INSTALL_DIR/stop.sh${NC}   - Stop the mining process"
echo -e "  ${YELLOW}$INSTALL_DIR/status.sh${NC} - Check if mining is running"
echo -e "  ${YELLOW}$HOME/update_refurbminer.sh${NC} - Update RefurbMiner to the latest version"
echo
echo -e "${BLUE}Mining will now start automatically on system boot.${NC}"
echo -e "${BLUE}You can also manually start it with:${NC} ${YELLOW}cd $INSTALL_DIR && npm start${NC}"
echo
echo -e "${BLUE}Installation log saved to:${NC} $LOG_FILE"
echo
