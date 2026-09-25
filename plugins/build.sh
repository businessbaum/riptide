#!/usr/bin/env bash
# Build our one Hyprland plugin against the installed Hyprland (run after every Hyprland
# update): plugins/riptide-wm – title bars with traffic lights (based on hyprbars) and
# the macOS window behaviour (see riptide-wm/plugin.hpp).
# Result: ~/.local/lib/hyprland-plugins/riptide-wm.so, loaded at login (hypr/modules/autostart.lua).
set -euo pipefail
cd "$(dirname "$0")"

dest="$HOME/.local/lib/hyprland-plugins"
version=$(pkg-config --modversion hyprland)

echo "==> riptide-wm for Hyprland $version"
make -C riptide-wm --quiet --always-make 2>&1 | grep -E 'error' && exit 1
install -Dm755 riptide-wm/riptide-wm.so "$dest/riptide-wm.so"
echo "$version" > "$dest/built-for"
echo "==> installed to $dest. Takes effect at the next login."
