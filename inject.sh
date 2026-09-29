#!/bin/bash

# ==============================================================================
# Radxa Dragon Q6A - Post-Build System Image Injector Script (v2)
# ==============================================================================

set -e

# 1. Find the latest Radxa image (.img)
IMAGE=$(ls -t out/*/*.img out/*.img 2>/dev/null | head -n 1)

if [ -z "$IMAGE" ]; then
    echo "Error: No .img file found in out/ directory!"
    exit 1
fi

echo "Preparing injection for: $IMAGE"

# 2. Mount the image as a virtual loop device
LOOP_DEV=$(sudo losetup -fP --show "$IMAGE")
sleep 2

# 3. Locate the root partition (ext4)
ROOT_PART=$(lsblk -rn -o NAME,FSTYPE "$LOOP_DEV" | awk '$2=="ext4" {print $1}')

if [ -z "$ROOT_PART" ]; then
    echo "Error: Could not find ext4 root partition!"
    sudo losetup -d "$LOOP_DEV"
    exit 1
fi

echo "Mounting /dev/$ROOT_PART to /tmp/robot_root..."
mkdir -p /tmp/robot_root
sudo mount "/dev/$ROOT_PART" /tmp/robot_root

# --- CHROOT & NETWORK SETUP ---
echo "Setting up chroot environment and DNS..."
sudo mount --bind /dev /tmp/robot_root/dev
sudo mount --bind /sys /tmp/robot_root/sys
sudo mount --bind /proc /tmp/robot_root/proc

# Force working DNS inside chroot
sudo rm -f /tmp/robot_root/etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee /tmp/robot_root/etc/resolv.conf > /dev/null

# --- FIX 1: FIRMWARE & DRIVER INJECTION ---
echo "Installing firmware, Wi-Fi drivers, and OpenSSH..."
sudo chroot /tmp/robot_root apt-get update
sudo DEBIAN_FRONTEND=noninteractive chroot /tmp/robot_root apt-get install -y \
    linux-firmware \
    radxa-firmware \
    openssh-server \
    aic8800-firmware \
    aic8800-usb-dkms \
    linux-headers-radxa-dragon-q6a || true

sudo chroot /tmp/robot_root systemctl enable ssh

# Fetch missing GPU Firmware (Adreno 643)
echo "Downloading a660_sqe.fw from kernel.org..."
sudo mkdir -p /tmp/robot_root/lib/firmware/qcom
sudo curl -sL "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/qcom/a660_sqe.fw" \
    -o /tmp/robot_root/lib/firmware/qcom/a660_sqe.fw

# --- FIX 2: INITRAMFS DSP FIRMWARE HOOK (NVMe Boot Fix) ---
echo "Creating Initramfs DSP hook to prevent NVMe early-boot timing error..."
sudo tee /tmp/robot_root/etc/initramfs-tools/hooks/qcom-dsp > /dev/null <<'EOF'
#!/bin/sh
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "$1" in prereqs) prereqs; exit 0 ;; esac
. /usr/share/initramfs-tools/hook-functions

# Dynamically locate and copy DSP firmware files (adsp.mbn, cdsp.mbn) under /lib/firmware/qcom/
for fw in $(find /lib/firmware/qcom/ -type f \( -name "adsp*.mbn" -o -name "cdsp*.mbn" \) 2>/dev/null); do
    if [ -f "$fw" ]; then
        copy_file firmware "$fw"
    fi
done

exit 0
EOF
sudo chmod +x /tmp/robot_root/etc/initramfs-tools/hooks/qcom-dsp

echo "Rebuilding initramfs inside image..."
sudo chroot /tmp/robot_root update-initramfs -u -k all || sudo chroot /tmp/robot_root update-initramfs -c -k all

# --- FIX 3: FASTRPC & DMA HEAP UDEV RULES ---
echo "Configuring udev rules for FastRPC (0666)..."
sudo tee /tmp/robot_root/etc/udev/rules.d/99-fastrpc.rules > /dev/null <<'EOF'
KERNEL=="fastrpc-*", MODE="0666"
SUBSYSTEM=="dma_heap", KERNEL=="system", MODE="0666"
EOF

# --- FIX 4: KERNEL HOLD & MACHINE-ID WIPE ---
echo "Locking kernel packages against unintended apt upgrades..."
echo -e "linux-image-radxa-dragon-q6a hold\nradxa-overlays-dkms hold" | sudo chroot /tmp/robot_root dpkg --set-selections

echo "Resetting machine-id for unique network identity..."
sudo rm -f /tmp/robot_root/etc/machine-id /tmp/robot_root/var/lib/dbus/machine-id
sudo touch /tmp/robot_root/etc/machine-id

# --- FIX 5: SOUNDWIRE AUDIO MODULES ---
echo "Enabling SoundWire audio modules..."
sudo mkdir -p /tmp/robot_root/etc/modules-load.d
echo -e "snd_soc_wcd938x\nsnd_soc_wcd938x_sdw" | sudo tee /tmp/robot_root/etc/modules-load.d/omnimow-audio.conf > /dev/null

# --- FIX 6: FIRST-BOOT SCRIPT PLACEMENT ---
if [ -f omnimow-first-boot.sh ]; then
    echo "Copying first-boot setup script..."
    sudo cp omnimow-first-boot.sh /tmp/robot_root/usr/local/bin/
    sudo chmod +x /tmp/robot_root/usr/local/bin/omnimow-first-boot.sh
    
    echo "radxa ALL=(ALL) NOPASSWD: /usr/local/bin/omnimow-first-boot.sh" | sudo tee /tmp/robot_root/etc/sudoers.d/omnimow-setup > /dev/null
    sudo chmod 440 /tmp/robot_root/etc/sudoers.d/omnimow-setup

    echo 'if [[ $- == *i* ]] && [ -f /usr/local/bin/omnimow-first-boot.sh ]; then sudo /usr/local/bin/omnimow-first-boot.sh; fi' | sudo tee /tmp/robot_root/etc/profile.d/99-omnimow-setup.sh > /dev/null
    sudo chmod +x /tmp/robot_root/etc/profile.d/99-omnimow-setup.sh
fi

# Remove default 'rock' user if present
sudo chroot /tmp/robot_root userdel -r -f rock 2>/dev/null || true

# --- CLEANUP & UNMOUNT ---
echo "Restoring DNS and unmounting partitions..."
sudo rm -f /tmp/robot_root/etc/resolv.conf
sudo ln -s ../run/systemd/resolve/stub-resolv.conf /tmp/robot_root/etc/resolv.conf

sudo umount /tmp/robot_root/proc
sudo umount /tmp/robot_root/sys
sudo umount /tmp/robot_root/dev
sudo umount /tmp/robot_root
sudo losetup -d "$LOOP_DEV"

echo "✅ Injection complete! Image is ready for flashing."
