#!/bin/bash

# === CONFIGURATION ===
REPO_DIR="$HOME/refurbminer"
SCREEN_NAME="refurbminer"
SKIP_FILES=(".env" "config/config.json")
SKIP_FOLDERS=("apps/")

# Helper functions for friendly output
info()    { echo -e "\033[1;34mℹ️  $1\033[0m"; }
success() { echo -e "\033[1;32m✅ $1\033[0m"; }
error()   { echo -e "\033[1;31m❌ $1\033[0m"; }
warn()    { echo -e "\033[1;33m⚠️  $1\033[0m"; }

# Run command silently with progress indication
run_silent() {
    local msg="$1"
    shift
    
    info "$msg"
    if "$@" > /dev/null 2>&1; then
        success "$msg completed"
        return 0
    else
        error "$msg failed"
        return 1
    fi
}

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
# Create backup folder
BACKUP_DIR="$REPO_DIR/backup_$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR" > /dev/null 2>&1

# Backup important configuration files
for file in "${SKIP_FILES[@]}"; do
    if [ -f "$REPO_DIR/$file" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$file")" > /dev/null 2>&1
        cp -f "$REPO_DIR/$file" "$BACKUP_DIR/$file" > /dev/null 2>&1
    fi
done

# Backup entire app folders
for folder in "${SKIP_FOLDERS[@]}"; do
    if [ -d "$REPO_DIR/$folder" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$folder")" > /dev/null 2>&1
        cp -rf "$REPO_DIR/$folder" "$BACKUP_DIR/$(dirname "$folder")" > /dev/null 2>&1
    fi
done
success "Backup created"

# === HANDLE LOCAL CHANGES MORE AGGRESSIVELY ===
info "Preparing for update..."

# First, explicitly remove the problematic file
if [ -f "$REPO_DIR/apps/ccminer/config.json" ]; then
    rm -f "$REPO_DIR/apps/ccminer/config.json" > /dev/null 2>&1
fi

# Reset and clean (silently)
git reset --hard HEAD > /dev/null 2>&1
git clean -fd > /dev/null 2>&1

# === UPDATE REPO ===
info "Downloading latest version..."
if git pull origin master > /dev/null 2>&1; then
    success "Downloaded latest version"
else
    # If pull still fails, try more aggressive approach
    info "Using alternative download method..."
    
    # Fetch updates but don't apply them yet
    git fetch origin > /dev/null 2>&1
    
    # Force checkout of master branch, overwriting local changes
    if git checkout -f origin/master > /dev/null 2>&1; then
        success "Downloaded latest version"
    else
        error "Update failed. Check your internet connection."
        # Restore from backup if the update fails
        info "Restoring from backup..."
        for file in "${SKIP_FILES[@]}"; do
            if [ -f "$BACKUP_DIR/$file" ]; then
                mkdir -p "$REPO_DIR/$(dirname "$file")" > /dev/null 2>&1
                cp -f "$BACKUP_DIR/$file" "$REPO_DIR/$file" > /dev/null 2>&1
            fi
        done
        for folder in "${SKIP_FOLDERS[@]}"; do
            if [ -d "$BACKUP_DIR/$folder" ]; then
                cp -rf "$BACKUP_DIR/$folder" "$REPO_DIR/$(dirname "$folder")" > /dev/null 2>&1
            fi
        done
        success "Restored previous configuration"
        exit 1
    fi
fi

# === RESTORE IMPORTANT FILES ===
info "Restoring your personal settings..."
for file in "${SKIP_FILES[@]}"; do
    if [ -f "$BACKUP_DIR/$file" ]; then
        mkdir -p "$REPO_DIR/$(dirname "$file")" > /dev/null 2>&1
        cp -f "$BACKUP_DIR/$file" "$REPO_DIR/$file" > /dev/null 2>&1
    fi
done

# Restore app folders
for folder in "${SKIP_FOLDERS[@]}"; do
    if [ -d "$BACKUP_DIR/$folder" ]; then
        # Make sure the destination directory exists
        mkdir -p "$REPO_DIR/$folder" > /dev/null 2>&1
        
        # Copy all contents from backup to the repo
        cp -rf "$BACKUP_DIR/$folder"* "$REPO_DIR/$folder" > /dev/null 2>&1
    fi
done
success "Personal settings restored"

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
