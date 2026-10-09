#!/bin/bash
#
# Bring a uConsole that is ALREADY FLASHED with the Omarchy image up to date
# with fixes that newer builds include, without reflashing. Runs ON the
# uConsole, as root:
#
#   git clone https://github.com/LofiFren/ImageEditor
#   sudo ImageEditor/Scripts/upgrade-uconsole-device.sh
#
# Safe to run more than once. What it does, each step only if still needed:
#   - lets pacman download on the 5.10 kernel (DisableSandboxFilesystem);
#   - installs ClockworkPi's kernel as the pacman package
#     uconsole-kernel-cm4-rpi, so `omarchy update` stops asking to reboot for
#     a kernel update that never happened, and removes Arch's unused
#     linux-aarch64 kernel;
#   - makes the gamepad's Select button act as Super, Omarchy's main key.
# The kernel itself is the same one already running: no reboot needed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/uconsole-arch-kernel.sh"

if [ "$(id -u)" != "0" ]; then
    echo "Run it with sudo: sudo $0" >&2
    exit 1
fi
if [ "$(uname -r)" != "${UCONSOLE_CWPI_KVER}" ]; then
    echo "ERROR: this uConsole runs kernel $(uname -r), not ClockworkPi's ${UCONSOLE_CWPI_KVER}." >&2
    echo "       This script is for images built with KERNEL=clockworkpi (the default)." >&2
    exit 1
fi

echo "==> pacman downloads"
uconsole_cwpi_pacman_sandbox /
grep '^DisableSandboxFilesystem' /etc/pacman.conf

echo "==> Kernel package"
if pacman -Qqo "/usr/lib/modules/${UCONSOLE_CWPI_KVER}/vmlinuz" >/dev/null 2>&1; then
    echo "    already installed: $(pacman -Q uconsole-kernel-cm4-rpi)"
else
    pacman -Q fakeroot >/dev/null 2>&1 || pacman -S --needed --noconfirm fakeroot
    WORK="$(mktemp -d /tmp/cwpi-kernel.XXXXXX)"
    trap 'rm -rf "${WORK}"' EXIT
    uconsole_cwpi_fetch_deb "${WORK}"
    uconsole_cwpi_install_kernel_package / "${WORK}/deb"
fi

echo "==> Select as Super"
pacman -Q python-evdev >/dev/null 2>&1 || pacman -S --needed --noconfirm python-evdev
install -m 0755 "${SCRIPT_DIR}/omarchy-look/bin/uconsole-select-super" /usr/local/bin/uconsole-select-super
install -m 0644 "${SCRIPT_DIR}/omarchy-look/systemd/uconsole-select-super.service" \
    /etc/systemd/system/uconsole-select-super.service
systemctl daemon-reload
systemctl enable uconsole-select-super.service
systemctl restart uconsole-select-super.service
sleep 2
systemctl is-active --quiet uconsole-select-super.service \
    || { echo "ERROR: the Select-as-Super service did not start: journalctl -u uconsole-select-super" >&2; exit 1; }
grep -q 'Name="uConsole Select as Super"' /proc/bus/input/devices \
    || { echo "ERROR: the Select-as-Super key did not appear: journalctl -u uconsole-select-super" >&2; exit 1; }
echo "    Select is now Super."

pacman -Qqo "/usr/lib/modules/${UCONSOLE_CWPI_KVER}/vmlinuz" >/dev/null \
    || { echo "ERROR: pacman does not own the running kernel." >&2; exit 1; }
grep -q 'panel-cwu50' "/usr/lib/modules/${UCONSOLE_CWPI_KVER}/modules.dep" \
    || { echo "ERROR: the uConsole panel driver is not in the module index." >&2; exit 1; }
[ -f /boot/kernel8.img ] && [ -f /boot/overlays/devterm-panel-uc.dtbo ] \
    || { echo "ERROR: the kernel or panel overlay is missing from /boot." >&2; exit 1; }

echo ""
echo "Done. Nothing to reboot for: the running kernel is unchanged."
echo "Hold Select as Super: Select + Space opens the Omarchy menu."
