# uConsole CM4 — Terminal-Only Linux Image

A second, separate build path for the ClockworkPi uConsole CM4. Where the Kali
build produces a full desktop, this one produces a machine that boots to a text
login prompt and stops there.

It exists for a specific reason: it is a machine for learning Linux, for someone
who should not be turned loose on the web. There is no browser and no desktop —
not as a lock, but because there is nothing else on it to do. The network works
fine; anyone who wants to get online from a shell can. The containment is
practical, not technical.

**This does not replace the Kali build.** The two are independent. See
[kali-linux-image-editor.md](kali-linux-image-editor.md) for that one.

---

## What you get

| | |
|---|---|
| Base | Raspberry Pi OS Lite (Debian 13 trixie), arm64 |
| Boots to | text login on tty1 — `multi-user.target`, no display manager |
| Display | ClockworkPi DSI panel driver + patched kernel, console rotated |
| Font | Terminus Bold 16x32 (the stock console font is punishing on a 5" panel) |
| Network | NetworkManager, radio unblocked, `wifi` command to pick a network |
| Keyboard | layout matched to the wifi country (avoids UK-default symbol swaps) |
| Accounts | one user (default `pilot`) + separate root/sudo password |
| SSH | enabled |
| Tools | `vim nano man-db manpages less tree htop tmux git python3 build-essential` |

The user gets `sudo`, but `sudo` asks for the **root** password, not their own
(`Defaults rootpw`). So they can be told to run something with `sudo` and simply
cannot, unless you are standing there. That was the point.

---

## Prerequisites

- Docker and Docker Compose
- ~20 GB free disk space
- Raspberry Pi OS Lite arm64 in `images/` —
  <https://www.raspberrypi.com/software/operating-systems/>
- An **8 GB or larger** SD card, and a way to write to it. The build grows the
  image to make room for the added packages, so the finished `.img` is roughly
  6 GB rather than the stock 3 GB (see [Disk space](#disk-space)).

---

## A note on platforms

**These instructions were written and tested on macOS.** Everything up to
flashing happens inside the Docker container and should behave identically
anywhere Docker runs — that part is not macOS-specific. It is **step 4,
flashing**, that differs, because `diskutil` and `/dev/rdiskN` are macOS names
for things every OS spells differently.

Below are the Linux and Windows equivalents. They are written from knowledge of
those platforms, **not from a run on this project** — nobody has built this on
Windows or Linux yet, so treat them as a starting point rather than a tested
recipe. If you get it working, a correction to this file is welcome.

| | macOS | Linux | Windows |
|---|---|---|---|
| Build (steps 1–3) | tested | should work as-is | should work via WSL2 |
| Flashing (step 4) | tested | see below | see below |

**Simplest cross-platform answer:** use
[Raspberry Pi Imager](https://www.raspberrypi.com/software/) on any of the
three. Choose *Use custom* and point it at the built `.img`. It verifies the
write, refuses to target a system disk, and sidesteps the whole
`dd`-to-the-wrong-device problem described below. Turn **off** its "customise
OS settings" prompt — that would inject its own user and wifi config on top of
what this build already sets up.

### Linux

Docker runs natively rather than in a VM, which if anything makes the loop-device
work more reliable than on macOS. Build steps are unchanged.

To flash:

```bash
lsblk                      # find your card; confirm size and that it is removable
sudo umount /dev/sdX*      # unmount any auto-mounted partitions
sudo dd if=images/2026-06-18-raspios-trixie-arm64-lite.img \
        of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Write to the **whole disk** (`/dev/sdX`), not a partition (`/dev/sdX1`). Note
`bs=4M` — uppercase on Linux, lowercase `4m` on macOS. There is no `rdisk`
equivalent; `/dev/sdX` is already the raw device.

### Windows

Run the build under **WSL2** with Docker Desktop's WSL integration enabled, and
keep the repo inside the WSL filesystem (`~/ImageEditor`), *not* under
`/mnt/c/`. Building on the Windows-mounted path is dramatically slower and the
permission mapping tends to confuse the mount/chroot steps.

WSL2 cannot write to a physical SD card directly, so flash from Windows itself
with Raspberry Pi Imager or [balenaEtcher](https://etcher.balena.io/). The image
will be at a path like
`\\wsl$\Ubuntu\home\<you>\ImageEditor\images\...img` from Windows Explorer.

One trap worth knowing: if you edit any script on Windows, make sure your editor
keeps **LF line endings**. A shell script saved with CRLF fails inside the
container with `bad interpreter: No such file or directory` — an error that
names the interpreter and says nothing about the actual cause.

---

## Build

### 1. Clear any previously extracted image

```bash
rm -f images/2026-06-18-raspios-trixie-arm64-lite.img
```

**Do not skip this.** The script only extracts the `.xz` when the `.img` is
absent, so a leftover `.img` from an earlier run gets modified *again* — the
vendor kernel installed on top of itself, config promoted twice. The symptoms
are confusing and the fix is one `rm`.

### 2. Start the container

```bash
docker compose build
docker compose up -d
```

### 3. Run the build

```bash
docker compose exec image-editor \
  bash -c "chmod +x /workdir/Scripts/create-uconsole-terminal.sh && \
           /workdir/Scripts/create-uconsole-terminal.sh"
```

It asks for one thing: the **wifi country code** (Enter accepts `US`). This does
double duty — it is not a formality:

- A Raspberry Pi's radio ships `rfkill`-blocked and stays that way until a
  country is set. Get it wrong and the symptom is "no wifi hardware at all,"
  which sends you debugging entirely the wrong thing.
- It also sets the **keyboard layout** (`us` for `US`, `gb` for `GB`, and so
  on). Raspberry Pi OS defaults to UK layout, which on a US keyboard silently
  swaps `@` and `"` and moves `#` and `\` — so a password typed correctly is
  rejected with no hint that the keyboard is the cause. Matching the layout to
  the country closes that trap.

No passwords are asked for. They are set on the device, on first boot — see
[Where the secrets live](#where-the-secrets-live).

The build takes several minutes. Watch for two lines near the end —
`wizard installed and enabled` and the `Terminal-only uConsole image built`
banner. If you do not see both, the run failed partway: it will say
`BUILD DID NOT COMPLETE` and tell you not to flash the image. Delete it and
run again.

### 4. Flash (macOS — see [platforms](#a-note-on-platforms) for Linux/Windows)

```bash
diskutil list          # find your card — read this yourself, do not assume
diskutil unmountDisk /dev/diskN
sudo dd if=images/2026-06-18-raspios-trixie-arm64-lite.img \
        of=/dev/rdiskN bs=4m status=progress
sync
diskutil eject /dev/diskN
```

Two things worth being careful about. The identifier changes between
insertions — confirm it every single time, because `dd` to the wrong disk is
unrecoverable and gives no warning. And use `rdiskN`, the raw device, not
`diskN`; it is roughly ten times faster.

### 5. First boot — do this one yourself

A setup wizard runs on tty1 before the login prompt appears and asks, in order:

1. **Root password** — yours. This is what `sudo` will ask for.
2. **Login password** for `pilot` — theirs.
3. **Wifi** — opens a network picker.

Because the root password comes first, **you** should do this boot, not your
kid. Nothing enforces that; it is a human sequencing problem.

The wizard runs once, then removes its own trigger.

---

## Default credentials

There are none, and that is deliberate.

In the default mode the accounts ship **locked** — the password field is `!`,
which no password matches. The first-boot wizard is what sets them. The stock
`pi` account is deleted during the build.

The only thing decided in advance is the **username**: `pilot` (override with
`KID_USER`). The hostname is `uconsole`.

If a card was built with `FIRSTBOOT_SETUP=0`, its passwords are whatever was
typed at build time. They are stored as one-way hashes and cannot be recovered
— if they are lost, reflash.

---

## Where the secrets live

The default (`FIRSTBOOT_SETUP=1`) puts **nothing secret in the image**. No
password hashes, no wifi key. The `.img` is an ordinary file — keep it, reflash
it, share it.

This matters more than it first appears. `/etc/shadow` hashes are
offline-crackable, so the alternative would leave you with a file you must
remember to delete after every single build. Now there is nothing to remember.

The other mode bakes credentials in at build time:

```bash
FIRSTBOOT_SETUP=0 ./create-uconsole-terminal.sh
```

Use it for flashing several cards unattended. It prompts for both passwords and
optionally a wifi SSID and passphrase, and it will tell you plainly that the
resulting `.img` is now a secret.

**On the wifi passphrase**, in that mode: it is converted to the derived WPA2
pre-shared key (PBKDF2-HMAC-SHA1, 4096 iterations, SSID as salt) before being
written, so the passphrase as a *string* never reaches the card. Be clear about
what that buys — it protects a phrase you have probably reused elsewhere. It
does **not** make the card safe to lose: the PSK is all anyone needs to join
your network, and no amount of hashing changes that.

And note that not baking it in does not help either. If the passphrase is typed
into `nmtui` on the device, NetworkManager writes it to that same card. If a
lost card genuinely worries you, the effective control is not cryptographic —
put the uConsole on a **guest network**.

---

## Options

All are environment variables; all have working defaults.

| Variable | Default | |
|---|---|---|
| `FIRSTBOOT_SETUP` | `1` | `0` bakes credentials in at build time |
| `CONSOLE_ROTATE` | `1` | `0`=normal `1`=90°cw `2`=180° `3`=270°cw |
| `CONSOLE_FONTSIZE` | `16x32` | step down: `14x28`, `12x24`, `10x20` |
| `CONSOLE_FONTFACE` | `TerminusBold` | |
| `WIFI_COUNTRY` | `US` | two-letter ISO code; also sets keyboard layout |
| `IMAGE_GROW` | `3G` | extra space added to the rootfs before installing (see [Disk space](#disk-space)) |
| `KID_USER` | `pilot` | |
| `KID_HOST` | `uconsole` | |

```bash
CONSOLE_ROTATE=3 CONSOLE_FONTSIZE=14x28 ./create-uconsole-terminal.sh
```

---

## Disk space

Raspberry Pi OS Lite ships a root partition sized for its own package set with
very little slack — around 2.4 GB, nearly full. Adding the vendor kernel plus
`vim`, `git`, `build-essential`, and the rest overruns it. apt's way of saying
so is `You don't have enough free space in /var/cache/apt/archives/`, thrown
partway through and leaving a half-built image. An earlier warning sign is
`mandb: can't write ... No space left on device` during package setup.

To avoid that, the build **grows the image before installing anything**:
`truncate` adds `IMAGE_GROW` (default 3 GB) to the file, `parted` extends the
root partition over it, and `resize2fs` grows the filesystem — all before the
first package is touched. It then verifies the free space is really there and
stops with a clear message if it is not, rather than letting the shortfall
surface as a confusing apt error hundreds of lines later.

Two consequences:

- The finished `.img` is about **6 GB**, not the stock 3 GB. Flashing takes
  proportionally longer and the card must be **8 GB or larger**.
- The device still expands the rootfs to fill the whole SD card on first boot,
  as normal — this grow is only about having room *during the build*.

If you add many more packages and hit the space check, raise the headroom:

```bash
IMAGE_GROW=5G ./create-uconsole-terminal.sh
```

---

## On the device

```
wifi                 pick a wifi network
ip a                 what address am I on
ping -c3 1.1.1.1     is the network up
```

`wifi` is a one-word wrapper around `nmtui-connect`, because a nine-year-old
should not have to remember `nmtui`. The same hints are in `/etc/motd`.

---

## How it works

### The display driver is not source code

It is a prebuilt Debian package, `uconsole-kernel-cm4-rpi`, from ClockworkPi's
APT repo. It carries the patched kernel, the DSI panel driver, and the
device-tree overlays. The key line it contributes is
`dtoverlay=devterm-panel-uc` in `config.txt`.

This single fact constrains everything else: the distro has to be one that
package will install onto, which means the Debian family.

### Shared driver logic

Both builds' driver steps live in
[`Scripts/lib/uconsole-drivers.sh`](Scripts/lib/uconsole-drivers.sh) — one place
to fix when ClockworkPi changes something. Three functions: install the kernel,
reconcile boot artifacts onto the FAT partition, set console rotation.

The install deliberately does **not** swallow errors with `|| true`. A failed
kernel install means a black screen, and a build that stops loudly beats an SD
card that looks fine and isn't.

### Rotation happens in the kernel

The Kali image rotates the display with `xrandr` from a LightDM greeter hook.
That cannot work here — there is no X server. Rotation is pushed down to
`fbcon=rotate:N` on the kernel command line so the text console itself comes up
the right way round.

### The distro kernel is pinned out

Raspberry Pi OS's own `linux-image-rpi-*` and `raspi-firmware` packages are
pinned to priority `-1`. Without this, a routine `apt upgrade` rewrites
`kernel8.img` and `config.txt` and silently kills the display — a failure that
would arrive weeks later, with no obvious connection to its cause.

---

## Why not Ubuntu Server

It was tried first and abandoned on evidence, not preference. Ubuntu 26.04 for
Raspberry Pi boots via an A/B "tryboot" layout: kernel at
`/boot/firmware/current/vmlinuz`, `os_prefix=current/`, its own `autoboot.txt`.

The ClockworkPi package writes `/boot/kernel8.img`, `/boot/*.dtb`,
`/boot/overlays/` and its own `config.txt`. Against Ubuntu that is five separate
mismatches — wrong partition, wrong filename, wrong nesting, no initramfs
handling, and a `config.txt` that would clobber the A/B setup.

Raspberry Pi OS has exactly **one** mismatch: it mounts the FAT partition at
`/boot/firmware` rather than `/boot`, which `uconsole_reconcile_boot` handles in
a few lines. That is the whole reason for the choice.

---

## Troubleshooting

**Black screen.** The driver install failed. Rebuild and read the output — it is
built to fail loudly rather than continue.

**Console sideways or upside down.** Rebuild with a different `CONSOLE_ROTATE`
(`0`–`3`). Note that the default `1` is derived from the Kali image's
`--rotate right`, not from measurement.

**Wizard fights with a `login:` prompt.** The unit is ordered
`Before=getty@tty1.service`; if they interleave, that ordering is the thing to
change.

**Locked out.** The wizard is the only way in. Rebuild with
`FIRSTBOOT_SETUP=0`, which sets passwords at build time instead.

**`wifi: command not found`.** `nmtui-connect` may be named differently.
Fall back to `sudo nmcli device wifi list` then
`sudo nmcli device wifi connect "SSID"`.

**No wifi hardware.** Almost always the regulatory country. Check with
`rfkill list`; if wlan is soft-blocked, rebuild with the right `WIFI_COUNTRY`.

**Correct password rejected at login.** Most likely the keyboard layout. Recent
builds set it from `WIFI_COUNTRY`, but a card built before that fix ships UK
layout, which swaps `@`/`"` and moves `#`/`\`. To see what the keyboard is
actually producing, type your password into the *username* field at the
`login:` prompt — it echoes in plaintext, fails harmlessly, and returns a fresh
prompt. Fix by rebuilding, or on the device with `sudo raspi-config` →
Localisation → Keyboard.

**Build stops with `You don't have enough free space` or the space check
aborts.** The rootfs ran out of room. Rebuild with more headroom,
`IMAGE_GROW=5G` — see [Disk space](#disk-space).

**`BUILD DID NOT COMPLETE` at the end.** The build failed partway and the image
may have locked accounts with no way to log in. Do not flash it. Delete it
(`rm -f images/…img`) and run again — the message above the banner names the
actual failure.

**Boot text spills over the login prompt.** Fixed by `console=tty3 quiet
loglevel=3` on the kernel command line — boot messages go to VT3, leaving tty1
to getty alone. They are not lost: press **Alt+F3** to read them, Alt+F1 to come
back. If you are debugging a boot problem and want them on screen again, remove
`quiet` and `console=tty3` from `cmdline.txt` on the FAT partition (readable
from any machine, no Linux required).

**DNS fails but ping by IP works.** Check `/etc/resolv.conf` is a real file and
not a dangling symlink:
`sudo rm -f /etc/resolv.conf && sudo systemctl restart NetworkManager`.

---

## Status

Known good: an earlier card boots, the panel comes on, and it reaches a login
prompt. The current script — with the first-boot wizard, the image-grow step,
and the keyboard-layout fix — has driven the build through package installation,
but a clean end-to-end run and a boot from the resulting card have not yet been
witnessed at the time of writing.

Not yet confirmed on hardware:

- a full build completing to the `Terminal-only uConsole image built` banner
  without a disk-space or ordering failure
- the first-boot wizard actually running on tty1, and its ordering against getty
- the rotation value — reasoned from the Kali config, not measured
- the console font — the card that booted was written before a chroot DNS bug
  was fixed, so `console-setup` never installed on it
- whether `nmtui-connect` exists under that name in trixie
- the Linux and Windows instructions — written from general knowledge of those
  platforms, never run against this project

Do not treat any of these as verified until you have watched them work.

---

## Never publish a built image

Even in the default mode the image is not a distribution artifact. Publish the
scripts — anyone can rebuild from them in a few minutes. `images/` is already
gitignored.
