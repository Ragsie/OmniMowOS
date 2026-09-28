#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

echo "=========================================================="
echo "         Welcome to OmniMow Base OS Initial Setup         "
echo "=========================================================="
echo "This guide will help you configure your new autonomous mower."
echo ""

# 1. Setup Timezone
echo "--- Step 1: Timezone Configuration ---"
echo "Example: Europe/Copenhagen, America/New_York, UTC"
read -p "Enter your timezone [Europe/Copenhagen]: " TIMEZONE
TIMEZONE=${TIMEZONE:-Europe/Copenhagen}
timedatectl set-timezone "$TIMEZONE"
echo "Timezone set to $TIMEZONE."
echo ""

# 2. Create New User
echo "--- Step 2: Create Personal User ---"
echo "You need a personal user for SSH and ROS 2 execution."
read -p "Enter new username (e.g., omnimow, alexander): " NEW_USER

# Create the user and prompt for password
adduser "$NEW_USER"

# 3. Assign Hardware & System Permissions
echo ""
echo "--- Step 3: Assigning Hardware Permissions ---"
echo "Granting $NEW_USER access to sudo, I2C, Serial/UART (VESC/ESP32), and video..."

# Create groups if they don't exist, then add the user
for group in sudo dialout tty i2c video plugdev; do
    groupadd -f "$group"
    usermod -aG "$group" "$NEW_USER"
done
echo "Permissions granted."
echo ""

# 4. Cleanup and Security
echo "--- Step 4: Finalizing & Securing ---"

# Remove the script trigger from the default user's bashrc so it only runs once
sed -i '/omnimow-first-boot.sh/d' /home/radxa/.bashrc

echo "=========================================================="
echo "✅ Setup Complete!"
echo "The system will now reboot to apply all hardware groups."
echo "After the reboot, please log in using your new user:"
echo "ssh $NEW_USER@<robot-ip>"
echo "=========================================================="
echo ""
echo "Rebooting in 5 seconds... Press Ctrl+C to abort reboot."

sleep 5
reboot
