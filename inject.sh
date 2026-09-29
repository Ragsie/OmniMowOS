#!/bin/bash

# 1. Find the newest Radxa image file
IMAGE=$(ls -t out/*/*.img 2>/dev/null | head -n 1)

if [ -z "$IMAGE" ]; then
    echo "Error: No .img files found!"
    exit 1
fi

echo "Modifying: $IMAGE"

# 2. Mount the image as a virtual loop device
LOOP_DEV=$(sudo losetup -fP --show "$IMAGE")
sleep 2

# 3. Find the root filesystem
ROOT_PART=$(lsblk -rn -o NAME,FSTYPE "$LOOP_DEV" | awk '$2=="ext4" {print $1}')

if [ -z "$ROOT_PART" ]; then
    echo "Error: Could not find the root partition!"
    sudo losetup -d "$LOOP_DEV"
    exit 1
fi

echo "Mounting /dev/$ROOT_PART..."
mkdir -p /tmp/robot_root
sudo mount "/dev/$ROOT_PART" /tmp/robot_root

# --- BIND SYSTEM FOLDERS FOR APT-GET ---
echo "Setting up chroot environment..."
sudo mount --bind /dev /tmp/robot_root/dev
sudo mount --bind /sys /tmp/robot_root/sys
sudo mount --bind /proc /tmp/robot_root/proc
sudo mount --bind /etc/resolv.conf /tmp/robot_root/etc/resolv.conf

# --- INSTALL MISSING DRIVERS, WI-FI AND SSH ---
echo "Installing firmware, Wi-Fi drivers, and SSH server directly into the image..."
sudo chroot /tmp/robot_root apt-get update
sudo DEBIAN_FRONTEND=noninteractive chroot /tmp/robot_root apt-get install -y \
    linux-firmware \
    radxa-firmware \
    openssh-server \
    aic8800-firmware \
    aic8800-usb-dkms \
    linux-headers-radxa-dragon-q6a

# Force SSH to start automatically at boot
echo "Enabling SSH service..."
sudo chroot /tmp/robot_root systemctl enable ssh

# --- FETCH MISSING GPU FIRMWARE ---
echo "Fetching missing a660_sqe.fw directly from kernel.org..."
sudo mkdir -p /tmp/robot_root/lib/firmware/qcom
sudo curl -sL "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/qcom/a660_sqe.fw" -o /tmp/robot_root/lib/firmware/qcom/a660_sqe.fw

# --- BAKE FIRMWARE INTO BOOT SEQUENCE ---
echo "Updating initramfs to include new firmware..."
sudo chroot /tmp/robot_root update-initramfs -c -k all

# 4. Transfer files and inject community fixes
echo "Transferring the setup script..."
sudo cp omnimow-first-boot.sh /tmp/robot_root/usr/local/bin/
sudo chmod +x /tmp/robot_root/usr/local/bin/omnimow-first-boot.sh

# --- ALLOW SCRIPT TO RUN WITHOUT SUDO PASSWORD ---
echo "radxa ALL=(ALL) NOPASSWD: /usr/local/bin/omnimow-first-boot.sh" | sudo tee /tmp/robot_root/etc/sudoers.d/omnimow-setup > /dev/null
sudo chmod 440 /tmp/robot_root/etc/sudoers.d/omnimow-setup

# Register the script in .bashrc (only for interactive terminals)
echo "Registering first-boot script in .bashrc..."
sudo sed -i '/omnimow-first-boot.sh/d' /tmp/robot_root/home/radxa/.bashrc
echo 'if [[ $- == *i* ]] && [ -f /usr/local/bin/omnimow-first-boot.sh ]; then sudo /usr/local/bin/omnimow-first-boot.sh; fi' | sudo tee -a /tmp/robot_root/home/radxa/.bashrc > /dev/null

echo "Applying Community Fix 1: Clearing machine-id for unique generation..."
sudo rm -f /tmp/robot_root/etc/machine-id /tmp/robot_root/var/lib/dbus/machine-id
sudo touch /tmp/robot_root/etc/machine-id

echo "Applying Community Fix 2: Locking kernel version to prevent upgrade breakage..."
echo -e "linux-image-radxa-dragon-q6a hold\nradxa-overlays-dkms hold" | sudo chroot /tmp/robot_root dpkg --set-selections

echo "Applying Community Fix 3: Enabling SoundWire and audio modules..."
echo "snd_soc_wcd938x" | sudo tee -a /tmp/robot_root/etc/modules-load.d/omnimow-audio.conf > /dev/null
echo "snd_soc_wcd938x_sdw" | sudo tee -a /tmp/robot_root/etc/modules-load.d/omnimow-audio.conf > /dev/null

# 5. Safely unmount and clean up (Must unmount binds first!)
echo "Cleaning up..."
sudo umount /tmp/robot_root/etc/resolv.conf
sudo umount /tmp/robot_root/proc
sudo umount /tmp/robot_root/sys
sudo umount /tmp/robot_root/dev
sudo umount /tmp/robot_root
sudo losetup -d "$LOOP_DEV"

echo "✅ Done! Image is now fully pre-configured."
