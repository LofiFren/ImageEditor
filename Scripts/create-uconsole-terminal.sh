#!/bin/bash
#
# Build a TERMINAL-ONLY Linux image for the ClockworkPi uConsole CM4.
#
# Base: Raspberry Pi OS Lite (Debian 13 "trixie", arm64).
#
# Why this base rather than Ubuntu Server: the ClockworkPi kernel package that
# drives the uConsole screen is built for the flat Raspberry Pi OS boot layout
# (/boot/kernel8.img, /boot/config.txt, /boot/overlays/). Ubuntu 26.04 uses an
# A/B "tryboot" layout with os_prefix=current/ and a vmlinuz-named kernel, which
# mismatches the package in five separate ways and needs fragile glue to bridge.
# Raspberry Pi OS Lite mismatches it in exactly one (the FAT partition mounts at
# /boot/firmware, not /boot), which uconsole_reconcile_boot handles.
#
# Lite ships zero GUI packages, so this is terminal-only by construction --
# there is no desktop to strip out and nothing to accidentally leave behind.
#
# Usage (inside the image-editor container, as root):
#   ./create-uconsole-terminal.sh [image-name.img.xz]

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/uconsole-drivers.sh"

# ---------------------------------------------------------------- configuration

WORKDIR="/workdir"
IMAGE_DIR="${WORKDIR}/images"

# Raspberry Pi OS Lite arm64. Latest release list:
#   https://downloads.raspberrypi.com/raspios_lite_arm64/images/
IMAGE_XZ="${1:-2026-06-18-raspios-trixie-arm64-lite.img.xz}"
IMAGE_NAME="${IMAGE_XZ%.xz}"

MOUNT_POINT="/mnt/uconsole"
FW_REL="boot/firmware"          # Raspberry Pi OS mounts the FAT partition here

# The kid's account. The stock 'pi' user is removed.
KID_USER="${KID_USER:-pilot}"
KID_HOST="${KID_HOST:-uconsole}"

# Tools worth having on day one. Nobody should hit "command not found" on `man`.
LEARNING_PACKAGES="vim nano man-db manpages less tree htop tmux git python3 build-essential"

# Console font. The uConsole's panel is small and dense, so the stock font is
# hard going. Terminus at 16x32 is the largest available and the bold weight
# reads better on a small screen than size alone. Step down through 14x28,
# 12x24, 10x20 if it feels too chunky.
CONSOLE_FONTFACE="${CONSOLE_FONTFACE:-TerminusBold}"
CONSOLE_FONTSIZE="${CONSOLE_FONTSIZE:-16x32}"

# Console rotation. The uConsole's panel is mounted sideways, so the text
# console has to be rotated in the kernel -- there is no X server here to do it.
# 0=normal 1=90cw 2=180 3=270cw. 1 matches the Kali image's `xrandr --rotate
# right`. If the login prompt comes up sideways or upside down, this is the
# single value to change.
CONSOLE_ROTATE="${CONSOLE_ROTATE:-1}"

# Wifi regulatory country. This is NOT optional paperwork: on a Raspberry Pi the
# wlan0 radio ships rfkill-blocked and stays blocked until a country is set, so
# without this the first-boot symptom is "no wifi hardware" rather than "no
# networks found". Two-letter ISO code -- GB, DE, CA, AU, etc.
WIFI_COUNTRY="${WIFI_COUNTRY:-US}"

# Raspberry Pi OS's own kernel packages. If these are ever upgraded they will
# rewrite kernel8.img and config.txt and silently kill the uConsole display, so
# they get pinned out once the vendor kernel is in place.
DISTRO_KERNEL_PKGS="linux-image-rpi-v8 linux-image-rpi-2712 raspi-firmware"

# ------------------------------------------------------------------- cleanup

LOOP_DEVICE=""

cleanup() {
    echo "Cleaning up..."
    umount "${MOUNT_POINT}/dev/pts"    2>/dev/null || true
    umount "${MOUNT_POINT}/dev"        2>/dev/null || true
    umount "${MOUNT_POINT}/proc"       2>/dev/null || true
    umount "${MOUNT_POINT}/sys"        2>/dev/null || true
    umount "${MOUNT_POINT}/${FW_REL}"  2>/dev/null || true
    umount "${MOUNT_POINT}"            2>/dev/null || true

    if [ -n "${LOOP_DEVICE}" ]; then
        kpartx -d "${LOOP_DEVICE}" 2>/dev/null || true
        losetup -d "${LOOP_DEVICE}" 2>/dev/null || true
    fi

    # A build that dies between locking the accounts and installing the wizard
    # leaves an image that boots fine and cannot be logged into by anyone. That
    # happened once and cost an afternoon; say so plainly rather than let the
    # next person discover it at the login prompt.
    if [ "${BUILD_COMPLETE:-0}" != "1" ]; then
        echo ""                                                        >&2
        echo "  BUILD DID NOT COMPLETE."                                >&2
        echo "  Do NOT flash ${IMAGE_NAME} -- it may have locked"       >&2
        echo "  accounts and no way to set a password."                 >&2
        echo "  Delete it and start again:"                             >&2
        echo "      rm -f ${IMAGE_DIR}/${IMAGE_NAME}"                   >&2
        echo ""                                                        >&2
    fi
}
trap cleanup EXIT

