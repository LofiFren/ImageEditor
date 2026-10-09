#!/bin/bash
#
# Build an Omarchy desktop image for the ClockworkPi uConsole CM4.
#
# Two editions, chosen with OMARCHY_EDITION:
#   look (default)  Hyprland styled after Omarchy 3.8.4, from Arch Linux ARM
#                   packages only. Light enough to be comfortable on a CM4.
#   real            Real Omarchy 4, repackaged for aarch64 by
#                   Scripts/omarchy-port/ and set up by Omarchy's own install
#                   stages. Quickshell desktop, SDDM login. Heavier.
#
# Base: the community uConsole Arch Linux ARM image
#   https://github.com/wdkdot/uconsole-arch
# for the Arch system itself. By default (KERNEL=clockworkpi) its kernel is
# replaced by ClockworkPi's own CM4 kernel plus the Pi GPU firmware, which the
# base image lacks -- see lib/uconsole-arch-kernel.sh.
#
# The 'look' edition adds Hyprland with Omarchy's look -- Omarchy 3.8.4's
# gaps, borders, blur, animations, Waybar layout and Tokyo Night theme -- from
# Arch Linux ARM packages. The 'real' edition installs Omarchy itself; see
# Scripts/omarchy-port/README.md for what the port changes and why.
#
# This sits alongside the Kali and terminal-only builds; it does not replace
# either of them.
#
# Usage (inside the image-editor container, as root):
#   ./create-uconsole-omarchy.sh                        Omarchy-look edition
#   OMARCHY_EDITION=real ./create-uconsole-omarchy.sh   real Omarchy

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/uconsole-drivers.sh"
source "${SCRIPT_DIR}/lib/uconsole-arch-kernel.sh"
LOOK_DIR="${SCRIPT_DIR}/omarchy-look"
PORT_DIR="${SCRIPT_DIR}/omarchy-port"

OMARCHY_EDITION="${OMARCHY_EDITION:-look}"
case "${OMARCHY_EDITION}" in
    look|real) ;;
    *) echo "OMARCHY_EDITION must be 'look' or 'real'."; exit 1 ;;
esac

# Which kernel boots the image:
#   clockworkpi (default)  ClockworkPi's own CM4 kernel + the Pi GPU firmware --
#                          the boot chain the Raspberry Pi OS builds use. Old
#                          (5.10), not updated by pacman, but it drives the panel.
#   community              the base image's newer uconsole-arch kernel, updated
#                          by pacman. On a real CM4 this left the screen black.
# See lib/uconsole-arch-kernel.sh.
KERNEL="${KERNEL:-clockworkpi}"
case "${KERNEL}" in
    clockworkpi|community) ;;
    *) echo "KERNEL must be 'clockworkpi' or 'community'."; exit 1 ;;
esac

# VERBOSE_BOOT=1 puts kernel messages on the screen instead of hiding them on
# tty3 -- the quickest way to see how far a black-screen boot gets.
VERBOSE_BOOT="${VERBOSE_BOOT:-0}"

# ---------------------------------------------------------------- configuration

WORKDIR="/workdir"
IMAGE_DIR="${WORKDIR}/images"

# Pinned to a specific community release. The asset name carries no version,
# so a newer upload would land under the same name -- the checksum below is
# what notices that. To move to a new release, update all three together.
BASE_RELEASE="${BASE_RELEASE:-v2026.07.04}"
BASE_ASSET="uconsole-arch-cm4.img.zst"
BASE_SHA256="${BASE_SHA256:-5c49cda49913d20ddb58f65bc85667b91ef623624875067d1365bf61fc540840}"
BASE_URL="https://github.com/wdkdot/uconsole-arch/releases/download/${BASE_RELEASE}/${BASE_ASSET}"

IMAGE_ZST="uconsole-arch-cm4-${BASE_RELEASE}.img.zst"
if [ "${OMARCHY_EDITION}" = "real" ]; then
    IMAGE_NAME="uconsole-omarchy-real-cm4.img"
else
    IMAGE_NAME="uconsole-omarchy-cm4.img"
fi

MOUNT_POINT="/mnt/uconsole-omarchy"

# Downloaded packages are kept on the host between builds, so a rebuild does
# not fetch the same 1-2 GB from Arch Linux ARM's slow mirrors again. Set
# PACMAN_CACHE="" to disable.
PACMAN_CACHE="${PACMAN_CACHE-${IMAGE_DIR}/pacman-cache}"
BOOT_REL="boot"                 # Arch mounts the FAT partition straight at /boot

# The wallpaper comes from Omarchy itself, pinned to the v3.8.4 commit so it
# cannot change under us.
OMARCHY_COMMIT="8fcc9d6048af4cb0e3af8512c78049857a3b53dd"
WALLPAPER_URL="https://raw.githubusercontent.com/basecamp/omarchy/${OMARCHY_COMMIT}/themes/tokyo-night/backgrounds/1-sunset-lake.png"

DESKTOP_USER="${DESKTOP_USER:-uconsole}"
DESKTOP_HOST="${DESKTOP_HOST:-uconsole}"

# The prebuilt image is minimised to ~768 MB free. Hyprland, Chromium, fonts
# and the pacman download cache need several GB on top of that -- and real
# Omarchy's full app set (~125 packages) a good deal more.
if [ "${OMARCHY_EDITION}" = "real" ]; then
    IMAGE_GROW="${IMAGE_GROW:-12G}"
    MIN_FREE_MB=9000
else
    IMAGE_GROW="${IMAGE_GROW:-6G}"
    MIN_FREE_MB=4000
fi

# Panel rotation. The console is rotated in the kernel (fbcon), the desktop by
# Hyprland -- they use different numbering, so there are two knobs.
#   CONSOLE_ROTATE  0=normal 1=90cw 2=180 3=270cw   (same as the terminal build)
#   HYPR_TRANSFORM  0=normal 1=90 2=180 3=270, counter-clockwise
# 1 and 3 respectively both mean "the Kali image's xrandr --rotate right".
CONSOLE_ROTATE="${CONSOLE_ROTATE:-1}"
HYPR_TRANSFORM="${HYPR_TRANSFORM:-3}"

# Hyprland's main modifier. Omarchy uses SUPER. If the key on your uConsole
# keyboard turns out to be awkward, ALT is the usual fallback. The Waybar
# buttons work either way.
HYPR_MOD="${HYPR_MOD:-SUPER}"

