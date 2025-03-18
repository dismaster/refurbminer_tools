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

info "Starting refurbminer update..."

# === NAVIGATE TO REPO ===
cd "$REPO_DIR" || { error "Repo directory not found!"; exit 1; }

# === STOP EXISTING SCREEN SESSION ===
info "Stopping existing screen session '$SCREEN_NAME'..."
if screen -list | grep -q "$SCREEN_NAME"; then
    screen -S "$SCREEN_NAME" -X quit && sleep 2
    success "Stopped existing session '$SCREEN_NAME'."
else
    warn "No active screen session '$SCREEN_NAME' found."
fi

# === BACKUP IMPORTANT FILES ===
info "Backing up config files..."
# Create backup folder
BACKUP_DIR="$REPO_DIR/backup_$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup important configuration files
for file in "${SKIP_FILES[@]}"; do
    if [ -f "$REPO_DIR/$file" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$file")"
        cp -f "$REPO_DIR/$file" "$BACKUP_DIR/$file"
        success "Backed up $file"
    fi
done

# Backup entire app folders
for folder in "${SKIP_FOLDERS[@]}"; do
    if [ -d "$REPO_DIR/$folder" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$folder")"
        cp -rf "$REPO_DIR/$folder" "$BACKUP_DIR/$(dirname "$folder")"
        success "Backed up $folder"
    fi
done

# === HANDLE LOCAL CHANGES MORE AGGRESSIVELY ===
info "Handling local changes to allow update..."

# First, explicitly remove the problematic file
if [ -f "$REPO_DIR/apps/ccminer/config.json" ]; then
    rm -f "$REPO_DIR/apps/ccminer/config.json"
    info "Removed apps/ccminer/config.json to prevent conflicts"
fi

# Reset and clean
git reset --hard HEAD
git clean -fd

# === UPDATE REPO ===
info "Pulling latest updates..."
if git pull origin master; then
    success "Repository updated successfully."
else
    # If pull still fails, try more aggressive approach
    warn "Standard pull failed. Trying alternative approach..."
    
    # Fetch updates but don't apply them yet
    git fetch origin
    
    # Force checkout of master branch, overwriting local changes
    if git checkout -f origin/master; then
        success "Repository updated successfully using alternative method."
    else
        error "Failed to update repository. Check your internet connection."
        # Restore from backup if the update fails
        info "Restoring from backup..."
        for file in "${SKIP_FILES[@]}"; do
            if [ -f "$BACKUP_DIR/$file" ]; then
                mkdir -p "$REPO_DIR/$(dirname "$file")"
                cp -f "$BACKUP_DIR/$file" "$REPO_DIR/$file"
            fi
        done
        for folder in "${SKIP_FOLDERS[@]}"; do
            if [ -d "$BACKUP_DIR/$folder" ]; then
                cp -rf "$BACKUP_DIR/$folder" "$REPO_DIR/$(dirname "$folder")"
            fi
        done
        success "Restored previous configuration"
        exit 1
    fi
fi

# === RESTORE IMPORTANT FILES ===
info "Restoring config files..."
for file in "${SKIP_FILES[@]}"; do
    if [ -f "$BACKUP_DIR/$file" ]; then
        mkdir -p "$REPO_DIR/$(dirname "$file")"
        cp -f "$BACKUP_DIR/$file" "$REPO_DIR/$file"
        success "Restored $file"
    fi
done

# Restore app folders
for folder in "${SKIP_FOLDERS[@]}"; do
    if [ -d "$BACKUP_DIR/$folder" ]; then
        # Make sure the destination directory exists
        mkdir -p "$REPO_DIR/$folder"
        
        # Copy all contents from backup to the repo
        cp -rf "$BACKUP_DIR/$folder"* "$REPO_DIR/$folder"
        success "Restored $folder contents"
    fi
done

# === INSTALL DEPENDENCIES ===
info "Installing npm dependencies (this may take a while)..."
if npm install; then
    success "Dependencies installed."
else
    error "Dependency installation failed!"
    exit 1
fi

# === BUILD APPLICATION ===
info "Building the application (this may take a moment)..."
if npm run build; then
    success "Application built successfully."
else
    error "Build process failed!"
    exit 1
fi

# === START APPLICATION ===
info "Launching '$SCREEN_NAME' in a detached screen session..."
if screen -dmS "$SCREEN_NAME" bash -c 'cd "$REPO_DIR" && npm start'; then
    success "'$SCREEN_NAME' is running!"
else
    error "Failed to launch screen session!"
    exit 1
fi

success "🎉 refurbminer update complete!"
