#!/bin/bash
#
# Shared uConsole CM4 driver/kernel installation.
#
# This is the single source of truth for getting the uConsole screen working.
# Both the Kali desktop image and the Ubuntu terminal image source this file
# so there is exactly one place to fix when ClockworkPi changes something.
#
# The "custom display driver" is not source code we hold -- it is a prebuilt
# Debian package (uconsole-kernel-cm4-rpi) from ClockworkPi's APT repo which
# ships the patched kernel, the DSI panel driver and the device-tree overlays.
#
# Usage:
#   source "$(dirname "$0")/lib/uconsole-drivers.sh"
#   uconsole_install_drivers "${MOUNT_POINT}"
#   uconsole_reconcile_boot "${MOUNT_POINT}" "boot/firmware"

CLOCKWORKPI_KEY_URL="https://raw.githubusercontent.com/clockworkpi/apt/main/debian/KEY.gpg"
CLOCKWORKPI_REPO="deb https://raw.githubusercontent.com/clockworkpi/apt/main/debian/ stable main"

# NOTE: upstream is pinned to "stable main" with no version, so the contents of
# this repo can change under us without warning. Once you have confirmed a
# working card, run `dpkg -l uconsole-kernel-cm4-rpi` on the device and record
# the version here, then set UCONSOLE_KERNEL_PKG to "name=version" to freeze it.
UCONSOLE_KERNEL_PKG="${UCONSOLE_KERNEL_PKG:-uconsole-kernel-cm4-rpi}"

# Install the ClockworkPi kernel + display driver into a mounted rootfs.
#
# Unlike the original Kali script, this does NOT swallow failures with `|| true`.
# A failed kernel install means a blank screen on boot, and we would rather the
# build stop loudly than hand you an SD card that looks fine and isn't.
uconsole_install_drivers() {
    local root="$1"

    if [ -z "${root}" ] || [ ! -d "${root}" ]; then
        echo "uconsole_install_drivers: bad rootfs '${root}'" >&2
        return 1
    fi

    cat << CHROOT_SCRIPT > "${root}/tmp/uconsole-drivers.sh"
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

echo "==> Checking the chroot can reach the network..."
# apt failing to resolve is the single most common reason this build dies, and
# it otherwise shows up as a confusing package-not-found error further down.
if ! getent hosts raw.githubusercontent.com >/dev/null 2>&1; then
    echo "ERROR: no DNS inside the chroot -- check /etc/resolv.conf." >&2
    exit 1
fi

echo "==> Adding ClockworkPi APT repository..."
# --batch --yes keeps gpg from trying to open /dev/tty, which does not exist here.
wget -q -O- ${CLOCKWORKPI_KEY_URL} | gpg --batch --yes --dearmor -o /etc/apt/trusted.gpg.d/clockworkpi.gpg
echo "${CLOCKWORKPI_REPO}" > /etc/apt/sources.list.d/clockworkpi.list

echo "==> Updating package lists..."
apt-get update

echo "==> Installing uConsole CM4 kernel and display driver..."
apt-get install -y ${UCONSOLE_KERNEL_PKG}

echo "==> Verifying the kernel package actually landed..."
dpkg -s ${UCONSOLE_KERNEL_PKG%%=*} >/dev/null

echo "==> Installing 4G modem support..."
apt-get install -y pppoe uconsole-4g-util-cm4

echo "==> Driver install complete."
CHROOT_SCRIPT

    chmod +x "${root}/tmp/uconsole-drivers.sh"
    chroot "${root}" /tmp/uconsole-drivers.sh
    local rc=$?
    rm -f "${root}/tmp/uconsole-drivers.sh"

    if [ ${rc} -ne 0 ]; then
        echo "" >&2
        echo "ERROR: uConsole driver install failed (exit ${rc})." >&2
        echo "Do NOT flash this image -- the screen will not come on." >&2
        return ${rc}
    fi

    return 0
}

