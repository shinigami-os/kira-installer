# kira-installer
> Live ISO build scripts and TUI installer for Kira Linux.

Builds two live-bootable ISO variants and provides the guided (not automatic) shell installer that runs from either one. No GUI wizard, no hand-holding: the installer expects the user to know what a partition is.

## ISO variants

| Target | Output | Contents |
|---|---|---|
| `make console` | `build/kira-console.iso` | Base system only: shell, flux, no DE |
| `make desktop` | `build/kira-desktop-$(DE).iso` | Base + one desktop environment baked in |
| `make all` | both | |

`DE` selects which desktop environment gets baked into the desktop ISO at build time: `sleex` (default) or `swayfx`.

```sh
make console
make desktop DE=swayfx
make all DE=sleex
```

Both variants boot through the same minimal `switch_root` initramfs kira-base produces (`runit/1-initramfs`) : the live ISO and an installed disk share the exact boot path, just with different `root=` kernel cmdline values (`root=live` vs `root=/dev/...`).

## Build pipeline

Requires `../shinigami` and `../kira-base` built first (the Makefile checks for `shinigami/arch/x86/boot/bzImage` and `kira-base/build/{rootfs.tar.gz,initramfs.cpio.gz}` and fails loudly with the exact command to run if either is missing):

```sh
make -C ../shinigami
make -C ../kira-base
make console          # or: make desktop DE=sleex
```

Per variant, the pipeline:
1. Extracts kira-base's `rootfs.tar.gz` into a scratch chroot (`/tmp/kira-installer-root-console` or `-desktop`).
2. Bind-mounts `/proc`, `/sys`, `/dev`, `/dev/pts`, copies in a working `resolv.conf`.
3. Runs `flux update` + `flux install -y <pkg>` inside the chroot for the packages every install needs regardless of tier: `kira-installer-tools`, `kira-net`, `kira-login`, `kira-seat`, `kira-session-bus`, `zsh`, `zsh-plugins`, `kira-branding`. For the desktop variant, also installs `kira-desktop-swayFX` or `kira-desktop-sleex` depending on `DE`, plus `nouveau-firmware` unconditionally (needed for display output on NVIDIA-equipped hardware even during the live/try-before-install session, before `install.sh`'s own hardware detection ever runs).
4. Writes `/etc/kira-tier` (`server` or `desktop`) into the chroot : this is the ISO's own coarse tier, read again and refined at install time (see below).
5. Copies `install.sh` into the chroot as `/usr/bin/kira-install`, stages the kernel/initramfs/rootfs tarball under `/installer/` so the installed system's own bootstrapping has something to start from.
6. Repacks the whole chroot into `live-rootfs-{console,desktop}.tar.gz` : this is what the live ISO actually extracts into tmpfs at boot, **not** a bootable initramfs itself.
7. Assembles the ISO: `bzImage` + `initramfs.cpio.gz` + the rootfs tarball + a GRUB EFI image (`grub-mkimage`, `BOOTX64.EFI`) at the ISO9660 root, via `xorriso`.

`make qemu-console` / `make qemu-desktop DE=<de>` boot the resulting ISO directly in QEMU with OVMF, serial console attached.

## Installer (`install.sh`)

Runs as `kira-install` from inside the live environment. Fully guided, no non-interactive mode:

1. **Network** : `nmcli` device/SSID prompts (wifi or ethernet), confirms connectivity with a ping.
2. **Partitioning** : guided whole-disk (wipes and creates GPT: ESP + optional swap + ext4 root) or guided free-space (finds the largest free region on an existing disk, partitions just that). Full manual mode is a documented stub (`3) not implemented`).
3. **Format + mount** : `mkfs.fat`/`mkfs.ext4`/`mkswap` as needed, mounts under `/mnt`.
4. **Base system** : extracts the staged `kira-base.tar.gz` onto the target, excluding runtime-only paths (`/tmp`, `/proc`, `/sys`, `/dev`, `/mnt`, `/run`, flux's cache/installed-db dirs), then recreates them empty.
5. **Kernel + fstab + hostname** : copies `bzImage`/`initramfs.cpio.gz` to `/boot` under a real `uname`-style name, writes `/etc/fstab` from the actual partition UUIDs, prompts for a hostname.
6. **Tier selection** : prompts `1) Sleex  2) SwayFX  3) server`, refining `/etc/kira-tier` from the ISO's coarse `desktop`/`server` value into `desktop-sleex` / `desktop-swayfx` / `server`, and drops a matching `~/.config/kira-desktop/active-de` for both `root` and the new user.
7. **Package install** : chroots in, `flux update`, then the same tier-independent package set the ISO baked in, plus `kira-desktop-{sleex,swayFX}` + `netsurf` + `git` + `greetd` for whichever desktop tier was chosen. Detects Intel wifi hardware (`/sys/bus/pci/devices/*`, class `0x028*`) and installs `iwlwifi-firmware` only when present.
8. **Users** : root password, then a new user (`kira` if left blank) in `wheel,video,input,audio`, `/usr/bin/zsh` as shell.
9. **Bootloader** : `grub-install --target=x86_64-efi` + `grub-mkconfig`, either onto the ESP this run just created or an existing one found elsewhere on the disk.
10. **Cleanup + reboot prompt.**

### Login path note

The tier-independent package set above still includes `kira-login`/`kira-seat` : the original getty-tty1-driven autologin flow (zsh-login script + seatd). That remains the real login path for `server` tier, which never installs `greetd`. For desktop tier, `greetd` (installed alongside the DE package) is now the actual path: cage + regreet on tty1, with `greetd`'s own `%post-install` disabling `getty-tty1` so the two never race for the same VT.

## Repository Layout

```
kira-installer/
  Makefile           ISO build pipeline (console + desktop x DE variants)
  install.sh         the guided installer itself, runs as /usr/bin/kira-install
  grub.cfg           live-ISO GRUB menu (search by ISO9660 label "KIRA", root=live)
  grub-early.cfg     embedded config for grub-mkimage's BOOTX64.EFI
  releases/          built ISOs kept for distribution (e.g. kira-console-26.07.iso)
  build/             GITIGNORED: chroots, tarballs, EFI images, final .iso files
```

## Status

Actively built and working: both ISO variants build and boot on real hardware, the guided installer completes a full disk install (whole-disk and free-space modes), and the resulting system boots via GRUB into either tier. Full manual partitioning mode is not implemented. See the [Kira Linux specification](https://github.com/shinigami-os) and the project roadmap.

## License
GPL-2.0