# --------------------------------------------------------------- credentials
#
# Two ways to do this, and the default is the safer one.
#
# FIRSTBOOT_SETUP=1 (default): no passwords are collected here and none are
#   written to the image. The device runs a setup wizard on the very first boot,
#   before the login prompt, and the secrets are typed there. The .img that
#   comes out of this build contains no credentials at all -- it can sit on your
#   disk, or be handed to someone else, without leaking anything.
#
# FIRSTBOOT_SETUP=0: the old behaviour. Passwords are hashed into /etc/shadow
#   here. Use it when you are flashing several cards unattended and would rather
#   not sit through a wizard on each -- and accept that the .img is then a
#   secret, because those hashes are offline-crackable.
FIRSTBOOT_SETUP="${FIRSTBOOT_SETUP:-1}"

if [ "${FIRSTBOOT_SETUP}" = "1" ]; then
    echo "Setup mode: first boot."
    echo "  No passwords or wifi details are stored in this image."
    echo "  The uConsole will ask for them on its first boot."
    echo ""
    echo "  Do that first boot yourself -- the wizard asks for the root/sudo"
    echo "  password, which is the one you are keeping from your kid."
    echo ""
    # Locked, not blank. A blank password field means "no password required",
    # which would be a considerably worse failure than being unable to log in.
    KID_HASH='!'
    SUDO_HASH='!'
    WIFI_SSID=""
else
    echo "Setup mode: bake credentials into the image."
    echo "  The resulting .img will contain password hashes -- treat it as a"
    echo "  secret and delete it once the card is written."
    echo ""
    read -rsp "Login password for ${KID_USER}: " KID_PASS; echo
    read -rsp "Confirm: " KID_PASS2; echo
    [ "${KID_PASS}" = "${KID_PASS2}" ] || { echo "Passwords did not match."; exit 1; }
    [ -n "${KID_PASS}" ] || { echo "Password cannot be empty."; exit 1; }

    read -rsp "Root/sudo password (yours): " SUDO_PASS; echo
    read -rsp "Confirm: " SUDO_PASS2; echo
    [ "${SUDO_PASS}" = "${SUDO_PASS2}" ] || { echo "Passwords did not match."; exit 1; }
    [ -n "${SUDO_PASS}" ] || { echo "Password cannot be empty."; exit 1; }

    KID_HASH="$(openssl passwd -6 "${KID_PASS}")"
    SUDO_HASH="$(openssl passwd -6 "${SUDO_PASS}")"
    unset KID_PASS KID_PASS2 SUDO_PASS SUDO_PASS2
fi

# ------------------------------------------------------------------ wifi setup

# The regulatory country is asked in both modes and stored in both. It is not a
# secret -- it is which radio channels are legal where you live -- and getting
# it wrong leaves the radio rfkill-blocked, presenting as "no wifi hardware"
# rather than anything that mentions a country.
echo ""
read -rp "Wifi country code [${WIFI_COUNTRY}]: " WIFI_COUNTRY_IN
WIFI_COUNTRY="${WIFI_COUNTRY_IN:-${WIFI_COUNTRY}}"
WIFI_COUNTRY="$(echo "${WIFI_COUNTRY}" | tr '[:lower:]' '[:upper:]')"
case "${WIFI_COUNTRY}" in
    [A-Z][A-Z]) ;;
    *) echo "Country must be a two-letter ISO code (US, GB, DE...)."; exit 1 ;;
esac
unset WIFI_COUNTRY_IN

# Baking the network in is optional. Leave the SSID blank and the image still
# ships with the radio working -- you just pick the network with 'wifi' on the
# device, which is what the previous build did.
WIFI_PSK=""
if [ "${FIRSTBOOT_SETUP}" != "1" ]; then
    echo ""
    echo "Bake in a wifi network so it connects with no interaction?"
    echo "  (leave blank to skip -- you can always run 'wifi' on the device)"
    read -rp "Wifi SSID: " WIFI_SSID
fi