# The ClockworkPi package is built for Raspberry Pi OS / Kali, which mount the
# FAT boot partition at /boot. Ubuntu mounts it at /boot/firmware. If the vendor
# package wrote its kernel and overlays to /boot on the ext4 rootfs, the
# bootloader will never see them and you get a black screen.
#
# This copies any stray boot artifacts onto the real firmware partition.
uconsole_reconcile_boot() {
    local root="$1"
    local fw_rel="${2:-boot/firmware}"
    local fw="${root}/${fw_rel}"

    if [ ! -d "${fw}" ]; then
        echo "uconsole_reconcile_boot: '${fw}' is not a directory" >&2
        return 1
    fi

    # If the firmware partition already has a kernel image, the package most
    # likely did the right thing and there is nothing to reconcile.
    echo "==> Checking where the vendor kernel put its boot artifacts..."
    echo "    ${fw_rel} contains:"
    ls -1 "${fw}" 2>/dev/null | sed 's/^/      /' || true

    # The package ships its own config.txt carrying the uConsole dtoverlay lines.
    # It writes it to /boot on the rootfs, where the bootloader will never read
    # it, so it has to be promoted onto the FAT partition. Keep the distro's
    # original alongside it -- if the panel comes up but something else (audio,
    # i2c, initramfs) breaks, the diff between these two files is the first
    # place to look.
    if [ -f "${root}/boot/config.txt" ] && [ -f "${fw}/config.txt" ]; then
        if ! cmp -s "${root}/boot/config.txt" "${fw}/config.txt"; then
            echo "    promoting vendor config.txt -> ${fw_rel}/ (original kept as config.txt.distro)"
            cp -a "${fw}/config.txt" "${fw}/config.txt.distro"
            cp -a "${root}/boot/config.txt" "${fw}/config.txt"
        fi
    fi

    local moved=0
    shopt -s nullglob
    for artifact in "${root}"/boot/kernel*.img "${root}"/boot/*.dtb; do
        # Skip anything that is already on the firmware partition.
        case "${artifact}" in
            "${fw}"/*) continue ;;
        esac
        echo "    copying $(basename "${artifact}") -> ${fw_rel}/"
        cp -a "${artifact}" "${fw}/"
        moved=1
    done

    if [ -d "${root}/boot/overlays" ] && [ ! -d "${fw}/overlays" ]; then
        echo "    copying overlays/ -> ${fw_rel}/"
        cp -a "${root}/boot/overlays" "${fw}/"
        moved=1
    fi
    shopt -u nullglob

    if [ ${moved} -eq 1 ]; then
        echo "    NOTE: vendor package wrote to /boot; copied onto the firmware partition."
    else
        echo "    Nothing to reconcile."
    fi

    return 0
}

# Stop late boot messages from landing on top of the login prompt.
#
# The symptom this fixes: getty draws "uconsole login:" and then a couple more
# kernel/driver lines print over it, so the prompt looks half-eaten and you have
# to press Enter to get a clean one. It is cosmetic, but it is the very first
# thing anyone sees, and on a device meant for a beginner "looks broken" costs
# more than it should.
#
# The fix is to send kernel messages to a tty nobody looks at, rather than to
# try to silence them -- they are still there on tty3 (Alt+F3) when something
# goes wrong and you need them.
uconsole_quiet_console() {
    local root="$1"
    local fw_rel="${2:-boot/firmware}"
    local cmdline="${root}/${fw_rel}/cmdline.txt"

    if [ ! -f "${cmdline}" ]; then
        echo "uconsole_quiet_console: ${cmdline} not found" >&2
        return 1
    fi

    echo "==> Moving boot messages off the login console..."

    # Strip anything we are about to set, so re-running does not stack duplicates
    # or leave two conflicting console= values (last one wins, silently).
    sed -i 's/[[:space:]]*console=tty[0-9]*//g' "${cmdline}"
    sed -i 's/[[:space:]]*loglevel=[0-9]*//g' "${cmdline}"
    sed -i 's/[[:space:]]*\(quiet\|logo\.nologo\|vt\.global_cursor_default=[0-9]*\|consoleblank=[0-9]*\)//g' "${cmdline}"

    # console=tty3   kernel messages go to VT3; tty1 is left to getty alone
    # quiet          drops all but urgent messages during boot
    # loglevel=3     errors and worse only
    # logo.nologo    no raspberry logos eating the top of a small screen
    # consoleblank=0 never blank the console -- this is a handheld, a screen
    #                that goes black looks like a crash
    sed -i "1s|\$| console=tty3 quiet loglevel=3 logo.nologo consoleblank=0|" "${cmdline}"

    echo "    cmdline.txt is now:"
    sed 's/^/      /' "${cmdline}"

    return 0
}

# Rotate the *console* framebuffer. The Kali desktop image does this with
# `xrandr` from LightDM's greeter hook, which cannot work on a terminal-only
# image -- there is no X server. This pushes rotation down to the kernel so the
# text console itself comes up the right way round.
#
# fbcon=rotate:1 is 90 degrees clockwise, matching the desktop image's
# `--rotate right`. If the console comes up upside down or mirrored, the value
# to change is this one: 0=normal 1=90cw 2=180 3=270cw.
uconsole_set_console_rotation() {
    local root="$1"
    local fw_rel="${2:-boot/firmware}"
    local rotate="${3:-1}"
    local cmdline="${root}/${fw_rel}/cmdline.txt"

    if [ ! -f "${cmdline}" ]; then
        echo "uconsole_set_console_rotation: ${cmdline} not found" >&2
        return 1
    fi

    echo "==> Setting console rotation (fbcon=rotate:${rotate})..."

    # cmdline.txt must remain a single line -- strip any existing fbcon setting
    # first so re-running the build does not stack duplicates.
    sed -i 's/[[:space:]]*fbcon=rotate:[0-9]*//g' "${cmdline}"
    sed -i "1s|\$| fbcon=rotate:${rotate}|" "${cmdline}"

    echo "    cmdline.txt is now:"
    sed 's/^/      /' "${cmdline}"

    return 0
}
