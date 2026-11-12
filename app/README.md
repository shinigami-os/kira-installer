# kira-installer / app

The Kira Linux installer, a Quickshell (QML) app laid out like The Line's settings app: the steps as a numbered
spine on the left, the current one in its panel.
It replaces the former shell script, Rust/ratatui and Rust/Slint attempts.

```
shell.qml                    window, ruler, hints, keys, leave dialog
launch.sh                    what the live medium runs (cage + qs -p)
backend/kira-install-backend probes + the real install (logic of the old install.sh, without prompts)
services/                    Theme, Anim (The Line's colours and motion), Installer (state + processes)
components/                  Page, Spine, ListRow, Choice, Field, HoldButton, ...
pages/                       one screen per step
```

Steps (one tick each on the ruler): welcome · keyboard · network · disk · how much of it · swap · hostname ·
user · password · root · timezone · system · review (hold to confirm) · install · done.

Try it without touching a disk (inside a Wayland session, with `quickshell` installed):

```sh
KI_DRY=1 qs -p kira-installer/app
```

The backend takes its answers as `KI_*` environment variables (never argv, so passwords stay out of `ps`) and
speaks `@progress N text`, `@error text`, `@done` on stdout. `KI_DRY=1` walks the stages without running anything.

Needs on the live medium: `quickshell`, `cage`, fonts Raleway + IBM Plex Mono, and what install.sh already needed
(`parted`, `e2fsprogs`, `dosfstools`, util-linux `lsblk`, `nmcli`, `efibootmgr`).
