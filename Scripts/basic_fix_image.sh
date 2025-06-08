#!/bin/bash
set -e

IMG_FILE="$1"
GROWTH_SIZE="${2:-1G}"  # Default 1GB growth space

if [ ! -f "$IMG_FILE" ]; then
  echo "Error: Image file not found: $IMG_FILE"
  echo "Usage: ./fix-image-with-growth.sh <image-filename> [growth-size]"
  echo "  growth-size: Amount of free space to add (default: 1G)"
  echo "  Examples: 500M, 1G, 2G"
  exit 1
fi

echo "Analyzing image: $IMG_FILE"
echo "----------------------------------------"

# Get current file size
CURRENT_SIZE=$(stat -c%s "$IMG_FILE")
echo "Current file size: $(numfmt --to=iec-i --suffix=B $CURRENT_SIZE)"

# Find the last partition end sector
LAST_SECTOR=$(fdisk -l "$IMG_FILE" 2>&1 | grep "^$IMG_FILE" | awk '{print $3}' | sort -n | tail -1)

if [ -z "$LAST_SECTOR" ]; then
  echo "Error: Could not determine last partition sector"
  exit 1
fi

# Calculate size needed for existing partitions
PARTITION_END_BYTES=$((($LAST_SECTOR + 1) * 512))
echo "Partitions end at: sector $LAST_SECTOR ($(numfmt --to=iec-i --suffix=B $PARTITION_END_BYTES))"

# Convert growth size to bytes
GROWTH_BYTES=$(numfmt --from=iec "$GROWTH_SIZE")
echo "Growth space requested: $GROWTH_SIZE ($GROWTH_BYTES bytes)"

# Calculate new total size
NEW_SIZE=$(($PARTITION_END_BYTES + $GROWTH_BYTES))
echo "New total size will be: $(numfmt --to=iec-i --suffix=B $NEW_SIZE)"

# Add some padding for GPT backup (33 sectors = 16.5KB)
GPT_PADDING=$((33 * 512))
FINAL_SIZE=$(($NEW_SIZE + $GPT_PADDING))

echo ""
echo "Plan:"
echo "1. Backup the image"
echo "2. Truncate to optimal size with growth space"
echo "3. Fix GPT tables"
echo ""

read -p "Proceed? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

# Create backup
BACKUP_NAME="${IMG_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
# echo "Creating backup: $BACKUP_NAME"
# cp "$IMG_FILE" "$BACKUP_NAME"

echo "Creating backup of $IMG_FILE as $BACKUP_NAME"
# cp "$IMG_FILE" "/backups/$BACKUP_NAME"

# Truncate to new size
echo "Resizing image to $(numfmt --to=iec-i --suffix=B $FINAL_SIZE)..."
truncate -s $FINAL_SIZE "$IMG_FILE"

# Fix GPT with gdisk
echo "Fixing GPT tables..."
(
  echo "x"     # Expert mode
  echo "e"     # Relocate backup structures to end of disk
  echo "w"     # Write changes
  echo "Y"     # Confirm
) | gdisk "$IMG_FILE"

echo ""
echo "✅ Image fixed successfully!"
echo "Original backed up to: /backups/$BACKUP_NAME"
echo ""

# Show final state
echo "Final partition layout:"
# fdisk -l "$IMG_FILE" 2>&1 | grep -v "GPT PMBR size mismatch" | grep -v "backup GPT table"

# Show available space
echo ""
echo "Available space for filesystem expansion:"
LAST_PARTITION=$(fdisk -l "$IMG_FILE" 2>&1 | grep "^$IMG_FILE" | tail -1)
PARTITION_NUM=$(echo "$LAST_PARTITION" | awk '{print $1}' | grep -o '[0-9]*$')
PARTITION_END=$(echo "$LAST_PARTITION" | awk '{print $3}')
DISK_SECTORS=$(fdisk -l "$IMG_FILE" 2>&1 | grep "sectors$" | awk '{print $(NF-1)}')
FREE_SECTORS=$(($DISK_SECTORS - $PARTITION_END - 33))  # 33 for GPT backup
FREE_BYTES=$(($FREE_SECTORS * 512))
echo "  Free space after partition $PARTITION_NUM: $(numfmt --to=iec-i --suffix=B $FREE_BYTES)"
echo ""
echo "To extend the root filesystem later, you can:"
echo "  1. Use 'parted' or 'gdisk' to extend partition $PARTITION_NUM"
echo "  2. Then resize the filesystem with 'resize2fs' or appropriate tool"