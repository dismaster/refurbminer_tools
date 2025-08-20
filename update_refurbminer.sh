#!/bin/bash

# === CONFIGURATION ===
REPO_DIR="$HOME/refurbminer"
SCREEN_NAME="refurbminer"
# Store backup outside of the git repo to prevent it being cleaned
BACKUP_DIR="$HOME/refurbminer_backup_$(date +%Y%m%d%H%M%S)"
# Configure maximum number of backup folders to keep
MAX_BACKUPS=3
# Add logging
LOG_FILE="$HOME/refurbminer_update.log"

# Helper functions for friendly output
info()    { echo -e "\033[1;34mℹ️  $1\033[0m"; log "INFO: $1"; }
success() { echo -e "\033[1;32m✅ $1\033[0m"; log "SUCCESS: $1"; }
error()   { echo -e "\033[1;31m❌ $1\033[0m"; log "ERROR: $1"; }
warn()    { echo -e "\033[1;33m⚠️  $1\033[0m"; log "WARNING: $1"; }

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Function to run commands with better error reporting
run_with_output() {
    local cmd="$1"
    local description="$2"
    
    log "Running: $cmd"
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        return 0
    else
        local exit_code=$?
        error "$description failed with exit code $exit_code"
        error "Check $LOG_FILE for detailed error information"
        return $exit_code
    fi
}

# Function to check Node.js and npm versions
check_nodejs_environment() {
    info "Checking Node.js environment..."
    
    # Check Node.js version
    if command -v node &>/dev/null; then
        NODE_VERSION=$(node -v)
        info "Node.js version: $NODE_VERSION"
        log "Node.js version: $NODE_VERSION"
    else
        error "Node.js is not installed or not in PATH"
        return 1
    fi
    
    # Check npm version
    if command -v npm &>/dev/null; then
        NPM_VERSION=$(npm -v)
        info "npm version: $NPM_VERSION"
        log "npm version: $NPM_VERSION"
    else
        error "npm is not installed or not in PATH"
        return 1
    fi
    
    # Check if we can write to npm cache
    if ! npm config get cache &>/dev/null; then
        warn "npm cache directory may not be accessible"
    fi
    
    return 0
}

# Function to clean npm cache and node_modules
clean_build_environment() {
    info "Cleaning build environment..."
    
    # Remove node_modules if it exists
    if [ -d "$REPO_DIR/node_modules" ]; then
        log "Removing existing node_modules directory"
        rm -rf "$REPO_DIR/node_modules"
    fi
    
    # Clear npm cache
    log "Clearing npm cache"
    npm cache clean --force >> "$LOG_FILE" 2>&1 || warn "Failed to clear npm cache"
    
    # Remove package-lock.json to force fresh install
    if [ -f "$REPO_DIR/package-lock.json" ]; then
        log "Removing package-lock.json for fresh install"
        rm -f "$REPO_DIR/package-lock.json"
    fi
    
    success "Build environment cleaned"
}

# Function to attempt build with fallback options
attempt_build() {
    info "Attempting to build application..."
    
    # First attempt: standard build
    if run_with_output "npm run build" "Standard build"; then
        return 0
    fi
    
    warn "Standard build failed. Trying alternative approaches..."
    
    # Second attempt: rebuild node modules and try again
    info "Rebuilding dependencies..."
    if run_with_output "npm install --force" "Forced dependency installation"; then
        if run_with_output "npm run build" "Build after forced install"; then
            return 0
        fi
    fi
    
    # Third attempt: use legacy peer deps
    warn "Trying with legacy peer dependencies..."
    if run_with_output "npm install --legacy-peer-deps" "Install with legacy peer deps"; then
        if run_with_output "npm run build" "Build with legacy deps"; then
            return 0
        fi
    fi
    
    # Fourth attempt: skip build and just prepare files
    warn "Build continues to fail. Attempting to run without build step..."
    
    # Check if the main files exist
    if [ -f "$REPO_DIR/package.json" ] && [ -f "$REPO_DIR/index.js" -o -f "$REPO_DIR/app.js" -o -f "$REPO_DIR/src/index.js" ]; then
        warn "Skipping build step - application may work without it"
        return 0
    fi
    
    return 1
}