WIFI_COUNTRY="${WIFI_COUNTRY:-US}"
TIMEZONE="${TIMEZONE:-UTC}"

# Omarchy 3.8.4's desktop stack, minus Walker (not packaged for ARM -- fuzzel
# stands in) and minus anything x86-only. Every name here was checked against
# archlinuxarm.org/packages/aarch64 when this was written.
DESKTOP_PACKAGES="hyprland hyprlock hypridle hyprpicker hyprsunset \
xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
waybar mako swaybg fuzzel alacritty \
polkit-gnome brightnessctl playerctl pamixer \
pipewire pipewire-pulse pipewire-alsa wireplumber \
bluez bluez-utils \
grim slurp wl-clipboard \
qt5-wayland qt6-wayland gnome-themes-extra \
ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji terminus-font \
mesa nautilus imv mpv btop fastfetch starship \
man-db less git cloud-guest-utils"

# The browser is the single heaviest package. Set EXTRA_PACKAGES="" to leave
# it out and save around a gigabyte.
EXTRA_PACKAGES="${EXTRA_PACKAGES-chromium}"

# The real edition gets its desktop from Omarchy; this is only what the build
# and first boot themselves need.
if [ "${OMARCHY_EDITION}" = "real" ]; then
    DESKTOP_PACKAGES="cloud-guest-utils terminus-font man-db less git"
    EXTRA_PACKAGES=""
    CHECK_BINS="growpart"
else
    CHECK_BINS="Hyprland waybar hyprlock fuzzel alacritty"
fi

# ------------------------------------------------------- existing output
#
# Checked before anything else -- before the questions, and before the cleanup
# handler, which would otherwise call a perfectly good image incomplete.
# Re-running on an already built image would layer a second build on the first.
if [ -f "${IMAGE_DIR}/${IMAGE_NAME}" ]; then
    echo "Error: images/${IMAGE_NAME} already exists, from an earlier run."
    echo "       Flash it, or delete it to build again. From the repo folder:"
    echo "           rm -f images/${IMAGE_NAME}"
    exit 1
fi

