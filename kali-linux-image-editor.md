# Kali Linux Image Editor for uConsole CM4

This tool automates the creation of a Kali Linux image specifically configured for the ClockworkPi uConsole CM4.

## Purpose

Convert a standard Kali Linux ARM64 image into a fully functional uConsole CM4 image with:
- uConsole-specific kernel
- Proper display rotation
- 4G module support
- ClockworkPi repository access

## Prerequisites

- Docker and Docker Compose installed
- At least 16GB of free disk space
- Kali Linux ARM64 image (`kali-linux-2024.1-raspberry-pi-arm64.img.xz`)
  - Download from: https://old.kali.org/arm-images/kali-2024.1/
- Root/sudo access for mounting disk images

## Step-by-Step Guide

### 1. Setup

```bash
# Place your Kali image in the images/ directory
cp kali-linux-2024.1-raspberry-pi-arm64.img.xz images/

# Build and start the Docker container
docker-compose up -d
```

### 2. Create the Modified Image

```bash
# Enter the container
docker exec -it image-editor bash

# Navigate to scripts
cd /workdir/Scripts

# Run the automated conversion script
./create-uconsole-cm4-image.sh
```

The script will:
1. Extract and mount the Kali image
2. Replace the kernel with uConsole CM4 kernel
3. Configure display settings for proper rotation
4. Install 4G module support packages
5. Add ClockworkPi repository
6. Set up package pinning to prevent kernel conflicts

### 3. Write to SD Card

After the script completes:

```bash
# Exit the container
exit

# Write to SD card (replace /dev/sdX with your device)
sudo dd if=images/kali-linux-2024.1-raspberry-pi-arm64.img of=/dev/sdX bs=1M status=progress
```

⚠️ **Warning**: Double-check the device path before running dd!

## Expected Output

A modified Kali Linux image that:
- Boots properly on uConsole CM4
- Has correct screen orientation
- Supports 4G module if installed
- Can receive uConsole-specific updates

## Troubleshooting

### Loop Device Errors
```bash
# Clear existing loop devices
sudo losetup -D
```

### Permission Issues
The script requires root privileges inside the container. This is handled automatically.

### Container Issues
```bash
# Restart the container
docker-compose down
docker-compose up -d
```

## Customization

Edit `Scripts/create-uconsole-cm4-image.sh` to:
- Add additional packages
- Modify display settings
- Change kernel parameters
- Add custom configurations

## Time Estimate

The entire process takes approximately 15-30 minutes depending on:
- Internet connection speed
- System performance
- Image extraction time

## Credits

This tool was inspired by and references the official ClockworkPi documentation:
- [Kali Linux image for uConsole CM4](https://github.com/clockworkpi/uConsole/wiki/Kali-linux-image-for-uConsole-cm4)

The automated script builds upon the manual process described in the official wiki, streamlining it into a Docker-based solution for improved reproducibility and ease of use.