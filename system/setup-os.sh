#!/usr/bin/env bash
# Root steps for the operating system services (docs/os-plan.md). Run once:
#   sudo ~/dotfiles/system/setup-os.sh
# Safe to run again; every step checks first.
#   1. packages from packages.txt (official repos): disk health, energy mode, firmware
#      updates, Night Shift, colour picker, screen recording, Quick Look, phones,
#      passwords app, disk utility; Flatpak goes (every app runs in our sandbox)
#   2. services: disk health watch (smartd), monthly btrfs check (scrub), energy mode,
#      firmware update check, NVIDIA sleep/wake (keeps the screen content across sleep)
#   3. monitor brightness over DDC: load the i2c-dev kernel module at every boot
#   4. the root helper riptide-helper (the only root part of the desktop) with its polkit
#      rules and the list of protected system packages; the old appstore-helper goes
#   5. our portal backend (riptide.portal): the portal's questions in our dialog
#   6. riptide itself: the package built from this repo (packaging/build.sh first, as
#      the user) in /usr/lib/riptide, root's; developer mode binds this repo over it
#      read-only (riptide-developer.service), so edits stay live
#   7. remote login (SSH) off – not used here (2026-09-26); a switch in
#      System Settings follows
#   8. printing and scanning: CUPS (started on demand) and Avahi – printers and scanners
#      in the home network are found by themselves (driverless IPP/AirPrint, eSCL), and
#      names like drucker.local resolve (nss-mdns before the other lookups); Wi-Fi gets the
#      country Germany (wireless-regdb): without it the card found no network
#   9. security: the firewall lets mDNS in (finding printers and devices) and no longer SSH
#      (remote login is off); snapshots of the system are readable for the user (their
#      date in System Settings; later Time Machine)
#  10. Time Machine, local part: hourly snapshots of /home (snapper config "home": the
#      last 24 hours, 7 days, 4 weeks, 6 months), readable for the user – "Frühere Versionen"
#  11. the login (greetd): at boot the session starts locked and its lock screen is the
#      login window – one passage into the desktop; our login screen for someone else;
#      should nothing come up, a text login takes its place
#  12. the boot menu (Limine): shown for 3 s to choose riptide, Windows, the reserve kernel or
#      the "Notfallmodus" – the LTS kernel up to the text login only, no graphics; no editor
#  13. the mainboard's boot menu (F11 at power-on): Windows, riptide, the Notfallmodus and the
#      reserve kernel to choose from
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
# Flatpak goes (2026-09-28): every app runs in our sandbox, Zen comes from its release
# archive (archive-app). Our sandbox is built from two of Flatpak's parts – bubblewrap and
# xdg-dbus-proxy – which were installed as its dependencies: kept on purpose first, or
# "pacman -Rns flatpak" would take the D-Bus filter of every app with it.
pacman -D --asexplicit bubblewrap xdg-dbus-proxy flatpak-xdg-utils >/dev/null
if pacman -Q flatpak >/dev/null 2>&1; then
    pacman -Rns --noconfirm flatpak
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

step "Chromium: Links öffnen im Standardbrowser"
# Chromium runs web apps only (WhatsApp, Word, PowerPoint in app mode). A link clicked in
# one opened in a Chromium window of its own; with Chromium's browser switcher every page
# outside the app's sites goes to xdg-open – in the app's sandbox the portal, so the default
# browser (Zen). Root-owned on purpose: a policy file the user could write would let any
# program force an extension into WhatsApp. A new web app adds its sites to the greylist.
install -D -o root -g root -m 644 system/files/etc/chromium/policies/managed/riptide.json \
    /etc/chromium/policies/managed/riptide.json

step "riptide: die Software root-eigen (/usr/lib/riptide) und der Entwicklermodus"
# The software that runs the system is a package built from this repo (packaging/build.sh,
# as the user, before this script): root's, in /usr/lib/riptide, every file known to pacman
# (pacman -Qkk riptide checks them). Developer mode, like turning off SIP on a Mac: while
# /etc/riptide/developer names this repo, riptide-developer.service binds it read-only over
# /usr/lib/riptide before anyone logs in – the system runs the code being worked on, and
# what runs as the user can change it. Turned off, the file is developer.off and this script
# leaves it so. The home folder links to /usr/lib/riptide (install.sh link, as the user).
pkg=$(ls -t packaging/out/riptide-*.pkg.tar.zst 2>/dev/null | head -1 || true)
if [[ -z "$pkg" ]]; then
    echo "  kein Paket gebaut – erst ~/dotfiles/packaging/build.sh (ohne sudo)"
