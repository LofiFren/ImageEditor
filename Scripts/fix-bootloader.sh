#!/bin/bash
set -e

BAD_IMG="$1"
GOOD_IMG="$2"

if [ ! -f "$BAD_IMG" ] || [ ! -f "$GOOD_IMG" ]; then
  echo "Usage: ./fix-bootloader.sh <bad-image> <good-image>"
  echo "This script copies the bootloader from good image to bad image"
  exit 1
fi

echo "Bootloader Fix Script"
echo "===================="
echo ""
echo "This will copy the bootloader area from:"
echo "  Good: $GOOD_IMG"
echo "  To:   $BAD_IMG"
echo ""
echo "The bootloader area includes:"
echo "  - Rockchip idbloader"
echo "  - GPT partition table"
echo "  - Other boot-critical data"
echo ""

# Show current difference
echo "Current bootloader checksums:"
echo -n "  Bad image:  "
dd if="$BAD_IMG" bs=512 count=8192 2>/dev/null | md5sum | awk '{print $1}'
echo -n "  Good image: "
dd if="$GOOD_IMG" bs=512 count=8192 2>/dev/null | md5sum | awk '{print $1}'
echo ""

read -p "Proceed with bootloader fix? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

# Create backup
BACKUP_NAME="${BAD_IMG}.before-bootloader-fix-$(date +%Y%m%d-%H%M%S)"
echo ""
echo "Creating backup: $BACKUP_NAME"
cp "$BAD_IMG" "/backups/$BACKUP_NAME"

# Copy the bootloader area (first 8192 sectors = 4MB)
echo "Copying bootloader area..."
dd if="$GOOD_IMG" of="$BAD_IMG" bs=512 count=8192 conv=notrunc status=progress

# Verify the fix
echo ""
echo "Verifying fix..."
NEW_MD5=$(dd if="$BAD_IMG" bs=512 count=8192 2>/dev/null | md5sum | awk '{print $1}')
GOOD_MD5=$(dd if="$GOOD_IMG" bs=512 count=8192 2>/dev/null | md5sum | awk '{print $1}')

if [ "$NEW_MD5" = "$GOOD_MD5" ]; then
  echo "✅ SUCCESS! Bootloader area now matches the good image."
  echo ""
  echo "The image should now be bootable!"
  echo "Original image backed up to: /backups/$BACKUP_NAME"
else
  echo "❌ ERROR: Bootloader copy failed!"
  echo "Restoring from backup..."
  cp "/backups/$BACKUP_NAME" "$BAD_IMG"

  exit 1
fi

# Final check - show partition table
echo ""
echo "Final partition table:"
fdisk -l "$BAD_IMG" 2>&1 | grep -v "GPT PMBR size mismatch" | grep -v "backup GPT table"