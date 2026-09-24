#!/usr/bin/env bash
# Stage 1: build unified kernel images (UKI) and add Limine entries for them.
# Secure Boot stays off. The old kernel/initramfs entries stay as a fallback
# until stage 4 (note: after a kernel update they are stale).
source "$(dirname "$0")/lib.sh"

step "Kernel-Befehlszeile und mkinitcpio-Presets installieren"
put 644 /etc/kernel/cmdline
put 644 /etc/mkinitcpio.d/linux.preset
put 644 /etc/mkinitcpio.d/linux-lts.preset

step "UKIs bauen"
mkdir -p /boot/EFI/Linux
mkinitcpio -P
ls -lh /boot/EFI/Linux

step "Limine-Einträge für die UKIs ergänzen"
if grep -q '^/Arch Linux (UKI)$' "$CONF"; then
    echo "  schon vorhanden"
else
    backup_conf
    export UKI_ENTRIES='/Arch Linux (UKI)
    protocol: efi
    path: boot():/EFI/Linux/arch-linux.efi

/Arch Linux LTS (UKI)
    protocol: efi
    path: boot():/EFI/Linux/arch-linux-lts.efi
'
    # insert before the first existing entry, so the UKI entry becomes default
    awk '!done && /^\// { print ENVIRON["UKI_ENTRIES"]; done = 1 } { print }' \
        "$CONF" > "$CONF.new"
    mv "$CONF.new" "$CONF"
fi

step "Neue limine.conf"
cat "$CONF"

printf '\nFertig. Bitte neu starten und im Limine-Menü "Arch Linux (UKI)" wählen (Standard).\n'
