# kira-installer
> The Kira Linux installer, and the one live ISO that is only that.

Kira ships a single ISO. It does not boot into a desktop or a shell: it boots straight into the installer, a fullscreen app running inside [cage](https://github.com/cage-kiosk/cage) on tty1, with no login and no way out of it except rebooting or powering off. Everything else (the desktop, the shell, the packages) is installed onto the disk by the installer through flux.

The app is a Quickshell (QML) application styled after The Line. It asks a few questions, shows what it is about to do, and writes nothing to a disk until you hold the button on the review screen.

## The installer

Steps, one tick each on the ruler: welcome, keyboard, network, disk, how much of it, swap, hostname, user, password, root, timezone, system, review (hold to confirm), install, done.

- **Keyboard and network.** The keymap is written to the installed system. Wi-Fi set up during the session carries over to it.
- **Disk.** Wipe a whole disk (GPT: a 512 MiB EFI system partition, optional swap, ext4 root) or install into the largest free region of an existing one. The disk the medium booted from is refused. At least 15 GiB is needed.
- **System.** Pick one: **The Line** (Kira's own desktop), **Sleex** (the AxOS desktop), or **Server** (a shell and nothing else). Another one can be added later with flux.
- **Install.** The base system is copied from the medium, then the packages for the chosen system are installed with flux (retried on a network error), then GRUB for UEFI. A failed install unmounts everything, so trying again from the app just works.
- **Done.** Reboot or power off. There is no shell to stay in.

UEFI only. Full manual partitioning is not available.

## Layout

```
app/                         the installer
  shell.qml                  window, ruler, hints, keys, power-off dialog
  launch.sh                  what cage runs on the live medium
  backend/kira-install-backend   probes, and the real install (the app never runs a pipeline itself)
  services/                  Theme, Anim (the style guide tokens), Installer (state and processes)
  components/                Page, ListRow, Choice, Field, HoldButton, Ruler, ...
  pages/                     one screen per step
iso/sv/kira-installer/       the runit service that starts cage and the app on tty1
Makefile                     builds the ISO
grub.cfg, grub-early.cfg     the ISO's GRUB menu (search by the ISO9660 label KIRA)
make_release.sh              build the ISO and publish it
```

The backend takes the answers as `KI_*` environment variables (never argv, so passwords stay out of `ps`) and reports on stdout with `@progress N text`, `@error text` and `@done`.

## Trying it without touching a disk

Inside a Wayland session with `quickshell` installed:

```sh
KI_DRY=1 qs -p app
```

`KI_DRY=1` walks every stage without running anything, and Esc closes the window instead of asking to power off.

## Building the ISO

Needs `../shinigami` and `../kira-base` built first (the Makefile fails with the exact command to run if the kernel, initramfs or rootfs is missing), plus `xorriso`, `grub-mkimage` and `mtools`, and root for the chroot:

```sh
make -C ../shinigami
make -C ../kira-base
sudo make iso            # build/kira-installer.iso
make qemu                # boot it in QEMU with OVMF
```

The build:
1. Extracts kira-base's `rootfs.tar.xz` into a scratch chroot and installs, with flux, what the app needs to run: the installer tools, networking, seatd, cage, Quickshell with Qt's graphics drivers, fonts and firmware.
2. Copies the app to `/usr/share/kira-installer`, adds the runit service, and **removes every other way into a shell**: the gettys, the serial console and sshd.
3. Stages the kernel, initramfs and base rootfs under `/installer/`, which is what gets copied onto the target disk.
4. Repacks the chroot into `live-rootfs.tar.xz`, extracted into tmpfs at boot by kira-base's `switch_root` initramfs, and assembles the ISO (kernel, initramfs, rootfs tarball, GRUB EFI image) with `xorriso`.

`./make_release.sh <version>` builds from scratch and publishes the ISO.

## License
GPL-2.0
