#!/bin/bash
set -e

IMG_FILE="/workdir/$1"

if [ ! -f "$IMG_FILE" ]; then
  echo "Error: Image file not found: $IMG_FILE"
  echo "Usage: ./analyze-image.sh <image-filename>"
  exit 1
fi

echo "Analyzing image: $IMG_FILE"
fdisk -l "$IMG_FILE"
