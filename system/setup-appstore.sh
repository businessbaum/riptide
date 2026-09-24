#!/usr/bin/env bash
# One-time root setup for the App Store. Run:  sudo ~/dotfiles/system/setup-appstore.sh
#   1. packages: the official app catalog (archlinux-appstream-data) and checkupdates
#   2. the root helper (/usr/local/sbin/appstore-helper) and its polkit rule
set -euo pipefail
cd "$(dirname "$0")"
((EUID == 0)) || { echo "Bitte mit sudo ausführen." >&2; exit 1; }

echo "==> Pakete: App-Katalog und Update-Prüfung"
pacman -S --needed archlinux-appstream-data pacman-contrib

echo "==> Hilfsskript und Polkit-Regel"
install -D -o root -g root -m 755 files/usr/local/sbin/appstore-helper /usr/local/sbin/appstore-helper
install -D -o root -g root -m 644 files/usr/share/polkit-1/actions/org.riptide.appstore.policy \
    /usr/share/polkit-1/actions/org.riptide.appstore.policy
echo "Fertig."
