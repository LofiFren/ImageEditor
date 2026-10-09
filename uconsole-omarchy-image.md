# uConsole CM4 — Omarchy Desktop Image

A third build path for the ClockworkPi uConsole CM4: Arch Linux ARM with
[Omarchy](https://omarchy.org), in two editions.

**This does not replace the other builds.** The Kali desktop
([kali-linux-image-editor.md](kali-linux-image-editor.md)) and the terminal-only
image ([uconsole-terminal-image.md](uconsole-terminal-image.md)) are unchanged
and independent of this one.

| Edition | Build with | What it is |
|---|---|---|
| **look** (default) | `./create-uconsole-omarchy.sh` | Hyprland styled after Omarchy 3.8.4, from Arch Linux ARM packages. Light and comfortable on a CM4. Not Omarchy's menus or tools. |
| **real** | `OMARCHY_EDITION=real ./create-uconsole-omarchy.sh` | Real Omarchy 4, ported to ARM. Quickshell desktop, Omarchy menu, SDDM login. **Boots and runs on a uConsole CM4** (with the default ClockworkPi kernel). Heavier than the look edition. |

---

## Omarchy on ARM

Omarchy is officially for Intel/AMD PCs, but it is partly on ARM already.
Omarchy publishes an `aarch64` package repo (mostly apps), and its settings
package has an Arch Linux ARM path written for Apple Silicon. What it does not
publish for ARM is `omarchy` itself, its settings, or its desktop shell.

Those packages turn out to contain no compiled code, just scripts, configs,
themes and images. The **real** edition repackages Omarchy's official builds
for aarch64, changing only what a Raspberry Pi can't use. See
[Scripts/omarchy-port/README.md](Scripts/omarchy-port/README.md) for every
change and why. The main ones:

- No Limine bootloader or btrfs snapshots. A Pi boots from firmware, and this
  image is ext4.
- Omarchy's PC initramfs settings are removed. Left in, they would make the
  uConsole fail to boot after its next kernel update.
- Omarchy's installer step that replaces `pacman.conf` is skipped. Its mirrors
  have no ARM base packages, and the replacement would drop the uConsole kernel
  repo.
- 124 of Omarchy's 147 base packages exist for ARM, plus 5 architecture-free
  ones. The rest are optional apps (LocalSend, Pinta, OBS, Obsidian, omacut,
  omawrite, omacalc, the tensaku screenshot editor), `yay`, and PC-only
  hardware tools.

## The look edition

The **look** edition rebuilds **Omarchy 3.8.4's look** from Arch Linux ARM
packages: the same Hyprland gaps, borders, blur and animation curves, the same
Waybar layout, Mako notifications, hyprlock, Alacritty, and the Tokyo Night
theme with an Omarchy wallpaper. Walker (Omarchy's launcher) is not packaged
for ARM, so fuzzel stands in for it. None of Omarchy's `omarchy-*` commands are
present, so the Omarchy menu, theme switcher and updater are not either. Update
with `sudo pacman -Syu`.

The look is taken from [basecamp/omarchy](https://github.com/basecamp/omarchy)
(MIT), pinned at v3.8.4.

---

## What you get (look edition)

| | |
|---|---|
| Base | Community uConsole Arch Linux ARM image, [wdkdot/uconsole-arch](https://github.com/wdkdot/uconsole-arch) `v2026.07.04` |
| Kernel | ClockworkPi `uconsole-kernel-cm4-rpi` 5.10.17 + Pi firmware (see [Base and kernel](#base-and-kernel)) |
| Desktop | Hyprland + Waybar + Mako + hyprlock/hypridle + fuzzel + Alacritty |
| Theme | Tokyo Night, Omarchy 3.8.4 gaps/borders/blur/animations |
| Apps | Chromium, Nautilus, imv, mpv, btop, fastfetch |
| Audio | PipeWire |
| Network | NetworkManager (systemd-networkd disabled so the two don't fight) |
| Accounts | one user (default `uconsole`) with sudo; root locked |
| SSH | enabled |

### Base and kernel

The Arch system comes from a community uConsole image,
[wdkdot/uconsole-arch](https://github.com/wdkdot/uconsole-arch) `v2026.07.04`.
The download is pinned to that release and **checked against a SHA-256 written
into the script**. The release file's name has no version in it, so a
re-upload would otherwise slip through unnoticed.

**What boots it is ClockworkPi's own kernel, not the community one.** On a real
CM4 the community image did not start:

- **It ships no Raspberry Pi GPU firmware** (`start4.elf`, `fixup4.dat`). A CM5
  keeps that firmware in its EEPROM; a CM4 has to load it from the card, so it
  never starts. The image seems to have been tested on a CM5 only.
- **With the firmware added, the screen stayed black** on its newer kernel.

So by default (`KERNEL=clockworkpi`) the build:

- installs the Pi firmware from Arch Linux ARM's `raspberrypi-bootloader` (plus
  `firmware-raspberrypi` for wifi/Bluetooth). Both keep updating with pacman.
- removes the community kernel package, so `pacman -Syu` can't write its kernel
  back over the working one.
- unpacks ClockworkPi's `uconsole-kernel-cm4-rpi` 0.13 package, the same
  package the Raspberry Pi OS builds in this repo install with `apt`. That gives
  the kernel (5.10.17), the CM4 device tree, the uConsole overlays
  (`devterm-panel-uc` and friends), ClockworkPi's `config.txt`, and the modules,
  which go into `/usr/lib/modules`. It's pinned to the SHA-256 in ClockworkPi's
  apt index.
- boots by `PARTUUID`. This kernel has no initramfs, and without one the kernel
  can't find the root filesystem by label.

The trade-off: **this kernel is old and doesn't update.** `pacman -Syu` updates
everything else. `KERNEL=community` keeps the newer, pacman-updated community
kernel (with the firmware added) for anyone who wants to try it again. The logic
lives in [Scripts/lib/uconsole-arch-kernel.sh](Scripts/lib/uconsole-arch-kernel.sh).
To convert an image that was already built, run
[Scripts/use-clockworkpi-kernel.sh](Scripts/use-clockworkpi-kernel.sh).

One more thing about the community project: its pacman repo is set to
`SigLevel = Optional TrustAll`, so its packages aren't signature-checked. With
the default kernel, nothing is installed from it after the build. The repo
entry is still in `pacman.conf`, though.

---

## Prerequisites

- Docker and Docker Compose
- ~25 GB free disk space
- An SD card big enough for the image: **16 GB or larger** for the look edition
  (about 11 GB), **32 GB or larger** for the real edition (about 17 GB). The
  root partition grows to fill the card on first boot.
- Internet access during the build. The base image (~650 MB) and the desktop
  packages are downloaded.

You don't need to download anything first. The script fetches the base image
into `images/` and reuses it on later runs.

---

## Build

### 1. Clear any previous output

```bash
rm -f images/uconsole-omarchy-cm4.img
```

The script refuses to run over an existing output image rather than build a
second time on top of the first.

### 2. Start the container

The Dockerfile now includes `zstd`, which the base image needs, so rebuild once:

```bash
docker compose build
docker compose up -d
```

### 3. Run the build

```bash
docker compose exec image-editor \
  bash -c "chmod +x /workdir/Scripts/create-uconsole-omarchy.sh && \
           /workdir/Scripts/create-uconsole-omarchy.sh"
```

For **real Omarchy**, add `-e OMARCHY_EDITION=real`:

```bash
docker compose exec -e OMARCHY_EDITION=real image-editor \
  /workdir/Scripts/create-uconsole-omarchy.sh
```

The output is `images/uconsole-omarchy-real-cm4.img` instead of
`uconsole-omarchy-cm4.img`, so the two editions can sit side by side.

It asks two things:

- **Wifi country code** (Enter accepts `US`). This sets the radio's regulatory
  domain on the kernel command line.
- **Timezone**, e.g. `America/New_York` (Enter accepts `UTC`).

No passwords are asked for. The image ships with locked accounts and sets the
password on first boot, the same as the terminal build.

Installing the desktop is the slow part, especially on an Intel Mac where the
ARM chroot runs under emulation. Arch Linux ARM's mirrors are also slow at
times, and the script retries pacman three times. The run is finished when you
see the `Omarchy uConsole image built` banner. If it says
`BUILD DID NOT COMPLETE`, delete the image and run it again.

### 4. Flash

Same as the terminal build (see its
[flashing section](uconsole-terminal-image.md#4-flash-macos--see-platforms-for-linuxwindows)),
with the file name changed:

```bash
diskutil list
diskutil unmountDisk /dev/diskN
sudo dd if=images/uconsole-omarchy-cm4.img of=/dev/rdiskN bs=4m status=progress
sync
diskutil eject /dev/diskN
```

Raspberry Pi Imager's *Use custom* option works too. Turn **off** its
"customise OS settings" prompt.

### 5. First boot

1. The root partition grows to fill the card, and a fresh pacman keyring is
   generated for this device. Nothing to do.
2. A wizard on the console asks for the **password** for `uconsole`. This is the
   login password, the screen-lock password and the sudo password.
3. It offers to **connect to wifi** with a network picker.
4. **Look edition:** at the console login prompt, log in as `uconsole` and
   Hyprland starts.
   **Real edition:** Omarchy's login screen (SDDM) appears. Log in as
   `uconsole`, and the Omarchy desktop starts. `Super + Space` opens the
   Omarchy menu, and `Super + K` lists every key binding.

---

## Using it

| Keys | Does |
|---|---|
| `SUPER + Enter` | terminal |
| `SUPER + Space` | app launcher |
| `SUPER + W` | close window |
| `SUPER + F` | fullscreen |
| `SUPER + T` | toggle floating |
| `SUPER + 1..5` | switch workspace |
| `SUPER + SHIFT + 1..5` | move window to workspace |
| `SUPER + arrows` | move focus |
| `SUPER + SHIFT + B` | Chromium |
| `SUPER + Escape` | lock |
| `SUPER + SHIFT + Escape` | log out of Hyprland |
| `Print` | screenshot a region to the clipboard |

The **top-left bar icons** open the launcher and a terminal with a trackball
click, so a key that doesn't do what you expect never leaves you stuck. The
wifi icon opens the network picker.

Configs live in `~/.config/{hypr,waybar,mako,alacritty,fuzzel}` and are plain
files you can edit.

### If the screen stays black from power-on

That means the problem is before Linux, or in the kernel's panel driver, not
in the desktop.

1. Rebuild with `VERBOSE_BOOT=1` (or, on an existing card, edit `cmdline.txt` on
   the boot partition: replace `console=tty3 quiet loglevel=3` with
   `console=tty1 loglevel=7`). If text scrolls, the kernel works, and the last
   lines show where it stops.
2. Put the card in a computer. If the second partition is still the image's
   size, not the whole card, first boot never got as far as growing it.
3. Check that `start4.elf` and `fixup4.dat` are on the boot partition. Without
   them a CM4 does nothing at all.
4. A CM4 **with eMMC** boots from its eMMC and ignores the SD card. The
   uConsole's card slot needs a CM4 Lite.

### If the desktop won't start

Only tty1 starts Hyprland. Press **Ctrl+Alt+F2**, log in there, and you get a
plain shell to fix things from. `~/.config/hypr/hyprland.conf` and
`journalctl --user -b` are the places to start.

---

## Options

Set as environment variables in front of the script:

| Variable | Default | What it does |
|---|---|---|
| `HYPR_TRANSFORM` | `3` | Desktop rotation. 0=normal 1=90 2=180 3=270 (counter-clockwise) |
| `CONSOLE_ROTATE` | `1` | Text console rotation. 0=normal 1=90cw 2=180 3=270cw |
| `OMARCHY_EDITION` | `look` | `look` or `real` (see the top of this page) |
| `KERNEL` | `clockworkpi` | `clockworkpi` or `community` (see [Base and kernel](#base-and-kernel)) |
| `VERBOSE_BOOT` | `0` | `1` shows kernel messages on the screen while booting, for a black screen |
| `PACMAN_CACHE` | `images/pacman-cache` | Keeps downloaded packages between builds. `""` disables it |
| `HYPR_MOD` | `SUPER` | Look edition only: Hyprland's main modifier, e.g. `ALT` |
| `DESKTOP_USER` | `uconsole` | Username |
| `DESKTOP_HOST` | `uconsole` | Hostname |
| `EXTRA_PACKAGES` | `chromium` | Look edition only: extra packages. `""` drops Chromium and saves ~1 GB |
| `IMAGE_GROW` | `6G` / `12G` | Space added to the base image for the install (look / real) |
| `WIFI_COUNTRY`, `TIMEZONE` | `US`, `UTC` | Defaults for the two prompts |

The two rotations use **different numbering**. The console's `1` and
Hyprland's `3` both mean "the Kali image's `xrandr --rotate right`". If the
login prompt is right but the desktop is upside down, change only
`HYPR_TRANSFORM`, or edit the rotation on the device. You don't need to
rebuild for that. In the look edition, it's the `monitor =` line in
`~/.config/hypr/hyprland.conf`. In the real edition, it's the `DSI-1` line in
`~/.config/hypr/monitors.lua`, plus `/etc/sddm/uconsole-greeter.lua` for the
login screen.

---

## Implementation notes

Things that look odd in the script but are there on purpose:

- **`uconsole-hyprland` launcher.** A CM4 has two GPU devices: `v3d` (rendering
  only, no outputs) and `vc4` (the display controller the panel is attached to).
  Their `cardN` numbers aren't stable. If Hyprland picks `v3d`, it finds no
  screen. `/etc/profile.d/uconsole-drm.sh` finds whichever card is `vc4` and
  sets `AQ_DRM_DEVICES` to it. Every login sources that file, including SDDM's
  sessions. The launcher sources it too, for the SDDM login screen, which does
  not read profile.d.
- **The gpg-agent is shut down after pacman runs.** `pacman-key` leaves one
  running inside the chroot, holding the image open. The unmount then fails,
  and a second build would mount the same filesystem twice, which corrupts it.
  The script also refuses to start if the image is already mounted, and warns
  loudly if an unmount fails.
- **`pacman --disable-sandbox`.** pacman's download sandbox doesn't work under
  qemu emulation and fails every download.
- **`-Syu`, never `-Sy` then `-S`.** A partial upgrade is the classic way to break
  an Arch system. This also brings the kernel up to date from the uConsole repo.
- **The keyring, SSH host keys and machine-id are deleted at the end.** An image
  is flashed onto many cards, and none of them should share a private key.
  They're regenerated on first boot.
- **The default `alarm`/`alarm` and `root`/`root` accounts are removed and
  locked.** The base image keeps them and has SSH enabled. On a device that
  joins wifi, that is an open door.
- **Blur is one pass, not Omarchy's two** (look edition). It's the most
  expensive effect on a CM4's GPU. If the desktop feels slow, turn blur off
  first (`decoration:blur:enabled = false`).

Real edition only:

- **SSH is allowed through Omarchy's firewall.** Omarchy blocks all incoming
  connections. Every image in this repo keeps SSH reachable so a device can be
  fixed without pulling the card. Everything else stays blocked.
- **Scale 1, not Omarchy's auto/2×.** On a 1280×720 five-inch panel, 2× leaves
  very little room.
- **The Omarchy session is pre-selected in SDDM.** Otherwise SDDM offers plain
  Hyprland first, which runs without Omarchy's session environment.
- **The first-boot wizard runs before SDDM,** so the login screen never
  appears before there is a password to check.

### Not yet confirmed on hardware

**Confirmed on a uConsole CM4:** the real edition boots with the default
ClockworkPi kernel. The first-boot wizard, the Omarchy login screen and the
desktop all come up the right way round with the default rotation settings, and
the desktop is usable. The community kernel on its own gave a black screen (see
[Base and kernel](#base-and-kernel)).

Not yet confirmed:

- whether the uConsole keyboard's layout makes `SUPER` comfortable
- the look edition on hardware, which shares the same boot chain