# Function to validate the installation
validate_installation() {
    info "Validating installation..."
    
    # Check if essential files exist
    if [ ! -f "$REPO_DIR/package.json" ]; then
        error "package.json not found"
        return 1
    fi
    
    # Try to identify the main application file
    local main_file=""
    if [ -f "$REPO_DIR/index.js" ]; then
        main_file="index.js"
    elif [ -f "$REPO_DIR/app.js" ]; then
        main_file="app.js"
    elif [ -f "$REPO_DIR/src/index.js" ]; then
        main_file="src/index.js"
    else
        # Try to extract from package.json
        main_file=$(grep -o '"main"[[:space:]]*:[[:space:]]*"[^"]*"' "$REPO_DIR/package.json" 2>/dev/null | head -1 | cut -d '"' -f4)
    fi
    
    if [ -n "$main_file" ] && [ -f "$REPO_DIR/$main_file" ]; then
        info "Main application file found: $main_file"
        log "Main application file: $main_file"
    else
        warn "Could not identify main application file"
    fi
    
    # Check if node_modules directory exists and has content
    if [ -d "$REPO_DIR/node_modules" ] && [ "$(ls -A $REPO_DIR/node_modules 2>/dev/null)" ]; then
        success "Dependencies appear to be installed"
    else
        warn "node_modules directory is missing or empty"
    fi
    
    return 0
}

# Function to clean up old backup folders
cleanup_old_backups() {
    info "Cleaning up old backups..."
    # List all backup folders, sort by modification time (newest first), skip the newest 3
    local old_backups=$(find "$HOME" -maxdepth 1 -type d -name "refurbminer_backup_*" | sort -r | tail -n +$((MAX_BACKUPS+1)))
    
    if [ -z "$old_backups" ]; then
        info "No old backups to clean up"
    else
        for backup in $old_backups; do
            rm -rf "$backup"
            info "Removed old backup: $(basename "$backup")"
        done
        success "Backup cleanup completed"
    fi
}

# Start logging
log "=== RefurbMiner Update Started ==="
info "Starting refurbminer update..."

# === NAVIGATE TO REPO ===
cd "$REPO_DIR" || { error "Repo directory not found at $REPO_DIR!"; exit 1; }

# === CHECK ENVIRONMENT ===
if ! check_nodejs_environment; then
    error "Node.js environment check failed. Please ensure Node.js and npm are properly installed."
    exit 1
fi

# === CAPTURE PREVIOUS VERSION ===
# Get previous version before updating
if [ -f "$REPO_DIR/package.json" ]; then
    PREVIOUS_VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$REPO_DIR/package.json" | head -1 | cut -d '"' -f4)
    info "Previous version: $PREVIOUS_VERSION"
else
    PREVIOUS_VERSION="unknown"
    warn "Could not determine previous version"
fi

# === STOP EXISTING SCREEN SESSION ===
info "Checking for running instances..."

