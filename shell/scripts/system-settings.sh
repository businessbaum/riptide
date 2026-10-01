#!/usr/bin/env bash
# Open System Settings; if it is already open, bring its window to the front.
#   system-settings.sh [page]   e.g. privacy, privacy/microphone, sound
# (qs -n cannot be used: it treats the main shell in the same folder as a duplicate.)
settings="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)/settings.qml"
if hyprctl clients -j | grep -q '"class": "org.riptide.SystemSettings"'; then
    hyprctl dispatch "macos.activate_app('org.riptide.SystemSettings')" >/dev/null
else
    setsid -f qs -p "$settings" >/dev/null 2>&1
fi
if [ -n "${1:-}" ]; then
    for _ in $(seq 1 50); do  # (a new window needs a moment until it listens)
        qs ipc -p "$settings" call settings page "$1" >/dev/null 2>&1 && break
        sleep 0.1
    done
fi
