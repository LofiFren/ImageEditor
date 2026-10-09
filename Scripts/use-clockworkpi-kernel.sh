#!/bin/bash
#
# Switch an ALREADY BUILT uConsole Arch image (either Omarchy edition) to
# ClockworkPi's own CM4 kernel. New builds do this by default (KERNEL=clockworkpi
# in create-uconsole-omarchy.sh); this is for images built before that, or with
# KERNEL=community. See lib/uconsole-arch-kernel.sh for the why.
#
# Usage (inside the image-editor container, as root):
#   ./use-clockworkpi-kernel.sh /workdir/images/<image>.img
#   VERBOSE_BOOT=1 ...   also show kernel messages on screen (for debugging)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/uconsole-arch-kernel.sh"

IMG="${1:?usage: use-clockworkpi-kernel.sh <image.img>}"
MP=/mnt/uconsole-kernel-swap
VERBOSE_BOOT="${VERBOSE_BOOT:-0}"
PACMAN_CACHE="${PACMAN_CACHE-/workdir/images/pacman-cache}"

if mountpoint -q "${MP}" || [ -n "$(losetup -j "${IMG}")" ]; then
    echo "ERROR: ${IMG} is already attached or ${MP} is mounted." >&2
    exit 1
fi

LOOP=""
cleanup() {
    chroot "${MP}" gpgconf --homedir /etc/pacman.d/gnupg --kill all 2>/dev/null || true
    for attempt in 1 2 3 4 5; do
        for m in var/cache/pacman/pkg dev/pts dev proc sys run boot ""; do
            umount "${MP}/${m}" 2>/dev/null || true
        done
        mountpoint -q "${MP}" || break
        sleep 1
    done
    if mountpoint -q "${MP}"; then
        echo "ERROR: ${MP} still mounted -- not detaching. Check: fuser -vm ${MP}" >&2
    elif [ -n "${LOOP}" ]; then
        kpartx -d "${LOOP}" 2>/dev/null || true
        losetup -d "${LOOP}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "==> Mounting ${IMG}..."
LOOP="$(losetup --find --show "${IMG}")"
kpartx -av "${LOOP}" >/dev/null
sleep 2
B="$(basename "${LOOP}")"
mkdir -p "${MP}"
mount "/dev/mapper/${B}p2" "${MP}"
mount "/dev/mapper/${B}p1" "${MP}/boot"
for d in dev dev/pts proc sys run; do mount --bind "/${d}" "${MP}/${d}"; done
if [ -n "${PACMAN_CACHE}" ]; then
    mkdir -p "${PACMAN_CACHE}"
    mount --bind "${PACMAN_CACHE}" "${MP}/var/cache/pacman/pkg"
fi
mv "${MP}/etc/resolv.conf" "${MP}/etc/resolv.conf.swap-orig" 2>/dev/null || true
cp /etc/resolv.conf "${MP}/etc/resolv.conf"

# A finished image deliberately has no keyring (each device makes its own on
# first boot); make a temporary one, and remove it again below.
chroot "${MP}" pacman-key --init >/dev/null 2>&1
chroot "${MP}" pacman-key --populate archlinuxarm >/dev/null 2>&1
chroot "${MP}" pacman --disable-sandbox -Sy --noconfirm >/dev/null

uconsole_arch_use_clockworkpi_kernel "${MP}" "${LOOP}"

if [ "${VERBOSE_BOOT}" = "1" ]; then
    sed -i -e 's/[[:space:]]*console=tty[0-9]*//g' -e 's/[[:space:]]*quiet//g' \
           -e 's/[[:space:]]*loglevel=[0-9]*//g' -e 's/[[:space:]]*logo\.nologo//g' "${MP}/boot/cmdline.txt"
    sed -i '1s|$| console=tty1 loglevel=7|' "${MP}/boot/cmdline.txt"
fi
echo "    cmdline.txt: $(cat "${MP}/boot/cmdline.txt")"

echo "==> Tidying..."
chroot "${MP}" gpgconf --homedir /etc/pacman.d/gnupg --kill all 2>/dev/null || true
umount "${MP}/var/cache/pacman/pkg" 2>/dev/null || true
mountpoint -q "${MP}/var/cache/pacman/pkg" && { echo "ERROR: cache still mounted" >&2; exit 1; }
rm -rf "${MP}/var/cache/pacman/pkg/"* "${MP}/var/lib/pacman/sync/"* "${MP}/etc/pacman.d/gnupg"
rm -f "${MP}/etc/resolv.conf"
mv "${MP}/etc/resolv.conf.swap-orig" "${MP}/etc/resolv.conf" 2>/dev/null || true
echo "==> Done."
