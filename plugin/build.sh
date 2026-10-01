#!/usr/bin/env bash
# Build our one Hyprland plugin against the installed Hyprland (run after every Hyprland
# update): plugin/riptide-wm – title bars with traffic lights (based on hyprbars) and
# the macOS window behaviour (see riptide-wm/plugin.hpp).
# Result: ~/.local/lib/hyprland-plugins/riptide-wm.so, loaded at login (hypr/modules/autostart.lua).
# Built in a folder of its own: the sources may lie read-only (/usr/lib/riptide).
set -euo pipefail
src="$(cd "$(dirname "$0")" && pwd)/riptide-wm"

dest="$HOME/.local/lib/hyprland-plugins"
version=$(pkg-config --modversion hyprland)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -r "$src" "$work/"

echo "==> riptide-wm for Hyprland $version"
make -C "$work/riptide-wm" --quiet --always-make 2>&1 | grep -E 'error' && exit 1
install -Dm755 "$work/riptide-wm/riptide-wm.so" "$dest/riptide-wm.so"
echo "$version" > "$dest/built-for"
echo "==> installed to $dest. Takes effect at the next login."