# ------------------------------------------------------- ARM emulation
#
# The build runs ARM programs inside the image. On an x86 machine the host
# kernel must hand ARM binaries to qemu (binfmt_misc). Docker Desktop sets that
# up itself; Docker on x86 Linux does not. Check before downloading anything --
# a second check later, once the image is mounted, is the backstop.
arm_emulation_help() {
    echo "       Enable ARM emulation on the HOST (not in the container), then" >&2
    echo "       run the same command again:" >&2
    echo "         Ubuntu 24.04 and older, Debian:" >&2
    echo "                       sudo apt install qemu-user-static binfmt-support" >&2
    echo "         Ubuntu 26.04 and newer:" >&2
    echo "                       sudo apt install qemu-user-binfmt" >&2
    echo "         Fedora:       sudo dnf install qemu-user-static" >&2
    echo "         Arch:         sudo pacman -S qemu-user-static-binfmt" >&2
}
#
# Only conclusive when binfmt_misc is visible here: inside a container it is
# often not mounted even though emulation works (Docker Desktop), and then the
# test is left to the backstop, which actually runs an ARM program.
if [ "$(uname -m)" != "aarch64" ] \
&& [ -e /proc/sys/fs/binfmt_misc/register ] \
&& ! grep -qs 'aarch64' /proc/sys/fs/binfmt_misc/*; then
    echo "ERROR: this machine has no ARM emulation, and the build needs it." >&2
    arm_emulation_help
    exit 1
fi

# ------------------------------------------------------------------- cleanup

LOOP_DEVICE=""

cleanup() {
    echo "Cleaning up..."
    # A gpg-agent left running inside the chroot holds the image open.
    chroot "${MOUNT_POINT}" gpgconf --homedir /etc/pacman.d/gnupg --kill all 2>/dev/null || true
    umount "${MOUNT_POINT}/var/cache/pacman/pkg" 2>/dev/null || true
    # Retry for a few seconds: processes started inside the chroot can take a
    # moment to exit, and a mount that is busy now may be free a second later.
    for attempt in 1 2 3 4 5; do
        umount "${MOUNT_POINT}/dev/pts"      2>/dev/null || true
        umount "${MOUNT_POINT}/dev"          2>/dev/null || true
        umount "${MOUNT_POINT}/proc"         2>/dev/null || true
        umount "${MOUNT_POINT}/sys"          2>/dev/null || true
        umount "${MOUNT_POINT}/run"          2>/dev/null || true
        umount "${MOUNT_POINT}/${BOOT_REL}"  2>/dev/null || true
        umount "${MOUNT_POINT}"              2>/dev/null || true
        mountpoint -q "${MOUNT_POINT}" || break
        sleep 1
    done

    # A failed unmount is not cosmetic: the image stays mounted, and the next
    # run would mount the same filesystem a second time and corrupt it.
    if mountpoint -q "${MOUNT_POINT}"; then
        echo ""                                                            >&2
        echo "  WARNING: ${MOUNT_POINT} is still mounted. Something inside"  >&2
        echo "  the chroot is holding it open. Do NOT run another build"     >&2
        echo "  until it is released:  fuser -vm ${MOUNT_POINT}"             >&2
        echo ""                                                            >&2
        BUILD_COMPLETE=0
        return
    fi

    if [ -n "${LOOP_DEVICE}" ]; then
        kpartx -d "${LOOP_DEVICE}" 2>/dev/null || true
        losetup -d "${LOOP_DEVICE}" 2>/dev/null || true
    fi

    # Same failure mode as the terminal build: a run that dies after locking
    # the accounts but before the wizard is installed boots to a login prompt
    # nobody can get past.
    #
    # The half-built image is useless, and leaving it would make the next run
    # refuse with "already exists" -- so delete it, but only one this run
    # created (the existing-output check guarantees that) and only now that
    # it is unmounted and detached.
    if [ "${BUILD_COMPLETE:-0}" != "1" ]; then
        echo ""                                                        >&2
        echo "  BUILD DID NOT COMPLETE."                                >&2
        if [ "${CREATED_IMAGE:-0}" = "1" ] && [ -f "${IMAGE_DIR}/${IMAGE_NAME}" ]; then
            rm -f "${IMAGE_DIR}/${IMAGE_NAME}"
            echo "  The unfinished images/${IMAGE_NAME} was deleted."  >&2
            echo "  Fix the error above and run the same command again." >&2
        fi
        echo ""                                                        >&2
    fi
}
trap cleanup EXIT

# ------------------------------------------------------------------ questions
#
# No passwords are asked for. As with the terminal build, the accounts ship
# locked and a wizard sets the password on first boot, so the .img holds no
# secrets.

echo "Omarchy uConsole build -- edition: ${OMARCHY_EDITION}."
echo "  No passwords or wifi details are stored in this image."
echo "  The uConsole asks for them on its first boot."
echo ""

read -rp "Wifi country code [${WIFI_COUNTRY}]: " WIFI_COUNTRY_IN
WIFI_COUNTRY="${WIFI_COUNTRY_IN:-${WIFI_COUNTRY}}"
WIFI_COUNTRY="$(echo "${WIFI_COUNTRY}" | tr '[:lower:]' '[:upper:]')"
case "${WIFI_COUNTRY}" in
    [A-Z][A-Z]) ;;
    *) echo "Country must be a two-letter ISO code (US, GB, DE...)."; exit 1 ;;
esac
unset WIFI_COUNTRY_IN

read -rp "Timezone, e.g. America/New_York [${TIMEZONE}]: " TIMEZONE_IN
TIMEZONE="${TIMEZONE_IN:-${TIMEZONE}}"
unset TIMEZONE_IN

case "${HYPR_TRANSFORM}" in [0-7]) ;; *) echo "HYPR_TRANSFORM must be 0-7."; exit 1 ;; esac
case "${CONSOLE_ROTATE}" in [0-3]) ;; *) echo "CONSOLE_ROTATE must be 0-3."; exit 1 ;; esac

# ------------------------------------------------------------------ base image

mkdir -p "${MOUNT_POINT}"

if [ ! -f "${IMAGE_DIR}/${IMAGE_ZST}" ]; then
    echo "==> Downloading community uConsole Arch image (${BASE_RELEASE})..."
    curl -fL --retry 3 --connect-timeout 20 -o "${IMAGE_DIR}/${IMAGE_ZST}.part" "${BASE_URL}"
    mv "${IMAGE_DIR}/${IMAGE_ZST}.part" "${IMAGE_DIR}/${IMAGE_ZST}"
fi

echo "==> Verifying ${IMAGE_ZST}..."
ACTUAL_SHA256="$(sha256sum "${IMAGE_DIR}/${IMAGE_ZST}" | cut -d' ' -f1)"
if [ "${ACTUAL_SHA256}" != "${BASE_SHA256}" ]; then
    echo "ERROR: checksum mismatch for ${IMAGE_ZST}" >&2
    echo "       expected ${BASE_SHA256}" >&2
    echo "       got      ${ACTUAL_SHA256}" >&2
    echo "       Either the download is damaged (delete it and retry) or the" >&2
    echo "       release was re-uploaded -- check before trusting it." >&2
    exit 1
fi
echo "    ok"

echo "==> Decompressing to ${IMAGE_NAME}..."
CREATED_IMAGE=1
zstd -d -f "${IMAGE_DIR}/${IMAGE_ZST}" -o "${IMAGE_DIR}/${IMAGE_NAME}"

if mountpoint -q "${MOUNT_POINT}"; then
    echo "Error: ${MOUNT_POINT} is already mounted -- probably a previous run that" >&2
    echo "       could not unmount. Mounting again would corrupt that filesystem." >&2
    echo "       Release it first:  fuser -vm ${MOUNT_POINT}" >&2
    exit 1
fi

for stale in $(losetup -j "${IMAGE_DIR}/${IMAGE_NAME}" | cut -d: -f1); do
    echo "==> Releasing stale loop device ${stale}..."
    kpartx -d "${stale}" 2>/dev/null || true
    losetup -d "${stale}" 2>/dev/null || true
done

# ---------------------------------------------------------------- grow the image

echo "==> Growing the image by ${IMAGE_GROW} to make room for the desktop..."
truncate -s "+${IMAGE_GROW}" "${IMAGE_DIR}/${IMAGE_NAME}"

echo "==> Attaching image to a loop device..."
# kpartx rather than `losetup --partscan` -- see create-uconsole-terminal.sh;
# --partscan never creates the partition nodes inside Docker Desktop's VM.
LOOP_DEVICE="$(losetup --find --show "${IMAGE_DIR}/${IMAGE_NAME}")"
echo "    ${LOOP_DEVICE}"

echo "==> Extending the root partition..."
parted -s "${LOOP_DEVICE}" resizepart 2 100%

kpartx -av "${LOOP_DEVICE}"
sleep 2

LOOP_BASE="$(basename "${LOOP_DEVICE}")"
PART_BOOT="/dev/mapper/${LOOP_BASE}p1"   # FAT32, label BOOT -- mounted at /boot
PART_ROOT="/dev/mapper/${LOOP_BASE}p2"   # ext4, label alarm-root

for dev in "${PART_BOOT}" "${PART_ROOT}"; do
    [ -b "${dev}" ] || { echo "Error: ${dev} missing. Is this really the uConsole Arch image?"; exit 1; }
done

# cmdline.txt finds the root filesystem by this label. If it is not there the
# image is not what this script expects, and it would not boot anyway.
ROOT_LABEL="$(blkid -s LABEL -o value "${PART_ROOT}" || true)"
if [ "${ROOT_LABEL}" != "alarm-root" ]; then
    echo "Error: root partition label is '${ROOT_LABEL}', expected 'alarm-root'." >&2
    exit 1
fi

echo "==> Growing the root filesystem..."
e2fsck -f -y "${PART_ROOT}" || true
resize2fs "${PART_ROOT}"

# Measured through a mount point for the reason given in the terminal build:
# df on a bare device path reports the container's /dev, not the image.
mkdir -p /mnt/sizecheck
mount "${PART_ROOT}" /mnt/sizecheck
AVAIL_MB="$(df -m --output=avail /mnt/sizecheck | tail -1 | tr -d ' ')"
umount /mnt/sizecheck
echo "    ${AVAIL_MB} MB free on the rootfs"
if [ -n "${AVAIL_MB}" ] && [ "${AVAIL_MB}" -lt "${MIN_FREE_MB}" ]; then
    echo "ERROR: only ${AVAIL_MB} MB free -- the desktop install will run out." >&2
    echo "       Retry with a bigger grow, e.g. IMAGE_GROW=16G" >&2
    exit 1
fi

echo "==> Mounting partitions..."
mount "${PART_ROOT}" "${MOUNT_POINT}"
mount "${PART_BOOT}" "${MOUNT_POINT}/${BOOT_REL}"

# The kernel, initramfs and config.txt all come from the base image. Check
# they are there now rather than discover a blank screen after flashing.
if ! grep -q 'vmlinuz-linux-uconsole-cm4-git' "${MOUNT_POINT}/${BOOT_REL}/config.txt" 2>/dev/null \
|| [ ! -f "${MOUNT_POINT}/${BOOT_REL}/vmlinuz-linux-uconsole-cm4-git" ]; then
    echo "ERROR: the uConsole CM4 kernel is not where config.txt expects it." >&2
    echo "       This does not look like the CM4 community image." >&2
    exit 1
fi

if [ "$(uname -m)" != "aarch64" ] && [ -f /usr/bin/qemu-aarch64-static ]; then
    echo "==> Non-arm64 host: installing qemu-aarch64-static into the rootfs..."
    cp /usr/bin/qemu-aarch64-static "${MOUNT_POINT}/usr/bin/"
fi

# The rest of the build runs ARM programs inside the image. On an x86 machine
# that needs the host kernel to hand ARM binaries to qemu (binfmt_misc).
# Docker Desktop sets that up itself; Docker on x86 Linux does not, and
# without it every step fails with "Exec format error". Check once, here.
if ! chroot "${MOUNT_POINT}" /usr/bin/true 2>/dev/null; then
    echo "ERROR: this machine cannot run ARM programs inside the image." >&2
    arm_emulation_help
    exit 1
fi

echo "==> Setting up chroot..."
mount --bind /dev     "${MOUNT_POINT}/dev"
mount --bind /dev/pts "${MOUNT_POINT}/dev/pts"
mount --bind /proc    "${MOUNT_POINT}/proc"
mount --bind /sys     "${MOUNT_POINT}/sys"
mount --bind /run     "${MOUNT_POINT}/run"
if [ -n "${PACMAN_CACHE}" ]; then
    mkdir -p "${PACMAN_CACHE}" "${MOUNT_POINT}/var/cache/pacman/pkg"
    mount --bind "${PACMAN_CACHE}" "${MOUNT_POINT}/var/cache/pacman/pkg"
    echo "    package cache: ${PACMAN_CACHE} ($(ls "${PACMAN_CACHE}" | wc -l) packages)"
fi

# DNS inside the chroot: same preserve-and-restore as the terminal build.
# Arch Linux ARM points resolv.conf at systemd-resolved's stub, which does not
# exist until the device is running.
if [ -e "${MOUNT_POINT}/etc/resolv.conf" ] || [ -L "${MOUNT_POINT}/etc/resolv.conf" ]; then
    mv "${MOUNT_POINT}/etc/resolv.conf" "${MOUNT_POINT}/etc/resolv.conf.build-orig"
fi
if [ -s /etc/resolv.conf ]; then
    cp /etc/resolv.conf "${MOUNT_POINT}/etc/resolv.conf"
else
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "${MOUNT_POINT}/etc/resolv.conf"
fi

if [ ! -f "${MOUNT_POINT}/usr/share/zoneinfo/${TIMEZONE}" ]; then
    echo "ERROR: unknown timezone '${TIMEZONE}'." >&2
    echo "       Use a name from /usr/share/zoneinfo, e.g. Europe/London." >&2
    exit 1
fi

# ------------------------------------------------------------- desktop packages

cat << PKGS > "${MOUNT_POINT}/tmp/packages.sh"
#!/bin/bash
set -e

if ! getent hosts mirror.archlinuxarm.org >/dev/null 2>&1; then
    echo "ERROR: no DNS inside the chroot -- check /etc/resolv.conf." >&2
    exit 1
fi

# The community image relies on the keyring it was built with. It is replaced
# with a fresh, per-device one on first boot (see uconsole-firstboot-prep).
pacman-key --init >/dev/null 2>&1 || true
pacman-key --populate archlinuxarm

# --disable-sandbox: pacman's Landlock download sandbox does not work under
# qemu user emulation, and pacman then fails every download.
#
# -Syu, never -Sy followed by -S: on Arch a partial upgrade is how you get a
# system where half the libraries do not match. This also brings the kernel up
# to the latest from the uconsole-arch repo, which is the point of that repo.
for attempt in 1 2 3; do
    if pacman --disable-sandbox -Syu --needed --noconfirm ${DESKTOP_PACKAGES} ${EXTRA_PACKAGES}; then
        break
    fi
    if [ \${attempt} -eq 3 ]; then
        echo "ERROR: package install failed three times." >&2
        exit 1
    fi
    echo "    pacman attempt \${attempt}/3 failed -- retrying (ARM mirrors are slow)..."
    rm -f /var/lib/pacman/db.lck
    sleep \$((attempt * 10))
done

for bin in ${CHECK_BINS}; do
    command -v \${bin} >/dev/null || { echo "ERROR: \${bin} did not install" >&2; exit 1; }
done
PKGS

chmod +x "${MOUNT_POINT}/tmp/packages.sh"
echo "==> Installing the desktop (this is the long part)..."
chroot "${MOUNT_POINT}" /tmp/packages.sh
rm -f "${MOUNT_POINT}/tmp/packages.sh"

# pacman-key leaves a gpg-agent running inside the chroot, holding files open
# on the image. Left alone, the unmount at the end fails and the image stays
# attached -- and a second build would then mount the same filesystem twice,
# which corrupts it.
chroot "${MOUNT_POINT}" gpgconf --homedir /etc/pacman.d/gnupg --kill all 2>/dev/null || true

# ------------------------------------------------------------- real Omarchy

if [ "${OMARCHY_EDITION}" = "real" ]; then
    echo "==> Installing real Omarchy (this is the long part)..."
    rm -rf "${MOUNT_POINT}/tmp/omarchy-port"
    cp -r "${PORT_DIR}" "${MOUNT_POINT}/tmp/omarchy-port"
    chroot "${MOUNT_POINT}" bash /tmp/omarchy-port/install-omarchy.sh
    rm -rf "${MOUNT_POINT}/tmp/omarchy-port"
    chroot "${MOUNT_POINT}" gpgconf --homedir /etc/pacman.d/gnupg --kill all 2>/dev/null || true
fi

# ------------------------------------------------------------------- kernel

if [ "${KERNEL}" = "clockworkpi" ]; then
    uconsole_arch_use_clockworkpi_kernel "${MOUNT_POINT}" "${LOOP_DEVICE}"
else
    # The base image has no Pi GPU firmware whichever kernel boots, and a CM4
    # does not start without it.
    echo "==> Installing Pi firmware for the community kernel..."
    chroot "${MOUNT_POINT}" pacman --disable-sandbox -S --needed --noconfirm raspberrypi-bootloader firmware-raspberrypi
    [ -f "${MOUNT_POINT}/${BOOT_REL}/start4.elf" ] || { echo "ERROR: start4.elf missing" >&2; exit 1; }
fi
chroot "${MOUNT_POINT}" gpgconf --homedir /etc/pacman.d/gnupg --kill all 2>/dev/null || true

# ------------------------------------------------------------- boot command line

uconsole_set_console_rotation "${MOUNT_POINT}" "${BOOT_REL}" "${CONSOLE_ROTATE}"
if [ "${VERBOSE_BOOT}" = "1" ]; then
    echo "==> Verbose boot: kernel messages will show on the screen."
    sed -i -e 's/[[:space:]]*console=tty[0-9]*//g' -e 's/[[:space:]]*quiet//g' \
           -e 's/[[:space:]]*loglevel=[0-9]*//g' "${MOUNT_POINT}/${BOOT_REL}/cmdline.txt"
    sed -i '1s|$| console=tty1 loglevel=7 consoleblank=0|' "${MOUNT_POINT}/${BOOT_REL}/cmdline.txt"
