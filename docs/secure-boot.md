# Secure Boot (sbctl + Limine + UKI)

Chain: firmware (own keys + Microsoft) -> signed Limine with enrolled
limine.conf checksum -> `protocol: efi` chainload of signed UKIs (firmware
verifies) -> sd-encrypt unlocks LUKS via TPM2 (PCR 7).

- UKIs: `/boot/EFI/Linux/arch-linux{,-lts}.efi`, built by mkinitcpio from
  `/etc/mkinitcpio.d/*.preset` and `/etc/kernel/cmdline`, signed by sbctl's
  mkinitcpio post hook.
- Limine: `/usr/local/sbin/limine-seal` copies the packaged binary, enrolls the
  b2sum of limine.conf, signs it. Run by `limine-deploy.hook` on
  Limine updates.
- With Secure Boot on and a checksum enrolled, Limine panics on a modified
  config and requires hashes for all non-chainloaded files; the editor is off.

## After editing limine.conf

Limine reads the limine.conf next to its EFI program: `/boot/EFI/limine/limine.conf`
(`limine-conf` prints the path it uses, following Limine's search order).

```bash
sudo limine-seal
```

Forgetting this makes Limine refuse to boot. Recovery: firmware boot menu ->
Windows Boot Manager or Arch ISO, or disable Secure Boot temporarily
(`hash_mismatch_panic` is only forced with Secure Boot on).

## The TPM after switching to UKIs (stage 1)

Booted from a UKI (measured by systemd-stub), systemd 261 runs systemd-pcrosseparator.service in
the initrd *before* cryptsetup: it extends PCRs 0–7 with an "os-separator". PCR 7 then differs
from the value the TPM slot was bound to under the old kernel+initramfs boot → the disk asks for
its passphrase once. Re-bind from the UKI-booted system (the separator is in the current PCR 7
too, so it matches from then on):

```bash
sudo systemd-cryptenroll /dev/disk/by-uuid/YOUR-LUKS-UUID \
     --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7
```

The old kernel+initramfs entries (no separator) then ask for the passphrase – fine, they go in
stage 4. Stage 3 does the same re-binding after Secure Boot is switched on.

## Choosing what starts: F11

Limine's own menu is hidden (`quiet`, 1 s – too quick to reach reliably: the screen is often
still dark and a key held before Limine starts does not count). What starts is chosen in the
mainboard's boot menu instead (ASRock: **F11** at power-on, the BIOS setup: F2/Del), like the
Option key on a Mac: Windows Boot Manager, "Arch Linux" (Limine → riptide), and two entries
straight to their kernel images – "riptide Notfallmodus" (up to the text login, no graphics)
and "riptide Reserve (LTS)" (system/setup-os.sh step 12, efibootmgr; appended to the start order – ASRock's menu shows
only entries that are in it, and the firmware dropped the others from it on the next boot).

The Notfallmodus: before Secure Boot also a Limine entry copied from the LTS entry
(system/limine-edit.py); stage 1 builds its own UKI (linux-lts.preset "recovery",
/etc/kernel/cmdline-recovery), stage 2 signs it, stage 4 points the Limine entry to it.

## Setup stages

Run in order with sudo from `system/secure-boot/`: `1-uki.sh`, reboot,
`2-sbctl.sh`, enable Secure Boot in firmware, boot (passphrase once),
`3-tpm.sh`, `4-cleanup.sh`.
