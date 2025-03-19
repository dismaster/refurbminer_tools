#!/bin/bash

# RefurbMiner Upgrade Script
# This script helps users transition from the old setup to the new RefurbMiner

# === Color definitions ===
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ANSI color codes for banner formatting
LC='\033[1;36m'  # Light Cyan
LP='\033[1;35m'  # Light Purple
LG='\033[1;32m'  # Light Green
LY='\033[1;33m'  # Light Yellow

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Display function for user-facing messages
display() {
    echo -e "${BLUE}$1${NC}"
}

# Display success messages
success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Display warning messages
warn() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

# Display error messages
error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to display banner
display_banner() {
    clear
    echo -e "${LC} ___             __         __ __${NC}"
    echo -e "${LC}|   .-----.-----|  |_.---.-|  |  .-----.----.${NC}"
    echo -e "${LC}|.  |     |__ --|   _|  _  |  |  |  -__|   _|${NC}"
    echo -e "${LC}|.  |__|__|_____|____|___._|__|__|_____|__|${NC}  "
    echo -e "${LC}|:  | Developer ~ ${LP}@Ch3ckr${NC}"
    echo -e "${LC}|::.| Tool      ~ ${LG}RefurbMiner Upgrade Tool${NC}"
    echo -e "${LC}'---' For More  ~ ${LY}https://gui.refurbminer.de${NC}"
    echo  # New line for spacing
    echo -e "${RED}->${NC} ${LC}RefurbMiner Upgrade Process${NC}"
    echo  # New line for spacing
}

display_banner

# === Step 1: Stop any running miners ===
display "Step 1: Stopping any running miners..."

# Check for running CCminer instances
if screen -list | grep -q "CCminer"; then
    display "Found CCminer instance. Stopping it..."
    screen -S CCminer -X quit
    sleep 2
    success "CCminer stopped"
else
    display "No CCminer instance found"
fi

# Check for running RefurbMiner instances
if screen -list | grep -q "refurbminer"; then
    display "Found RefurbMiner instance. Stopping it..."
    screen -S refurbminer -X quit
    sleep 2
    success "RefurbMiner stopped"
else
    display "No RefurbMiner instance found"
fi

# Check for Scheduler
if screen -list | grep -q "Scheduler"; then
    display "Found Scheduler instance. Stopping it..."
    screen -S Scheduler -X quit
    sleep 1
    success "Scheduler stopped"
fi

# === Step 2: Backup important configuration ===
display "Step 2: Backing up important configuration..."

# Create backup directory
BACKUP_DIR="$HOME/refurbminer_backup_$(date '+%Y%m%d%H%M%S')"
mkdir -p "$BACKUP_DIR"

# Backup rig.conf if it exists
if [ -f "$HOME/rig.conf" ]; then
    cp "$HOME/rig.conf" "$BACKUP_DIR/"
    success "Backed up rig.conf"
fi

# Backup ccminer config if it exists
if [ -f "$HOME/ccminer/config.json" ]; then
    mkdir -p "$BACKUP_DIR/ccminer"
    cp "$HOME/ccminer/config.json" "$BACKUP_DIR/ccminer/"
    success "Backed up ccminer config"
fi

# Backup Termux boot_start if it exists
if [ -f "$HOME/.termux/boot/boot_start" ]; then
    mkdir -p "$BACKUP_DIR/.termux/boot"
    cp "$HOME/.termux/boot/boot_start" "$BACKUP_DIR/.termux/boot/"
    success "Backed up Termux boot_start file"
fi

display "Configuration backed up to $BACKUP_DIR"

# === Step 3: Clean up old crontab entries ===
display "Step 3: Cleaning up old crontab entries..."

# Remove ALL old crontab entries related to mining
crontab -l > /tmp/crontab.tmp 2>/dev/null || touch /tmp/crontab.tmp
grep -v "jobscheduler.sh" /tmp/crontab.tmp | grep -v "monitor.sh" | grep -v "ccminer" | grep -v "refurbminer" | grep -v "@reboot.*ccminer" > /tmp/clean_crontab.tmp
crontab /tmp/clean_crontab.tmp
rm /tmp/crontab.tmp /tmp/clean_crontab.tmp

success "Cleaned up all mining-related crontab entries"

# === Step 4: Clean up old files ===
display "Step 4: Cleaning up old files..."

# Remove Termux boot_start if it exists
if [ -f "$HOME/.termux/boot/boot_start" ]; then
    rm "$HOME/.termux/boot/boot_start"
    display "Removed Termux boot_start file"
fi

# List of files to remove
OLD_FILES=(
    "$HOME/jobscheduler.sh"
    "$HOME/monitor.sh"
    "$HOME/rg3d_cpu.sh"
    "$HOME/schedule_job.sh"
    "$HOME/vcgencmd"
    "$HOME/clean_rig_conf.sh"
    "$HOME/locator.sh"
    "$HOME/cpu_check_arm"
)

# Remove old files if they exist
for file in "${OLD_FILES[@]}"; do
    if [ -f "$file" ]; then
        rm "$file"
        display "Removed $file"
    fi
done

# Remove existing ccminer folder
if [ -d "$HOME/ccminer" ]; then
    display "Removing existing ccminer folder..."
    rm -rf "$HOME/ccminer"
    success "Removed ccminer folder"
fi

# Remove existing ccminer_build folder if it exists
if [ -d "$HOME/ccminer_build" ]; then
    display "Removing existing ccminer_build folder..."
    rm -rf "$HOME/ccminer_build"
    success "Removed ccminer_build folder"
fi

# Remove existing refurbminer folder if it exists
if [ -d "$HOME/refurbminer" ]; then
    display "Removing existing refurbminer folder..."
    rm -rf "$HOME/refurbminer"
    success "Removed refurbminer folder"
fi

success "Cleaned up old files"

# === Step 5: Download and run new installer ===
display "Step 5: Downloading and running new installer..."

# Download new installer
wget -q -O "$HOME/install_refurbminer.sh" "https://raw.githubusercontent.com/dismaster/refurbminer_tools/main/install_refurbminer.sh"
chmod +x "$HOME/install_refurbminer.sh"

if [ ! -f "$HOME/install_refurbminer.sh" ]; then
    error "Failed to download new installer. Please check your internet connection."
    exit 1
fi

success "New installer downloaded successfully"

# Run new installer
display "Running new installer..."
echo -e "\n${GREEN}The new installer will now start. You will be asked to enter a new RIG token.${NC}"
echo -e "${YELLOW}Note: Your old rig password is NOT the same as the new RIG token.${NC}"
echo -e "${YELLOW}You'll need to obtain a new RIG token from the RefurbMiner website.${NC}\n"
sleep 3

# Execute the new installer
bash "$HOME/install_refurbminer.sh"

# Clean up installer after completion
rm "$HOME/install_refurbminer.sh"

echo
echo -e "${GREEN}Upgrade process completed!${NC}"
echo -e "${BLUE}Your previous configuration has been backed up to:${NC} $BACKUP_DIR"
echo