# Omarchy on the uConsole (aarch64 port)

Runs **real Omarchy**, not the Omarchy-look desktop, on the ClockworkPi
uConsole CM4. The resulting image boots and runs on hardware.

## Why a port is possible

- Omarchy publishes an `aarch64` package repo (`pkgs.omarchy.org/stable/aarch64`)
  with 54 packages: apps such as Ghostty, Chromium and Hyprland. It does **not**
  yet carry `omarchy` itself, `omarchy-settings`, the Quickshell desktop or
  Walker.
- The x86_64 `omarchy` and `omarchy-settings` packages contain **no compiled
  code**. They are shell scripts, Hyprland Lua, Quickshell QML, themes and
  images, so their files run unchanged on ARM.
- `omarchy-settings` already has an Arch Linux ARM code path, written for Apple
  Silicon. That is the same base the uConsole runs.

## What the repackage changes

`omarchy/PKGBUILD` and `omarchy-settings/PKGBUILD` take the official x86_64
packages (checksum-pinned) and change only what a Pi needs:

| Change | Why |
|---|---|
| `arch=(aarch64)` | so pacman will install it |
| drop `limine`, `limine-mkinitcpio-hook`, `limine-snapper-sync`, `snapper` deps | a Pi boots from firmware via `config.txt`, not Limine; the image is ext4, so there is nothing to snapshot |
| remove `/etc/mkinitcpio.conf.d/omarchy_hooks.conf` | replaces the initramfs hooks with a PC set that includes `btrfs-overlayfs`. That hook is not installed here, so **the next kernel update would produce an unbootable uConsole** |
| remove `/etc/mkinitcpio.conf.d/thunderbolt_module.conf` | no Thunderbolt on a CM4 |
| remove `/etc/limine-entry-tool.d/` | Limine config |
| widen the Apple Silicon check in the install script to all aarch64 | keeps Arch Linux ARM's system identity (os-release, PAM, NSS), which is upstream's own choice for an ARM base |

Each PKGBUILD fails the build if upstream ever starts shipping a compiled
(ELF) binary. That would be x86_64 and would silently break on the device.

## Install-time differences from Omarchy's ISO

Omarchy normally runs its system setup from its own ISO installer. On the
uConsole image these stages run from the build instead, with two exceptions:

- **`post-install/pacman.sh` is skipped.** It overwrites `/etc/pacman.conf`
  with Omarchy's mirrors. Those have no aarch64 core/extra repos, and the
  overwrite would also drop the `[uconsole-arch]` kernel repo. pacman would
  break, and kernel updates would stop.
- **`config/snapper.sh` is skipped.** No btrfs.

## Building

Inside an Arch Linux ARM system (the uConsole image's chroot, or a uConsole):

```bash
sudo ./build-packages.sh /path/to/output
```

## Use

Most people don't run these directly. Build the whole image instead:

```bash
docker compose exec -e OMARCHY_EDITION=real image-editor /workdir/Scripts/create-uconsole-omarchy.sh
```

## Status

All of Omarchy's install stages pass in the build chroot except the ones listed
above as skipped. The resulting image boots and runs on a uConsole CM4 with the
default ClockworkPi kernel. See
[uconsole-omarchy-image.md](../../uconsole-omarchy-image.md).
