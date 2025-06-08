#!/bin/bash
set -e

BACKUP_FILE="/backups/$1"
TARGET_FILE="/workdir/$2"

if [ ! -f "$BACKUP_FILE" ]; then
  echo "Error: Backup file not found: $BACKUP_FILE"
  echo "Usage: /scripts/restore.sh <backup-filename> <target-filename>"
  exit 1
fi

echo "Restoring $BACKUP_FILE to $TARGET_FILE"

# Confirm restore
echo "This will overwrite $TARGET_FILE with $BACKUP_FILE"
read -p "Are you sure you want to proceed? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Restore cancelled"
  exit 1
fi

cp "$BACKUP_FILE" "$TARGET_FILE"
echo "Restore completed successfully!"