# Function to thoroughly clean up running processes
cleanup_running_processes() {
    local cleanup_needed=false
    
    # Check for any screen sessions related to mining
    if screen -list 2>/dev/null | grep -E "(refurbminer|miner)" > /dev/null; then
        cleanup_needed=true
        info "Found running screen sessions, cleaning up..."
        
        # Get all mining-related screen sessions
        local sessions=$(screen -list 2>/dev/null | grep -E "(refurbminer|miner)" | awk '{print $1}' | cut -d. -f1)
        
        for session in $sessions; do
            info "Stopping screen session: $session"
            screen -S "$session" -X quit > /dev/null 2>&1
        done
        
        # Wait a bit for sessions to close
        sleep 3
        
        # Force kill any remaining screen processes
        if screen -list 2>/dev/null | grep -E "(refurbminer|miner)" > /dev/null; then
            warn "Some screen sessions didn't close gracefully, force killing..."
            pkill -f "SCREEN.*refurbminer" 2>/dev/null || true
            pkill -f "SCREEN.*miner" 2>/dev/null || true
            sleep 2
        fi
    fi
    
    # Check for processes using port 3000 (RefurbMiner's default port)
    local port_processes=$(lsof -ti:3000 2>/dev/null || netstat -tlnp 2>/dev/null | grep ":3000 " | awk '{print $7}' | cut -d/ -f1)
    
    if [ -n "$port_processes" ]; then
        cleanup_needed=true
        warn "Found processes using port 3000, terminating them..."
        
        for pid in $port_processes; do
            if [ -n "$pid" ] && [ "$pid" != "-" ]; then
                info "Killing process $pid using port 3000"
                kill -TERM "$pid" 2>/dev/null || true
            fi
        done
        
        # Wait for graceful shutdown
        sleep 5
        
        # Force kill if still running
        for pid in $port_processes; do
            if [ -n "$pid" ] && [ "$pid" != "-" ] && kill -0 "$pid" 2>/dev/null; then
                warn "Force killing stubborn process $pid"
                kill -KILL "$pid" 2>/dev/null || true
            fi
        done
    fi
    
    # Check for any node processes running RefurbMiner
    local node_processes=$(pgrep -f "node.*refurbminer\|npm.*start" 2>/dev/null || true)
    
    if [ -n "$node_processes" ]; then
        cleanup_needed=true
        warn "Found RefurbMiner node processes, terminating them..."
        
        for pid in $node_processes; do
            if [ -n "$pid" ]; then
                info "Killing RefurbMiner process $pid"
                kill -TERM "$pid" 2>/dev/null || true
            fi
        done
        
        # Wait for graceful shutdown
        sleep 3
        
        # Force kill if still running
        for pid in $node_processes; do
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                warn "Force killing stubborn node process $pid"
                kill -KILL "$pid" 2>/dev/null || true
            fi
        done
    fi
    
    # Clean up stale screen socket files
    if [ -d "$HOME/.screen" ]; then
        info "Cleaning up stale screen socket files..."
        screen -wipe > /dev/null 2>&1 || true
        
        # Remove any remaining stale socket files
        find "$HOME/.screen" -name "*refurbminer*" -type s -delete 2>/dev/null || true
        find "$HOME/.screen" -name "*miner*" -type s -delete 2>/dev/null || true
    fi
    
    if [ "$cleanup_needed" = true ]; then
        success "Cleanup completed, waiting for system to stabilize..."
        sleep 3
        
        # Final verification
        if screen -list 2>/dev/null | grep -E "(refurbminer|miner)" > /dev/null; then
            warn "Some screen sessions may still be running, but continuing with update..."
        fi
        
        # Check if port 3000 is still in use
        if lsof -ti:3000 2>/dev/null > /dev/null || netstat -tln 2>/dev/null | grep ":3000 " > /dev/null; then
            warn "Port 3000 may still be in use, but continuing with update..."
            warn "If the update fails to start, wait a few minutes and try again."
        fi
    else
        info "No running instances found"
    fi
}

# Perform the cleanup
cleanup_running_processes

# === BACKUP IMPORTANT FILES ===
info "Creating backup of your configuration..."
# Create backup folder OUTSIDE the git repo
mkdir -p "$BACKUP_DIR" > /dev/null 2>&1

# Backup .env file
if [ -f "$REPO_DIR/.env" ]; then
    cp -f "$REPO_DIR/.env" "$BACKUP_DIR/.env" > /dev/null 2>&1
    log "Backed up .env file"
fi

# Backup config/config.json
if [ -f "$REPO_DIR/config/config.json" ]; then
    mkdir -p "$BACKUP_DIR/config" > /dev/null 2>&1
    cp -f "$REPO_DIR/config/config.json" "$BACKUP_DIR/config/config.json" > /dev/null 2>&1
    log "Backed up config/config.json"
fi

# Backup apps directory
if [ -d "$REPO_DIR/apps" ]; then
    cp -rf "$REPO_DIR/apps" "$BACKUP_DIR/" > /dev/null 2>&1
    log "Backed up apps directory"
fi

# Backup package.json for version tracking
if [ -f "$REPO_DIR/package.json" ]; then
    cp -f "$REPO_DIR/package.json" "$BACKUP_DIR/package.json" > /dev/null 2>&1
    log "Backed up package.json"
fi

success "Backup created at $BACKUP_DIR"

# === CLEAN UP OLD BACKUPS ===
cleanup_old_backups

# === CLEAN BUILD ENVIRONMENT ===
clean_build_environment

# === UPDATE REPO ===
info "Downloading latest version..."

