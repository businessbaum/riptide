#!/usr/bin/env bash
# Set up riptide from this repo.
#   sudo ./install.sh packages   install everything in packages.txt (official repos)
#   ./install.sh link            link configs into ~/.config etc. with GNU stow
set -euo pipefail
cd "$(dirname "$0")"

case "${1:-}" in
packages)
    ((EUID == 0)) || { echo "Bitte mit sudo ausführen." >&2; exit 1; }
    grep -Ev '^[[:space:]]*(#|$)' packages.txt | pacman -S --needed -
    ;;
link)
    ((EUID != 0)) || { echo "Bitte ohne sudo ausführen." >&2; exit 1; }
    # every directory in home/ is one stow package mirroring $HOME
    stow --dir=home --target="$HOME" --restow $(ls home)
    ;;
*)
    sed -n '2,4p' "$0"
    exit 1
    ;;
esac