else
    uconsole_quiet_console "${MOUNT_POINT}" "${BOOT_REL}"
fi

# Wifi regulatory domain, set on the kernel command line so it is in force
# before NetworkManager first touches the radio.
echo "==> Setting wifi regulatory domain (${WIFI_COUNTRY})..."
CMDLINE="${MOUNT_POINT}/${BOOT_REL}/cmdline.txt"
sed -i 's/[[:space:]]*cfg80211\.ieee80211_regdom=[A-Z]*//g' "${CMDLINE}"
sed -i "1s|\$| cfg80211.ieee80211_regdom=${WIFI_COUNTRY}|" "${CMDLINE}"
sed 's/^/      /' "${CMDLINE}"

# ---------------------------------------------------------------- the look

if [ "${OMARCHY_EDITION}" = "look" ]; then
echo "==> Installing the Omarchy look..."
SKEL="${MOUNT_POINT}/etc/skel"
mkdir -p "${SKEL}/.config/hypr" "${SKEL}/.config/waybar" "${SKEL}/.config/mako" \
         "${SKEL}/.config/alacritty" "${SKEL}/.config/fuzzel" "${SKEL}/.config/omarchy-look"

sed -e "s/__HYPR_TRANSFORM__/${HYPR_TRANSFORM}/" \
    -e "s/__HYPR_MOD__/${HYPR_MOD}/" \
    "${LOOK_DIR}/hypr/hyprland.conf" > "${SKEL}/.config/hypr/hyprland.conf"
