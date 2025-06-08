#!/bin/bash
set -e

IMG_FILE="/workdir/$1"
PARTITION_NUMBER=$2
MOUNT_POINT="/mnt/image"

if [ -z "$PARTITION_NUMBER" ]; then
  echo "Error: Partition number not specified"
  echo "Usage: ./mount-partition.sh <image-filename> <partition-number>"
  exit 1
fi

if [ ! -f "$IMG_FILE" ]; then
  echo "Error: Image file not found: $IMG_FILE"
  exit 1
fi

# Get start sector of partition
START_SECTOR=$(fdisk -l "$IMG_FILE" | grep "^${IMG_FILE}$PARTITION_NUMBER" | awk '{print $2}')

if [ -z "$START_SECTOR" ]; then
  echo "Error: Could not determine start sector for partition $PARTITION_NUMBER"
  exit 1
fi

# Calculate offset
OFFSET=$((START_SECTOR * 512))

echo "Mounting partition $PARTITION_NUMBER from $IMG_FILE"
echo "Start sector: $START_SECTOR, Offset: $OFFSET bytes"

mkdir -p "$MOUNT_POINT"
mount -o loop,offset=$OFFSET "$IMG_FILE" "$MOUNT_POINT"

echo "Mounted at $MOUNT_POINT"
echo "When finished, run ./unmount.sh to unmount"
