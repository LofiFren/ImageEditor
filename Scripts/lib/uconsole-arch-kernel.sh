#!/bin/bash
#
# Boot an Arch Linux ARM uConsole CM4 image on ClockworkPi's own kernel.
#
# This is the Arch counterpart of uconsole-drivers.sh: the same ClockworkPi
# package (uconsole-kernel-cm4-rpi) that the Raspberry Pi OS builds install
# with apt, unpacked into an Arch root instead.
#
# Why it exists: the community uConsole Arch image ships
#   - no Raspberry Pi GPU firmware (start4.elf / fixup4.dat). A CM5 keeps that
#     in EEPROM; a CM4 must load it from the card, so the CM4 never starts.
#   - a newer community kernel and overlay set that, even with the firmware
#     added, left the uConsole screen black on real hardware.
# ClockworkPi's package is old (5.10) and gets no updates, but it is the
# kernel known to drive this panel.
#
# Usage:
#   source "$(dirname "$0")/lib/uconsole-arch-kernel.sh"
#   uconsole_arch_use_clockworkpi_kernel <root> <loop-device>
#
# <root> must be the mounted image root, with /boot (the FAT partition), /dev,
# /proc and /sys mounted, working DNS, and an initialised pacman keyring.

UCONSOLE_CWPI_DEB_URL="https://raw.githubusercontent.com/clockworkpi/apt/main/debian/pool/main/u/uconsole-kernel-cm4-rpi/uconsole-kernel-cm4-rpi_0.13_arm64.deb"
# The SHA-256 ClockworkPi's own apt index lists for this exact package.
UCONSOLE_CWPI_DEB_SHA256="f8ecd5385a6ed19490d3f54ad7f406439bcdd0d293615ae2506fbcd66ed6fa3e"
UCONSOLE_CWPI_KVER="5.10.17-v8+"

uconsole_arch_use_clockworkpi_kernel() {
    local root="$1"
    local loop="$2"
    local work deb ptuuid

    if [ -z "${root}" ] || [ ! -f "${root}/boot/config.txt" ]; then
        echo "uconsole_arch_use_clockworkpi_kernel: '${root}/boot' is not the boot partition" >&2
        return 1
    fi

    # The MBR disk identifier survives dd onto the card, so PARTUUID=<id>-02
    # names the root partition on the device too. This kernel has no
    # initramfs, and without one root=LABEL= cannot be resolved.
    ptuuid="$(blkid -s PTUUID -o value "${loop}")"
    [ -n "${ptuuid}" ] || { echo "ERROR: could not read the disk identifier of ${loop}" >&2; return 1; }

    work="$(mktemp -d /tmp/cwpi-kernel.XXXXXX)"
    deb="${work}/kernel.deb"

    echo "==> Fetching ClockworkPi's CM4 kernel package..."
    curl -fsSL --retry 3 -o "${deb}" "${UCONSOLE_CWPI_DEB_URL}" || { rm -rf "${work}"; return 1; }
    if ! echo "${UCONSOLE_CWPI_DEB_SHA256}  ${deb}" | sha256sum -c - >/dev/null; then
        echo "ERROR: checksum mismatch for the ClockworkPi kernel package" >&2
        rm -rf "${work}"; return 1
    fi
    dpkg-deb -x "${deb}" "${work}/deb"
    if [ ! -f "${work}/deb/boot/kernel8.img" ] || [ ! -d "${work}/deb/lib/modules/${UCONSOLE_CWPI_KVER}" ]; then
        echo "ERROR: the ClockworkPi package does not have the expected layout" >&2
        rm -rf "${work}"; return 1
    fi

    # GPU firmware for the CM4 and the board's wifi/bluetooth firmware come
    # from Arch Linux ARM, so they keep updating with pacman. The community
    # kernel package is removed so that pacman can never write its kernel and
    # device tree back over these.
    echo "==> Installing Pi firmware, removing the community kernel..."
    chroot "${root}" pacman --disable-sandbox -S --needed --noconfirm raspberrypi-bootloader firmware-raspberrypi \
        || { rm -rf "${work}"; return 1; }
    if chroot "${root}" pacman -Q linux-uconsole-cm4-git >/dev/null 2>&1; then
        chroot "${root}" pacman -Rdd --noconfirm linux-uconsole-cm4-git || { rm -rf "${work}"; return 1; }
    fi

    echo "==> Installing ClockworkPi's ${UCONSOLE_CWPI_KVER} kernel, device tree and overlays..."
    install -m 0644 "${work}/deb/boot/kernel8.img"         "${root}/boot/kernel8.img"
    install -m 0644 "${work}/deb/boot/bcm2711-rpi-cm4.dtb" "${root}/boot/bcm2711-rpi-cm4.dtb"
    rm -rf "${root}/boot/overlays"
    cp -r "${work}/deb/boot/overlays" "${root}/boot/overlays"

    rm -rf "${root}/usr/lib/modules/${UCONSOLE_CWPI_KVER}"
    cp -a "${work}/deb/lib/modules/${UCONSOLE_CWPI_KVER}" "${root}/usr/lib/modules/${UCONSOLE_CWPI_KVER}"
    chroot "${root}" depmod "${UCONSOLE_CWPI_KVER}"

    cp "${root}/boot/config.txt" "${root}/boot/config.txt.community"
    {
        echo "# ClockworkPi uConsole CM4 -- ClockworkPi's own kernel and overlays,"
        echo "# the same set the Raspberry Pi OS builds in this repo boot."
        echo "# The community image's original is kept as config.txt.community."
        echo "arm_64bit=1"
        echo "kernel=kernel8.img"
        echo "enable_uart=1"
        echo ""
        cat "${work}/deb/boot/config.txt"
    } > "${root}/boot/config.txt"

    sed -i "s|root=LABEL=alarm-root|root=PARTUUID=${ptuuid}-02 rootfstype=ext4|" "${root}/boot/cmdline.txt"
    rm -rf "${work}"

    # Verify the parts that, if missing, mean a black screen.
    local f
    for f in kernel8.img bcm2711-rpi-cm4.dtb start4.elf fixup4.dat overlays/devterm-panel-uc.dtbo; do
        [ -f "${root}/boot/${f}" ] || { echo "ERROR: /boot/${f} missing" >&2; return 1; }
    done
    grep -q 'panel-cwu50' "${root}/usr/lib/modules/${UCONSOLE_CWPI_KVER}/modules.dep" \
        || { echo "ERROR: the uConsole panel driver is not in the module index" >&2; return 1; }
    grep -q "root=PARTUUID=${ptuuid}-02" "${root}/boot/cmdline.txt" \
        || { echo "ERROR: cmdline.txt does not boot by PARTUUID" >&2; return 1; }
    echo "    boots ClockworkPi ${UCONSOLE_CWPI_KVER} from PARTUUID=${ptuuid}-02"
    return 0
}
