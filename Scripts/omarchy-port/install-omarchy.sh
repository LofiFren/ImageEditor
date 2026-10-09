#!/bin/bash
#
# Install real Omarchy onto an Arch Linux ARM uConsole system.
#
# Runs INSIDE the image's chroot (or on a uConsole) as root, with network.
# Builds the aarch64 repackages, installs them plus every Omarchy base package
# that exists for aarch64, then runs Omarchy's own system setup stages -- the
# ones its ISO installer would run -- minus the few that do not apply to a Pi.
#
# The per-user stage (omarchy-provision-user) is separate: it needs the user to
# exist first. See create-uconsole-omarchy.sh.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$(mktemp -d /tmp/omarchy-pkgs.XXXXXX)"

# pacman-key starts a gpg-agent that holds the image open; stop it however this
# script exits, or the build cannot unmount the image afterwards.
trap 'gpgconf --homedir /etc/pacman.d/gnupg --kill all 2>/dev/null || true' EXIT
X86_REPO=https://pkgs.omarchy.org/stable/x86_64

# Arch-independent packages Omarchy publishes only in its x86_64 repo. 'any'
# packages install on aarch64 unchanged. Each is pinned to the SHA-256 that
# Omarchy's own repo database lists for it, then installed as a local file.
# (Installing straight from the URL would need pacman to verify a signature
# against omarchy-keyring -- which is one of these packages.)
ANY_PACKAGES=(
    "f4bc258879f493462736f9a072c4f4c7f753eb559f6b346f5bdf8ed816f75f66 omarchy-keyring-20251027-1-any.pkg.tar.zst"
    "e6b935306e5e9fea5416964388abc4f7ca19e775c9ff3a187cf7ced4ae933fa6 ttf-jetbrains-mono-nerd-basic-3.5.1-1-any.pkg.tar.zst"
    "5d352780fb3d33f9762a36fcc14babe4ebe71bbb41d8103b1d4e023974e921c7 xdg-terminal-exec-0.14.3-1-any.pkg.tar.zst"
)
ANY_EXTRAS=(
    "ff7cca4d58198ef6ea0c16ff93bd0369b307a40fae4ed300f6a2a75bb444fe1f omarchy-nvim-2026.8.13-1-any.pkg.tar.zst"
    "96201613d8b3edc742b85e0be0168b5a8a4e8b8c46b8e236c6b8e3e5a37b4ed2 yaru-icon-theme-26.04.5.1ubuntu-1-any.pkg.tar.zst"
    "64ba9e4bc1f8ef2eb1fe20b79f3fe37421e4ff63656e5f6063c530ac83071bf7 ttf-ia-writer-20181225-1-any.pkg.tar.zst"
    "13553f5fc2176806585d466f05fd36d49631d552af9a720cd4bb6e9ca3dae933 ufw-docker-251123-1-any.pkg.tar.zst"
    "6359cbb97d7a6986975c90830d470f5d18998272019bafa0c7087f3b13a77558 tobi-try-1.8.1-3-any.pkg.tar.zst"
)

# Download "<sha256> <file>" entries into OUT, verify, print the local paths.
fetch_verified() {
    local entry sum file
    for entry in "$@"; do
        sum="${entry%% *}"; file="${entry#* }"
        curl -fsSL --retry 3 -o "${OUT}/${file}" "${X86_REPO}/${file}"
        echo "${sum}  ${OUT}/${file}" | sha256sum -c - >/dev/null || {
            echo "ERROR: checksum mismatch for ${file}" >&2; return 1; }
        echo "${OUT}/${file}"
    done
}

# Omarchy setup stages that must not run on a uConsole:
#   post-install/pacman.sh   replaces pacman.conf with Omarchy's mirrors, which
#                            have no aarch64 core/extra -- and drops the
#                            [uconsole-arch] kernel repo. pacman would break.
#   config/snapper.sh        btrfs snapshots; the image is ext4.
#   hardware/apple/fix-spi-keyboard.sh
#                            MacBook-only; reads PC firmware (DMI) data that
#                            does not exist on ARM and dies trying.
SKIP_STAGES="post-install/pacman.sh config/snapper.sh hardware/apple/fix-spi-keyboard.sh"

pacman_() { pacman --disable-sandbox "$@"; }

echo "==> Building the aarch64 Omarchy packages..."
pacman_ -S --needed --noconfirm fakeroot file binutils >/dev/null
bash "${SRC}/build-packages.sh" "${OUT}"

