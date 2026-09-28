#!/bin/bash

# 1. Find the newest Radxa image file
IMAGE=$(ls -t out/*.img 2>/dev/null | head -n 1)

if [ -z "$IMAGE" ]; then
    echo "Error: No .img files found in the out/ directory!"
    exit 1
fi

echo "Modifying: $IMAGE"

# 2. Mount the image as a virtual loop device
LOOP_DEV=$(sudo losetup -fP --show "$IMAGE")

# VIGTIG TILFØJELSE TIL GITHUB ACTIONS: 
# Giv serveren 2 sekunder til at lade partitionerne poppe op i systemet
sleep 2

# 3. Find the root filesystem (Radxa's Ubuntu root drive is always ext4)
ROOT_PART=$(lsblk -rn -o NAME,FSTYPE "$LOOP_DEV" | awk '$2=="ext4" {print $1}')

if [ -z "$ROOT_PART" ]; then
    echo "Error: Could not find the root partition!"
    sudo losetup -d "$LOOP_DEV"
    exit 1
fi

# 4. Mount the partition to /tmp/robot_root
echo "Mounting /dev/$ROOT_PART..."
mkdir -p /tmp/robot_root
sudo mount "/dev/$ROOT_PART" /tmp/robot_root

# 5. Transfer files and inject community fixes!
echo "Transferring the setup script..."
sudo cp omnimow-first-boot.sh /tmp/robot_root/usr/local/bin/
sudo chmod +x /tmp/robot_root/usr/local/bin/omnimow-first-boot.sh

echo "Registering the script in the system..."
echo "sudo bash /usr/local/bin/omnimow-first-boot.sh" | sudo tee -a /tmp/robot_root/home/radxa/.bashrc > /dev/null

echo "Applying Community Fix 1: Clearing machine-id for unique generation..."
sudo rm -f /tmp/robot_root/etc/machine-id /tmp/robot_root/var/lib/dbus/machine-id
sudo touch /tmp/robot_root/etc/machine-id

echo "Applying Community Fix 2: Locking kernel version to prevent upgrade breakage..."
echo -e "linux-image-radxa-dragon-q6a hold\nradxa-overlays-dkms hold" | sudo chroot /tmp/robot_root dpkg --set-selections

echo "Applying Community Fix 3: Enabling SoundWire and audio modules..."
echo "snd_soc_wcd938x" | sudo tee -a /tmp/robot_root/etc/modules-load.d/omnimow-audio.conf > /dev/null
echo "snd_soc_wcd938x_sdw" | sudo tee -a /tmp/robot_root/etc/modules-load.d/omnimow-audio.conf > /dev/null

# 6. Safely unmount and clean up
echo "Cleaning up..."
sudo umount /tmp/robot_root
sudo losetup -d "$LOOP_DEV"

echo "✅ Done! OmniMow setup script, machine-id wipe, and kernel locks are permanently integrated."
