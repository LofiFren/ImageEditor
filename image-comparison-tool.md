# Image Comparison and Analysis Tool

This tool provides utilities for analyzing, comparing, and modifying disk images, particularly useful for embedded systems and single-board computers.

## Purpose

- Analyze disk image partitions and structure
- Mount and modify image contents
- Create backups before modifications
- Compare different image versions
- Perform surgical fixes on boot sectors

## Prerequisites

- Docker and Docker Compose installed
- Disk images to analyze/modify
- Root/sudo access for mounting operations

## Available Scripts

### Core Operations

1. **analyze.sh** - Examine image structure
2. **mount.sh** - Mount specific partitions
3. **unmount.sh** - Safely unmount partitions
4. **backup.sh** - Create image backups
5. **restore.sh** - Restore from backups

### Advanced Operations

1. **deep-image-analysis.sh** - Detailed partition analysis
2. **surgical-boot-fix.sh** - Fix boot sector issues
3. **check-rockchip-boot.sh** - Verify Rockchip boot structures

## Step-by-Step Usage

### 1. Setup Environment

```bash
# Start the Docker container
docker-compose up -d

# Enter the container
docker exec -it image-editor bash

# Update package list
apt-get update
```

### 2. Analyze an Image

```bash
# Create a backup first
/workdir/Scripts/backup.sh your-image.img

# Analyze partition structure
/workdir/Scripts/deep-image-analysis.sh your-image.img
```

### 3. Mount and Modify

```bash
# Mount a specific partition (e.g., partition 3 for rootfs)
/workdir/Scripts/mount.sh your-image.img 3

# Navigate to mounted filesystem
cd /mnt/image

# Make your modifications
nano etc/hostname
# ... other edits ...

# Unmount when done
/workdir/Scripts/unmount.sh
```

### 4. Write Modified Image

```bash
# Exit the container
exit

# On the host, write to SD card
diskutil list  # macOS
diskutil unmountDisk /dev/disk5

sudo dd if=your-modified-image.img of=/dev/disk5 bs=10M status=progress conv=fsync
```

## Common Use Cases

### Changing Hostname
```bash
/workdir/Scripts/mount.sh image.img 3
nano /mnt/image/etc/hostname
/workdir/Scripts/unmount.sh
```

### Modifying Network Configuration
```bash
/workdir/Scripts/mount.sh image.img 3
nano /mnt/image/etc/network/interfaces
/workdir/Scripts/unmount.sh
```

### Adding SSH Keys
```bash
/workdir/Scripts/mount.sh image.img 3
mkdir -p /mnt/image/root/.ssh
echo "your-ssh-key" > /mnt/image/root/.ssh/authorized_keys
chmod 600 /mnt/image/root/.ssh/authorized_keys
/workdir/Scripts/unmount.sh
```

### Deep Analysis
```bash
/workdir/Scripts/deep-image-analysis.sh image.img
```

## Comparing Two Images

### Method 1: Side-by-Side Mounting
```bash
# Mount first image
/workdir/Scripts/mount.sh image1.img 3
mv /mnt/image /mnt/image1

# Mount second image
/workdir/Scripts/mount.sh image2.img 3
mv /mnt/image /mnt/image2

# Compare specific files
diff /mnt/image1/etc/hostname /mnt/image2/etc/hostname

# Compare entire directories
diff -r /mnt/image1/etc /mnt/image2/etc

# Find all differences (may be verbose)
diff -r /mnt/image1 /mnt/image2 > differences.txt

# Unmount both
umount /mnt/image1
umount /mnt/image2
```

### Method 2: Sequential Comparison
```bash
# Analyze first image
/workdir/Scripts/deep-image-analysis.sh image1.img > image1-analysis.txt

# Analyze second image  
/workdir/Scripts/deep-image-analysis.sh image2.img > image2-analysis.txt

# Compare analyses
diff image1-analysis.txt image2-analysis.txt
```

### Method 3: Specific File Comparison
```bash
# Extract specific files from both images without full mount
# Mount first image
/workdir/Scripts/mount.sh image1.img 3
cp /mnt/image/etc/fstab /tmp/fstab-image1
cp -r /mnt/image/etc/network /tmp/network-image1
/workdir/Scripts/unmount.sh

# Mount second image
/workdir/Scripts/mount.sh image2.img 3
cp /mnt/image/etc/fstab /tmp/fstab-image2
cp -r /mnt/image/etc/network /tmp/network-image2
/workdir/Scripts/unmount.sh

# Compare extracted files
diff /tmp/fstab-image1 /tmp/fstab-image2
diff -r /tmp/network-image1 /tmp/network-image2
```

### Tips for Image Comparison
- Use `diff -u` for unified diff format (easier to read)
- Use `diff --brief -r` for a summary of different files only
- Consider using `rsync -rvn --delete` to see what would change
- For binary differences, use `cmp -l image1.img image2.img`

## Safety Guidelines

1. **Always backup** before modifications
2. **Verify partition numbers** before mounting
3. **Unmount properly** to ensure changes are written
4. **Check device paths** carefully when using dd

## Troubleshooting

### Mount Fails
- Ensure no other mounts are active
- Check partition exists with analyze.sh
- Verify image isn't corrupted

### Changes Not Persisting
- Ensure proper unmounting
- Check filesystem isn't read-only
- Verify no errors during unmount

### Loop Device Busy
```bash
# Force cleanup
losetup -D
```

## Advanced Features

### Comparing Images
```bash
# Mount two images simultaneously
/scripts/mount.sh image1.img 3
mv /mnt/image /mnt/image1
/scripts/mount.sh image2.img 3
# Compare contents
diff -r /mnt/image1 /mnt/image
```

### Fixing Boot Issues
```bash
/workdir/Scripts/surgical-boot-fix.sh broken-image.img
```

### Rockchip-Specific
```bash
/workdir/Scripts/check-rockchip-boot.sh rockchip-image.img
```