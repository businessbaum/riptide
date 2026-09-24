#!/usr/bin/env bash
# Open System Settings; if it is already open, bring its window to the front.
# (qs -n cannot be used: it treats the main shell in the same folder as a duplicate.)
if hyprctl clients -j | grep -q '"class": "org.riptide.SystemSettings"'; then
    hyprctl dispatch "macos.activate_app('org.riptide.SystemSettings')" >/dev/null
else
    exec qs -p "$HOME/.config/quickshell/settings.qml"
fi
