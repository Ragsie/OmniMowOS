# OmniMow - Base OS

This repository contains the official, pre-configured operating system for the **OmniMow** autonomous robot lawnmower project. 

The image is tailor-made for the **Radxa Dragon Q6A** board and serves as a rock-solid, reproducible foundation for running ROS 2 and Docker, with critical hardware and stability fixes built directly into the core. But can also be used for other projects.

## 🌟 Key Features
* **OS Versions:** Ubuntu 24.04 LTS (Noble) / Ubuntu 26.04 LTS (Resolute) Server CLI (Headless).
* **Hardware-Ready:** Pre-installed Qualcomm BSP for full NPU/GPU and FastRPC support.
* **ROS 2 Optimized:** Ready for ROS 2 (Jazzy / Lyrical Luth) and Docker out of the box.
* **Interactive Setup:** Built-in `omnimow-first-boot.sh` script automatically guides you through user creation, timezone setup, and hardware permissions on your first login.
* **Cloud Native Builds:** 100% automated native ARM64 builds via GitHub Actions.

## 🛠️ Built-in Community Fixes
We apply several critical fixes on top of the stock Radxa SDK to ensure OmniMow is stable in a production environment:
* **Unique Network Identity:** Clears the baked-in `machine-id` during the build process, ensuring every robot generates a unique ID/IP on the network.
* **Update Resilience:** Locks the kernel (`linux-image-radxa-dragon-q6a`) and hardware overlays (`radxa-overlays-dkms`) using `apt-mark hold` to prevent `sudo apt upgrade` from breaking the boot sequence.
* **Audio/SoundWire Support:** Pre-loads `snd_soc_wcd938x` and `snd_soc_wcd938x_sdw` modules so audio works out of the box.
* **Hardware Permissions:** Automatically configures groups for `i2c`, `dialout`, `video`, and `tty` for seamless ESP32 and VESC communication.

---

## 🚀 Getting Started

### 1. Download the OS
Go to the **Actions** tab in this repository, click on the latest successful "Build OmniMow OS" workflow, and download the `.img.xz` artifact from the bottom of the page (or check the [Releases](../../releases) page for stable versions).

### 2. Flash to MicroSD or NVMe
We highly recommend using [Raspberry Pi Imager](https://www.raspberrypi.com/software/) as it natively supports compressed `.xz` files.

1. Insert your MicroSD card (or NVMe drive via USB adapter).
2. Open Raspberry Pi Imager.
3. Select **Choose OS** -> Scroll down and select **Use custom** -> Select your downloaded `.img.xz` file.
4. Choose your drive and click **Write**.

### 3. First Boot
1. Insert the flashed drive into your Radxa Dragon Q6A.
2. Connect a network cable.
3. Power the board on. (Wait ~60 seconds for the filesystem to expand automatically).

### 4. Setup via SSH
Find the robot's IP address on your router. Open a terminal and log in using the default credentials:

```bash
# Default password is: radxa
ssh radxa@<your-robot-ip>