if [ -n "${WIFI_SSID}" ]; then
    read -rsp "Wifi passphrase for '${WIFI_SSID}': " WIFI_PSK; echo
    read -rsp "Confirm: " WIFI_PSK2; echo
    [ "${WIFI_PSK}" = "${WIFI_PSK2}" ] || { echo "Passphrases did not match."; exit 1; }
    unset WIFI_PSK2
    # WPA2 requires 8-63 characters; catching it here beats a device that
    # silently never associates.
    if [ ${#WIFI_PSK} -lt 8 ] || [ ${#WIFI_PSK} -gt 63 ]; then
        echo "Passphrase must be 8-63 characters."; exit 1
    fi
    # Convert the passphrase to the WPA2 pre-shared key it derives, so the
    # passphrase itself never touches the card.
    #
    # PMK = PBKDF2-HMAC-SHA1(passphrase, ssid, 4096 iterations, 32 bytes).
    # NetworkManager accepts this 64-hex-digit form directly.
    #
    # Be clear about what this does and does not buy you. It does NOT make the
    # card safe to lose: the PSK is all anyone needs to join your network, so
    # that risk is unchanged. What it protects is the *passphrase as a string* --
    # the thing people reuse on other accounts, and the thing that is derived
    # from something guessable often enough to matter. It also cannot be shoulder
    # -read off a screen or a scrollback buffer later.
    #
    # Passed by environment, not argv, so it never appears in `ps`.
    WIFI_PSK_HEX="$(
        WPA_PSK="${WIFI_PSK}" WPA_SSID="${WIFI_SSID}" python3 -c '
import hashlib, os, binascii
pmk = hashlib.pbkdf2_hmac("sha1", os.environb[b"WPA_PSK"],
                          os.environb[b"WPA_SSID"], 4096, 32)
print(binascii.hexlify(pmk).decode())
'
    )"
    unset WIFI_PSK

    case "${WIFI_PSK_HEX}" in
        [0-9a-f]*) [ ${#WIFI_PSK_HEX} -eq 64 ] || { echo "PSK derivation failed."; exit 1; } ;;
        *) echo "PSK derivation failed."; exit 1 ;;
    esac

    echo ""
    echo "  Passphrase converted to a pre-shared key; the passphrase itself is"
    echo "  not written to the card."
    echo ""
    echo "  It is still true that anyone holding the card can join your wifi --"
    echo "  the key is enough for that, and no amount of hashing changes it."
    echo "  If that matters, put the uConsole on a guest network."
fi

# ------------------------------------------------------------------ prepare

mkdir -p "${MOUNT_POINT}"

if [ ! -f "${IMAGE_DIR}/${IMAGE_NAME}" ]; then
    if [ ! -f "${IMAGE_DIR}/${IMAGE_XZ}" ]; then
        echo "Error: neither ${IMAGE_NAME} nor ${IMAGE_XZ} found in ${IMAGE_DIR}"
        echo "Get Raspberry Pi OS Lite (64-bit) from:"
        echo "  https://downloads.raspberrypi.com/raspios_lite_arm64/images/"
        exit 1
    fi
    echo "==> Extracting ${IMAGE_XZ}..."
    xz -d -k "${IMAGE_DIR}/${IMAGE_XZ}"
fi

for stale in $(losetup -j "${IMAGE_DIR}/${IMAGE_NAME}" | cut -d: -f1); do
    echo "==> Releasing stale loop device ${stale}..."
    kpartx -d "${stale}" 2>/dev/null || true
    losetup -d "${stale}" 2>/dev/null || true
done

# ---------------------------------------------------------------- grow the image
#
# Raspberry Pi OS Lite ships a root partition sized for its own package set with
# very little slack -- around 2.4 GB, most of it used. Adding the 29 MB vendor
# kernel plus vim/git/build-essential/tmux overruns it, and apt's way of saying
# so is "You don't have enough free space in /var/cache/apt/archives/" partway
# through, leaving a half-built image.
#
# The device expands the rootfs to fill the SD card on first boot, but that is no
# help here, so grow the file and the filesystem before writing anything to it.
IMAGE_GROW="${IMAGE_GROW:-3G}"

echo "==> Growing the image by ${IMAGE_GROW} to make room for packages..."
truncate -s "+${IMAGE_GROW}" "${IMAGE_DIR}/${IMAGE_NAME}"

echo "==> Attaching image to a loop device..."
# NOTE: do not use `losetup --partscan` here. Inside Docker Desktop's Linux VM
# it attaches the device but never creates the /dev/loopNpN partition nodes.
# kpartx builds mappings under /dev/mapper/ instead, and works.
LOOP_DEVICE="$(losetup --find --show "${IMAGE_DIR}/${IMAGE_NAME}")"
echo "    ${LOOP_DEVICE}"

# Extend partition 2 over the space just added. This has to happen on the whole
# -disk loop device and BEFORE kpartx maps the partitions -- the mappings capture
# partition sizes at creation time, so growing the table afterwards leaves them
# pointing at the old, smaller extent.
echo "==> Extending the root partition..."
parted -s "${LOOP_DEVICE}" resizepart 2 100%

kpartx -av "${LOOP_DEVICE}"
sleep 2

LOOP_BASE="$(basename "${LOOP_DEVICE}")"
PART_BOOT="/dev/mapper/${LOOP_BASE}p1"   # FAT32 -- bootloader, config.txt, cmdline.txt
PART_ROOT="/dev/mapper/${LOOP_BASE}p2"   # ext4  -- rootfs

for dev in "${PART_BOOT}" "${PART_ROOT}"; do
    [ -b "${dev}" ] || { echo "Error: ${dev} missing. Is this really a Pi image?"; exit 1; }
done

# resize2fs refuses to touch a filesystem that has not been checked.
echo "==> Growing the root filesystem..."
e2fsck -f -y "${PART_ROOT}" || true
resize2fs "${PART_ROOT}"

# Confirm we actually gained room. This MUST be measured through a mount point:
# `df` on an unmounted device path reports whatever filesystem the /dev node
# lives on (the container's /dev), not the image -- which reads as ~64 MB and
# aborts a perfectly good build. Mount, measure, unmount.
mkdir -p /mnt/sizecheck
mount "${PART_ROOT}" /mnt/sizecheck
AVAIL_MB="$(df -m --output=avail /mnt/sizecheck | tail -1 | tr -d ' ')"
umount /mnt/sizecheck
echo "    ${AVAIL_MB} MB free on the rootfs"
if [ -n "${AVAIL_MB}" ] && [ "${AVAIL_MB}" -lt 1500 ]; then
    echo "ERROR: only ${AVAIL_MB} MB free -- the package install will run out." >&2
    echo "       Retry with a bigger grow, e.g. IMAGE_GROW=5G" >&2
    exit 1
fi

echo "==> Mounting partitions..."
mount "${PART_ROOT}" "${MOUNT_POINT}"
mkdir -p "${MOUNT_POINT}/${FW_REL}"
mount "${PART_BOOT}" "${MOUNT_POINT}/${FW_REL}"

if [ "$(uname -m)" != "aarch64" ] && [ -f /usr/bin/qemu-aarch64-static ]; then
    echo "==> Non-arm64 host: installing qemu-aarch64-static into the rootfs..."
    cp /usr/bin/qemu-aarch64-static "${MOUNT_POINT}/usr/bin/"
fi

echo "==> Setting up chroot..."
mount --bind /dev     "${MOUNT_POINT}/dev"
mount --bind /dev/pts "${MOUNT_POINT}/dev/pts"
mount --bind /proc    "${MOUNT_POINT}/proc"
mount --bind /sys     "${MOUNT_POINT}/sys"

# Keep DNS working inside the chroot for apt.
#
# Debian/Ubuntu ship /etc/resolv.conf as a symlink to a systemd-resolved stub
# that does not exist inside a chroot. Copying onto it fails silently ("not
# writing through dangling symlink"), leaving the chroot with no DNS -- apt then
# fails to resolve anything and the kernel install dies. Remove it, write a real
# file, and restore the symlink at the end.
# Preserve whatever was there -- symlink or real file -- so it can be put back
# byte-for-byte afterwards. Do NOT assume the distro uses systemd-resolved:
# Raspberry Pi OS does not, and recreating that symlink leaves a dangling link
# and a system that cannot resolve names.
if [ -e "${MOUNT_POINT}/etc/resolv.conf" ] || [ -L "${MOUNT_POINT}/etc/resolv.conf" ]; then
    mv "${MOUNT_POINT}/etc/resolv.conf" "${MOUNT_POINT}/etc/resolv.conf.build-orig"
fi
if [ -s /etc/resolv.conf ]; then
    cp /etc/resolv.conf "${MOUNT_POINT}/etc/resolv.conf"
else
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "${MOUNT_POINT}/etc/resolv.conf"
fi

# ------------------------------------------------ the uConsole display driver

uconsole_install_drivers "${MOUNT_POINT}"
uconsole_reconcile_boot "${MOUNT_POINT}" "${FW_REL}"
uconsole_set_console_rotation "${MOUNT_POINT}" "${FW_REL}" "${CONSOLE_ROTATE}"
uconsole_quiet_console "${MOUNT_POINT}" "${FW_REL}"

echo "==> Pinning Raspberry Pi OS kernel packages out of the way..."
# The vendor kernel owns kernel8.img and config.txt now. Let apt upgrade either
# of these back and the screen goes dark on the next reboot.
{
    for pkg in ${DISTRO_KERNEL_PKGS}; do
        echo "Package: ${pkg}"
        echo "Pin: release *"
        echo "Pin-Priority: -1"
        echo ""
    done
} > "${MOUNT_POINT}/etc/apt/preferences.d/no-distro-rpi-kernel"

# --------------------------------------------------------------- terminal-only

echo "==> Locking the image to a text console..."
# Lite has no display manager to begin with. Setting this explicitly means that
# installing something with a GUI dependency later cannot quietly turn this into
# a desktop machine.
chroot "${MOUNT_POINT}" systemctl set-default multi-user.target

# --------------------------------------------------------------- the account

echo "==> Creating '${KID_USER}' and removing the stock 'pi' user..."
cat << ACCOUNT > "${MOUNT_POINT}/tmp/account.sh"
#!/bin/bash
set -e

# Create the kid's account with the login password.
if ! id -u ${KID_USER} >/dev/null 2>&1; then
    useradd -m -s /bin/bash -c "uConsole" ${KID_USER}
fi
usermod -p '${KID_HASH}' ${KID_USER}

# Hardware groups so serial, audio and GPIO work without fighting permissions.
for g in adm dialout audio video plugdev netdev i2c spi gpio sudo; do
    getent group \$g >/dev/null 2>&1 && usermod -aG \$g ${KID_USER} || true
done

# sudo asks for its OWN password (root's), not the login password. The parent
# holds it. Removing the stock passwordless rule is the important half.
rm -f /etc/sudoers.d/010_pi-nopasswd /etc/sudoers.d/010_${KID_USER}-nopasswd
echo 'Defaults rootpw' > /etc/sudoers.d/90-uconsole
echo '${KID_USER} ALL=(ALL:ALL) ALL' >> /etc/sudoers.d/90-uconsole
chmod 0440 /etc/sudoers.d/90-uconsole
visudo -cf /etc/sudoers.d/90-uconsole

# Root password is the sudo password.
usermod -p '${SUDO_HASH}' root

# Drop the default 'pi' account so there is no known-name way in.
if id -u pi >/dev/null 2>&1 && [ "${KID_USER}" != "pi" ]; then
    userdel -r pi 2>/dev/null || userdel pi 2>/dev/null || true
fi

# Raspberry Pi OS's first-boot wizard would otherwise prompt to create a user.
systemctl disable userconfig.service 2>/dev/null || true
rm -f /etc/systemd/system/multi-user.target.wants/userconfig.service
systemctl enable getty@tty1.service 2>/dev/null || true

echo "${KID_HOST}" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1\t${KID_HOST}/" /etc/hosts 2>/dev/null || true
ACCOUNT

chmod +x "${MOUNT_POINT}/tmp/account.sh"
chroot "${MOUNT_POINT}" /tmp/account.sh
rm -f "${MOUNT_POINT}/tmp/account.sh"

# ------------------------------------------------------------ first-boot setup
#
# Runs once, on tty1, BEFORE the login prompt appears -- so it does not need
# anyone to be logged in, which is just as well, since in this mode no account
# has a usable password until the wizard sets one.

if [ "${FIRSTBOOT_SETUP}" = "1" ]; then
echo "==> Installing first-boot setup wizard..."

cat << 'FIRSTBOOT' > "${MOUNT_POINT}/usr/local/sbin/uconsole-firstboot"
#!/bin/bash
# First-boot setup. Sets the passwords and joins a wifi network, then removes
# its own trigger so it never runs again.
#
# Deliberately NOT `set -e`: a failure partway through would leave a device with
# no usable password and no wizard to fix it. Every step is checked by hand.

STAMP=/var/lib/uconsole-firstboot-pending

echo ""
echo "=============================================="
echo "  uConsole first-time setup"
echo "=============================================="
echo ""
echo "  This runs once. Nothing was stored in the image."
echo ""

# ---- root / sudo password (the parent's) ----
echo "1. Root password -- this is the one 'sudo' will ask for."
echo "   Keep it to yourself."
echo ""
while true; do
    if passwd root; then
        break
    fi
    echo "   Try again."
done

# ---- login password (the kid's) ----
echo ""
echo "2. Login password for '__KID_USER__'."
echo "   This is the one they type to log in. Let them set it."
echo ""
while true; do
    if passwd __KID_USER__; then
        break
    fi
    echo "   Try again."
done

# No `usermod -U` here, on purpose. The accounts ship locked (hash '!'), and a
# successful `passwd` above already replaced that with a real hash -- which is
# what unlocks them. Running `usermod -U` against a still-locked account would
# strip the '!' and leave the password field EMPTY, meaning no password at all.
# That is a far worse outcome than the problem it would be trying to fix.

# ---- wifi ----
echo ""
echo "3. Wifi."
echo ""
if command -v nmtui-connect >/dev/null 2>&1; then
    read -rp "   Connect to wifi now? [Y/n] " ans
    case "${ans}" in
        [Nn]*) echo "   Skipped -- run 'wifi' later." ;;
        *)     nmtui-connect || echo "   Wifi setup did not complete -- run 'wifi' later." ;;
    esac
