#!/usr/bin/env bash
# Stage 4: remove the old unsigned kernel/initramfs entries and files. After
# this, the ESP holds only signed EFI binaries plus the sealed limine.conf.
source "$(dirname "$0")/lib.sh"

[[ "$(sb_state)" == *'"secure_boot":true'* ]] || die "erst nach Stufe 3 (Secure Boot aktiv)."

step "Limine-Einträge mit 'protocol: linux' entfernen, UKI-Einträge umbenennen"
backup_conf
# Buffer each top-level entry (line starting with a single '/') and drop it
# if it uses the linux protocol. Everything before the first entry is kept.
awk '
    function flush() { if (buf != "" && !drop) printf "%s", buf; buf = ""; drop = 0 }
    /^\/[^\/]/ { flush(); inentry = 1 }
    inentry { buf = buf $0 "\n"; if ($0 ~ /^[ \t]*protocol:[ \t]*linux[ \t]*$/) drop = 1; next }
    { print }
    END { flush() }
' "$CONF" | sed 's|^/Arch Linux (UKI)$|/Arch Linux|; s|^/Arch Linux LTS (UKI)$|/Arch Linux LTS|' > "$CONF.new"
mv "$CONF.new" "$CONF"
cat "$CONF"

step "Alte Initramfs-Dateien löschen"
rm -fv /boot/initramfs-*.img

step "Limine neu versiegeln"
/usr/local/sbin/limine-seal
sbctl verify

printf '\nFertig. Bitte einmal neu starten und prüfen, dass Arch, Arch LTS und Windows starten.\n'