if grep -q '__HYPR_' "${SKEL}/.config/hypr/hyprland.conf"; then
    echo "ERROR: unsubstituted placeholder left in hyprland.conf" >&2
    exit 1
fi
cp "${LOOK_DIR}/hypr/hyprlock.conf"        "${SKEL}/.config/hypr/"
cp "${LOOK_DIR}/hypr/hypridle.conf"        "${SKEL}/.config/hypr/"
cp "${LOOK_DIR}/waybar/config.jsonc"       "${SKEL}/.config/waybar/"
cp "${LOOK_DIR}/waybar/style.css"          "${SKEL}/.config/waybar/"
cp "${LOOK_DIR}/mako/config"               "${SKEL}/.config/mako/"
cp "${LOOK_DIR}/alacritty/alacritty.toml"  "${SKEL}/.config/alacritty/"
cp "${LOOK_DIR}/fuzzel/fuzzel.ini"         "${SKEL}/.config/fuzzel/"
cp "${LOOK_DIR}/bash_profile"              "${SKEL}/.bash_profile"
echo 'eval "$(starship init bash)"' >> "${SKEL}/.bashrc"

# A missing wallpaper is cosmetic -- swaybg just shows grey -- so it does not
# stop the build.
if curl -fsSL --retry 3 -o "${SKEL}/.config/omarchy-look/background" "${WALLPAPER_URL}"; then
    echo "    wallpaper: Omarchy tokyo-night/1-sunset-lake"
else
    echo "    WARNING: could not download the wallpaper; the desktop will be grey."
    rm -f "${SKEL}/.config/omarchy-look/background"
fi
fi

# Both editions: start Hyprland on the vc4 display device, not the render-only
# v3d one. See the comments in uconsole-drm.sh.
install -m 0755 "${LOOK_DIR}/bin/uconsole-hyprland" "${MOUNT_POINT}/usr/local/bin/uconsole-hyprland"
install -m 0644 "${LOOK_DIR}/profile.d/uconsole-drm.sh" "${MOUNT_POINT}/etc/profile.d/uconsole-drm.sh"

# --------------------------------------------------------------- the account

echo "==> Creating '${DESKTOP_USER}' and removing the stock 'alarm' user..."
cat << ACCOUNT > "${MOUNT_POINT}/tmp/account.sh"
#!/bin/bash
set -e

# Arch Linux ARM ships alarm/alarm and root/root, and sshd is enabled. On a
# card that joins wifi, that is an open door -- so both go.
if id -u alarm >/dev/null 2>&1 && [ "${DESKTOP_USER}" != "alarm" ]; then
    userdel -r alarm 2>/dev/null || userdel alarm
fi

# Root is locked outright. sudo is the way in, with the user's own password.
usermod -p '!' root

if ! id -u ${DESKTOP_USER} >/dev/null 2>&1; then
    useradd -m -s /bin/bash -c "uConsole" ${DESKTOP_USER}
fi
# Locked, not blank -- blank means "no password required". The first-boot
# wizard replaces this with a real hash.
usermod -p '!' ${DESKTOP_USER}

for g in wheel video audio input render uucp lp docker; do
    getent group \$g >/dev/null 2>&1 && usermod -aG \$g ${DESKTOP_USER} || true
done

echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel
visudo -cf /etc/sudoers.d/10-wheel

echo "${DESKTOP_HOST}" > /etc/hostname
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime

# Large console font for the login prompt and the first-boot wizard -- the same
# reasoning as the terminal build: the stock font is punishing on a 5" panel.
cat > /etc/vconsole.conf << VCONSOLE
KEYMAP=us
FONT=ter-v32b
VCONSOLE

