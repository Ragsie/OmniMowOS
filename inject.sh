#!/bin/bash

# ==============================================================================
# Radxa Dragon Q6A - Post-Build System Image Injector Script (v5)
# ==============================================================================

set -e

# 1. Find the latest Radxa image (.img)
IMAGE=$(ls -t out/*/*.img out/*.img 2>/dev/null | head -n 1)

if [ -z "$IMAGE" ]; then
    echo "Error: No .img file found in out/ directory!"
    exit 1
fi

echo "Preparing injection for: $IMAGE"

# --- EXPAND IMAGE & FIX PARTITION TABLE ---
echo "Expanding image by +2GB to prevent disk full errors during apt operations..."
truncate -s +2G "$IMAGE"

# 2. Mount the image as a virtual loop device
LOOP_DEV=$(sudo losetup -fP --show "$IMAGE")
sleep 2
sudo udevadm settle || true

# Fix GPT backup header and resize partition 2
echo "Fixing partition table and expanding root partition..."
sudo sgdisk -e "$LOOP_DEV" 2>/dev/null || true
sudo parted -s "$LOOP_DEV" resizepart 2 100% 2>/dev/null || true
sudo partprobe "$LOOP_DEV" 2>/dev/null || true
sleep 2
sudo udevadm settle || true

# 3. Locate the root partition (ext4)
ROOT_PART=$(lsblk -rn -o NAME,FSTYPE "$LOOP_DEV" | awk '$2=="ext4" {print $1}' | head -n 1)

# Fallback if FSTYPE wasn't scanned by udev yet
if [ -z "$ROOT_PART" ]; then
    echo "Warning: FSTYPE detection delayed, trying second partition of $LOOP_DEV..."
    LOOP_BASE=$(basename "$LOOP_DEV")
    if [ -b "/dev/${LOOP_BASE}p2" ]; then
        ROOT_PART="${LOOP_BASE}p2"
    elif [ -b "/dev/${LOOP_BASE}p1" ]; then
        ROOT_PART="${LOOP_BASE}p1"
    fi
fi

if [ -z "$ROOT_PART" ]; then
    echo "Error: Could not find root partition!"
    sudo losetup -d "$LOOP_DEV"
    exit 1
fi

echo "Root partition identified as: /dev/$ROOT_PART"

# Resize ext4 filesystem to fill expanded space
sudo e2fsck -f -y "/dev/$ROOT_PART" || true
sudo resize2fs "/dev/$ROOT_PART" || true

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

# --- ADD RADXA QCS6490-RESOLUTE REPOSITORY ---
echo "Configuring Radxa QCS6490 APT repositories..."
sudo chroot /tmp/robot_root apt-get update || true
sudo chroot /tmp/robot_root apt-get install -y curl ca-certificates gnupg || true

# Add qcs6490-resolute repository if missing
if ! sudo chroot /tmp/robot_root test -f /etc/apt/sources.list.d/qcs6490-resolute.list; then
    echo "Adding qcs6490-resolute repository..."
    sudo chroot /tmp/robot_root sh -c 'curl -s https://radxa-repo.github.io/qcs6490-resolute/install.sh | sh' || true
fi

# --- FIX 1: FIRMWARE, DRIVERS & SSH INJECTION ---
echo "Installing firmware, Wi-Fi drivers, and OpenSSH..."
sudo chroot /tmp/robot_root apt-get update || true
sudo DEBIAN_FRONTEND=noninteractive chroot /tmp/robot_root apt-get install -y \
    linux-firmware \
    radxa-firmware \
    openssh-server \
    aic8800-firmware \
    aic8800-usb-dkms \
    fastrpc \
    libcdsprpc1 \
    linux-headers-radxa-dragon-q6a || true

# Generate SSH host keys and enable SSH
echo "Generating SSH host keys and enabling SSH service..."
sudo chroot /tmp/robot_root ssh-keygen -A || true
sudo chroot /tmp/robot_root systemctl enable ssh.service || true
sudo chroot /tmp/robot_root systemctl enable ssh.socket || true

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

for fw in /lib/firmware/qcom/qcs6490/radxa/dragon-q6a/*.mbn /lib/firmware/qcom/qcs6490/*.mbn; do
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

# --- FIX 4: KEYBOARD LAYOUT (DANISH) ---
echo "Setting permanent Danish keyboard layout..."
sudo tee /tmp/robot_root/etc/default/keyboard > /dev/null <<'EOF'
XKBMODEL="pc105"
XKBLAYOUT="dk"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF

# --- FIX 5: USER CLEANUP (REMOVE DEFAULT 'ROCK' USER) ---
echo "Removing default 'rock' user..."
sudo chroot /tmp/robot_root userdel -r -f rock 2>/dev/null || true
sudo rm -rf /tmp/robot_root/home/rock
sudo rm -f /tmp/robot_root/etc/sudoers.d/*rock*

# --- FIX 6: KERNEL HOLD & MACHINE-ID WIPE ---
echo "Locking kernel packages against unintended apt upgrades..."
echo -e "linux-image-radxa-dragon-q6a hold\nradxa-overlays-dkms hold" | sudo chroot /tmp/robot_root dpkg --set-selections

echo "Resetting machine-id for unique network identity..."
sudo rm -f /tmp/robot_root/etc/machine-id /tmp/robot_root/var/lib/dbus/machine-id
sudo touch /tmp/robot_root/etc/machine-id

# --- FIX 7: SOUNDWIRE AUDIO MODULES ---
echo "Enabling SoundWire audio modules..."
sudo mkdir -p /tmp/robot_root/etc/modules-load.d
echo -e "snd_soc_wcd938x\nsnd_soc_wcd938x_sdw" | sudo tee /tmp/robot_root/etc/modules-load.d/omnimow-audio.conf > /dev/null

# --- FIX 8: FIRST-BOOT SCRIPT PLACEMENT ---
if [ -f omnimow-first-boot.sh ]; then
    echo "Copying first-boot setup script..."
    sudo cp omnimow-first-boot.sh /tmp/robot_root/usr/local/bin/
    sudo chmod +x /tmp/robot_root/usr/local/bin/omnimow-first-boot.sh
    
    echo "radxa ALL=(ALL) NOPASSWD: /usr/local/bin/omnimow-first-boot.sh" | sudo tee /tmp/robot_root/etc/sudoers.d/omnimow-setup > /dev/null
    sudo chmod 440 /tmp/robot_root/etc/sudoers.d/omnimow-setup

    sudo tee /tmp/robot_root/etc/profile.d/99-omnimow-setup.sh > /dev/null <<'EOF'
if [[ $- == *i* ]] && [ -f /usr/local/bin/omnimow-first-boot.sh ]; then
    sudo /usr/local/bin/omnimow-first-boot.sh
fi
EOF
    sudo chmod +x /tmp/robot_root/etc/profile.d/99-omnimow-setup.sh
fi

# Clean up apt caches inside chroot
sudo chroot /tmp/robot_root apt-get clean
sudo rm -rf /tmp/robot_root/var/lib/apt/lists/*

# --- CLEANUP & UNMOUNT ---
echo "Restoring DNS and unmounting partitions..."
sudo rm -f /tmp/robot_root/etc/resolv.conf
sudo ln -s ../run/systemd/resolve/stub-resolv.conf /tmp/robot_root/etc/resolv.conf 2>/dev/null || true

sudo umount /tmp/robot_root/proc
sudo umount /tmp/robot_root/sys
sudo umount /tmp/robot_root/dev
sudo umount /tmp/robot_root
sudo losetup -d "$LOOP_DEV"

echo "✅ Injection complete! Image is ready for flashing with Raspberry Pi Imager."
