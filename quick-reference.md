
# Quick Reference

## Container Management
```bash
# Start container
docker-compose up -d

# Enter container
docker exec -it image-editor bash

# Stop container
docker-compose down

# View logs
docker-compose logs -f
```

## Kali Linux Image Creation
```bash
# Inside container
cd /workdir/Scripts
./create-uconsole-cm4-image.sh
```

## General Image Modification Workflow
```bash
# 1. Update packages (inside container)
apt-get update

# 2. Backup image before modifications
/workdir/Scripts/backup.sh your-image.img

# 3. Analyze image structure
/workdir/Scripts/deep-image-analysis.sh your-image.img

# 4. Mount partition (typically 3 for rootfs)
/workdir/Scripts/mount.sh your-image.img 3

# 5. Make modifications
cd /mnt/image
nano etc/hostname
nano etc/network/interfaces
# Add SSH keys, modify configs, etc.

# 6. Unmount when done
/workdir/Scripts/unmount.sh

# 7. Exit container
exit
```

## Writing to SD Card

### macOS
```bash
# List disks
diskutil list

# Unmount disk (replace diskX with your disk)
diskutil unmountDisk /dev/diskX

# Write image
sudo dd if=modified-image.img of=/dev/diskX bs=10M status=progress conv=fsync
```

### Linux
```bash
# List disks
lsblk

# Write image (replace sdX with your device)
sudo dd if=modified-image.img of=/dev/sdX bs=1M status=progress
```

## Common Script Usage

### Analysis Scripts
```bash
/workdir/Scripts/deep-image-analysis.sh image.img  # Detailed analysis
/workdir/Scripts/check-rockchip-boot.sh image.img  # Rockchip-specific
```

### Modification Scripts
```bash
/workdir/Scripts/mount.sh image.img 3              # Mount partition 3
/workdir/Scripts/unmount.sh                        # Unmount current
/workdir/Scripts/surgical-boot-fix.sh image.img    # Fix boot issues
```

### Backup/Restore
```bash
/workdir/Scripts/backup.sh original.img            # Creates timestamped backup
/workdir/Scripts/restore.sh backup-file.img        # Restore from backup
```

## Troubleshooting Commands

### Loop Device Issues
```bash
# List active loop devices
losetup -a

# Clear all loop devices
sudo losetup -D
```

### Container Issues
```bash
# Check container status
docker ps -a

# Remove and recreate
docker-compose down
docker-compose up -d --build
```

### Permission Issues
```bash
# Inside container - switch to root
sudo -i

# Or run scripts with sudo
sudo /workdir/Scripts/mount.sh image.img 3
```