else
    echo "   nmtui-connect not found -- use 'sudo nmcli device wifi list' later."
fi

# ---- done ----
# Remove the stamp last. If anything above died or the power was pulled, the
# stamp survives and the wizard runs again on the next boot, which is the
# behaviour you want -- a half-configured device retries rather than locking you
# out permanently.
rm -f "${STAMP}"
systemctl disable uconsole-firstboot.service 2>/dev/null

echo ""
echo "  Done. Logging in from here."
echo ""
sleep 2
FIRSTBOOT

sed -i "s/__KID_USER__/${KID_USER}/g" "${MOUNT_POINT}/usr/local/sbin/uconsole-firstboot"
chmod 0755 "${MOUNT_POINT}/usr/local/sbin/uconsole-firstboot"

mkdir -p "${MOUNT_POINT}/var/lib"
touch "${MOUNT_POINT}/var/lib/uconsole-firstboot-pending"

cat << 'FBUNIT' > "${MOUNT_POINT}/etc/systemd/system/uconsole-firstboot.service"
[Unit]
Description=uConsole first-boot setup
# Must own tty1 before getty offers a login prompt, or the two fight over the
# terminal and the wizard's output is interleaved with "login:".
Before=getty@tty1.service
After=NetworkManager.service
Wants=NetworkManager.service
# The stamp file is the trigger. Once the wizard deletes it, this never runs
# again even if the unit is somehow still enabled.
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