# Function to check network connectivity
check_network_connectivity() {
    info "Checking network connectivity..."
    
    # Test basic internet connectivity using HTTP instead of ping
    # Many networks block ICMP ping but allow HTTP traffic
    if curl -s --connect-timeout 10 --max-time 15 "http://www.google.com" > /dev/null 2>&1; then
        log "Basic internet connectivity confirmed via HTTP"
    elif wget --timeout=10 --tries=1 -q --spider "http://www.google.com" 2>&1; then
        log "Basic internet connectivity confirmed via wget"
    else
        # Try HTTPS as fallback
        if curl -s --connect-timeout 10 --max-time 15 "https://www.google.com" > /dev/null 2>&1; then
            log "Basic internet connectivity confirmed via HTTPS"
        elif wget --timeout=10 --tries=1 -q --spider "https://www.google.com" 2>&1; then
            log "Basic internet connectivity confirmed via wget HTTPS"
        else
            # Try DNS resolution as another fallback
            if command -v nslookup &>/dev/null && nslookup google.com 8.8.8.8 > /dev/null 2>&1; then
                log "Basic internet connectivity confirmed via DNS lookup"
            elif command -v dig &>/dev/null && dig @8.8.8.8 google.com > /dev/null 2>&1; then
                log "Basic internet connectivity confirmed via dig"
            else
                warn "No internet connectivity detected"
                log "All connectivity tests failed (HTTP, HTTPS, and DNS via curl, wget, nslookup, and dig)"
                return 1
            fi
        fi
    fi
    
    # Test GitHub connectivity using HTTP methods
    if curl -s --connect-timeout 10 --max-time 15 "https://api.github.com" > /dev/null 2>&1; then
        log "GitHub connectivity confirmed via HTTPS API"
    elif wget --timeout=10 --tries=1 -q --spider "https://github.com" 2>&1; then
        log "GitHub connectivity confirmed via wget"
    elif curl -s --connect-timeout 10 --max-time 15 "https://github.com" > /dev/null 2>&1; then
        log "GitHub connectivity confirmed via HTTPS"
    else
        # Try DNS resolution for GitHub as fallback
        if command -v nslookup &>/dev/null && nslookup github.com 8.8.8.8 > /dev/null 2>&1; then
            log "GitHub connectivity confirmed via DNS lookup (HTTP methods failed but DNS works)"
        elif command -v dig &>/dev/null && dig @8.8.8.8 github.com > /dev/null 2>&1; then
            log "GitHub connectivity confirmed via dig (HTTP methods failed but DNS works)"
        else
            warn "Cannot reach GitHub servers via HTTP methods or DNS"
            log "GitHub connectivity test failed - but this might be due to network restrictions"
            # Don't fail here as the main git operations might still work
            log "Continuing with update as basic internet connectivity was confirmed"
        fi
    fi
    
    return 0
}

# Function to check git configuration
check_git_configuration() {
    info "Checking git configuration..."
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir >> "$LOG_FILE" 2>&1; then
        error "Not in a git repository"
        return 1
    fi
    
    # Check git remote configuration
    local remote_url=$(git remote get-url origin 2>/dev/null)
    if [ -z "$remote_url" ]; then
        warn "No git remote 'origin' configured"
        log "Adding origin remote"
        if git remote add origin "https://github.com/dismaster/refurbminer.git" >> "$LOG_FILE" 2>&1; then
            log "Added origin remote successfully"
        else
            error "Failed to add origin remote"
            return 1
        fi
    else
        log "Git remote origin: $remote_url"
        # Ensure it's the correct URL
        if [[ "$remote_url" != *"dismaster/refurbminer"* ]]; then
            warn "Incorrect remote URL detected, updating..."
            if git remote set-url origin "https://github.com/dismaster/refurbminer.git" >> "$LOG_FILE" 2>&1; then
                log "Updated remote URL successfully"
            else
                error "Failed to update remote URL"
                return 1
            fi
        fi
    fi
    
    return 0
}