else
    ver=$(pacman -Qp "$pkg" | awk '{print $2}')
    if [[ "$(pacman -Q riptide 2>/dev/null | awk '{print $2}' || true)" == "$ver" ]]; then
        echo "  riptide $ver: schon installiert"
    else
        pacman -U --noconfirm "$pkg"
    fi
fi
if [[ ! -e /etc/riptide/developer && ! -e /etc/riptide/developer.off ]]; then
    install -d -m 755 /etc/riptide
    printf '%s\n' "$PWD" > /etc/riptide/developer
    chmod 644 /etc/riptide/developer
    echo "  Entwicklermodus an: $PWD über /usr/lib/riptide"
fi
if [[ -f /usr/lib/systemd/system/riptide-developer.service ]]; then
    systemctl daemon-reload
    systemctl enable --now riptide-developer.service
    findmnt -no SOURCE,OPTIONS /usr/lib/riptide 2>/dev/null | sed 's/^/  eingehängt: /' || true
fi

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

step "WLAN: Land Deutschland (Kanäle und Sendeleistung)"
# Without a country the Wi-Fi card uses the "world" rules: most channels listen only, 5 GHz
# networks stay invisible. cfg80211 loads after the initramfs (from the real root), so the
# option applies at the next start without rebuilding the boot images.
conf=/etc/modprobe.d/riptide-wifi.conf
if grep -qs "ieee80211_regdom=DE" "$conf"; then
    echo "  schon eingerichtet"
else
    echo "options cfg80211 ieee80211_regdom=DE" > "$conf"
    echo "  gilt ab dem nächsten Start"
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

step "Anmeldung (greetd): gesperrt starten, Anmeldefenster = Sperrbildschirm"
# At boot the person is logged in and the session starts locked: its lock screen is the
# login window, one passage into the desktop (greetd's initial session). The login screen
# for someone else runs as the unprivileged user "greeter" and reads only these root-owned
# files – the window itself is the shell's LoginScreen.qml, the same as the lock screen's.
# Enabled for the next start – starting it now would end this session.
[[ -n "$user" ]] || { echo "  bitte mit sudo als der Benutzer ausführen, der sich anmeldet" >&2; exit 1; }
sed "s/@USER@/$user/" system/files/etc/greetd/config.toml > /etc/greetd/config.toml.new
chmod 644 /etc/greetd/config.toml.new
mv /etc/greetd/config.toml.new /etc/greetd/config.toml
for f in start run session-locked relock; do
    install -D -o root -g root -m 755 "system/files/usr/local/lib/riptide/greeter/$f" "/usr/local/lib/riptide/greeter/$f"
done
# greetd runs its initial session once per boot; after a logout "relock" lets it run once more
install -D -o root -g root -m 644 system/files/etc/systemd/system/greetd.service.d/riptide.conf \
    /etc/systemd/system/greetd.service.d/riptide.conf
systemctl daemon-reload
for f in shell.qml Login.qml hyprland.lua; do
    install -D -o root -g root -m 644 "system/files/usr/local/share/riptide/greeter/$f" "/usr/local/share/riptide/greeter/$f"
done
install -D -o root -g root -m 644 shell/LoginScreen.qml /usr/local/share/riptide/greeter/LoginScreen.qml
# after a logout the login screen starts the next locked session: it may restart greetd
install -D -o root -g root -m 644 system/files/etc/polkit-1/rules.d/50-riptide-greeter.rules \
    /etc/polkit-1/rules.d/50-riptide-greeter.rules
# the keyring: opened with the password at a login here (the lock screen does it for the
# session at boot) – not for the user "greeter" itself
if ! grep -q pam_gnome_keyring /etc/pam.d/greetd; then
    sed -i -e '/^auth[[:space:]]*include[[:space:]]*system-local-login/a auth       optional     pam_gnome_keyring.so' \
        -e '/^session[[:space:]]*include[[:space:]]*system-local-login/a session    [success=1 default=ignore] pam_succeed_if.so user = greeter quiet\nsession    optional     pam_gnome_keyring.so auto_start' \
        /etc/pam.d/greetd
    echo "  Schlüsselbund bei der Anmeldung"
fi
install -d -o greeter -g greeter -m 755 /var/lib/riptide/greeter # who logged in last
# each person's session leaves mouse and keyboard settings for the login screen here
# (hypr/modules/greeter.lua) and the moment of a logout (Quickshell Session.qml)
install -d -o root -g root -m 755 /var/lib/riptide/greeter/users
install -d -o "$user" -g "$(id -gn "$user")" -m 755 "/var/lib/riptide/greeter/users/$user"
runuser -u "$user" -- env XDG_RUNTIME_DIR="/run/user/$(id -u "$user")" hyprctl -i 0 reload >/dev/null 2>&1 || true
systemctl enable greetd.service
echo "  ab dem nächsten Start (angemeldet wird: $user)"

