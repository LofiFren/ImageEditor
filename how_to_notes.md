
docker-compose up -d

docker-compose exec image-editor bash

# Inside the container
apt-get update
apt-get install -y fdisk e2fsprogs nano

# Make a backup
/scripts/backup.sh picocalc-luckfox-lyra-sd-2025-04-19-sdcard-slot-raw.img

# Analyze partitions
/scripts/analyze.sh picocalc-luckfox-lyra-sd-2025-04-19-sdcard-slot-raw.img

# Mount partition (typically 3 for rootfs)
/scripts/mount.sh picocalc-luckfox-lyra-sd-2025-04-19-sdcard-slot-raw.img 3

# Edit files
cd /mnt/image
nano etc/hostname
# etc.

# Unmount when done
/scripts/unmount.sh

# Exit container when finished
exit


# One the host - insert the micro sd card


diskutil list
diskutil unmountDisk /dev/disk5

sudo dd if=picocalc-luckfox-lyra-lofi-fren-2025-05-21.img of=/dev/disk5 bs=10M status=progress conv=fsync