chroot "${MOUNT_POINT}" systemctl enable uconsole-firstboot.service

# The wizard is the only way into this device. If it is not going to run, the
# card is a brick -- catch that here rather than after a 20-minute flash.
if [ ! -x "${MOUNT_POINT}/usr/local/sbin/uconsole-firstboot" ]; then
    echo "ERROR: first-boot wizard is not executable." >&2
    exit 1
fi
if [ ! -e "${MOUNT_POINT}/var/lib/uconsole-firstboot-pending" ]; then
    echo "ERROR: first-boot trigger file missing -- wizard would never run." >&2
    exit 1
fi
if [ ! -L "${MOUNT_POINT}/etc/systemd/system/multi-user.target.wants/uconsole-firstboot.service" ]; then
    echo "ERROR: first-boot service did not get enabled -- no way to log in." >&2
    exit 1
fi
echo "    wizard installed and enabled."
fi

# ------------------------------------------------------------- learning tools

cat << TOOLS > "${MOUNT_POINT}/tmp/tools.sh"
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
echo "==> Installing learning tools..."
apt-get install -y --no-install-recommends ${LEARNING_PACKAGES}
TOOLS

chmod +x "${MOUNT_POINT}/tmp/tools.sh"
chroot "${MOUNT_POINT}" /tmp/tools.sh
rm -f "${MOUNT_POINT}/tmp/tools.sh"

