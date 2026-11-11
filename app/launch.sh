#!/bin/sh
# The installer, as the live medium starts it: inside cage, on tty1, no login (see the runit service
# that runs this). In a session, `KI_DRY=1 qs -p app/` is enough to try it without touching a disk.
dir="$(dirname "$(readlink -f "$0")")"

export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export QSG_RENDER_LOOP=basic
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/kira-installer}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/run/kira-installer/cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-/run/kira-installer/state}"
mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
chmod 700 "$XDG_RUNTIME_DIR"

exec qs -p "$dir"
