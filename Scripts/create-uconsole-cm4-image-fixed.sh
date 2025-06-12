#!/bin/bash

# Script to create Kali Linux image for uConsole CM4
# Based on the instructions in Kali-linux-image-for-uConsole-cm4.md

set -e

# Check if running with proper privileges
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root or with sudo"
    exit 1
fi

# Configuration
WORKDIR="/workdir"
IMAGE_DIR="${WORKDIR}/images"
IMAGE_NAME="kali-linux-2024.1-raspberry-pi-arm64.img"
IMAGE_XZ="${IMAGE_NAME}.xz"
MOUNT_POINT="/mnt/p1"

# Function to cleanup on exit
cleanup() {
    echo "Cleaning up..."
    # Unmount chroot environment if mounted
    umount ${MOUNT_POINT}/dev/pts 2>/dev/null || true
    umount ${MOUNT_POINT}/dev 2>/dev/null || true
    umount ${MOUNT_POINT}/proc 2>/dev/null || true
    umount ${MOUNT_POINT}/sys 2>/dev/null || true
    umount ${MOUNT_POINT}/boot 2>/dev/null || true
    umount ${MOUNT_POINT} 2>/dev/null || true
    
    # Remove device mappings and detach loop device
    if [ ! -z "${IMAGE_NAME}" ] && [ -f "${IMAGE_DIR}/${IMAGE_NAME}" ]; then
        kpartx -d ${IMAGE_DIR}/${IMAGE_NAME} 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Create mount point if it doesn't exist
mkdir -p ${MOUNT_POINT}

# Clean up any existing loop devices for this image
echo "Checking for existing loop devices..."
EXISTING_LOOPS=$(losetup -a | grep "${IMAGE_NAME}" | cut -d: -f1)
if [ ! -z "${EXISTING_LOOPS}" ]; then
    echo "Found existing loop devices, cleaning up..."
    for loop in ${EXISTING_LOOPS}; do
        echo "Removing ${loop}..."
        kpartx -d ${loop} 2>/dev/null || true
        losetup -d ${loop} 2>/dev/null || true
    done
fi

# Check if image exists
if [ ! -f "${IMAGE_DIR}/${IMAGE_XZ}" ]; then
    echo "Error: Image file ${IMAGE_XZ} not found in ${IMAGE_DIR}"
    exit 1
fi

# Extract image if needed
if [ ! -f "${IMAGE_DIR}/${IMAGE_NAME}" ]; then
    echo "Extracting ${IMAGE_XZ}..."
    cd ${IMAGE_DIR}
    xz -d -k ${IMAGE_XZ}
    cd -
fi

echo "Setting up loop device for ${IMAGE_NAME}..."
# Use kpartx to create device mappings for partitions
kpartx -av ${IMAGE_DIR}/${IMAGE_NAME}
sleep 2

# Find the loop device that was created
LOOP_DEVICE=$(losetup -a | grep ${IMAGE_NAME} | cut -d: -f1)
echo "Loop device: ${LOOP_DEVICE}"

# Get the loop device number
LOOP_NUM=$(echo ${LOOP_DEVICE} | grep -o '[0-9]*$')

echo "Mounting partitions..."
# Wait a moment for device mappings to be created
sleep 1

# Find the actual mapper devices created
MAPPER_DEVICES=$(ls /dev/mapper/loop*p* 2>/dev/null | grep -E "loop[0-9]+p[12]$" | sort)
echo "Debug: Found mapper devices:"
echo "${MAPPER_DEVICES}"
if [ -z "${MAPPER_DEVICES}" ]; then
    echo "Error: No mapper devices found!"
    echo "Contents of /dev/mapper/:"
    ls -la /dev/mapper/
    exit 1
fi

# Get the first device to extract the loop number
FIRST_DEVICE=$(echo "${MAPPER_DEVICES}" | head -n1)
echo "Debug: First mapper device: ${FIRST_DEVICE}"

# Get the correct loop device number from the mapper devices
MAPPER_LOOP_NUM=$(echo "${FIRST_DEVICE}" | sed 's/.*loop\([0-9]*\)p[0-9]*/\1/')
echo "Debug: Extracted MAPPER_LOOP_NUM='${MAPPER_LOOP_NUM}'"
echo "Using mapper devices for loop${MAPPER_LOOP_NUM}"

# kpartx creates mappings in /dev/mapper/
if [ -z "${MAPPER_LOOP_NUM}" ]; then
    echo "Error: Could not determine mapper loop number!"
    exit 1
fi

# Construct the device paths
DEVICE_P2="/dev/mapper/loop${MAPPER_LOOP_NUM}p2"
DEVICE_P1="/dev/mapper/loop${MAPPER_LOOP_NUM}p1"

echo "Debug: DEVICE_P2='${DEVICE_P2}'"
echo "Debug: DEVICE_P1='${DEVICE_P1}'"
echo "Debug: MOUNT_POINT='${MOUNT_POINT}'"

# Verify devices exist before mounting
if [ ! -b "${DEVICE_P2}" ]; then
    echo "Error: Device ${DEVICE_P2} does not exist!"
    echo "Available block devices in /dev/mapper:"
    ls -la /dev/mapper/loop* 2>/dev/null || echo "No loop devices found"
    exit 1
fi

if [ ! -b "${DEVICE_P1}" ]; then
    echo "Error: Device ${DEVICE_P1} does not exist!"
    exit 1
fi

echo "Mounting ${DEVICE_P2} to ${MOUNT_POINT}..."
mount "${DEVICE_P2}" "${MOUNT_POINT}"
if [ $? -ne 0 ]; then
    echo "Error: Failed to mount ${DEVICE_P2}"
    exit 1
fi

mkdir -p ${MOUNT_POINT}/boot
echo "Mounting ${DEVICE_P1} to ${MOUNT_POINT}/boot..."
mount "${DEVICE_P1}" "${MOUNT_POINT}/boot"
if [ $? -ne 0 ]; then
    echo "Error: Failed to mount ${DEVICE_P1}"
    exit 1
fi

echo "Setting up chroot environment..."
cd ${MOUNT_POINT}
mount --bind /dev dev/
mount --bind /sys sys/
mount --bind /proc proc/
mount --bind /dev/pts dev/pts

# Create a script to run inside chroot to handle errors better
cat << 'CHROOT_SCRIPT' > ${MOUNT_POINT}/tmp/setup.sh
#!/bin/bash

# Continue on errors
set +e

echo "Removing Kali kernel and headers..."
apt remove kalipi-kernel kalipi-kernel-headers -y

echo "Updating package keys..."
# Try to fix Kali GPG keys
wget -q -O- https://archive.kali.org/archive-key.asc | apt-key add - 2>/dev/null || true
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ED65462EC8D5E4C5 2>/dev/null || true

echo "Adding ClockworkPi APT repository..."
wget -q -O- https://raw.githubusercontent.com/clockworkpi/apt/main/debian/KEY.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/clockworkpi.gpg 2>/dev/null || true
echo "deb https://raw.githubusercontent.com/clockworkpi/apt/main/debian/ stable main" > /etc/apt/sources.list.d/clockworkpi.list

# Update with --allow-unauthenticated as fallback
echo "Updating package lists..."
apt update || apt update --allow-unauthenticated || true

echo "Installing uConsole CM4 kernel..."
apt install -y uconsole-kernel-cm4-rpi || apt install -y --allow-unauthenticated uconsole-kernel-cm4-rpi || true

echo "Installing 4G support packages..."
apt install -y pppoe uconsole-4g-util-cm4 || apt install -y --allow-unauthenticated pppoe uconsole-4g-util-cm4 || true

echo "Setup complete!"
CHROOT_SCRIPT

chmod +x ${MOUNT_POINT}/tmp/setup.sh

echo "Running setup in chroot..."
chroot ${MOUNT_POINT} /tmp/setup.sh

echo "Configuring display rotation for LightDM..."
cat << 'EOF' > ${MOUNT_POINT}/etc/lightdm/setup.sh
#!/bin/bash
xrandr --output DSI-1 --rotate right
exit 0
EOF

chmod +x ${MOUNT_POINT}/etc/lightdm/setup.sh
chroot ${MOUNT_POINT} /bin/bash -c "sed -i 's/^#greeter-setup-script=.*/greeter-setup-script=\/etc\/lightdm\/setup.sh/' /etc/lightdm/lightdm.conf"

echo "Configuring 4G extension blacklist..."
cat << 'EOF' > ${MOUNT_POINT}/etc/modprobe.d/blacklist-qmi.conf
blacklist qmi_wwan
blacklist cdc_wdm
EOF

echo "Preventing Kali kernel package installation..."
cat << 'EOF' > ${MOUNT_POINT}/etc/apt/preferences.d/kalipi-kernel
Package: kalipi-kernel
Pin: release *
Pin-Priority: -1
EOF

cat << 'EOF' > ${MOUNT_POINT}/etc/apt/preferences.d/kalipi-kernel-headers
Package: kalipi-kernel-headers
Pin: release *
Pin-Priority: -1
EOF

echo "Cleaning up..."
rm -f ${MOUNT_POINT}/tmp/setup.sh
cd -

echo "Unmounting chroot environment..."
umount ${MOUNT_POINT}/dev/pts
umount ${MOUNT_POINT}/dev
umount ${MOUNT_POINT}/proc
umount ${MOUNT_POINT}/sys

echo "Removing bash history..."
rm -rf ${MOUNT_POINT}/root/.bash_history

echo "Unmounting partitions..."
umount ${MOUNT_POINT}/boot
umount ${MOUNT_POINT}

echo "Removing device mappings..."
kpartx -d ${IMAGE_DIR}/${IMAGE_NAME}

echo "Image modification complete!"
echo "The modified image is at: ${IMAGE_DIR}/${IMAGE_NAME}"
echo "You can now write it to an SD card with:"
echo "  sudo dd if=${IMAGE_DIR}/${IMAGE_NAME} of=/dev/sdX bs=1M status=progress"
echo "Replace /dev/sdX with your actual SD card device"