#!/usr/bin/env bash
# Set up riptide from this repo.
#   sudo ./install.sh packages   install everything in packages.txt (official repos)
#   ./install.sh link            link configs into ~/.config etc. with GNU stow
#   ./install.sh services        enable the user services of the desktop session
set -euo pipefail
cd "$(dirname "$0")"

case "${1:-}" in
packages)
    ((EUID == 0)) || { echo "Bitte mit sudo ausführen." >&2; exit 1; }
    grep -Ev '^[[:space:]]*(#|$)' packages.txt | pacman -S --needed -
    ;;
link)
    ((EUID != 0)) || { echo "Bitte ohne sudo ausführen." >&2; exit 1; }
    # every directory in home/ is one stow package mirroring $HOME. Config folders
    # are linked as a whole; shared folders under ~/.local/share get one link per
    # file (--no-folding), so other programs never write into this repo.
    # Folded packages: only add what is missing, never --restow – that removes a link such
    # as ~/.config/hypr for a moment, Hyprland reloads without its config in between and
    # every window loses its floating size. Shared packages: --restow (per-file links, no
    # folder vanishes) also drops links of files that are gone.
    shared=(applications apps wireplumber systemd)
    stow --dir=home --target="$HOME" $(ls home | grep -vxF -f <(printf '%s\n' "${shared[@]}"))
    stow --dir=home --target="$HOME" --restow --no-folding "${shared[@]}"
    ;;
services)
    ((EUID != 0)) || { echo "Bitte ohne sudo ausführen." >&2; exit 1; }
    systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service
    systemctl --user enable hypridle.service   # starts with the next Hyprland session
    systemctl --user enable --now riptide-session.service   # permissions, sandboxes, new apps
    ~/.local/bin/app-sandbox --sync
    ;;
*)
    sed -n '2,5p' "$0"
    exit 1
    ;;
esac
