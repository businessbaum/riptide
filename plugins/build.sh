#!/usr/bin/env bash
# Build our Hyprland plugins against the installed Hyprland (run after every Hyprland update):
#   hyprbars        official plugin (github.com/hyprwm/hyprland-plugins, tag matching
#                   the installed version) + our patch hyprbars-on-drag-end.patch
#   window-buttons  our own plugin (plugins/window-buttons)
# Result: ~/.local/lib/hyprland-plugins/*.so, loaded at login (hypr/modules/autostart.lua).
set -euo pipefail
cd "$(dirname "$0")"

dest="$HOME/.local/lib/hyprland-plugins"
src="$HOME/.local/src/hyprland-plugins"
version=$(pkg-config --modversion hyprland)        # e.g. 0.56.2
tag="v${version%.*}.0"                             # plugins are tagged per minor release

echo "==> Hyprland $version, hyprland-plugins $tag"
if [[ ! -d "$src/.git" ]]; then
    git clone --quiet https://github.com/hyprwm/hyprland-plugins "$src"
fi
git -C "$src" fetch --quiet --tags origin
git -C "$src" checkout --quiet --force "$tag"
git -C "$src" clean --quiet -fdx hyprbars
git -C "$src" apply "$PWD/hyprbars-on-drag-end.patch"

echo "==> hyprbars"
make -C "$src/hyprbars" --quiet 2>&1 | grep -E 'error' || true
echo "==> window-buttons"
make -C window-buttons --quiet --always-make 2>&1 | grep -E 'error' || true

install -Dm755 "$src/hyprbars/hyprbars.so" "$dest/hyprbars.so"
install -Dm755 window-buttons/window-buttons.so "$dest/window-buttons.so"
echo "$version" > "$dest/built-for"
echo "==> installed to $dest (built for Hyprland $version). Takes effect at the next login."
