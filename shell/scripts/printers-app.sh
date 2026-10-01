#!/usr/bin/env bash
# Open the printer app "Drucker" (the print queue); if it is already open, bring it to the front.
#   printers-app.sh [printer]   show this printer's queue
app="$HOME/.config/quickshell/printers.qml"
if hyprctl clients -j | grep -q '"class": "org.riptide.Printers"'; then
    hyprctl dispatch "macos.activate_app('org.riptide.Printers')" >/dev/null
elif [ -z "${1:-}" ]; then
    exec qs -p "$app"
else
    setsid -f qs -p "$app" >/dev/null 2>&1
fi
if [ -n "${1:-}" ]; then
    for _ in $(seq 1 50); do  # (a new window needs a moment until it listens)
        qs ipc -p "$app" call printers select "$1" >/dev/null 2>&1 && break
        sleep 0.1
    done
fi
