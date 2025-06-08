#!/bin/bash
set -e

IMG="$1"

if [ ! -f "$IMG" ]; then
  echo "Usage: ./check-rockchip-boot.sh <image>"
  echo "This checks for Rockchip-specific boot structures"
  exit 1
fi

echo "Rockchip Boot Structure Analysis"
echo "================================"
echo "Image: $IMG"
echo ""

# Function to check for signatures
check_signature() {
  local offset=$1
  local desc=$2
  local sig=$3
  
  echo -n "$desc (offset $offset): "
  if dd if="$IMG" bs=1 skip=$offset count=${#sig} 2>/dev/null | grep -q "$sig"; then
    echo "✓ Found '$sig'"
    dd if="$IMG" bs=1 skip=$offset count=32 2>/dev/null | hexdump -C | head -2
  else
    echo "✗ Not found"
  fi
}

# Check various offsets for Rockchip signatures
echo "1. Checking for Rockchip signatures:"
echo "-----------------------------------"

# Check sector 64 (0x40 * 512 = 0x8000)
check_signature $((0x40 * 512)) "Sector 64 (typical IDBlock)" "RK"

# Check for RK signatures at various offsets
for offset in 0x0 0x200 0x400 0x1000 0x2000 0x4000 0x8000 0x10000; do
  if dd if="$IMG" bs=1 skip=$((offset)) count=4 2>/dev/null | grep -q "RK"; then
    echo "Found RK signature at offset $offset:"
    dd if="$IMG" bs=1 skip=$((offset)) count=64 2>/dev/null | hexdump -C | head -4
  fi
done

echo ""
echo "2. Checking pre-GPT area (sectors 0-33):"
echo "----------------------------------------"
# First 34 sectors before GPT
PREGPT=$(dd if="$IMG" bs=512 count=34 2>/dev/null | hexdump -C | grep -v "00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00" | wc -l)
echo "Non-zero lines in pre-GPT area: $PREGPT"
if [ $PREGPT -gt 10 ]; then
  echo "✓ Pre-GPT area contains data (likely boot code)"
else
  echo "⚠ Pre-GPT area is mostly empty"
fi

echo ""
echo "3. IDBlock structure check:"
echo "--------------------------"
# Check for IDBlock at sector 64
dd if="$IMG" bs=512 skip=64 count=1 2>/dev/null > /tmp/sector64.bin
if [ -s /tmp/sector64.bin ]; then
  echo "Sector 64 content:"
  hexdump -C /tmp/sector64.bin | head -8
  
  # Check for RC4 encrypted marker (0x4 offset in sector)
  RC4_MARKER=$(dd if=/tmp/sector64.bin bs=1 skip=4 count=4 2>/dev/null | od -An -tx4 | tr -d ' ')
  if [ "$RC4_MARKER" = "0ff0aa55" ]; then
    echo "✓ Found RC4 encryption marker"
  fi
fi
rm -f /tmp/sector64.bin

echo ""
echo "4. Boot partition signatures:"
echo "-----------------------------"
# Check partition 1 (uboot)
echo -n "Partition 1 (uboot) signature: "
dd if="$IMG" bs=512 skip=8192 count=1 2>/dev/null | file -

# Check partition 2 (boot) 
echo -n "Partition 2 (boot) signature: "
dd if="$IMG" bs=512 skip=16384 count=1 2>/dev/null | file -

echo ""
echo "5. Comparing with working image structure:"
echo "-----------------------------------------"
if [ -n "$2" ] && [ -f "$2" ]; then
  GOOD_IMG="$2"
  echo "Comparing first 128 sectors with: $GOOD_IMG"
  
  for sector in 0 32 64 96; do
    MD5_1=$(dd if="$IMG" bs=512 skip=$sector count=32 2>/dev/null | md5sum | awk '{print $1}')
    MD5_2=$(dd if="$GOOD_IMG" bs=512 skip=$sector count=32 2>/dev/null | md5sum | awk '{print $1}')
    if [ "$MD5_1" = "$MD5_2" ]; then
      echo "  Sectors $sector-$((sector+31)): ✓ Match"
    else
      echo "  Sectors $sector-$((sector+31)): ✗ Different"
    fi
  done
else
  echo "To compare with working image, run:"
  echo "  $0 $IMG <working-image>"
fi

echo ""
echo "6. Recommendations:"
echo "------------------"
echo "If boot structures are missing, you may need to:"
echo "1. Use rkdeveloptool to create a complete backup:"
echo "   rkdeveloptool rl 0x0 0x200000 complete_backup.img"
echo ""
echo "2. Or flash using rkdeveloptool with proper loader:"
echo "   rkdeveloptool db MiniLoaderAll.bin"
echo "   rkdeveloptool wl 0x0 your_image.img"
echo ""
echo "3. Or extract and write the loader separately:"
echo "   dd if=idbloader.img of=your_image.img seek=64 conv=notrunc"