systemctl enable NetworkManager.service
systemctl enable bluetooth.service
systemctl enable sshd.service
# Only the audio units that are installed -- the real edition's package set
# (Omarchy's) does not include pipewire-pulse, and enabling a missing unit fails.
for unit in pipewire.socket pipewire-pulse.socket wireplumber.service; do
    if [ -e "/usr/lib/systemd/user/\${unit}" ]; then
        systemctl --global enable "\${unit}"
    fi
done

# Arch Linux ARM manages wifi with systemd-networkd out of the box. Two network
# managers fighting over wlan0 is a reliable way to get flapping wifi.
systemctl disable systemd-networkd.service systemd-networkd.socket 2>/dev/null || true
ACCOUNT

chmod +x "${MOUNT_POINT}/tmp/account.sh"
chroot "${MOUNT_POINT}" /tmp/account.sh
rm -f "${MOUNT_POINT}/tmp/account.sh"

# ------------------------------------------------- real Omarchy on a uConsole

if [ "${OMARCHY_EDITION}" = "real" ]; then
    echo "==> Fitting Omarchy to the uConsole screen..."
    USER_HOME="${MOUNT_POINT}/home/${DESKTOP_USER}"
    MONITORS="${USER_HOME}/.config/hypr/monitors.lua"
    [ -f "${MONITORS}" ] || { echo "ERROR: Omarchy did not seed ${MONITORS}" >&2; exit 1; }

    # Omarchy's defaults are scale "auto" and GDK_SCALE 2 -- right for a
    # laptop, but on a 1280x720 five-inch panel they leave room for very
    # little. Scale 1, and the panel's rotation, set in the user's own
    # monitors.lua, which is where Omarchy expects personal overrides.
    sed -i -e 's/^local omarchy_gdk_scale = .*/local omarchy_gdk_scale = 1/' \
           -e 's/^local omarchy_monitor_scale = .*/local omarchy_monitor_scale = 1/' "${MONITORS}"
    cat >> "${MONITORS}" << LUA

-- ClockworkPi uConsole: the DSI panel is a portrait 720x1280 mounted sideways.
-- transform 3 = 270 degrees, which reads landscape. Try 1 if it is upside down.
hl.monitor({ output = "DSI-1", mode = "preferred", position = "auto", scale = 1, transform = ${HYPR_TRANSFORM} })
LUA
    grep -q '^local omarchy_monitor_scale = 1$' "${MONITORS}" \
        || { echo "ERROR: could not set Omarchy's monitor scale -- monitors.lua changed shape" >&2; exit 1; }

    # The SDDM login screen runs its own Hyprland with its own config, so it
    # needs the same rotation -- and, like the desktop, the vc4 display device.
    echo "==> Setting up the Omarchy login screen for the uConsole..."
    mkdir -p "${MOUNT_POINT}/etc/sddm"
    cat > "${MOUNT_POINT}/etc/sddm/uconsole-greeter.lua" << LUA
-- Omarchy's SDDM greeter config, plus the uConsole panel's rotation.
dofile("/usr/share/sddm/hyprland.lua")
hl.monitor({ output = "DSI-1", mode = "preferred", position = "auto", scale = 1, transform = ${HYPR_TRANSFORM} })
LUA
    cat > "${MOUNT_POINT}/etc/sddm.conf.d/20-uconsole.conf" << 'SDDM'
# Overrides Omarchy's 10-wayland.conf: same greeter compositor, started through
# the uConsole launcher (vc4 display device) with the rotated greeter config.
[Wayland]
CompositorCommand=/usr/local/bin/uconsole-hyprland -- --config /etc/sddm/uconsole-greeter.lua
SDDM

    # Pre-select the Omarchy session. SDDM otherwise offers whichever session
    # sorts first -- plain Hyprland, without Omarchy's uwsm environment.
    SDDM_STATE="${MOUNT_POINT}/var/lib/sddm/state.conf"
    mkdir -p "$(dirname "${SDDM_STATE}")"
    printf '[Last]\nSession=/usr/local/share/wayland-sessions/omarchy.desktop\nUser=%s\n' "${DESKTOP_USER}" > "${SDDM_STATE}"
    chroot "${MOUNT_POINT}" chown -R sddm:sddm /var/lib/sddm

    [ -L "${MOUNT_POINT}/etc/systemd/system/display-manager.service" ] \
        || chroot "${MOUNT_POINT}" systemctl enable sddm.service

    # Omarchy's per-user stage: default apps, xdg dirs, mise and Node, etc.
    # OMARCHY_SETUP_CONTEXT: with --first-install, Omarchy otherwise assumes
    # it is inside its own ISO and insists on the ISO's bundled x64 Node.js.
    echo "==> Running Omarchy's user setup for '${DESKTOP_USER}'..."
    chroot "${MOUNT_POINT}" runuser -u "${DESKTOP_USER}" -- env \
        HOME="/home/${DESKTOP_USER}" OMARCHY_PATH=/usr/share/omarchy \
        PATH="/usr/share/omarchy/bin:/usr/local/bin:/usr/bin" \
        OMARCHY_LOG_TO_STDOUT=1 OMARCHY_SETUP_CONTEXT=uconsole-image \
        bash -c 'omarchy-provision-user --first-install' \
        > /tmp/omarchy-user.log 2>&1 \
        || { tail -30 /tmp/omarchy-user.log >&2; echo "ERROR: Omarchy user setup failed" >&2; exit 1; }
    tail -1 /tmp/omarchy-user.log | sed 's/^/    /'
fi

# ------------------------------------------------------------ first-boot setup

echo "==> Installing first-boot services..."

# Part 1: non-interactive, runs before the wizard. Things that must differ per
# card and so cannot be baked into a shared image.
cat << 'PREP' > "${MOUNT_POINT}/usr/local/sbin/uconsole-firstboot-prep"
#!/bin/bash
# Per-device setup. Not `set -e`: none of this may stop the device booting.

STAMP=/var/lib/uconsole-firstboot-prep-pending

# A pacman keyring baked into an image means every card shares one private
# signing key. Generate a fresh one here instead.
if [ ! -d /etc/pacman.d/gnupg ]; then
    pacman-key --init && pacman-key --populate archlinuxarm
fi

