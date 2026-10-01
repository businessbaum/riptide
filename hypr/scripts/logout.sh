#!/usr/bin/env bash
# ⇧⌘Q: ask, then end the session (uwsm stops Hyprland and all apps cleanly).
# Interim dialog from hyprland-guiutils; the Apple menu in Quickshell replaces it.
set -euo pipefail

choice=$(hyprland-dialog --title "Abmelden" --apptitle "Möchtest du dich abmelden?" \
    --text "Alle Programme werden beendet." --buttons "Abbrechen;Abmelden") || exit 0
[ "$choice" = "Abmelden" ] && exec ~/.config/quickshell/scripts/logout.sh
