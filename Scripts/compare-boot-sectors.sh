#!/bin/bash
set -e

IMG1="$1"
IMG2="$2"

if [ ! -f "$IMG1" ] || [ ! -f "$IMG2" ]; then
  echo "Usage: ./compare-boot-sectors.sh <image1> <image2>"
  echo "This script compares boot sectors and partition contents"
  exit 1
fi

echo "Comparing boot sectors and partitions..."
echo "======================================="
echo ""

# Compare first 8192 sectors (before first partition)
echo "1. Comparing pre-partition area (first 8192 sectors):"
echo "   This contains bootloader and GPT headers"
dd if="$IMG1" bs=512 count=8192 2>/dev/null | md5sum | awk '{print "   Image 1: " $1}'
dd if="$IMG2" bs=512 count=8192 2>/dev/null | md5sum | awk '{print "   Image 2: " $1}'

# Compare partition 1 (bootloader)
echo ""
echo "2. Comparing Partition 1 (sectors 8192-16383, typically bootloader):"
dd if="$IMG1" bs=512 skip=8192 count=8192 2>/dev/null | md5sum | awk '{print "   Image 1: " $1}'
dd if="$IMG2" bs=512 skip=8192 count=8192 2>/dev/null | md5sum | awk '{print "   Image 2: " $1}'

# Compare partition 2 (usually kernel/boot)
echo ""
echo "3. Comparing Partition 2 (sectors 16384-40959, typically kernel):"
dd if="$IMG1" bs=512 skip=16384 count=24576 2>/dev/null | md5sum | awk '{print "   Image 1: " $1}'
dd if="$IMG2" bs=512 skip=16384 count=24576 2>/dev/null | md5sum | awk '{print "   Image 2: " $1}'

# Look at partition 1 content
echo ""
echo "4. Examining Partition 1 content (first 512 bytes):"
echo "   Image 1:"
dd if="$IMG1" bs=512 skip=8192 count=1 2>/dev/null | hexdump -C | head -8
echo "   Image 2:"
dd if="$IMG2" bs=512 skip=8192 count=1 2>/dev/null | hexdump -C | head -8

# Check for Rockchip bootloader signatures
echo ""
echo "5. Checking for Rockchip bootloader signatures:"
echo -n "   Image 1: "
if dd if="$IMG1" bs=1 skip=$((0x8000)) count=4 2>/dev/null | grep -q "RK33"; then
  echo "Found RK33 signature at offset 0x8000"
else
  echo "No RK33 signature found"
fi
echo -n "   Image 2: "
if dd if="$IMG2" bs=1 skip=$((0x8000)) count=4 2>/dev/null | grep -q "RK33"; then
  echo "Found RK33 signature at offset 0x8000"
else
  echo "No RK33 signature found"
fi

# Mount and compare partition 3 if possible
echo ""
echo "6. Partition 3 filesystem info:"
TEMP_DIR1=$(mktemp -d)
TEMP_DIR2=$(mktemp -d)
LOOP1=$(losetup -f)
LOOP2=$(losetup -f)

# Setup loop devices with proper offset
losetup -o $((40960*512)) "$LOOP1" "$IMG1" 2>/dev/null || true
losetup -o $((40960*512)) "$LOOP2" "$IMG2" 2>/dev/null || true

# Try to get filesystem info
echo -n "   Image 1: "
file -sL "$LOOP1" 2>/dev/null | grep -o "ext[234]\|squashfs\|f2fs" || echo "Unknown filesystem"
echo -n "   Image 2: "
file -sL "$LOOP2" 2>/dev/null | grep -o "ext[234]\|squashfs\|f2fs" || echo "Unknown filesystem"

# Cleanup
losetup -d "$LOOP1" 2>/dev/null || true
losetup -d "$LOOP2" 2>/dev/null || true
rmdir "$TEMP_DIR1" "$TEMP_DIR2" 2>/dev/null || true

echo ""
echo "Summary of differences:"
echo "----------------------"
if dd if="$IMG1" bs=512 count=8192 2>/dev/null | md5sum | grep -q $(dd if="$IMG2" bs=512 count=8192 2>/dev/null | md5sum | awk '{print $1}'); then
  echo "✓ Pre-partition area (bootloader) is identical"
else
  echo "✗ Pre-partition area differs - this could be the boot issue!"
fi

if dd if="$IMG1" bs=512 skip=8192 count=8192 2>/dev/null | md5sum | grep -q $(dd if="$IMG2" bs=512 skip=8192 count=8192 2>/dev/null | md5sum | awk '{print $1}'); then
  echo "✓ Partition 1 is identical"
else
  echo "✗ Partition 1 differs"
fi

if dd if="$IMG1" bs=512 skip=16384 count=24576 2>/dev/null | md5sum | grep -q $(dd if="$IMG2" bs=512 skip=16384 count=24576 2>/dev/null | md5sum | awk '{print $1}'); then
  echo "✓ Partition 2 is identical"
else
  echo "✗ Partition 2 differs"
fi