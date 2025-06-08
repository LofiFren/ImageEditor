#!/bin/bash
set -e

IMG_FILE="/workdir/$1"

if [ ! -f "$IMG_FILE" ]; then
  echo "Error: Image file not found: $IMG_FILE"
  echo "Usage: /scripts/backup.sh <image-filename>"
  exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="$(basename ${IMG_FILE%.img})_backup_${TIMESTAMP}.img"

echo "Creating backup of $IMG_FILE as $BACKUP_NAME"
cp "$IMG_FILE" "/backups/$BACKUP_NAME"
echo "Backup created successfully at /backups/$BACKUP_NAME"
