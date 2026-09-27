#!/usr/bin/env bash
# Stage 2: create own Secure Boot keys, enroll them together with Microsoft's
# (Windows, NVIDIA GOP option ROM), sign Limine and the UKIs, and enroll the
# limine.conf checksum into Limine. Secure Boot is switched on afterwards in
# the firmware setup.
source "$(dirname "$0")/lib.sh"

grep -q '^/Arch Linux (UKI)$' "$CONF" || die "zuerst Stufe 1 ausführen."

step "sbctl installieren (offizielles Repo extra)"
pacman -S --needed --noconfirm sbctl

step "Firmware-Zustand prüfen"
sbctl status
state="$(sb_state)"
if [[ "$state" != *'"installed":true'* ]]; then
    [[ "$state" == *'"setup_mode":true'* ]] || die "Firmware ist nicht im Setup Mode."
    step "Eigene Schlüssel erzeugen"
    sbctl create-keys
    step "Schlüssel einspielen: eigene + Microsoft (+ Option-ROM-Prüfsummen aus dem TPM-Log)"
    sbctl enroll-keys --microsoft --tpm-eventlog
else
    echo "  Schlüssel sind bereits installiert, überspringe Erzeugen/Einspielen"
fi

step "limine-seal und pacman-Hook installieren"
put 755 /usr/local/sbin/limine-conf
put 755 /usr/local/sbin/limine-seal
put 644 /etc/pacman.d/hooks/limine-deploy.hook

step "UKIs signieren"
sbctl sign -s /boot/EFI/Linux/arch-linux.efi
sbctl sign -s /boot/EFI/Linux/arch-linux-lts.efi
sbctl sign -s /boot/EFI/Linux/arch-linux-recovery.efi

step "Limine: Config-Prüfsumme einbauen und signieren"
/usr/local/sbin/limine-seal

step "Prüfen"
sbctl verify
sbctl status

cat <<'MSG'

Fertig. Nächste Schritte:
  1. Neu starten, ins BIOS/UEFI-Setup, Secure Boot einschalten (Modus "Custom"/"Benutzer",
     Schlüssel NICHT auf Werkseinstellung zurücksetzen).
  2. Arch startet: einmal Passphrase oder Wiederherstellungsschlüssel eingeben.
  3. Dann: sudo ~/dotfiles/system/secure-boot/3-tpm.sh

Falls etwas nicht startet: Secure Boot im BIOS wieder ausschalten, dann läuft alles wie vorher.
MSG
