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
#  10. the login screen: greetd with our own login window instead of the text console
#      (from the next start); should it not come up, a text login takes its place
#  11. start without waiting and the Notfallmodus: Limine boots at once (its menu stays
#      reachable: hold the space bar at power-on) and gets an entry "Notfallmodus" – the LTS
#      kernel up to the text login only, no graphics
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
# not needed: the wallpaper is drawn by our shell
if pacman -Q hyprpaper >/dev/null 2>&1; then
    pacman -Rns --noconfirm hyprpaper
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

step "Anmeldebildschirm (greetd) statt Textkonsole"
# Our login window runs as the unprivileged user "greeter" (created with the package) and
# reads only these root-owned files. Enabled for the next start – starting it now would end
# this session (it takes over the first console).
install -D -o root -g root -m 644 system/files/etc/greetd/config.toml /etc/greetd/config.toml
for f in start run; do
    install -D -o root -g root -m 755 "system/files/usr/local/lib/riptide/greeter/$f" "/usr/local/lib/riptide/greeter/$f"
done
for f in shell.qml Login.qml LoginScreen.qml hyprland.lua; do
    install -D -o root -g root -m 644 "system/files/usr/local/share/riptide/greeter/$f" "/usr/local/share/riptide/greeter/$f"
done
install -d -o greeter -g greeter -m 755 /var/lib/riptide/greeter # who logged in last
# each person's session leaves mouse and keyboard settings for the login screen here
# (hypr/modules/greeter.lua); written now once, then on every change
if [[ -n "$user" ]]; then
    install -d -o root -g root -m 755 /var/lib/riptide/greeter/users
    install -d -o "$user" -g "$(id -gn "$user")" -m 755 "/var/lib/riptide/greeter/users/$user"
    runuser -u "$user" -- env XDG_RUNTIME_DIR="/run/user/$(id -u "$user")" hyprctl -i 0 reload >/dev/null 2>&1 || true
fi
systemctl enable greetd.service
echo "  ab dem nächsten Start"

step "Start ohne Wartezeit und Notfallmodus (Limine)"
mode=""
if ! conf="$(system/files/usr/local/sbin/limine-conf)"; then
    echo "  übersprungen"
elif [[ -f /etc/kernel/cmdline ]] && command -v sbctl >/dev/null && [[ -x /usr/local/sbin/limine-seal ]]; then
    # Secure Boot set up (unified kernel images, docs/secure-boot.md): the Notfallmodus is
    # the LTS kernel as its own signed image, up to the text login only (multi-user.target:
    # no greetd, no graphics). Its command line follows /etc/kernel/cmdline.
    mode=uki
    recovery_cmdline="$(sed -E 's/(^| )quiet( |$)/ /g; s/  +/ /g; s/^ //; s/ $//' /etc/kernel/cmdline | tr -d '\n') systemd.unit=multi-user.target"
    if [[ -f /boot/EFI/Linux/arch-linux-recovery.efi ]] \
        && [[ "$(cat /etc/kernel/cmdline-recovery 2>/dev/null)" == "$recovery_cmdline" ]] \
        && cmp -s system/files/etc/mkinitcpio.d/linux-lts.preset /etc/mkinitcpio.d/linux-lts.preset; then
        echo "  Notfall-Image aktuell"
    else
        printf '%s\n' "$recovery_cmdline" > /etc/kernel/cmdline-recovery
        install -D -o root -g root -m 644 system/files/etc/mkinitcpio.d/linux-lts.preset /etc/mkinitcpio.d/linux-lts.preset
        mkinitcpio -p linux-lts
        sbctl sign -s /boot/EFI/Linux/arch-linux-recovery.efi >/dev/null # signed now and after every update
    fi
else
    # before Secure Boot: kernel + initramfs entries; the Notfallmodus is a copy of the LTS
    # entry with its own command line (after the Secure Boot stages run this again)
    mode=linux
fi

if [[ -n "$mode" ]]; then
    backup="$conf.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$conf" "$backup"
    python3 system/limine-edit.py "$backup" "$conf.new" "$mode"
    mv "$conf.new" "$conf"
    if cmp -s "$conf" "$backup"; then
        rm -f "$backup"
        echo "  limine.conf unverändert"
    else
        if [[ "$mode" == uki ]] && ! /usr/local/sbin/limine-seal; then
            # never leave a changed, unsealed config: Limine would refuse to start
            cp "$backup" "$conf"
            /usr/local/sbin/limine-seal
            echo "  Fehler beim Versiegeln – alte limine.conf wiederhergestellt" >&2
            exit 1
        fi
        echo "  neue limine.conf (Sicherung: $backup):"
        sed 's/^/    /' "$conf"
    fi
fi

echo
echo "Fertig. Neu starten: der Anmeldebildschirm kommt beim nächsten Start."