echo "==> Installing Omarchy..."
# Omarchy ships its own trimmed Nerd font; it conflicts with the full one.
pacman -Rdd --noconfirm ttf-jetbrains-mono-nerd >/dev/null 2>&1 || true
mapfile -t any_files < <(fetch_verified "${ANY_PACKAGES[@]}")
[ ${#any_files[@]} -eq ${#ANY_PACKAGES[@]} ] || { echo "ERROR: download failed" >&2; exit 1; }
pacman_ -U --noconfirm "${any_files[@]}" "${OUT}"/omarchy-settings-*.pkg.tar.* "${OUT}"/omarchy-4*.pkg.tar.*
pacman-key --populate omarchy >/dev/null

echo "==> Adding Omarchy's aarch64 package repo..."
if ! grep -q '^\[omarchy\]' /etc/pacman.conf; then
    printf '\n[omarchy]\nSigLevel = Required DatabaseOptional\nServer = https://pkgs.omarchy.org/stable/$arch\n' >> /etc/pacman.conf
fi
pacman_ -Sy --noconfirm >/dev/null

echo "==> Installing Omarchy's base packages that exist for aarch64..."
avail=(); missing=()
for p in $(grep -vE '^\s*(#|$)' /usr/share/omarchy/install/omarchy-base.packages); do
    [ "$p" = nvim ] && p=neovim       # same package, Arch Linux ARM's name
    if pacman -Si "$p" >/dev/null 2>&1 || pacman -Sg "$p" >/dev/null 2>&1; then
        avail+=("$p")
    else
        missing+=("$p")
    fi
done
echo "    ${#avail[@]} available, ${#missing[@]} not built for aarch64:"
printf '      %s\n' "${missing[@]}"
# --ask=4: accept replacing conflicting packages and take default providers.
pacman_ -S --needed --noconfirm --ask=4 "${avail[@]}"
mapfile -t extra_files < <(fetch_verified "${ANY_EXTRAS[@]}")
[ ${#extra_files[@]} -eq ${#ANY_EXTRAS[@]} ] || { echo "ERROR: download failed" >&2; exit 1; }
pacman_ -U --needed --noconfirm --ask=4 "${extra_files[@]}"

echo "==> Running Omarchy's system setup stages..."
export OMARCHY_PATH=/usr/share/omarchy
export OMARCHY_INSTALL=${OMARCHY_PATH}/install
export PATH="${OMARCHY_PATH}/bin:${PATH}"
failed=0
for group in config hardware login post-install; do
    for stage in $(grep -oE '\$OMARCHY_INSTALL/[^"]+' "${OMARCHY_INSTALL}/${group}/all.sh" \
                   | sed "s|\\\$OMARCHY_INSTALL/||"); do
        if [[ " ${SKIP_STAGES} " == *" ${stage} "* ]]; then
            echo "    skip  ${stage}"
            continue
        fi
        if bash -eE -c 'source "$1"' bash "${OMARCHY_INSTALL}/${stage}" >/tmp/omarchy-stage.log 2>&1; then
            echo "    ok    ${stage}"
        else
            echo "    FAIL  ${stage}"
            sed 's/^/          /' /tmp/omarchy-stage.log | tail -8
            failed=1
        fi
    done
done
rm -f /tmp/omarchy-stage.log
if [ ${failed} -ne 0 ]; then
    echo "ERROR: an Omarchy setup stage failed (see above)." >&2
    exit 1
fi

# Omarchy's firewall denies all incoming, SSH included. Every image in this
# repo ships with SSH on so a device can be fixed without pulling the card;
# keep that, and leave the rest of Omarchy's firewall as it is.
#
# Omarchy's firewall stage has already set ENABLED=yes, and with that set ufw
# tries to load the rule into the running kernel -- which a build chroot has
# no access to ("ERROR: problem running"). Write the rule with the firewall
# marked off, then turn it back on; it loads for real on first boot.
sed -i 's/^ENABLED=.*/ENABLED=no/' /etc/ufw/ufw.conf
ufw allow 22/tcp >/dev/null
sed -i 's/^ENABLED=.*/ENABLED=yes/' /etc/ufw/ufw.conf
grep -q -- '--dport 22 ' /etc/ufw/user.rules || { echo "ERROR: SSH firewall rule was not written" >&2; exit 1; }
grep -q '^ENABLED=yes' /etc/ufw/ufw.conf || { echo "ERROR: firewall left disabled" >&2; exit 1; }

rm -rf "${OUT}"
echo "==> Omarchy installed."
