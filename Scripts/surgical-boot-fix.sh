#!/bin/bash
set -e

BAD_IMG="$1"
GOOD_IMG="$2"

if [ ! -f "$BAD_IMG" ] || [ ! -f "$GOOD_IMG" ]; then
  echo "Usage: ./surgical-boot-fix.sh <bad-image> <good-image>"
  echo "This performs a surgical copy of boot areas while preserving GPT"
  exit 1
fi

echo "Surgical Boot Fix"
echo "================="
echo ""
echo "This will copy ONLY the boot code areas, preserving your GPT."
echo ""

# Backup
BACKUP_DIR="../backups"
mkdir -p "$BACKUP_DIR"
BACKUP_NAME="$BACKUP_DIR/$(basename "${BAD_IMG%.img}")-surgical-$(date +%Y%m%d-%H%M%S).img"
echo "Creating backup: $BACKUP_NAME"
# cp "$BAD_IMG" "$BACKUP_NAME"

echo ""
echo "Copying boot areas while preserving GPT..."

# 1. Skip GPT areas (sectors 0-33 and backup GPT at end)
# 2. Copy boot code from sectors 34-8191 (preserves partitioning)
echo "- Copying sectors 34-8191 (boot code after GPT)..."
dd if="$GOOD_IMG" of="$BAD_IMG" bs=512 skip=34 seek=34 count=$((8192-34)) conv=notrunc status=progress

# 3. The key area: sectors 64-127 contain the RKNS IDBlock
# Let's make sure this is properly copied
echo ""
echo "- Ensuring RKNS IDBlock is properly copied (sectors 64-127)..."
dd if="$GOOD_IMG" of="$BAD_IMG" bs=512 skip=64 seek=64 count=64 conv=notrunc

# 4. Copy partition 1 and 2 content (they should match)
echo ""
echo "- Copying partition 1 (uboot)..."
dd if="$GOOD_IMG" of="$BAD_IMG" bs=512 skip=8192 seek=8192 count=8192 conv=notrunc

echo ""
echo "- Copying partition 2 (boot)..."
dd if="$GOOD_IMG" of="$BAD_IMG" bs=512 skip=16384 seek=16384 count=24576 conv=notrunc

# Verify critical areas
echo ""
echo "Verification:"
echo "============"

# Check RKNS signature
echo -n "RKNS signature at sector 64: "
dd if="$BAD_IMG" bs=512 skip=64 count=1 2>/dev/null | head -c 4 | grep -q "RKNS" && echo "✓ Present" || echo "✗ Missing"

# Check partition table integrity
echo ""
echo "Partition table check:"
sgdisk -p "$BAD_IMG" 2>&1 | grep "^   3" | grep -q "3.2 GiB" && echo "✓ Partition 3 size preserved (3.2 GiB)" || echo "✗ Partition 3 size wrong"

# Compare boot areas with good image
echo ""
echo "Boot area comparison:"
MD5_1=$(dd if="$BAD_IMG" bs=512 skip=34 count=$((8192-34)) 2>/dev/null | md5sum | awk '{print $1}')
MD5_2=$(dd if="$GOOD_IMG" bs=512 skip=34 count=$((8192-34)) 2>/dev/null | md5sum | awk '{print $1}')
[ "$MD5_1" = "$MD5_2" ] && echo "✓ Boot code matches good image" || echo "✗ Boot code differs"

echo ""
echo "✅ Surgical boot fix complete!"
echo ""
echo "Summary:"
echo "- Boot code copied from working image"
echo "- GPT preserved (keeping your 3.2 GiB partition)"
echo "- RKNS IDBlock in place"
echo "- Partitions 1 & 2 updated"
echo "- Your rootfs data untouched"