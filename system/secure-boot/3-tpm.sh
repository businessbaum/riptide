#!/usr/bin/env bash
# Stage 3: with Secure Boot on, re-bind the TPM2 unlock to the new PCR 7 value.
source "$(dirname "$0")/lib.sh"

step "Secure Boot prüfen"
sbctl status
[[ "$(sb_state)" == *'"secure_boot":true'* ]] || die "Secure Boot ist noch nicht aktiv."

step "TPM neu an PCR 7 binden (fragt nach Passphrase oder Wiederherstellungsschlüssel)"
systemd-cryptenroll "$LUKS_DEV" --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7

step "Schlüsselplätze"
systemd-cryptenroll "$LUKS_DEV"

printf '\nFertig. Beim nächsten Start sollte der TPM die Platte wieder ohne Abfrage entsperren.\n'
