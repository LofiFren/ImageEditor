# ImageEditor Scripts Documentation

This directory contains scripts for analyzing, fixing, and creating disk images, particularly for Rockchip-based devices and the uConsole CM4.

## Script Categories

### Image Analysis
- **deep-image-analysis.sh** - Comprehensive comparison between two images
- **check-rockchip-boot.sh** - Verifies Rockchip boot structures and signatures

### Image Fixing
- **complete-image-fix.sh** - All-in-one solution for fixing boot issues
- **surgical-boot-fix.sh** - Precision boot fixing while preserving GPT and data
- **basic_fix_image.sh** - Resizes images and fixes GPT tables

### Image Creation
- **create-uconsole-cm4-image-fixed.sh** - Creates Kali Linux image for uConsole CM4

### Mounting Operations
- **mount.sh** - Mounts image partitions to /mnt/image
- **unmount.sh** - Unmounts mounted image partitions

### Backup/Restore
- **backup.sh** - Creates timestamped backups of images
- **restore.sh** - Restores images from backups

## Typical Workflows

### 1. Analyzing a Problematic Image
```bash
# Compare with a known good image
./deep-image-analysis.sh good-image.img problematic-image.img

# Check Rockchip boot structures
./check-rockchip-boot.sh problematic-image.img
```

### 2. Fixing Boot Issues
```bash
# Create a backup first
./backup.sh problematic-image.img

# Apply comprehensive fix using a good image as reference
./complete-image-fix.sh good-image.img problematic-image.img

# OR use surgical fix to preserve more data
./surgical-boot-fix.sh good-image.img problematic-image.img
```

### 3. Resizing an Image
```bash
# Resize image with 1GB growth space
./basic_fix_image.sh image.img 1
```

## Creating uConsole CM4 Kali Linux Image

The `create-uconsole-cm4-image-fixed.sh` script creates a customized Kali Linux image for the uConsole CM4 device.

### Prerequisites
- Docker environment with required tools (kpartx, chroot)
- Internet connection for downloading kernel and packages
- Sufficient disk space (~8GB)

### Usage
```bash
./create-uconsole-cm4-image-fixed.sh <compressed-kali-image.xz>
```

### What it does:
1. Extracts the compressed Kali image
2. Sets up loop devices for partitions
3. Removes default Kali kernel
4. Installs uConsole CM4 specific kernel
5. Configures display rotation
6. Installs 4G modem support
7. Blacklists conflicting kernel modules
8. Prevents Kali kernel reinstallation

### Example
```bash
./create-uconsole-cm4-image-fixed.sh kali-linux-2024.1-raspberry-pi-arm64.img.xz
```

## Flashing the Image to SD Card

After creating or fixing an image, flash it to your SD card using dd:

**⚠️ WARNING: Be absolutely certain of your target device! Using the wrong device will destroy data!**

### macOS Instructions:

#### Step 1: Identify Your SD Card
```bash
# Before inserting the SD card, run:
diskutil list

# Insert your SD card, then run again:
diskutil list

# Look for the new disk that appeared. It will typically show:
# - Size matching your SD card (e.g., 32.0 GB)
# - Name like "NO NAME" or "UNTITLED"
# - Format like FAT32 or ExFAT
# - Identifier like /dev/disk2 or /dev/disk3 (external disks usually start from disk2)
```

Example output:
```
/dev/disk3 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:     FDisk_partition_scheme                        *32.0 GB    disk3
   1:                 DOS_FAT_32 NO NAME                 32.0 GB    disk3s1
```

#### Step 2: Unmount the SD Card
```bash
# Replace diskX with your actual disk number (e.g., disk3)
diskutil unmountDisk /dev/diskX
```

#### Step 3: Flash the Image
```bash
# Replace diskX with your SD card's disk number
sudo dd if=kali-linux-2024.1-raspberry-pi-arm64.img \
         of=/dev/diskX \
         bs=4M \
         status=progress \
    && sync
```

**Note:** On macOS, you may get better performance using raw disk mode:
```bash
sudo dd if=kali-linux-2024.1-raspberry-pi-arm64.img \
         of=/dev/rdiskX \
         bs=4m \
         status=progress \
    && sync
```
(Notice the 'r' before disk and lowercase 'm' in bs=4m)

### Linux Example:
```bash
# Identify your SD card
lsblk

# Flash the image (replace sdX with your actual device)
sudo dd if=kali-linux-2024.1-raspberry-pi-arm64.img \
         of=/dev/sdX \
         bs=4M \
         status=progress \
    && sync
```

### Important Notes:
- Always use `diskutil list` (macOS) or `lsblk` (Linux) to verify the correct device
- The `bs=4M` parameter optimizes write speed
- The `status=progress` shows transfer progress
- The `sync` command ensures all data is written before removing the SD card
- Wait for the command to complete fully before removing the SD card

## Safety Tips

1. **Always create backups** before modifying images
2. **Verify device paths** twice before using dd commands
3. **Test modified images** before deploying to production
4. **Keep a known-good image** as reference

## Troubleshooting

If an image won't boot after modification:
1. Use `check-rockchip-boot.sh` to verify boot structures
2. Compare with a working image using `deep-image-analysis.sh`
3. Try `surgical-boot-fix.sh` for minimal changes
4. As a last resort, use `complete-image-fix.sh` for full boot area replacement