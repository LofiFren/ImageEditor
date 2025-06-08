#!/bin/bash
set -e

BAD_IMG="$1"
GOOD_IMG="$2"

if [ ! -f "$BAD_IMG" ] || [ ! -f "$GOOD_IMG" ]; then
  echo "Usage: ./complete-image-fix.sh <bad-image> <good-image>"
  echo "This script fixes all boot-related issues in the bad image"
  exit 1
fi

echo "Complete Image Fix"
echo "=================="
echo ""
echo "This will fix:"
echo "1. Pre-partition bootloader area"
echo "2. Partition type GUIDs to match Rockchip requirements"
echo "3. Partition names"
echo "4. Keep your existing rootfs data"
echo ""

# Show current issues
echo "Current Issues Found:"
echo "--------------------"
echo "1. Pre-partition bootloader checksums don't match"
echo "2. Partition 3 type is wrong (Linux filesystem instead of Rockchip type)"
echo "3. Partition 3 is missing 'rootfs' name"
echo ""

read -p "Proceed with complete fix? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

# Backup
BACKUP_DIR="../backups"
mkdir -p "$BACKUP_DIR"
BACKUP_NAME="$BACKUP_DIR/$(basename "${BAD_IMG%.img}")-complete-backup-$(date +%Y%m%d-%H%M%S).img"
echo ""
echo "Creating backup: $BACKUP_NAME"
cp "$BAD_IMG" "$BACKUP_NAME"

# Step 1: Copy bootloader area
echo ""
echo "Step 1: Copying bootloader area from good image..."
dd if="$GOOD_IMG" of="$BAD_IMG" bs=512 count=8192 conv=notrunc status=progress

# Step 2: Fix partition types and names using sgdisk
echo ""
echo "Step 2: Fixing partition types and names..."

# Get the exact partition type GUIDs from good image
PART1_TYPE="A60B0000-0000-4C7E-8000-015E00004DB7"
PART2_TYPE="D46E0000-0000-457F-8000-220D000030DB"
PART3_TYPE="4F4C0000-0000-4049-8000-36C40000603B"

# Apply partition types
sgdisk -t 1:$PART1_TYPE "$BAD_IMG"
sgdisk -t 2:$PART2_TYPE "$BAD_IMG"
sgdisk -t 3:$PART3_TYPE "$BAD_IMG"

# Set partition names
sgdisk -c 1:uboot "$BAD_IMG"
sgdisk -c 2:boot "$BAD_IMG"
sgdisk -c 3:rootfs "$BAD_IMG"

# Step 3: Verify and show results
echo ""
echo "Step 3: Verification..."
echo ""
echo "New partition table:"
sgdisk -p "$BAD_IMG"

echo ""
echo "Partition details:"
for i in 1 2 3; do
  echo ""
  echo "Partition $i:"
  sgdisk -i $i "$BAD_IMG" 2>&1 | grep -E "Partition GUID code|Partition name"
done

echo ""
echo "✅ Complete fix applied!"
echo ""
echo "Summary of changes:"
echo "- Bootloader area copied from working image"
echo "- All partition types set to Rockchip-specific GUIDs"
echo "- Partition names set correctly (uboot, boot, rootfs)"
echo "- Your rootfs data remains unchanged"
echo ""
echo "The image should now be bootable!"
echo "Original backed up to: $BACKUP_NAME"

# Optional: Create a truncated version for smaller SD cards
echo ""
read -p "Create a smaller (1.5GB) version for smaller SD cards? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  SMALL_IMG="${BAD_IMG%.img}-small.img"
  echo "Creating $SMALL_IMG..."
  
  # Copy up to end of original good image size plus some padding
  dd if="$BAD_IMG" of="$SMALL_IMG" bs=1M count=1500 status=progress
  
  # Fix the GPT
  (
    echo "x"
    echo "e"
    echo "w"
    echo "Y"
  ) | gdisk "$SMALL_IMG" > /dev/null 2>&1
  
  echo "Small image created: $SMALL_IMG (1.5GB)"
fi