# Function to attempt git update with multiple strategies
attempt_git_update() {
    local update_success=false
    
    # First, explicitly remove the problematic file
    if [ -f "$REPO_DIR/apps/ccminer/config.json" ]; then
        rm -f "$REPO_DIR/apps/ccminer/config.json" >> "$LOG_FILE" 2>&1
        log "Removed problematic config.json file"
    fi
    
    # Strategy 1: Standard git pull
    info "Attempting standard git pull..."
    if git pull origin master >> "$LOG_FILE" 2>&1; then
        update_success=true
        log "Standard git pull succeeded"
    else
        warn "Standard git pull failed, trying alternative methods..."
        log "Standard git pull failed with exit code $?"
        
        # Strategy 2: Clean and fetch/reset
        info "Trying clean and reset approach..."
        git clean -fd >> "$LOG_FILE" 2>&1
        git reset --hard HEAD >> "$LOG_FILE" 2>&1
        
        if git fetch origin >> "$LOG_FILE" 2>&1; then
            log "Git fetch succeeded"
            if git reset --hard origin/master >> "$LOG_FILE" 2>&1; then
                update_success=true
                log "Git reset to origin/master succeeded"
            else
                log "Git reset failed with exit code $?"
            fi
        else
            log "Git fetch failed with exit code $?"
        fi
        
        # Strategy 3: Force checkout
        if [ "$update_success" = false ]; then
            warn "Trying force checkout..."
            if git fetch origin >> "$LOG_FILE" 2>&1; then
                if git checkout -f origin/master >> "$LOG_FILE" 2>&1; then
                    update_success=true
                    log "Force checkout succeeded"
                else
                    log "Force checkout failed with exit code $?"
                fi
            fi
        fi
        
        # Strategy 4: Re-clone if all else fails
        if [ "$update_success" = false ]; then
            warn "All git update methods failed. Attempting to re-clone repository..."
            
            # Move current directory to backup location
            local repo_backup="${REPO_DIR}_failed_$(date +%Y%m%d%H%M%S)"
            if mv "$REPO_DIR" "$repo_backup" >> "$LOG_FILE" 2>&1; then
                log "Moved failed repository to $repo_backup"
                
                # Try to clone fresh
                if git clone "https://github.com/dismaster/refurbminer.git" "$REPO_DIR" >> "$LOG_FILE" 2>&1; then
                    update_success=true
                    log "Fresh clone succeeded"
                    
                    # Navigate back to the repo directory
                    cd "$REPO_DIR" || { error "Failed to enter new repository directory"; return 1; }
                    
                    # Copy back important files from backup
                    if [ -f "$repo_backup/.env" ]; then
                        cp "$repo_backup/.env" "$REPO_DIR/.env" >> "$LOG_FILE" 2>&1
                        log "Restored .env from failed repo"
                    fi
                    
                    if [ -d "$repo_backup/apps" ]; then
                        cp -rf "$repo_backup/apps" "$REPO_DIR/" >> "$LOG_FILE" 2>&1
                        log "Restored apps directory from failed repo"
                    fi
                    
                    if [ -d "$repo_backup/config" ]; then
                        cp -rf "$repo_backup/config" "$REPO_DIR/" >> "$LOG_FILE" 2>&1
                        log "Restored config directory from failed repo"
                    fi
                else
                    log "Fresh clone also failed with exit code $?"
                    # Restore original directory
                    mv "$repo_backup" "$REPO_DIR" >> "$LOG_FILE" 2>&1
                    log "Restored original repository directory"
                    cd "$REPO_DIR" || { error "Failed to return to repository directory"; return 1; }
                fi
            else
                log "Failed to backup current repository"
            fi
        fi
    fi
    
    if [ "$update_success" = true ]; then
        return 0
    else
        return 1
    fi
}

# Perform network connectivity check
if ! check_network_connectivity; then
    error "Network connectivity issues detected. Please check your internet connection."
    echo
    echo -e "\033[1;36mTroubleshooting network issues:\033[0m"
    echo -e "\033[1;33m• Test connectivity manually: curl -s https://www.google.com\033[0m"
    echo -e "\033[1;33m• Or try: wget --spider https://github.com\033[0m"
    echo -e "\033[1;33m• Test DNS resolution: nslookup google.com 8.8.8.8\033[0m"
    echo -e "\033[1;33m• If using mobile data, ensure data is enabled\033[0m"
    echo -e "\033[1;33m• If using WiFi, check if you need to authenticate\033[0m"
    echo -e "\033[1;33m• Some networks block certain traffic - try different network\033[0m"
    echo -e "\033[1;33m• Try running the update script again in a few minutes\033[0m"
    echo -e "\033[1;33m• Check $LOG_FILE for detailed network diagnostics\033[0m"
    exit 1
fi

# Check git configuration
if ! check_git_configuration; then
    error "Git repository configuration issues detected."
    echo -e "\033[1;36mTry these git troubleshooting steps:\033[0m"
    echo -e "\033[1;33m• Check if you're in the right directory: pwd\033[0m"
    echo -e "\033[1;33m• Verify git repository: git status\033[0m"
    echo -e "\033[1;33m• Check git remote: git remote -v\033[0m"
    echo -e "\033[1;33m• Check $LOG_FILE for detailed git diagnostics\033[0m"
    exit 1
