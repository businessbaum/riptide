#!/usr/bin/env bash
# Force quit an app ("Sofort beenden", ⌥⌘Esc, "reagiert nicht"): all of it at once – the
# systemd scope it runs in (sandboxed apps: app-sandbox-<app>-…, apps from the dock:
# app-Hyprland-<app>-…), else only the processes that own its windows.
#   force-quit.sh <window class>
# Never the shell itself or the compositor.
set -u
class="${1:?window class}"
compositor=$(pgrep -x Hyprland)
units=()
for pid in $(hyprctl clients -j | jq -r --arg c "$class" '.[] | select(.class == $c) | .pid' | sort -u); do
    [ "$pid" -gt 1 ] 2>/dev/null || continue
    [ "$pid" = "$compositor" ] && continue
    unit=$(sed -n 's|^0::.*/\([^/]*\.scope\)$|\1|p' "/proc/$pid/cgroup" 2>/dev/null)
    case "$unit" in
        app-Hyprland-qs-*) ;;                  # the shell: never
        app-*.scope) units+=("$unit") ;;
        *) kill -KILL "$pid" 2>/dev/null ;;
    esac
done
for unit in $(printf '%s\n' "${units[@]}" | sort -u); do
    systemctl --user kill --signal=SIGKILL "$unit"
done
