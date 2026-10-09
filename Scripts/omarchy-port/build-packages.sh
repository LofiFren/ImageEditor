#!/bin/bash
#
# Build the aarch64 repackages of 'omarchy' and 'omarchy-settings'.
#
# Runs INSIDE an Arch Linux ARM system (the uConsole image's chroot, or a real
# uConsole) as root. makepkg refuses to run as root, so the build itself runs
# as a throwaway unprivileged user.
#
# Usage: build-packages.sh <output-dir>

set -euo pipefail

OUT="${1:?usage: build-packages.sh <output-dir>}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d /tmp/omarchy-port.XXXXXX)"
BUILDER=omarchy-port-builder

cleanup() {
    rm -rf "${WORK}"
    userdel "${BUILDER}" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "${OUT}"
cp -r "${SRC}/omarchy" "${SRC}/omarchy-settings" "${WORK}/"

# Patch omarchy-settings' install script (see the PKGBUILD for why). Fetch the
# upstream package once here, checksum-verified against the PKGBUILD, so the
# patched script is derived from exactly the file makepkg will package.
(
    cd "${WORK}/omarchy-settings"
    # shellcheck disable=SC1091
    source ./PKGBUILD
    pkg="${pkgname}-${pkgver}-${_uprel}-x86_64.pkg.tar.zst"
    curl -fsSL -o "${pkg}" "${source[0]}"
    echo "${sha256sums[0]}  ${pkg}" | sha256sum -c - >/dev/null
    bsdtar -xf "${pkg}" .INSTALL
    sed 's/^  \[\[ \$(uname -m) == aarch64 \]\] && grep -aq .apple,. \/proc\/device-tree\/compatible 2>\/dev\/null$/  [[ $(uname -m) == aarch64 ]]/' \
        .INSTALL > omarchy-settings.install
    rm -f .INSTALL
    if ! grep -qx '  \[\[ \$(uname -m) == aarch64 \]\]' omarchy-settings.install; then
        echo "ERROR: upstream's Apple Silicon check changed shape; the install script was not patched." >&2
        exit 1
    fi
)

useradd -r -M -d "${WORK}" "${BUILDER}" 2>/dev/null || true
chown -R "${BUILDER}:" "${WORK}"

for pkg in omarchy-settings omarchy; do
    echo "==> Building ${pkg} for aarch64..."
    # -d: dependencies are checked at install time, not here. Several (sddm,
    # quickshell...) need not be on the build machine to repackage files.
    runuser -u "${BUILDER}" -- bash -c "cd '${WORK}/${pkg}' && PKGDEST='${WORK}' makepkg -d --noconfirm --cleanbuild"
done

cp "${WORK}"/*.pkg.tar.* "${OUT}/"
echo "==> Packages written to ${OUT}:"
ls -1 "${OUT}"/*.pkg.tar.*
