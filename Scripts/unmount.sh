#!/bin/bash
set -e

MOUNT_POINT="/mnt/image"

if mount | grep -q "$MOUNT_POINT"; then
  echo "Unmounting $MOUNT_POINT"
  umount "$MOUNT_POINT"
  echo "Successfully unmounted"
else
  echo "Nothing mounted at $MOUNT_POINT"
fi
