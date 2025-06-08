#!/bin/bash
set -e

IMG1="$1"
IMG2="$2"

if [ ! -f "$IMG1" ] || [ ! -f "$IMG2" ]; then
  echo "Usage: ./deep-image-analysis.sh <image1> <image2>"
  echo "This script performs deep analysis of image differences"
  exit 1
fi

echo "Deep Image Analysis"
echo "==================="
echo "Image 1: $IMG1 ($(stat -c%s "$IMG1" | numfmt --to=iec-i --suffix=B))"
echo "Image 2: $IMG2 ($(stat -c%s "$IMG2" | numfmt --to=iec-i --suffix=B))"
echo ""

# 1. Check exact file sizes
echo "1. File Size Comparison:"
SIZE1=$(stat -c%s "$IMG1")
SIZE2=$(stat -c%s "$IMG2")
echo "   Image 1: $SIZE1 bytes"
echo "   Image 2: $SIZE2 bytes"
echo "   Difference: $((SIZE1 - SIZE2)) bytes"
echo ""

# 2. GPT header analysis
echo "2. GPT Header Analysis:"
echo "   Image 1:"
sgdisk -p "$IMG1" 2>&1 | head -20
echo ""
echo "   Image 2:"
sgdisk -p "$IMG2" 2>&1 | head -20
echo ""

# 3. Detailed partition comparison
echo "3. Detailed Partition Information:"
for i in 1 2 3; do
  echo ""
  echo "   Partition $i comparison:"
  echo "   Image 1:"
  sgdisk -i $i "$IMG1" 2>&1 | grep -E "Partition GUID|Partition unique|First sector|Last sector|Partition size|Attribute flags|Partition name"
  echo "   Image 2:"
  sgdisk -i $i "$IMG2" 2>&1 | grep -E "Partition GUID|Partition unique|First sector|Last sector|Partition size|Attribute flags|Partition name"
done

# 4. Check for Rockchip boot signatures at various offsets
echo ""
echo "4. Rockchip Boot Signature Search:"
for offset in 0x0 0x200 0x400 0x8000 0x8800 0x9000 0x10000 0x20000; do
  echo -n "   Offset $offset - Image 1: "
  if dd if="$IMG1" bs=1 skip=$((offset)) count=8 2>/dev/null | strings | grep -E "RK|LOADER|IDBlock" > /dev/null; then
    dd if="$IMG1" bs=1 skip=$((offset)) count=8 2>/dev/null | od -c | head -1
  else
    echo "No signature"
  fi
  echo -n "   Offset $offset - Image 2: "
  if dd if="$IMG2" bs=1 skip=$((offset)) count=8 2>/dev/null | strings | grep -E "RK|LOADER|IDBlock" > /dev/null; then
    dd if="$IMG2" bs=1 skip=$((offset)) count=8 2>/dev/null | od -c | head -1
  else
    echo "No signature"
  fi
done

# 5. Binary difference scan
echo ""
echo "5. Binary Difference Regions (first differences in each 1MB block):"
BLOCK_SIZE=$((1024*1024))  # 1MB blocks
MAX_BLOCKS=100  # Check first 100MB
DIFF_COUNT=0

for ((i=0; i<MAX_BLOCKS; i++)); do
  MD5_1=$(dd if="$IMG1" bs=$BLOCK_SIZE skip=$i count=1 2>/dev/null | md5sum | awk '{print $1}')
  MD5_2=$(dd if="$IMG2" bs=$BLOCK_SIZE skip=$i count=1 2>/dev/null | md5sum | awk '{print $1}')
  
  if [ "$MD5_1" != "$MD5_2" ]; then
    echo "   Block $i (offset $((i*BLOCK_SIZE))): DIFFERENT"
    DIFF_COUNT=$((DIFF_COUNT + 1))
    if [ $DIFF_COUNT -ge 10 ]; then
      echo "   ... (stopping after 10 differences)"
      break
    fi
  fi
done

# 6. Check partition 3 content specifically
echo ""
echo "6. Partition 3 (rootfs) Analysis:"
# Calculate partition 3 size in both images
P3_START=40960
P3_END_1=$(sgdisk -i 3 "$IMG1" 2>&1 | grep "Last sector" | awk '{print $3}')
P3_END_2=$(sgdisk -i 3 "$IMG2" 2>&1 | grep "Last sector" | awk '{print $3}')
echo "   Image 1 partition 3: sectors $P3_START to $P3_END_1"
echo "   Image 2 partition 3: sectors $P3_START to $P3_END_2"

# Check if partition 3 content matches (first 1MB)
echo -n "   First 1MB of partition 3: "
MD5_1=$(dd if="$IMG1" bs=512 skip=$P3_START count=2048 2>/dev/null | md5sum | awk '{print $1}')
MD5_2=$(dd if="$IMG2" bs=512 skip=$P3_START count=2048 2>/dev/null | md5sum | awk '{print $1}')
if [ "$MD5_1" = "$MD5_2" ]; then
  echo "MATCH"
else
  echo "DIFFERENT"
fi

echo ""
echo "7. Recommendations:"
echo "   Based on the analysis above, check for:"
echo "   - Size differences that might indicate truncation"
echo "   - Missing boot signatures"
echo "   - Partition table inconsistencies"
echo "   - Actual partition content differences"