fi

# Attempt the git update
if attempt_git_update; then
    success "Downloaded latest version"
else
    error "Failed to download latest version after trying multiple methods."
    echo
    echo -e "\033[1;31mThis could be due to:\033[0m"
    echo -e "\033[1;31m  • Temporary network issues\033[0m"
    echo -e "\033[1;31m  • GitHub server problems\033[0m"
    echo -e "\033[1;31m  • Git repository corruption\033[0m"
    echo -e "\033[1;31m  • Local file permission problems\033[0m"
    echo
    echo -e "\033[1;36mManual recovery options:\033[0m"
    echo -e "\033[1;33m1. Wait a few minutes and try again\033[0m"
    echo -e "\033[1;33m2. Check detailed logs: cat $LOG_FILE\033[0m"
    echo -e "\033[1;33m3. Try manually: cd $REPO_DIR && git pull origin master\033[0m"
    echo -e "\033[1;33m4. Check network: ping github.com\033[0m"
    echo -e "\033[1;33m5. If all else fails, backup your config and reinstall RefurbMiner\033[0m"
    exit 1
fi

# === RESTORE IMPORTANT FILES ===
info "Restoring your personal settings..."

# Restore .env file
if [ -f "$BACKUP_DIR/.env" ]; then
    cp -f "$BACKUP_DIR/.env" "$REPO_DIR/.env" > /dev/null 2>&1
    log "Restored .env file"
fi

# Restore config/config.json
if [ -f "$BACKUP_DIR/config/config.json" ]; then
    mkdir -p "$REPO_DIR/config" > /dev/null 2>&1
    cp -f "$BACKUP_DIR/config/config.json" "$REPO_DIR/config/config.json" > /dev/null 2>&1
    log "Restored config/config.json"
fi

# Restore apps folder
if [ -d "$BACKUP_DIR/apps" ]; then
    mkdir -p "$REPO_DIR/apps" > /dev/null 2>&1
    cp -rf "$BACKUP_DIR/apps/"* "$REPO_DIR/apps/" > /dev/null 2>&1
    log "Restored apps directory"
fi

success "Personal settings restored"

# Download utility scripts from the repository
info "Updating utility scripts..."
wget -q -O "$REPO_DIR/start.sh" "https://raw.githubusercontent.com/dismaster/refurbminer/refs/heads/master/start.sh" > /dev/null 2>&1
wget -q -O "$REPO_DIR/stop.sh" "https://raw.githubusercontent.com/dismaster/refurbminer/refs/heads/master/stop.sh" > /dev/null 2>&1
wget -q -O "$REPO_DIR/status.sh" "https://raw.githubusercontent.com/dismaster/refurbminer/refs/heads/master/status.sh" > /dev/null 2>&1

# Make all scripts executable
chmod +x "$REPO_DIR/start.sh" "$REPO_DIR/stop.sh" "$REPO_DIR/status.sh" > /dev/null 2>&1
success "Utility scripts updated"

# === INSTALL DEPENDENCIES ===
info "Installing updates (this may take a while)..."
if run_with_output "npm install" "Dependency installation"; then
    success "Updates installed"
else
    error "Update installation failed!"
    exit 1
fi

# === BUILD APPLICATION ===
info "Preparing application for use (please wait)..."
if attempt_build; then
    success "Application prepared successfully"
else
    error "Application preparation failed after multiple attempts!"
    error "The application may still work, attempting to continue..."
fi

# === VALIDATE INSTALLATION ===
validate_installation

# === START APPLICATION ===
info "Starting mining process..."

# Function to check if port 3000 is available
check_port_availability() {
    local port=3000
    local max_attempts=12  # Wait up to 1 minute (12 * 5 seconds)
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # Check if port is in use
        if ! (lsof -ti:$port 2>/dev/null > /dev/null || netstat -tln 2>/dev/null | grep ":$port " > /dev/null); then
            log "Port $port is available"
            return 0
        fi
        
        if [ $attempt -eq 1 ]; then
            warn "Port $port is still in use, waiting for it to become available..."
        fi
        
        log "Attempt $attempt/$max_attempts: Port $port still in use, waiting 5 seconds..."
        sleep 5
        attempt=$((attempt + 1))
    done
    
    error "Port $port is still in use after waiting. Cannot start RefurbMiner."
    return 1
}

