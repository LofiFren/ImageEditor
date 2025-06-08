#!/bin/bash
set -e

IMG1="$1"
IMG2="$2"

if [ ! -f "$IMG1" ]; then
  echo "Usage: ./analyze-first-sectors.sh <image1> [image2]"
  exit 1
fi

echo "Analyzing First 32 Sectors"
echo "=========================="
echo ""

# Function to analyze an image's first sectors
analyze_image() {
  local img=$1
  local label=$2
  
  echo "$label: $img"
  echo "----------------------------------------"
  
  # Check if first sectors are empty
  ZEROS=$(dd if="$img" bs=512 count=32 2>/dev/null | od -x | grep -c "0000 0000 0000 0000" || true)
  echo "Zero blocks in first 32 sectors: $ZEROS"
  
  # Look for any signatures
  echo ""
  echo "Checking for signatures in first 16KB:"
  dd if="$img" bs=512 count=32 2>/dev/null | strings -n 8 | head -10
  
  # Show first sector
  echo ""
  echo "First sector (0) content:"
  dd if="$img" bs=512 count=1 2>/dev/null | xxd | head -8
  
  # Show sector 1
  echo ""
  echo "Sector 1 content:"
  dd if="$img" bs=512 skip=1 count=1 2>/dev/null | xxd | head -8
  
  echo ""
}

# Analyze first image
analyze_image "$IMG1" "Image 1"

# Analyze second image if provided
if [ -n "$IMG2" ] && [ -f "$IMG2" ]; then
  echo ""
  analyze_image "$IMG2" "Image 2"
  
  # Direct comparison
  echo ""
  echo "Sector-by-sector comparison (first 32):"
  echo "--------------------------------------"
  for s in $(seq 0 31); do
    MD5_1=$(dd if="$IMG1" bs=512 skip=$s count=1 2>/dev/null | md5sum | awk '{print $1}')
    MD5_2=$(dd if="$IMG2" bs=512 skip=$s count=1 2>/dev/null | md5sum | awk '{print $1}')
    if [ "$MD5_1" != "$MD5_2" ]; then
      echo "Sector $s: DIFFERENT"
    fi
  done
fi

echo ""
echo "Note: Sectors 0-31 often contain:"
echo "- MBR protective boot code"
echo "- Rockchip parameter block"
echo "- Board-specific configuration"