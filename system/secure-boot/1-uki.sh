#!/usr/bin/env bash
# Stage 1: build unified kernel images (UKI) and add Limine entries for them.
# Secure Boot stays off. The old kernel/initramfs entries stay as a fallback
# until stage 4 (note: after a kernel update they are stale).
source "$(dirname "$0")/lib.sh"

step "Kernel-Befehlszeile und mkinitcpio-Presets installieren"
put 644 /etc/kernel/cmdline
# the Notfallmodus (linux-lts.preset "recovery"): up to the text login only (as setup-os.sh)
{ sed -E 's/(^| )quiet( |$)/ /g; s/  +/ /g; s/^ //; s/ $//' /etc/kernel/cmdline | tr -d '\n'
  printf ' systemd.unit=multi-user.target\n'; } > /etc/kernel/cmdline-recovery
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

cat <<'MSG'

Fertig. Nächste Schritte:
  1. Neu starten ("Arch Linux (UKI)" startet von selbst). Die Festplatte fragt EINMAL nach der
     Passphrase: beim Start über das Kernel-Image setzt systemd vor dem Entsperren einen
     Trennwert in die TPM-Register (systemd-pcrosseparator), Register 7 passt nicht mehr.
  2. Den TPM neu binden (fragt nach der Passphrase), dann entsperrt er wieder von selbst:
       sudo systemd-cryptenroll /dev/disk/by-uuid/YOUR-LUKS-UUID \
            --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7
MSG
