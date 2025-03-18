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

# === PROTECT LOCAL FILES ===
info "Protecting important local files from overwrites..."
SKIP_ALL_FILES=("${SKIP_FILES[@]}")
for folder in "${SKIP_FOLDERS[@]}"; do
    mapfile -t folder_files < <(git ls-files "$folder")
    SKIP_ALL_FILES+=("${folder_files[@]}")
done
git update-index --skip-worktree "${SKIP_ALL_FILES[@]}" &>/dev/null
success "Local files are protected."

# === UPDATE REPO ===
info "Pulling latest updates..."
git fetch origin &>/dev/null
if git pull origin master | grep -q 'Already up to date.'; then
    success "Repository already up to date."
else
    success "Repository updated successfully."
fi

# === INSTALL DEPENDENCIES ===
info "Installing npm dependencies (this may take a while)..."
if npm install --silent &>/dev/null; then
    success "Dependencies installed."
else
    error "Dependency installation failed!"
    exit 1
fi

# === BUILD APPLICATION ===
info "Building the application (this may take a moment)..."
if npm run build --silent &>/dev/null; then
    success "Application built successfully."
else
    error "Build process failed!"
    exit 1
fi

# === START APPLICATION ===
info "Launching '$SCREEN_NAME' in a detached screen session..."
if screen -dmS "$SCREEN_NAME" bash -c 'npm start'; then
    success "'$SCREEN_NAME' is running!"
else
    error "Failed to launch screen session!"
    exit 1
fi

success "🎉 refurbminer update complete!"