# Check port availability before starting
if ! check_port_availability; then
    error "Cannot start RefurbMiner because port 3000 is still in use."
    echo
    echo -e "\033[1;36mTroubleshooting steps:\033[0m"
    echo -e "\033[1;33m• Wait a few more minutes and try running the update again\033[0m"
    echo -e "\033[1;33m• Check what's using port 3000: lsof -ti:3000\033[0m"
    echo -e "\033[1;33m• Manually kill processes: kill -9 \$(lsof -ti:3000)\033[0m"
    echo -e "\033[1;33m• Restart your device if the issue persists\033[0m"
    exit 1
fi

if screen -dmS "$SCREEN_NAME" bash -c "cd '$REPO_DIR' && npm start" > /dev/null 2>&1; then
    success "Mining process started"
    # Give it a moment to start up, then check if it's actually running
    sleep 5
    if screen -list | grep -q "$SCREEN_NAME"; then
        # Additional check: verify the process is actually working
        sleep 3
        if lsof -ti:3000 2>/dev/null > /dev/null || netstat -tln 2>/dev/null | grep ":3000 " > /dev/null; then
            success "Mining process is running successfully on port 3000"
        else
            warn "Mining process started but may not be listening on port 3000"
            info "Check the logs with: screen -r $SCREEN_NAME"
        fi
    else
        warn "Mining process may have failed to start properly"
        info "Check the logs with: screen -r $SCREEN_NAME"
    fi
else
    error "Failed to start mining process!"
    exit 1
fi

# === SEND UPDATE NOTIFICATION ===
info "Sending update notification..."

# Try to extract miner ID from config first (since this is the most reliable source)
MINER_ID=""
if [ -f "$REPO_DIR/config/config.json" ]; then
    # Use a more robust JSON parsing approach
    MINER_ID=$(grep -o '"minerId"[[:space:]]*:[[:space:]]*"[^"]*"' "$REPO_DIR/config/config.json" 2>/dev/null | head -1 | cut -d '"' -f4)
fi

# For debugging purposes, log what we found
if [ -n "$MINER_ID" ]; then
    info "Found miner ID: $MINER_ID"
else
    warn "Could not find miner ID in any configuration file"
fi

# Get current version from package.json
CURRENT_VERSION=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$REPO_DIR/package.json" 2>/dev/null | head -1 | cut -d '"' -f4)

# If we couldn't determine versions, use defaults
if [ -z "$CURRENT_VERSION" ]; then
    CURRENT_VERSION="unknown"
fi

if [ -z "$PREVIOUS_VERSION" ]; then
    PREVIOUS_VERSION="unknown"
fi

# Only send notification if we have a miner ID
if [ -n "$MINER_ID" ]; then
    # Send update notification to API
    curl -s -X POST "http://api.refurbminer.de/api/miners/error" \
    -H "Content-Type: application/json" \
    -d '{
      "minerId": "'"$MINER_ID"'",
      "message": "Software update completed successfully",
      "additionalInfo": {
        "updateType": "software",
        "status": "completed",
        "version": "'"$CURRENT_VERSION"'", 
        "updatedComponents": ["mining-engine"],
        "updateTime": "'"$(date -u +"%Y-%m-%dT%H:%M:%SZ")"'",
        "previousVersion": "'"$PREVIOUS_VERSION"'"
      }
    }' > /dev/null 2>&1
    
    success "Update notification sent"
else
    warn "Could not send update notification - miner ID not found"
fi

log "=== RefurbMiner Update Completed Successfully ==="
success "🎉 RefurbMiner updated and running!"
echo
echo -e "\033[1;32mTo view mining status: screen -r refurbminer\033[0m"
echo -e "\033[1;33mTo detach from mining view: press Ctrl+A then D\033[0m"
echo -e "\033[1;32mOr use: ./refurbminer/status.sh\033[0m"
echo
echo -e "\033[1;36mTroubleshooting:\033[0m"
echo -e "\033[1;33m• If mining doesn't start: check $LOG_FILE for errors\033[0m"
echo -e "\033[1;33m• To manually restart: ./refurbminer/stop.sh && ./refurbminer/start.sh\033[0m"
echo -e "\033[1;33m• If port 3000 is busy: killall screen && killall node\033[0m"
echo -e "\033[1;33m• For complete cleanup: pkill -f refurbminer && screen -wipe\033[0m"
echo -e "\033[1;33m• For support: check https://gui.refurbminer.de\033[0m"
