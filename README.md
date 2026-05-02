# kira-installer
> TUI installer and ISO build scripts for Kira Linux.

Produces two ISO variants:
- `kira-base.iso` — base system only, no GUI (~500MB target)
- `kira-desktop.iso` — base + SwayFX desktop (~2GB target)

Both ISOs are live-bootable. The installer is a clean, guided TUI written in C or shell. No GUI wizard, no hand-holding. ISOs are built reproducibly and signed with the Kira project GPG key.

## Status
Pre-development. See the [Kira Linux specification](https://github.com/shinigami-os) and the project roadmap.

## License
GPL-2.0
