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

# Download ClockworkPi's kernel .deb, check it against the pinned SHA-256 and
# unpack it into <work>/deb. dpkg-deb in the build container; bsdtar (always
# on Arch) on a uConsole itself.
uconsole_cwpi_fetch_deb() {
    local work="$1"
    local deb="${work}/kernel.deb"

    echo "==> Fetching ClockworkPi's CM4 kernel package..."
    curl -fsSL --retry 3 -o "${deb}" "${UCONSOLE_CWPI_DEB_URL}" || return 1
    if ! echo "${UCONSOLE_CWPI_DEB_SHA256}  ${deb}" | sha256sum -c - >/dev/null; then
        echo "ERROR: checksum mismatch for the ClockworkPi kernel package" >&2
        return 1
    fi
    mkdir -p "${work}/deb"
    if command -v dpkg-deb >/dev/null 2>&1; then
        dpkg-deb -x "${deb}" "${work}/deb"
    else
        bsdtar -xOf "${deb}" 'data.tar.*' | bsdtar -xf - -C "${work}/deb"
    fi
    if [ ! -f "${work}/deb/boot/kernel8.img" ] || [ ! -d "${work}/deb/lib/modules/${UCONSOLE_CWPI_KVER}" ]; then
        echo "ERROR: the ClockworkPi package does not have the expected layout" >&2
        return 1
    fi
}

# Build ClockworkPi's kernel, device tree, overlays and modules (the unpacked
# .deb in <debdir>) into a pacman package and install it into <root>, which
# is "/" on a running uConsole. Needs makepkg and fakeroot in <root>.
uconsole_cwpi_install_kernel_package() {
    local root="$1"
    local debdir="$2"

    # Installed as a pacman package, not loose files, so pacman knows the
    # running kernel. Omarchy's updater looks for a pacman-owned
    # /usr/lib/modules/$(uname -r)/vmlinuz and, finding none, asks to reboot
    # for a "kernel update" after every update. It provides 'linux', standing
    # in for Arch's generic kernel, which this board never boots.
    echo "==> Packaging ClockworkPi's ${UCONSOLE_CWPI_KVER} kernel, device tree and overlays..."
    local pkgsrc="${root}/tmp/uconsole-kernel-pkg"
    local builder=uconsole-kernel-builder
    rm -rf "${pkgsrc}"
    mkdir -p "${pkgsrc}/files/boot" "${pkgsrc}/files/usr/lib/modules"
    install -m 0644 "${debdir}/boot/kernel8.img"         "${pkgsrc}/files/boot/kernel8.img"
    install -m 0644 "${debdir}/boot/bcm2711-rpi-cm4.dtb" "${pkgsrc}/files/boot/bcm2711-rpi-cm4.dtb"
    cp -r "${debdir}/boot/overlays" "${pkgsrc}/files/boot/overlays"
    cp -a "${debdir}/lib/modules/${UCONSOLE_CWPI_KVER}" "${pkgsrc}/files/usr/lib/modules/${UCONSOLE_CWPI_KVER}"
    install -m 0644 "${debdir}/boot/kernel8.img" "${pkgsrc}/files/usr/lib/modules/${UCONSOLE_CWPI_KVER}/vmlinuz"
    # depmod's index files are generated on install (below), as Arch's own
    # kernel packages do, so pacman doesn't flag them as altered afterwards.
    rm -f "${pkgsrc}/files/usr/lib/modules/${UCONSOLE_CWPI_KVER}"/modules.{alias,alias.bin,builtin.alias.bin,builtin.bin,dep,dep.bin,devname,softdep,symbols,symbols.bin,weakdep}
    cat > "${pkgsrc}/PKGBUILD" << PKGBUILD
pkgname=uconsole-kernel-cm4-rpi
pkgver=0.13
pkgrel=1
pkgdesc="ClockworkPi's uConsole CM4 kernel ${UCONSOLE_CWPI_KVER}, device tree and overlays"
arch=(aarch64)
url="https://github.com/clockworkpi/apt"
license=(GPL-2.0-only)
provides=("linux=${UCONSOLE_CWPI_KVER%%-*}")
conflicts=(linux-uconsole-cm4-git)
options=(!strip !debug)
install=uconsole-kernel.install
package() { cp -a "\${startdir}/files/." "\${pkgdir}/"; }
PKGBUILD
    cat > "${pkgsrc}/uconsole-kernel.install" << INSTALL
post_install() { depmod ${UCONSOLE_CWPI_KVER}; }
post_upgrade() { post_install; }
INSTALL
    chroot "${root}" useradd -r -M -d /tmp/uconsole-kernel-pkg "${builder}" 2>/dev/null || true
    chroot "${root}" chown -R "${builder}:" /tmp/uconsole-kernel-pkg
    # Uncompressed: nothing to gain for a package that is installed once, and
    # it avoids depending on a compressor inside the image.
    if ! chroot "${root}" runuser -u "${builder}" -- bash -c \
            "cd /tmp/uconsole-kernel-pkg && PKGDEST=/tmp/uconsole-kernel-pkg PKGEXT=.pkg.tar makepkg -d --noconfirm"; then
        chroot "${root}" userdel "${builder}" 2>/dev/null
        rm -rf "${pkgsrc}"; return 1
    fi
    chroot "${root}" userdel "${builder}" 2>/dev/null || true
    # Arch's generic kernel only fills /boot (a 7.x Image, initramfs and every
    # board's device trees) and drags in updates; the firmware never loads it.
    # It also conflicts with any other 'linux', so it must go before ours.
    if chroot "${root}" pacman -Q linux-aarch64 >/dev/null 2>&1; then
        chroot "${root}" pacman -R --noconfirm linux-aarch64 \
            || { echo "ERROR: could not remove the unused linux-aarch64 kernel" >&2; rm -rf "${pkgsrc}"; return 1; }
    fi
    # --overwrite: an image patched before this kept the same files unowned.
    chroot "${root}" bash -c "pacman -U --noconfirm \
            --overwrite '/boot/kernel8.img' --overwrite '/boot/bcm2711-rpi-cm4.dtb' \
            --overwrite '/boot/overlays/*' --overwrite '/usr/lib/modules/${UCONSOLE_CWPI_KVER}/*' \
            /tmp/uconsole-kernel-pkg/uconsole-kernel-cm4-rpi-*.pkg.tar" \
        || { rm -rf "${pkgsrc}"; return 1; }
    rm -rf "${pkgsrc}"
}

