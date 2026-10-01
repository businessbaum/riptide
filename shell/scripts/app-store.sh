#!/usr/bin/env bash
# Open the App Store; if it is already open, bring its window to the front.
#   app-store.sh [page]   e.g. updates
store="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)/appstore.qml"
if hyprctl clients -j | grep -q '"class": "org.riptide.AppStore"'; then
    hyprctl dispatch "macos.activate_app('org.riptide.AppStore')" >/dev/null
elif [ -z "${1:-}" ]; then
    exec qs -p "$store"
else
    setsid -f qs -p "$store" >/dev/null 2>&1
fi
if [ -n "${1:-}" ]; then
    for _ in $(seq 1 50); do  # (a new window needs a moment until it listens)
        qs ipc -p "$store" call appstore page "$1" >/dev/null 2>&1 && break
        sleep 0.1
    done
fi
