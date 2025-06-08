#!/bin/bash
set -e

BAD_IMG="$1"
GOOD_IMG="$2"

if [ ! -f "$BAD_IMG" ] || [ ! -f "$GOOD_IMG" ]; then
  echo "Usage: ./fix-partition-types.sh <bad-image> <good-image>"
  echo "This script will copy partition types from good image to bad image"
  exit 1
fi

echo "Comparing partition types between images..."
echo "=========================================="
echo ""

# Function to get partition type GUIDs
get_partition_info() {
  local img=$1
  echo "Image: $img"
  echo "-------------------------------------------"
  
  # Use sgdisk to show partition type GUIDs
  sgdisk -p "$img" 2>/dev/null | grep "^   [0-9]" || true
  
  # Also show the actual GUIDs
  echo ""
  echo "Partition Type GUIDs:"
  for i in 1 2 3; do
    guid=$(sgdisk -i $i "$img" 2>/dev/null | grep "Partition GUID code:" | awk '{print $4}')
    if [ ! -z "$guid" ]; then
      echo "  Partition $i: $guid"
    fi
  done
  echo ""
}

# Show current state
echo "CURRENT STATE:"
get_partition_info "$BAD_IMG"
echo ""
get_partition_info "$GOOD_IMG"

# Get the type GUIDs from the good image
echo "Extracting partition types from good image..."
PART1_TYPE=$(sgdisk -i 1 "$GOOD_IMG" 2>/dev/null | grep "Partition GUID code:" | awk '{print $4}' | cut -d' ' -f1)
PART2_TYPE=$(sgdisk -i 2 "$GOOD_IMG" 2>/dev/null | grep "Partition GUID code:" | awk '{print $4}' | cut -d' ' -f1)
PART3_TYPE=$(sgdisk -i 3 "$GOOD_IMG" 2>/dev/null | grep "Partition GUID code:" | awk '{print $4}' | cut -d' ' -f1)

echo ""
echo "Found partition types:"
echo "  Partition 1: $PART1_TYPE"
echo "  Partition 2: $PART2_TYPE"
echo "  Partition 3: $PART3_TYPE"
echo ""

read -p "Apply these partition types to $BAD_IMG? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

# Backup first
BACKUP_NAME="${BAD_IMG}.backup-types-$(date +%Y%m%d-%H%M%S)"
echo "Creating backup: $BACKUP_NAME"
cp "$BAD_IMG" "/backups/$BACKUP_NAME"

# Apply the partition types
echo "Applying partition types..."
sgdisk -t 1:"${PART1_TYPE#*:}" "$BAD_IMG"
sgdisk -t 2:"${PART2_TYPE#*:}" "$BAD_IMG"
sgdisk -t 3:"${PART3_TYPE#*:}" "$BAD_IMG"

echo ""
echo "✅ Partition types updated!"
echo ""
echo "AFTER FIX:"
get_partition_info "$BAD_IMG"

echo ""
echo "Done! The partition types have been copied from the good image."
echo "Original backed up to: /backups/$BACKUP_NAME"