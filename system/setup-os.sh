#!/usr/bin/env bash
# Root steps for the operating system services (docs/os-plan.md). Run once:
#   sudo ~/dotfiles/system/setup-os.sh
# Safe to run again; every step checks first.
#   1. packages from packages.txt (official repos): disk health, energy mode, firmware
#      updates, Night Shift, colour picker, screen recording, Quick Look, phones,
#      passwords app, disk utility
#   2. services: disk health watch (smartd), monthly btrfs check (scrub), energy mode,
#      firmware update check, NVIDIA sleep/wake (keeps the screen content across sleep)
#   3. monitor brightness over DDC: load the i2c-dev kernel module at every boot
#   4. the root helper riptide-helper (the only root part of the desktop) with its polkit
#      rules and the list of protected system packages; the old appstore-helper goes
#   5. our portal backend (riptide.portal): the portal's questions in our dialog
set -euo pipefail
cd "$(dirname "$0")/.."

((EUID == 0)) || { echo "Bitte mit sudo ausführen." >&2; exit 1; }
step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

step "Pakete aus den offiziellen Repos (packages.txt)"
grep -Ev '^[[:space:]]*(#|$)' packages.txt | pacman -S --needed -

step "Dienste"
systemctl enable --now smartd.service
systemctl enable --now btrfs-scrub@-.timer
systemctl enable --now power-profiles-daemon.service
systemctl enable --now fwupd-refresh.timer
systemctl enable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service

step "Bildschirmhelligkeit über DDC (i2c-dev)"
conf=/etc/modules-load.d/i2c-dev.conf
if [[ -f "$conf" ]]; then
    echo "  schon eingerichtet"
else
    echo i2c-dev > "$conf"
    modprobe i2c-dev
fi

step "Root-Helfer (riptide-helper) und Polkit-Regeln"
install -D -o root -g root -m 755 system/files/usr/local/sbin/riptide-helper /usr/local/sbin/riptide-helper
install -D -o root -g root -m 644 system/files/usr/local/share/riptide/protected-packages \
    /usr/local/share/riptide/protected-packages
install -D -o root -g root -m 644 system/files/usr/share/polkit-1/actions/org.riptide.helper.policy \
    /usr/share/polkit-1/actions/org.riptide.helper.policy
rm -f /usr/local/sbin/appstore-helper /usr/share/polkit-1/actions/org.riptide.appstore.policy

step "Portal-Backend (riptide.portal)"
install -D -o root -g root -m 644 system/files/usr/share/xdg-desktop-portal/portals/riptide.portal \
    /usr/share/xdg-desktop-portal/portals/riptide.portal

echo
echo "Fertig."
