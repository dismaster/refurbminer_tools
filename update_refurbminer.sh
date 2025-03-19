#!/bin/bash

# === CONFIGURATION ===
REPO_DIR="$HOME/refurbminer"
SCREEN_NAME="refurbminer"
# Store backup outside of the git repo to prevent it being cleaned
BACKUP_DIR="$HOME/refurbminer_backup_$(date +%Y%m%d%H%M%S)"
# Configure maximum number of backup folders to keep
MAX_BACKUPS=3

# Helper functions for friendly output
info()    { echo -e "\033[1;34mℹ️  $1\033[0m"; }
success() { echo -e "\033[1;32m✅ $1\033[0m"; }
error()   { echo -e "\033[1;31m❌ $1\033[0m"; }
warn()    { echo -e "\033[1;33m⚠️  $1\033[0m"; }

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

info "Starting refurbminer update..."

# === NAVIGATE TO REPO ===
cd "$REPO_DIR" || { error "Repo directory not found!"; exit 1; }

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
if screen -list | grep -q "$SCREEN_NAME"; then
    info "Stopping existing session '$SCREEN_NAME'..."
    screen -S "$SCREEN_NAME" -X quit > /dev/null 2>&1
    sleep 2
    success "Stopped mining session"
else
    info "No active mining session found"
fi

# === BACKUP IMPORTANT FILES ===
info "Creating backup of your configuration..."
# Create backup folder OUTSIDE the git repo
mkdir -p "$BACKUP_DIR" > /dev/null 2>&1

# Backup .env file
if [ -f "$REPO_DIR/.env" ]; then
    cp -f "$REPO_DIR/.env" "$BACKUP_DIR/.env" > /dev/null 2>&1
fi

# Backup config/config.json
if [ -f "$REPO_DIR/config/config.json" ]; then
    mkdir -p "$BACKUP_DIR/config" > /dev/null 2>&1
    cp -f "$REPO_DIR/config/config.json" "$BACKUP_DIR/config/config.json" > /dev/null 2>&1
fi

# Backup apps directory
if [ -d "$REPO_DIR/apps" ]; then
    cp -rf "$REPO_DIR/apps" "$BACKUP_DIR/" > /dev/null 2>&1
fi

# Backup package.json for version tracking
if [ -f "$REPO_DIR/package.json" ]; then
    cp -f "$REPO_DIR/package.json" "$BACKUP_DIR/package.json" > /dev/null 2>&1
fi

success "Backup created"

# === CLEAN UP OLD BACKUPS ===
cleanup_old_backups

# === UPDATE REPO ===
info "Downloading latest version..."
# First, explicitly remove the problematic file
if [ -f "$REPO_DIR/apps/ccminer/config.json" ]; then
    rm -f "$REPO_DIR/apps/ccminer/config.json" > /dev/null 2>&1
fi

# Reset and clean repository
git reset --hard HEAD > /dev/null 2>&1
git clean -fd > /dev/null 2>&1

# Try standard pull first
if git pull origin master > /dev/null 2>&1; then
    success "Downloaded latest version"
else
    # If standard pull fails, try more aggressive approach
    info "Using alternative download method..."
    git fetch origin > /dev/null 2>&1
    if git checkout -f origin/master > /dev/null 2>&1; then
        success "Downloaded latest version"
    else
        error "Update failed. Check your internet connection."
        exit 1
    fi
fi

# === RESTORE IMPORTANT FILES ===
info "Restoring your personal settings..."

# Restore .env file
if [ -f "$BACKUP_DIR/.env" ]; then
    cp -f "$BACKUP_DIR/.env" "$REPO_DIR/.env" > /dev/null 2>&1
fi

# Restore config/config.json
if [ -f "$BACKUP_DIR/config/config.json" ]; then
    mkdir -p "$REPO_DIR/config" > /dev/null 2>&1
    cp -f "$BACKUP_DIR/config/config.json" "$REPO_DIR/config/config.json" > /dev/null 2>&1
fi

# Restore apps folder
if [ -d "$BACKUP_DIR/apps" ]; then
    mkdir -p "$REPO_DIR/apps" > /dev/null 2>&1
    cp -rf "$BACKUP_DIR/apps/"* "$REPO_DIR/apps/" > /dev/null 2>&1
fi

success "Personal settings restored"

# Download utility scripts from the repository
wget -q -O "$REPO_DIR/start.sh" "https://raw.githubusercontent.com/dismaster/refurbminer/refs/heads/master/start.sh" > /dev/null 2>&1
wget -q -O "$REPO_DIR/stop.sh" "https://raw.githubusercontent.com/dismaster/refurbminer/refs/heads/master/stop.sh" > /dev/null 2>&1
wget -q -O "$REPO_DIR/status.sh" "https://raw.githubusercontent.com/dismaster/refurbminer/refs/heads/master/status.sh" > /dev/null 2>&1

# Make all scripts executable
chmod +x "$REPO_DIR/start.sh" "$REPO_DIR/stop.sh" "$REPO_DIR/status.sh" > /dev/null 2>&1

# === INSTALL DEPENDENCIES ===
info "Installing updates (this may take a while)..."
if npm install > /dev/null 2>&1; then
    success "Updates installed"
else
    error "Update installation failed!"
    exit 1
fi

# === BUILD APPLICATION ===
info "Preparing application for use (please wait)..."
if npm run build > /dev/null 2>&1; then
    success "Application prepared successfully"
else
    error "Application preparation failed!"
    exit 1
fi

# === START APPLICATION ===
info "Starting mining process..."
if screen -dmS "$SCREEN_NAME" bash -c "cd '$REPO_DIR' && npm start" > /dev/null 2>&1; then
    success "Mining process started"
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

success "🎉 RefurbMiner updated and running!"
echo
echo -e "\033[1;32mTo view mining status: screen -r refurbminer\033[0m"
echo -e "\033[1;33mTo detach from mining view: press Ctrl+A then D\033[0m"
echo -e "\033[1;32mOr use: ./refurbminer/status.sh\033[0m"