# --------------------------------------------------------------- ssh + hardware

echo "==> Setting console font (${CONSOLE_FONTFACE} ${CONSOLE_FONTSIZE})..."
cat << FONT > "${MOUNT_POINT}/tmp/font.sh"
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# console-setup ships the Terminus faces; make sure it is actually present.
apt-get install -y --no-install-recommends console-setup kbd

# Raspberry Pi OS ships XKBLAYOUT="gb". On a US keyboard that silently swaps
# @ with " and moves # and \\ -- so a password typed correctly is rejected, with
# no indication that the keyboard is the problem. Match the layout to the wifi
# country, which is the only locale signal this build collects.
KBLAYOUT="\$(echo '${WIFI_COUNTRY}' | tr '[:upper:]' '[:lower:]')"
if [ -f /etc/default/keyboard ]; then
    sed -i "s/^XKBLAYOUT=.*/XKBLAYOUT=\"\${KBLAYOUT}\"/" /etc/default/keyboard
    grep -q '^XKBLAYOUT=' /etc/default/keyboard || echo "XKBLAYOUT=\"\${KBLAYOUT}\"" >> /etc/default/keyboard
fi
echo "    keyboard layout set to \${KBLAYOUT}"

sed -i 's/^FONTFACE=.*/FONTFACE="${CONSOLE_FONTFACE}"/' /etc/default/console-setup
sed -i 's/^FONTSIZE=.*/FONTSIZE="${CONSOLE_FONTSIZE}"/' /etc/default/console-setup