# Make pacman in <root> able to download on this kernel.
uconsole_cwpi_pacman_sandbox() {
    local root="$1"

    # pacman 7 sandboxes its downloads with Landlock, which arrived in Linux
    # 5.13. On this 5.10 kernel every download fails ("Landlock is not
    # supported by the kernel"), so the device could never update. Builds
    # don't see it: they run pacman with --disable-sandbox on the host kernel.
    # Turn off only the filesystem part, as pacman.conf(5) advises for such
    # kernels; the syscall filter still applies.
    if grep -q '^#DisableSandboxFilesystem' "${root}/etc/pacman.conf"; then
        sed -i 's/^#DisableSandboxFilesystem/DisableSandboxFilesystem/' "${root}/etc/pacman.conf"
    elif ! grep -q '^DisableSandboxFilesystem' "${root}/etc/pacman.conf"; then
        sed -i '/^\[options\]/a DisableSandboxFilesystem' "${root}/etc/pacman.conf"
    fi
}

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
    uconsole_cwpi_fetch_deb "${work}" || { rm -rf "${work}"; return 1; }

    # GPU firmware for the CM4 and the board's wifi/bluetooth firmware come
    # from Arch Linux ARM, so they keep updating with pacman. The community
    # kernel package is removed so that pacman can never write its kernel and
    # device tree back over these.
    echo "==> Installing Pi firmware, removing the community kernel..."
    chroot "${root}" pacman --disable-sandbox -S --needed --noconfirm raspberrypi-bootloader firmware-raspberrypi fakeroot \
        || { rm -rf "${work}"; return 1; }
    if chroot "${root}" pacman -Q linux-uconsole-cm4-git >/dev/null 2>&1; then
        chroot "${root}" pacman -Rdd --noconfirm linux-uconsole-cm4-git || { rm -rf "${work}"; return 1; }
    fi

    uconsole_cwpi_install_kernel_package "${root}" "${work}/deb" || { rm -rf "${work}"; return 1; }

    # Only the first time: a second run must not replace the community
    # original with the ClockworkPi config written here.
    [ -f "${root}/boot/config.txt.community" ] || cp "${root}/boot/config.txt" "${root}/boot/config.txt.community"
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

    uconsole_cwpi_pacman_sandbox "${root}"

    # Verify the parts that, if missing, mean a black screen.
    local f
    for f in kernel8.img bcm2711-rpi-cm4.dtb start4.elf fixup4.dat overlays/devterm-panel-uc.dtbo; do
        [ -f "${root}/boot/${f}" ] || { echo "ERROR: /boot/${f} missing" >&2; return 1; }
    done
    grep -q 'panel-cwu50' "${root}/usr/lib/modules/${UCONSOLE_CWPI_KVER}/modules.dep" \
        || { echo "ERROR: the uConsole panel driver is not in the module index" >&2; return 1; }
    grep -q "root=PARTUUID=${ptuuid}-02" "${root}/boot/cmdline.txt" \
        || { echo "ERROR: cmdline.txt does not boot by PARTUUID" >&2; return 1; }
    chroot "${root}" pacman -Qqo "/usr/lib/modules/${UCONSOLE_CWPI_KVER}/vmlinuz" >/dev/null 2>&1 \
        || { echo "ERROR: pacman does not own the kernel -- Omarchy would ask to reboot after every update" >&2; return 1; }
    grep -q '^DisableSandboxFilesystem' "${root}/etc/pacman.conf" \
        || { echo "ERROR: pacman.conf would leave the device unable to download updates" >&2; return 1; }
    echo "    boots ClockworkPi ${UCONSOLE_CWPI_KVER} from PARTUUID=${ptuuid}-02"
    return 0
}
