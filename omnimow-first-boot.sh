#!/bin/bash

# Ensure the script is run with root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (using sudo)"
  exit 1
fi

clear
echo "===================================================="
echo "       Welcome to OmniMow Base OS Initial Setup     "
echo "===================================================="
echo "This guide will help you configure your new autonomous mower."
echo ""

# --- Step 1: Timezone Configuration ---
echo "--- Step 1: Timezone Configuration ---"
echo "Example: Europe/Copenhagen, America/New_York, UTC"
read -p "Enter your timezone [Europe/Copenhagen]: " tz_input
tz_input=${tz_input:-Europe/Copenhagen}
echo "Setting timezone to $tz_input..."
timedatectl set-timezone "$tz_input"
echo ""

# --- Step 2: Keyboard Layout Configuration ---
echo "--- Step 2: Keyboard Layout Configuration ---"
echo "Example: dk (Danish), us (US English), uk (UK English), de (German)"
read -p "Enter your 2-letter keyboard layout [dk]: " kbd_input
kbd_input=${kbd_input:-dk}
echo "Setting keyboard layout to $kbd_input..."
# Update the default keyboard configuration file
sed -i "s/XKBLAYOUT=.*/XKBLAYOUT=\"$kbd_input\"/g" /etc/default/keyboard
# Apply the settings immediately if setupcon is available
if command -v setupcon &> /dev/null; then
    setupcon
fi
echo ""

# --- Step 3: Create Robot User ---
echo "--- Step 3: Create Robot User ---"
read -p "Enter new username for the robot [omnimow]: " new_user
new_user=${new_user:-omnimow}

# Check if user already exists to avoid errors
if id "$new_user" &>/dev/null; then
    echo "User $new_user already exists."
else
    echo "Creating user $new_user. Please set a password:"
    adduser "$new_user"
    echo "Adding $new_user to sudo group..."
    usermod -aG sudo "$new_user"
fi
echo ""

# --- Step 4: Cleanup and Reboot ---
echo "--- Step 4: Final Cleanup ---"
echo "Removing temporary setup script and sudoers rules..."
rm -f /usr/local/bin/omnimow-first-boot.sh
rm -f /etc/sudoers.d/omnimow-setup

echo "Initial setup is complete!"
echo "The default 'radxa' user will now be permanently removed."
echo "After the reboot, please log in with your new user: $new_user"
echo ""
echo "Rebooting in 5 seconds..."

# Run user deletion and reboot in a detached background process.
# This prevents the script from hanging when the active 'radxa' session is killed.
nohup bash -c "sleep 5; userdel -r -f radxa; reboot" >/dev/null 2>&1 &

exit 0