# Fill the SD card. The image is only as big as the build made it.
ROOT_DEV="$(findmnt -no SOURCE /)"
case "${ROOT_DEV}" in
    /dev/mmcblk*p[0-9]*)
        DISK="${ROOT_DEV%p[0-9]*}"
        PART="${ROOT_DEV##*p}"
        growpart "${DISK}" "${PART}" && resize2fs "${ROOT_DEV}"
        ;;
esac

rm -f "${STAMP}"
PREP
chmod 0755 "${MOUNT_POINT}/usr/local/sbin/uconsole-firstboot-prep"
touch "${MOUNT_POINT}/var/lib/uconsole-firstboot-prep-pending"

cat << 'PREPUNIT' > "${MOUNT_POINT}/etc/systemd/system/uconsole-firstboot-prep.service"
[Unit]
Description=uConsole per-device first-boot preparation
Before=uconsole-firstboot.service getty@tty1.service sddm.service display-manager.service
ConditionPathExists=/var/lib/uconsole-firstboot-prep-pending

[Service]
Type=oneshot
RemainAfterExit=no
ExecStart=/usr/local/sbin/uconsole-firstboot-prep

[Install]
WantedBy=multi-user.target
PREPUNIT

# Part 2: the wizard, on tty1 before the login prompt. Same shape as the
# terminal build's, minus the root password -- root stays locked here.
cat << 'FIRSTBOOT' > "${MOUNT_POINT}/usr/local/sbin/uconsole-firstboot"
#!/bin/bash
# Deliberately NOT `set -e`: a failure partway through would leave a device with
# no usable password and no wizard to fix it.

STAMP=/var/lib/uconsole-firstboot-pending

# clear and nmtui both need a terminal type; a systemd unit may not set one.
export TERM="${TERM:-linux}"

# Kernel and systemd messages go to the console. With VERBOSE_BOOT that is this
# very screen, and joining wifi produces a burst of them (driver, DHCP, regdom)
# that paints over nmtui and leaves it hard to read or navigate. Hold them
# back while the wizard runs; the kernel's level is put back at the end.
read -r PRINTK_LEVEL _ < /proc/sys/kernel/printk
echo 1 > /proc/sys/kernel/printk
kill -s SIGRTMIN+21 1 2>/dev/null    # systemd: no status lines on the console

clear
echo ""
echo "=============================================="
echo "  uConsole first-time setup"
echo "=============================================="
echo ""
echo "  This runs once. Nothing was stored in the image."
echo ""

echo "1. Password for '__DESKTOP_USER__'."
echo "   You type it to log in, to unlock the screen, and for sudo."
echo ""
while true; do
    if passwd __DESKTOP_USER__; then
        break
    fi
    echo "   Try again."
done

# No `usermod -U` -- see create-uconsole-terminal.sh. A successful passwd has
# already replaced the '!' lock with a real hash.

echo ""
echo "2. Wifi."
echo ""
read -rp "   Connect to wifi now? [Y/n] " ans
case "${ans}" in
    [Nn]*) echo "   Skipped -- click the wifi icon in the top bar later." ;;
    *)     nmtui-connect || echo "   Wifi setup did not complete -- click the wifi icon in the top bar later." ;;
esac

# Stamp removed last, so an interrupted wizard runs again next boot.
rm -f "${STAMP}"
echo "${PRINTK_LEVEL}" > /proc/sys/kernel/printk
systemctl disable uconsole-firstboot.service 2>/dev/null

clear
echo ""
echo "  Done. __DONE_HINT_1__"
echo ""
echo "  __DONE_HINT_2__"
echo "  __DONE_HINT_3__"
echo ""
sleep 4
FIRSTBOOT

if [ "${OMARCHY_EDITION}" = "real" ]; then
    DONE_HINT_1="The Omarchy login screen comes next -- log in as '${DESKTOP_USER}'."
    DONE_HINT_2="Super: hold Fn, hold Alt, let go of Fn (keep Alt), then press the key."
    DONE_HINT_3="Super + Space: Omarchy menu.  Super + Enter: foot, the default terminal."
else
    DONE_HINT_1="Log in as '${DESKTOP_USER}' and the desktop starts."
    DONE_HINT_2="Launcher: ${HYPR_MOD} + Space     Terminal: ${HYPR_MOD} + Enter"
    DONE_HINT_3="(Super: hold Fn + Alt, let go of Fn. Or click the top-left icons.)"
fi
sed -i -e "s|__DESKTOP_USER__|${DESKTOP_USER}|g" \
       -e "s|__DONE_HINT_1__|${DONE_HINT_1}|" \
       -e "s|__DONE_HINT_2__|${DONE_HINT_2}|" \
       -e "s|__DONE_HINT_3__|${DONE_HINT_3}|" \
    "${MOUNT_POINT}/usr/local/sbin/uconsole-firstboot"
grep -q '__[A-Z_]*__' "${MOUNT_POINT}/usr/local/sbin/uconsole-firstboot" \
    && { echo "ERROR: unsubstituted placeholder left in the first-boot wizard" >&2; exit 1; }
chmod 0755 "${MOUNT_POINT}/usr/local/sbin/uconsole-firstboot"
touch "${MOUNT_POINT}/var/lib/uconsole-firstboot-pending"

cat << 'FBUNIT' > "${MOUNT_POINT}/etc/systemd/system/uconsole-firstboot.service"
[Unit]
Description=uConsole first-boot setup
# Before the console login AND the graphical login: SDDM must not take the
# screen while the wizard is still asking for the password it will check.
Before=getty@tty1.service sddm.service display-manager.service
After=uconsole-firstboot-prep.service NetworkManager.service
Wants=NetworkManager.service
ConditionPathExists=/var/lib/uconsole-firstboot-pending

[Service]
Type=oneshot
RemainAfterExit=no
ExecStart=/usr/local/sbin/uconsole-firstboot
StandardInput=tty
StandardOutput=tty
StandardError=tty
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes

[Install]
WantedBy=multi-user.target
FBUNIT

chroot "${MOUNT_POINT}" systemctl enable uconsole-firstboot-prep.service uconsole-firstboot.service

# ------------------------------------------------------------------ finalise

echo "==> Final tidy..."
# Detach the host package cache BEFORE emptying the image's own cache dir --
# with it still mounted, this rm would delete the host's cache instead.
if [ -n "${PACMAN_CACHE}" ]; then
    umount "${MOUNT_POINT}/var/cache/pacman/pkg"
fi
if mountpoint -q "${MOUNT_POINT}/var/cache/pacman/pkg"; then
    echo "ERROR: package cache is still mounted; refusing to clear it." >&2
    exit 1
