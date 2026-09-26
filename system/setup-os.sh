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
#   6. remote login (SSH) off – not used here (2026-09-26); a switch in
#      System Settings follows
#   7. printing and scanning: CUPS (started on demand) and Avahi – printers and scanners
#      in the home network are found by themselves (driverless IPP/AirPrint, eSCL), and
#      names like drucker.local resolve (nss-mdns before the other lookups)
#   8. security: the firewall lets mDNS in (finding printers and devices) and no longer SSH
#      (remote login is off); snapshots of the system are readable for the user (their
#      date in System Settings; later Time Machine)
#   9. Time Machine, local part: hourly snapshots of /home (snapper config "home": the
#      last 24 hours, 7 days, 4 weeks, 6 months), readable for the user – "Frühere Versionen"
set -euo pipefail
cd "$(dirname "$0")/.."

((EUID == 0)) || { echo "Bitte mit sudo ausführen." >&2; exit 1; }
step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

step "Pakete aus den offiziellen Repos (packages.txt)"
grep -Ev '^[[:space:]]*(#|$)' packages.txt | pacman -S --needed -
# gpu-screen-recorder goes: its KMS helper (cap_sys_admin, runnable by anyone) recorded the
# screen past Hyprland's question; wf-recorder records through screencopy instead
if pacman -Q gpu-screen-recorder >/dev/null 2>&1; then
    pacman -Rns --noconfirm gpu-screen-recorder
fi

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

step "Entfernte Anmeldung (SSH) aus"
if systemctl is-enabled --quiet sshd.service 2>/dev/null || systemctl is-active --quiet sshd.service; then
    systemctl disable --now sshd.service
else
    echo "  schon aus"
fi

step "Drucken und Scannen (CUPS, Avahi, Namen im Heimnetz)"
systemctl enable --now avahi-daemon.service cups.socket
if grep -q "mdns_minimal" /etc/nsswitch.conf; then
    echo "  Namensauflösung im Heimnetz schon eingerichtet"
else
    cp /etc/nsswitch.conf /etc/nsswitch.conf.riptide-backup
    sed -i 's/^\(hosts:.*\)mymachines /\1mymachines mdns_minimal [NOTFOUND=return] /' /etc/nsswitch.conf
    grep -q "mdns_minimal" /etc/nsswitch.conf || sed -i 's/^hosts: /hosts: mdns_minimal [NOTFOUND=return] /' /etc/nsswitch.conf
    grep "^hosts" /etc/nsswitch.conf
fi

step "Sicherheit (Firewall, Snapshots)"
if systemctl is-active --quiet firewalld.service; then
    zone=$(firewall-cmd --get-default-zone)
    for flag in "" --permanent; do
        firewall-cmd $flag --zone="$zone" --add-service=mdns >/dev/null
        systemctl is-enabled --quiet sshd.service 2>/dev/null || firewall-cmd $flag --zone="$zone" --remove-service=ssh >/dev/null
    done
    echo "  Firewall ($zone): $(firewall-cmd --zone="$zone" --list-services)"
fi
user=${SUDO_USER:-}
if [[ -n "$user" ]] && snapper -c root get-config >/dev/null 2>&1; then
    snapper -c root set-config "ALLOW_USERS=$user" SYNC_ACL=yes
    echo "  Snapshots für $user lesbar"
fi

step "Time Machine: stündliche Snapshots des Benutzerordners"
if [[ -f /etc/snapper/configs/home ]]; then
    echo "  schon eingerichtet"
elif [[ -n "$user" ]]; then
    snapper -c home create-config /home
    snapper -c home set-config "ALLOW_USERS=$user" SYNC_ACL=yes TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes \
        TIMELINE_LIMIT_HOURLY=24 TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=4 TIMELINE_LIMIT_MONTHLY=6 \
        TIMELINE_LIMIT_YEARLY=0
    snapper -c home create --description "Erster Snapshot"
    echo "  /home: stündlich (24 Std., 7 Tage, 4 Wochen, 6 Monate)"
fi

echo
echo "Fertig."
