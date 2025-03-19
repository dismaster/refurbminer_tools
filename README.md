# RefurbMiner Tools

![RefurbMiner Logo](https://gui.rg3d.eu/assets/img/logo.png)

A collection of tools for RefurbMiner - the repurposed device miner for VERUS and other cryptocurrencies.

## Overview

This repository contains tools to help with the installation, upgrade, and management of RefurbMiner.

| Tool | Description |
|------|-------------|
| `install_refurbminer.sh` | Fresh installation script for RefurbMiner |
| `upgrade_refurbminer.sh` | Upgrade from older mining setup to RefurbMiner |
| `update_refurbminer.sh` | Update an existing RefurbMiner installation |

## Installation Guide

### ![Termux Setup](images/banner_1.png)

If you're using Termux on Android, you'll need to install some additional apps:

1. Install Termux from F-Droid (recommended) or Google Play Store
2. Install [Termux:Boot](https://f-droid.org/en/packages/com.termux.boot/) - required for auto-starting at boot
3. Install [Termux:API](https://f-droid.org/en/packages/com.termux.api/) - required for device interaction

After installing these apps, you'll need to set up basic permissions:
```bash
# Grant storage permission
termux-setup-storage

# Install required packages
pkg update
pkg install wget curl
```

### ![Fresh Installation](images/banner_2.png)

If you're starting from scratch with a new device, use the installation script:

```bash
# Download the installer
wget -q -O install_refurbminer.sh https://raw.githubusercontent.com/dismaster/refurbminer_tools/main/install_refurbminer.sh

# Make it executable
chmod +x install_refurbminer.sh

# Run the installer
./install_refurbminer.sh
```

During installation, you'll be asked to provide your RIG token. You can obtain this from the [RefurbMiner website](https://gui.refurbminer.de).

### ![Upgrading from Old Version](images/banner_3.png)

If you were using the previous version with CCminer and scripts like `monitor.sh`, `jobscheduler.sh`, etc., you should use the upgrade script to transition to the new RefurbMiner:

```bash
# Download the upgrade script
wget -q -O upgrade_refurbminer.sh https://raw.githubusercontent.com/dismaster/refurbminer_tools/main/upgrade_refurbminer.sh

# Make it executable
chmod +x upgrade_refurbminer.sh

# Run the upgrade script
./upgrade_refurbminer.sh
```

The upgrade script will:
1. Stop any running miners
2. Backup your important configuration files
3. Clean up old crontab entries
4. Remove old script files and folders
5. Download and run the new installer

> **Important Note:** Your old rig password is NOT the same as the new RIG token. You'll need to obtain a new RIG token from the [RefurbMiner website](https://gui.refurbminer.de).

### ![Updating an Existing Installation](images/banner_4.png)

If you already have RefurbMiner installed and want to update to the latest version:

```bash
# If you don't already have the update script
wget -q -O update_refurbminer.sh https://raw.githubusercontent.com/dismaster/refurbminer_tools/main/update_refurbminer.sh
chmod +x update_refurbminer.sh

# Run the update script
./update_refurbminer.sh
```

## ![Supported Devices](images/banner_5.png)

RefurbMiner is designed to work on a variety of 64-bit devices including:

- Android phones and tablets with 64-bit architecture (via Termux)
- Raspberry Pi and other ARM64-based single-board computers
- x86_64 desktop and laptop computers
- Various 64-bit Linux distributions

> **Important Note:** 32-bit operating systems and devices are NOT supported. The mining software requires a 64-bit architecture to function properly, as mining on 32-bit systems is not efficient. The installer will only download and configure 64-bit versions of the necessary software.

## Managing Your Miner

After installation, you can use these commands to manage your miner:

- **Start**: `~/refurbminer/start.sh`
- **Stop**: `~/refurbminer/stop.sh`
- **Check Status**: `~/refurbminer/status.sh`
- **Update**: `~/update_refurbminer.sh`
- **Local WebUI**: `http://<miner_ip>:3000`
- **RefurbMiner APP**: `install refurbminer.apk`

## Troubleshooting

### Common Issues

1. **Screen Command Not Found**
   
   Install screen:
   ```bash
   # Debian/Ubuntu:
   sudo apt-get install screen
   
   # Termux:
   pkg install screen
   ```

2. **Permission Denied**
   
   Make scripts executable:
   ```bash
   chmod +x *.sh
   ```

3. **Failed to Download Scripts**
   
   Check your internet connection or try with `--insecure` option if you have SSL issues:
   ```bash
   wget --no-check-certificate -q -O install_refurbminer.sh https://raw.githubusercontent.com/dismaster/refurbminer_tools/main/install_refurbminer.sh
   ```

4. **Termux Package Installation Issues**
   
   If you're having trouble installing packages in Termux, the default repository might be unavailable or outdated. Try changing to a different repository:
   
   ```bash
   # Install termux-tools if not already installed
   pkg install termux-tools
   
   # Change repository
   termux-change-repo
   ```
   
   This will open a menu where you can select a different mirror. Choose a different repository (e.g., Grimler or BFSU) and try installing again.
   
   Alternatively, you can manually update your sources:
   
   ```bash
   # Edit the sources.list file
   nano $PREFIX/etc/apt/sources.list
   ```
   
   Replace the existing URL with:
   ```
   deb https://packages.termux.dev/apt/termux-main stable main
   ```
   
   Then update and try again:
   ```bash
   pkg update
   pkg upgrade
   ```

5. **Termux Boot Not Working**

   If your miner isn't starting at boot on Android:
   
   - Make sure you've installed the Termux:Boot app from F-Droid
   - Enable autostart permission for Termux:Boot in Android settings
   - Ensure your script permissions are correct:
   ```bash
   chmod -R 755 ~/.termux/boot/
   ```
   - Check if the boot script exists:
   ```bash
   ls -la ~/.termux/boot/
   ```

### Getting Help

If you encounter issues, please:

1. Check the logs at `~/refurbminer/logs/`
2. Visit our [support discord](https://discord.gg/P5BmXK8dkp)
3. Open an issue on GitHub with detailed information about your problem

## Contributing

We welcome contributions to improve RefurbMiner. Feel free to submit pull requests or report issues.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

Special thanks to all contributors and the Vertcoin community for their support.

---

Developed by [@Ch3ckr](https://github.com/dismaster)  
For more information, visit [gui.refurbminer.de](https://gui.refurbminer.de)