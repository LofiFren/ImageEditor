# Image Editor Tools

This repository contains Docker-based tools for working with disk images:

1. **[Kali Linux Image Editor](kali-linux-image-editor.md)** - Automated tool for creating Kali Linux images for uConsole CM4
2. **[Image Comparison Tool](image-comparison-tool.md)** - General-purpose image analysis and modification utilities
3. **[Quick Reference](quick-reference.md)** - Common commands and workflows

## Prerequisites

- Docker and Docker Compose installed on your system
- At least 16GB of free disk space
- The Kali Linux ARM64 image (`kali-linux-2024.1-raspberry-pi-arm64.img.xz`) in the `images/` directory
- I was able to find it here: https://old.kali.org/arm-images/kali-2024.1/
- Root/sudo access for mounting and modifying disk images

## Quick Start

### 1. Build and Start the Docker Container

```bash
# Build the Docker image and start the container
docker-compose up -d
```

### 2. Enter the Container

```bash
# Access the running container
docker exec -it image-editor bash
```

### 3. Run the Image Creation Script

```bash
# Navigate to the scripts directory
cd /workdir/Scripts

# Execute the image creation script
./create-uconsole-cm4-image-fixed.sh
```

## What the Script Does

The automated script performs the following modifications to the base Kali Linux image:

1. **Kernel Replacement**: Removes the default Kali kernel and installs the uConsole CM4-specific kernel
2. **Display Configuration**: Sets up proper display rotation (right) for the uConsole screen
3. **4G Module Support**: Installs necessary packages and configurations for 4G connectivity
4. **Repository Configuration**: Adds ClockworkPi's APT repository for uConsole-specific packages
5. **Package Pinning**: Prevents accidental installation of incompatible Kali kernel packages

## Writing to SD Card

After the script completes successfully, you'll have a modified image ready to write:

```bash
# Write the image to your SD card (replace /dev/sdX with your actual device)
# Note this is to be run on the host machine i.e your mac. be sure to cd to the images dir where your new image islikely ImageEditor/images
# Replace /dev/sdX with your actual SD card device

sudo dd if=kali-linux-2024.1-raspberry-pi-arm64.img of=/dev/sdX bs=1M status=progress
```

**⚠️ Warning**: Be extremely careful with the `dd` command. Using the wrong device path can destroy data on your system.

## Directory Structure

```
/workdir/
├── images/                 # Contains the Kali Linux image files
├── Scripts/               # Automation scripts
├── backups/              # Backup directory (if needed)
└── docker-compose.yml    # Docker configuration
```

## Troubleshooting

### Permission Denied Errors
The script requires root privileges to mount and modify the image. It will automatically check for proper permissions.

### Loop Device Issues
If you encounter loop device errors, ensure no other loop devices are in use:
```bash
# List current loop devices
losetup -a

# Clear unused loop devices
sudo losetup -D
```

### Container Won't Start
Check if the container is already running:
```bash
docker ps -a
docker-compose down
docker-compose up -d
```

## Advanced Usage

### Modifying the Script
The main script is located at `Scripts/create-uconsole-cm4-image.sh`. You can edit it to:
- Change package selections
- Modify display settings
- Add custom configurations

### Using Existing Scripts
The `Scripts/` directory contains various utility scripts for:
- Image analysis
- Partition mounting/unmounting
- Bootloader fixes
- Backup and restore operations

## Requirements

- Docker Engine 20.10 or later
- Docker Compose 1.27 or later
- Linux host system (for proper loop device support)
- Minimum 8GB RAM recommended
- SD card (8GB or larger) for the final image

## Notes

- The image modification process can take 15-30 minutes depending on your internet connection and system performance
- The container runs in privileged mode to access loop devices and mount filesystems
- All modifications are performed within the container for safety and reproducibility