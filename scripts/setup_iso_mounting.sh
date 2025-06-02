#!/bin/bash

# Setup script for Wine Prefix Manager ISO mounting
# This script configures sudo permissions for mounting operations

echo "Wine Prefix Manager - ISO Mounting Setup"
echo "======================================="
echo ""
echo "This script will configure sudo permissions to allow ISO mounting"
echo "without password prompts for the following commands:"
echo "  - losetup (for creating loop devices)"
echo "  - mount (for mounting ISOs)"
echo "  - umount (for unmounting ISOs)"
echo ""

# Check if user has sudo privileges
if ! sudo -n true 2>/dev/null; then
    echo "❌ You need sudo privileges to run this setup."
    echo "Please run: sudo $0"
    exit 1
fi

# Get the actual username (in case script is run with sudo)
if [ -n "$SUDO_USER" ]; then
    USERNAME="$SUDO_USER"
else
    USERNAME="$USER"
fi

echo "Setting up permissions for user: $USERNAME"
echo ""

# Create sudoers rule
SUDOERS_RULE="$USERNAME ALL=(ALL) NOPASSWD: /usr/bin/losetup, /usr/bin/mount, /usr/bin/umount"
SUDOERS_FILE="/etc/sudoers.d/wine-prefix-manager-iso"

# Write the rule to a sudoers file
echo "$SUDOERS_RULE" | sudo tee "$SUDOERS_FILE" > /dev/null

# Set proper permissions
sudo chmod 440 "$SUDOERS_FILE"

# Validate the sudoers file
if sudo visudo -c -f "$SUDOERS_FILE" > /dev/null 2>&1; then
    echo "✅ Successfully configured sudo permissions!"
    echo ""
    echo "The following file has been created:"
    echo "  $SUDOERS_FILE"
    echo ""
    echo "You can now use ISO mounting in Wine Prefix Manager without"
    echo "password prompts for mounting operations."
    echo ""
    echo "To remove these permissions later, run:"
    echo "  sudo rm $SUDOERS_FILE"
else
    echo "❌ Error: Failed to create valid sudoers configuration."
    sudo rm -f "$SUDOERS_FILE"
    exit 1
fi

echo ""
echo "Setup complete! You can now restart Wine Prefix Manager and try"
echo "mounting ISOs without password prompts." 