# Add the keys if they were absent rather than silently doing nothing.
grep -q '^FONTFACE=' /etc/default/console-setup || echo 'FONTFACE="${CONSOLE_FONTFACE}"' >> /etc/default/console-setup
grep -q '^FONTSIZE=' /etc/default/console-setup || echo 'FONTSIZE="${CONSOLE_FONTSIZE}"' >> /etc/default/console-setup

systemctl enable console-setup 2>/dev/null || true
FONT

chmod +x "${MOUNT_POINT}/tmp/font.sh"
chroot "${MOUNT_POINT}" /tmp/font.sh
rm -f "${MOUNT_POINT}/tmp/font.sh"

# ------------------------------------------------------------------- networking
#
# Goal: on first boot the only thing left to do is pick an SSID and type the
# passphrase. Everything upstream of that choice is settled here.

echo "==> Setting up wifi (country ${WIFI_COUNTRY})..."
cat << NET > "${MOUNT_POINT}/tmp/net.sh"
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# nmtui is the whole point -- it is the "choose a network from a list" UI, and
# it lives in the network-manager package alongside nmcli.
apt-get install -y --no-install-recommends network-manager wireless-regdb rfkill iw

# The unit below calls these by absolute path; if they are not here, wifi comes
# up rfkill-blocked on the device and the failure is a long way from the cause.
command -v rfkill >/dev/null || { echo "ERROR: rfkill missing" >&2; exit 1; }
command -v iw >/dev/null || { echo "ERROR: iw missing" >&2; exit 1; }

# Unblock the radio and set the regulatory domain. raspi-config's non-interactive
# path is used where available because it knows every place the Pi stores this;
# the explicit writes below are the fallback for when it is not installed.
if command -v raspi-config >/dev/null 2>&1; then
    raspi-config nonint do_wifi_country ${WIFI_COUNTRY} || true
fi
echo 'REGDOMAIN=${WIFI_COUNTRY}' > /etc/default/crda
mkdir -p /etc/systemd/system
rfkill unblock wifi || true

# The rfkill soft-block is re-applied at boot, so undoing it once in the chroot
# is not enough -- it has to happen on the running system, before NetworkManager
# gives up on wlan0.
cat > /etc/systemd/system/uconsole-wifi-unblock.service << 'UNIT'
[Unit]
Description=Unblock wifi radio and set regulatory domain
Before=NetworkManager.service
Wants=network-pre.target
After=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
; Leading '-' so a failure here never blocks boot -- a device that reaches a
; login prompt with no wifi is recoverable; one that hangs before it is not.
ExecStart=-/usr/sbin/rfkill unblock wifi
ExecStart=-/usr/sbin/iw reg set ${WIFI_COUNTRY}

[Install]
WantedBy=multi-user.target
UNIT
systemctl enable uconsole-wifi-unblock.service

# NetworkManager must actually own wlan0, and must come up before the login
# prompt is useful.
systemctl enable NetworkManager

# A one-word command beats remembering "nmtui". This is the thing a kid runs.
cat > /usr/local/bin/wifi << 'WIFI'
#!/bin/bash
# Pick a wifi network. No arguments -- it shows you a list.
exec nmtui-connect "\$@"
WIFI
chmod 0755 /usr/local/bin/wifi

# Say so at the login prompt, so nobody has to be told twice.
cat > /etc/motd << 'MOTD'

  uConsole -- terminal only.

    wifi        pick a wifi network
    ip a        what address am I on
    ping -c3 1.1.1.1    is the network up
    man <cmd>   how does <cmd> work

MOTD
NET

chmod +x "${MOUNT_POINT}/tmp/net.sh"
chroot "${MOUNT_POINT}" /tmp/net.sh
rm -f "${MOUNT_POINT}/tmp/net.sh"

if [ -n "${WIFI_SSID}" ]; then
    echo "==> Baking in wifi network '${WIFI_SSID}'..."
    # Written from the host rather than through a chroot heredoc on purpose: a
    # passphrase containing $ ` or \ would be mangled by shell expansion on the
    # way in, and the failure would only show up as "cannot associate".
    NM_DIR="${MOUNT_POINT}/etc/NetworkManager/system-connections"
    mkdir -p "${NM_DIR}"
    NM_FILE="${NM_DIR}/${WIFI_SSID}.nmconnection"
    {
        printf '[connection]\n'
        printf 'id=%s\n' "${WIFI_SSID}"
        printf 'type=wifi\n'
        printf 'autoconnect=true\n'
        printf '\n[wifi]\n'
        printf 'mode=infrastructure\n'
        printf 'ssid=%s\n' "${WIFI_SSID}"
        printf '\n[wifi-security]\n'
        printf 'key-mgmt=wpa-psk\n'
        printf 'psk=%s\n' "${WIFI_PSK_HEX}"
        printf '\n[ipv4]\n'
        printf 'method=auto\n'
        printf '\n[ipv6]\n'
        printf 'method=auto\n'
    } > "${NM_FILE}"

    # NetworkManager refuses to load a profile that others can read, and it
    # refuses *silently* -- the connection simply never appears.
    chmod 0600 "${NM_FILE}"
    chown 0:0 "${NM_FILE}"

    if ! grep -q '^psk=' "${NM_FILE}"; then
        echo "ERROR: wifi profile written without a passphrase." >&2
        exit 1
    fi
