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

## Choosing what starts: F11

Limine's own menu is hidden (`quiet`, 1 s – too quick to reach reliably: the screen is often
still dark and a key held before Limine starts does not count). What starts is chosen in the
mainboard's boot menu instead (ASRock: **F11** at power-on, the BIOS setup: F2/Del), like the
Option key on a Mac: Windows Boot Manager, "Arch Linux" (Limine → riptide), and two entries
straight to their kernel images – "riptide Notfallmodus" (up to the text login, no graphics)
and "riptide Reserve (LTS)" (system/setup-os.sh step 12, efibootmgr; the start order stays).

The Notfallmodus: before Secure Boot also a Limine entry copied from the LTS entry
(system/limine-edit.py); stage 1 builds its own UKI (linux-lts.preset "recovery",
/etc/kernel/cmdline-recovery), stage 2 signs it, stage 4 points the Limine entry to it.

## Setup stages

Run in order with sudo from `system/secure-boot/`: `1-uki.sh`, reboot,
`2-sbctl.sh`, enable Secure Boot in firmware, boot (passphrase once),
`3-tpm.sh`, `4-cleanup.sh`.
