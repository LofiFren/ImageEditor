#!/bin/bash
set -e

IMG="$1"
NEW_END_SECTOR="${2:-6854655}"  # Default to your original partition 3 end

if [ ! -f "$IMG" ]; then
  echo "Usage: ./restore-partition-size.sh <image> [end-sector]"
  echo "This restores partition 3 to its larger size"
  echo "Default end sector: 6854655 (3.2 GiB)"
  exit 1
fi

echo "Restore Partition Size"
echo "====================="
echo ""
echo "Current partition table:"
sgdisk -p "$IMG" | grep "^   3"
echo ""
echo "Will resize partition 3 to end at sector: $NEW_END_SECTOR"
echo ""

read -p "Proceed? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

# Backup
BACKUP_DIR="../backups"
mkdir -p "$BACKUP_DIR"
BACKUP_NAME="$BACKUP_DIR/$(basename "${IMG%.img}")-before-resize-$(date +%Y%m%d-%H%M%S).img"
echo "Creating backup: $BACKUP_NAME"
cp "$IMG" "$BACKUP_NAME"

# Delete and recreate partition 3 with correct size
echo ""
echo "Resizing partition 3..."

# We need to preserve the partition type GUID and name
PART3_TYPE="4F4C0000-0000-4049-8000-36C40000603B"

# Delete partition 3
sgdisk -d 3 "$IMG"

# Create new partition 3 with larger size
sgdisk -n 3:40960:$NEW_END_SECTOR "$IMG"
sgdisk -t 3:$PART3_TYPE "$IMG"
sgdisk -c 3:rootfs "$IMG"

# Verify
echo ""
echo "New partition table:"
sgdisk -p "$IMG" | grep "^   3"

echo ""
echo "✅ Partition 3 restored to larger size!"
echo "The image now has the correct:"
echo "- Bootloader from good image"
echo "- Rockchip partition types"
echo "- Correct partition names"
echo "- Your original larger partition size"