step "Boot-Menü (Limine) und Notfallmodus"
mode=""
seal=no
if ! conf="$(system/files/usr/local/sbin/limine-conf)"; then
    echo "  übersprungen"
else
    if [[ -f /etc/kernel/cmdline ]]; then
        # kernel images (Secure Boot stage 1): the Notfallmodus is the LTS kernel as its own
        # image, up to the text login only (multi-user.target: no greetd, no graphics); its
        # command line follows /etc/kernel/cmdline
        recovery_cmdline="$(sed -E 's/(^| )quiet( |$)/ /g; s/  +/ /g; s/^ //; s/ $//' /etc/kernel/cmdline | tr -d '\n') systemd.unit=multi-user.target"
        if [[ -f /boot/EFI/Linux/arch-linux-recovery.efi ]] \
            && [[ "$(cat /etc/kernel/cmdline-recovery 2>/dev/null)" == "$recovery_cmdline" ]] \
            && cmp -s system/files/etc/mkinitcpio.d/linux-lts.preset /etc/mkinitcpio.d/linux-lts.preset; then
            echo "  Notfall-Image aktuell"
        else
            printf '%s\n' "$recovery_cmdline" > /etc/kernel/cmdline-recovery
            install -D -o root -g root -m 644 system/files/etc/mkinitcpio.d/linux-lts.preset /etc/mkinitcpio.d/linux-lts.preset
            mkinitcpio -p linux-lts
            if command -v sbctl >/dev/null; then
                sbctl sign -s /boot/EFI/Linux/arch-linux-recovery.efi >/dev/null # signed now and after every update
            fi
        fi
    fi
    # the Notfallmodus entry: its own image when there is one, else a kernel+initramfs copy
    if [[ -f /boot/EFI/Linux/arch-linux-recovery.efi ]]; then mode=uki; else mode=linux; fi
    # sealed from Secure Boot stage 2 on: after a change Limine needs the new checksum
    if command -v sbctl >/dev/null && [[ -x /usr/local/sbin/limine-seal ]]; then seal=yes; fi
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
        if [[ "$seal" == yes ]] && ! /usr/local/sbin/limine-seal; then
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

step "Boot-Menü des Mainboards (F11 beim Einschalten)"
# Choosing what starts, like the Option key on a Mac: the mainboard's own boot menu reads
# the key itself (Limine's hidden menu is too quick to reach). Windows is there already; the
# Notfallmodus and the reserve kernel get entries of their own, straight to their kernel
# images (built by the Secure Boot stage 1, signed from stage 2 on). The start order stays.
esp_dev=$(findmnt -no SOURCE /boot)
esp_disk="/dev/$(lsblk -no PKNAME "$esp_dev")"
esp_part=$(lsblk -no PARTN "$esp_dev")
for entry in "riptide Notfallmodus|arch-linux-recovery.efi" "riptide Reserve (LTS)|arch-linux-lts.efi"; do
    label=${entry%%|*}
    file=${entry##*|}
    if [[ ! -f "/boot/EFI/Linux/$file" ]]; then
        echo "  $label: noch kein Kernel-Image (erst Secure-Boot-Stufe 1)"
    elif efibootmgr | grep -qF "* $label"$'\t'; then
        echo "  $label: schon da"
    else
        efibootmgr --create-only --disk "$esp_disk" --part "$esp_part" --label "$label" \
            --loader "\\EFI\\Linux\\$file" >/dev/null
        echo "  $label: eingetragen"
    fi
done
# in the start order too (after the rest): the ASRock menu shows only entries that are in it
order=$(efibootmgr | sed -n 's/^BootOrder: //p')
for label in "riptide Notfallmodus" "riptide Reserve (LTS)"; do
    num=$(efibootmgr | grep -F "* $label"$'\t' | sed -E 's/^Boot([0-9A-F]{4}).*/\1/' | head -1)
    if [[ -n "$num" && ",$order," != *",$num,"* ]]; then
        order="${order:+$order,}$num"
    fi
done
efibootmgr -o "$order" >/dev/null
efibootmgr | grep -E '^Boot[0-9A-F]{4}|^BootOrder' | sed -E 's/\t.*//; s/^/    /'

echo
echo "Fertig. Neu starten: der Anmeldebildschirm kommt beim nächsten Start."