fi
rm -rf "${MOUNT_POINT}/var/cache/pacman/pkg/"*
rm -rf "${MOUNT_POINT}/var/lib/pacman/sync/"*
rm -f  "${MOUNT_POINT}/root/.bash_history"
rm -f  "${MOUNT_POINT}/usr/bin/qemu-aarch64-static"

# Per-device identity is regenerated on first boot: the pacman keyring by the
# prep service, ssh host keys by sshdgenkeys.service, machine-id by systemd.
rm -rf "${MOUNT_POINT}/etc/pacman.d/gnupg"
rm -f  "${MOUNT_POINT}"/etc/ssh/ssh_host_*
: > "${MOUNT_POINT}/etc/machine-id"

rm -f "${MOUNT_POINT}/etc/resolv.conf"
if [ -e "${MOUNT_POINT}/etc/resolv.conf.build-orig" ] || [ -L "${MOUNT_POINT}/etc/resolv.conf.build-orig" ]; then
    mv "${MOUNT_POINT}/etc/resolv.conf.build-orig" "${MOUNT_POINT}/etc/resolv.conf"
fi

# A resolv.conf pointing at systemd-resolved's stub only works if resolved is
# actually running. (Its target lives under /run, so it reads as dangling here
# in the build -- that is expected and not checked.)
if [ -L "${MOUNT_POINT}/etc/resolv.conf" ] \
&& readlink "${MOUNT_POINT}/etc/resolv.conf" | grep -q 'systemd/resolve'; then
    chroot "${MOUNT_POINT}" systemctl enable systemd-resolved.service
fi

echo "==> Checking the image can be logged into..."
fail() { echo "ERROR: $*" >&2; echo "       This image is not usable." >&2; exit 1; }

[ -x "${MOUNT_POINT}/usr/local/sbin/uconsole-firstboot" ] || fail "first-boot wizard is not executable."
[ -e "${MOUNT_POINT}/var/lib/uconsole-firstboot-pending" ] || fail "first-boot trigger missing -- wizard would never run."
[ -L "${MOUNT_POINT}/etc/systemd/system/multi-user.target.wants/uconsole-firstboot.service" ] \
    || fail "first-boot service is not enabled -- no way to set a password."
grep -q "^${DESKTOP_USER}:!:" "${MOUNT_POINT}/etc/shadow" || fail "${DESKTOP_USER} is not in the expected locked state."
grep -q '^root:!' "${MOUNT_POINT}/etc/shadow" || fail "root is not locked."
grep -q '^alarm:' "${MOUNT_POINT}/etc/passwd" && fail "the default 'alarm' account is still present."
if [ "${OMARCHY_EDITION}" = "real" ]; then
    chroot "${MOUNT_POINT}" pacman -Q omarchy omarchy-settings >/dev/null || fail "Omarchy is not installed."
    [ -f "${MOUNT_POINT}/home/${DESKTOP_USER}/.config/hypr/hyprland.lua" ] || fail "Omarchy's Hyprland config did not reach the user's home."
    grep -q 'output = "DSI-1"' "${MOUNT_POINT}/home/${DESKTOP_USER}/.config/hypr/monitors.lua" || fail "uConsole monitor line missing."
    [ -L "${MOUNT_POINT}/etc/systemd/system/display-manager.service" ] || fail "SDDM is not enabled -- no login screen."
    [ -f "${MOUNT_POINT}/etc/sddm.conf.d/20-uconsole.conf" ] || fail "uConsole SDDM config missing."
    grep -q '^\[uconsole-arch\]' "${MOUNT_POINT}/etc/pacman.conf" || fail "the uConsole kernel repo was dropped from pacman.conf."
    [ ! -e "${MOUNT_POINT}/etc/mkinitcpio.conf.d/omarchy_hooks.conf" ] || fail "Omarchy's PC initramfs hooks are present -- next kernel update would not boot."
else
    [ -f "${MOUNT_POINT}/home/${DESKTOP_USER}/.config/hypr/hyprland.conf" ] || fail "Hyprland config did not reach the user's home."
fi
[ -x "${MOUNT_POINT}/usr/local/bin/uconsole-hyprland" ] || fail "Hyprland launcher missing."
echo "    ok"

BUILD_COMPLETE=1

echo ""
echo "=========================================================="
echo " Omarchy uConsole image built -- edition: ${OMARCHY_EDITION}."
echo "=========================================================="
echo " Base:   community uConsole Arch Linux ARM ${BASE_RELEASE}"
echo " Kernel: ${KERNEL}$([ "${KERNEL}" = clockworkpi ] && echo " (${UCONSOLE_CWPI_KVER}, as the Raspberry Pi OS builds)")"
echo " Image:  ${IMAGE_DIR}/${IMAGE_NAME}"
echo " Setup:  first boot asks for ${DESKTOP_USER}'s password, then wifi."
echo "         This .img contains no passwords and no wifi key."
if [ "${OMARCHY_EDITION}" = "real" ]; then
echo " Login:  Omarchy's login screen (SDDM), as ${DESKTOP_USER}."
echo " Keys:   Super = hold Fn, hold Alt, let go of Fn (keep Alt), press the key."
echo "         Super + Enter opens foot, Omarchy's default terminal."
echo "         Ctrl+Alt+F2 is a plain console if the desktop will not start."
echo " Note:   confirmed booting on a uConsole CM4 with KERNEL=clockworkpi."
else
echo " Login:  ${DESKTOP_USER} on tty1 starts Hyprland."
echo "         Ctrl+Alt+F2 is a plain console if the desktop will not start."
fi
echo " SSH:    enabled (root locked; log in as ${DESKTOP_USER})"
echo ""
echo " CHECKPOINT -- in this order:"
echo "   1. does the console come up the right way round?"
echo "        no -> CONSOLE_ROTATE=3 (0=normal 1=90cw 2=180 3=270cw)"
echo "   2. does the desktop come up the right way round?"
echo "        no -> HYPR_TRANSFORM=1, or edit the transform in ~/.config/hypr/"
if [ "${OMARCHY_EDITION}" = "real" ]; then
echo "   3. does the Omarchy login screen appear, and the desktop after it?"
echo "        black screen -> Ctrl+Alt+F2, log in, journalctl -b -u sddm"
else
echo "   3. does ${HYPR_MOD}+Enter open a terminal?"
echo "        no -> HYPR_MOD=ALT, or use the top-left bar icons"
fi
echo "=========================================================="