fi
unset WIFI_PSK_HEX

echo "==> Enabling SSH (so you can fix things without pulling the card)..."
chroot "${MOUNT_POINT}" systemctl enable ssh 2>/dev/null || true
touch "${MOUNT_POINT}/${FW_REL}/ssh"

echo "==> Blacklisting conflicting 4G modem drivers..."
cat << 'EOF' > "${MOUNT_POINT}/etc/modprobe.d/blacklist-qmi.conf"
blacklist qmi_wwan
blacklist cdc_wdm
EOF

# ------------------------------------------------------------------ finalise

echo "==> Final tidy..."
chroot "${MOUNT_POINT}" apt-get clean
rm -f "${MOUNT_POINT}/root/.bash_history"

# Put back exactly what the distro shipped. If there was nothing, leave nothing
# and let NetworkManager create it on first boot -- writing our own symlink here
# is how DNS got broken once already.
rm -f "${MOUNT_POINT}/etc/resolv.conf"
if [ -e "${MOUNT_POINT}/etc/resolv.conf.build-orig" ] || [ -L "${MOUNT_POINT}/etc/resolv.conf.build-orig" ]; then
    mv "${MOUNT_POINT}/etc/resolv.conf.build-orig" "${MOUNT_POINT}/etc/resolv.conf"
fi

# Sanity check: a dangling resolv.conf means no name resolution on the device,
# which presents as "could not resolve <host>" and is easy to misread as a
# wifi problem. Fail loudly here rather than let it reach the card.
if [ -L "${MOUNT_POINT}/etc/resolv.conf" ] && [ ! -e "${MOUNT_POINT}/etc/resolv.conf" ]; then
    echo "ERROR: /etc/resolv.conf is a dangling symlink -- DNS would be broken." >&2
    exit 1
fi

# Last chance to catch the fatal case: firstboot mode with locked accounts and
# no wizard means nobody can ever log in. Better to fail here than on the device.
if [ "${FIRSTBOOT_SETUP}" = "1" ]; then
    if [ ! -x "${MOUNT_POINT}/usr/local/sbin/uconsole-firstboot" ] \
    || [ ! -e "${MOUNT_POINT}/var/lib/uconsole-firstboot-pending" ]; then
        echo "ERROR: accounts are locked but the first-boot wizard is missing." >&2
        echo "       This image would be impossible to log into. Not usable." >&2
        exit 1
    fi
fi

BUILD_COMPLETE=1

echo ""
echo "=========================================================="
echo " Terminal-only uConsole image built."
echo "=========================================================="
echo " Base:   Raspberry Pi OS Lite (Debian 13 trixie, arm64)"
echo " Image:  ${IMAGE_DIR}/${IMAGE_NAME}"
if [ "${FIRSTBOOT_SETUP}" = "1" ]; then
echo " Setup:  first boot runs a wizard on tty1 before the login prompt."
echo "         It asks for the root password, then ${KID_USER}'s, then wifi."
echo "         YOU should do this boot -- the root password is yours."
echo ""
echo "         This .img contains no passwords and no wifi key. It is not"
echo "         a secret; you can keep it or reflash it freely."
else
echo " Login:  ${KID_USER}  (login password)"
echo " Sudo:   asks for the root password you set"
echo ""
echo "         This .img CONTAINS password hashes. Delete it after"
echo "         flashing:  rm -P ${IMAGE_DIR}/${IMAGE_NAME}"
fi
echo " SSH:    enabled"
echo ""
if [ -n "${WIFI_SSID}" ]; then
echo " Wifi:   '${WIFI_SSID}' baked in -- should connect on its own"
echo "         type 'wifi' to switch to a different network"
else
echo " Wifi:   log in, type 'wifi', pick the network, type the passphrase"
fi
echo "         (regulatory country ${WIFI_COUNTRY})"
echo ""
echo " CHECKPOINT -- the only question that matters on this pass:"
echo "   does the screen come on and show a login prompt?"
echo " If the console is sideways, rebuild with a different rotation:"
echo "   CONSOLE_ROTATE=3 ./create-uconsole-terminal.sh   (0=normal 1=90cw 2=180 3=270cw)"
echo " Font too big/small:"
echo "   CONSOLE_FONTSIZE=14x28 ./create-uconsole-terminal.sh"
echo "=========================================================="
