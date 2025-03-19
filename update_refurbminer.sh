#!/bin/bash

# === CONFIGURATION ===
REPO_DIR="$HOME/refurbminer"
SCREEN_NAME="refurbminer"

# Helper functions for friendly output
info()    { echo -e "\033[1;34mℹ️  $1\033[0m"; }
success() { echo -e "\033[1;32m✅ $1\033[0m"; }
error()   { echo -e "\033[1;31m❌ $1\033[0m"; }
warn()    { echo -e "\033[1;33m⚠️  $1\033[0m"; }

info "Starting refurbminer update..."

# === NAVIGATE TO REPO ===
cd "$REPO_DIR" || { error "Repo directory not found!"; exit 1; }

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
# Create backup folder with timestamp
BACKUP_DIR="$REPO_DIR/backup_$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR" > /dev/null 2>&1

# Backup .env file directly
if [ -f "$REPO_DIR/.env" ]; then
    cp "$REPO_DIR/.env" "$BACKUP_DIR/.env" > /dev/null 2>&1
fi

# Backup config/config.json
if [ -f "$REPO_DIR/config/config.json" ]; then
    mkdir -p "$BACKUP_DIR/config" > /dev/null 2>&1
    cp "$REPO_DIR/config/config.json" "$BACKUP_DIR/config/config.json" > /dev/null 2>&1
fi

# Backup apps directory
if [ -d "$REPO_DIR/apps" ]; then
    cp -r "$REPO_DIR/apps" "$BACKUP_DIR/" > /dev/null 2>&1
fi

success "Backup created"

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
    cp "$BACKUP_DIR/.env" "$REPO_DIR/.env" > /dev/null 2>&1
fi

# Restore config/config.json
if [ -f "$BACKUP_DIR/config/config.json" ]; then
    mkdir -p "$REPO_DIR/config" > /dev/null 2>&1
    cp "$BACKUP_DIR/config/config.json" "$REPO_DIR/config/config.json" > /dev/null 2>&1
fi

# Restore apps folder
if [ -d "$BACKUP_DIR/apps" ]; then
    mkdir -p "$REPO_DIR/apps" > /dev/null 2>&1
    cp -r "$BACKUP_DIR/apps/"* "$REPO_DIR/apps/" > /dev/null 2>&1
fi

success "Personal settings restored"

# Make all scripts executable
run_silent chmod +x "$REPO_DIR/start.sh" "$REPO_DIR/stop.sh" "$REPO_DIR/status.sh"

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

success "🎉 RefurbMiner updated and running!"
echo
echo -e "\033[1;32mTo view mining status: screen -r refurbminer\033[0m"
echo -e "\033[1;33mTo detach from mining view: press Ctrl+A then D\033[0m"
