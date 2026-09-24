#!/usr/bin/env bash
# Open the App Store; if it is already open, bring its window to the front.
if hyprctl clients -j | grep -q '"class": "org.riptide.AppStore"'; then
    hyprctl dispatch "macos.activate_app('org.riptide.AppStore')" >/dev/null
else
    exec qs -p "$HOME/.config/quickshell/appstore.qml"
fi
