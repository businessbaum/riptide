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

## Notfallmodus

The boot menu (hidden: `quiet`, 1 s – hold the space bar at power-on) has an entry
"Notfallmodus (Textanmeldung)": up to the text login only, no graphics. Before Secure Boot it
is a copy of the LTS kernel entry (system/setup-os.sh → system/limine-edit.py); stage 1 builds
its own UKI (linux-lts.preset "recovery", /etc/kernel/cmdline-recovery), stage 2 signs it,
stage 4 points the entry to it.

## Setup stages

Run in order with sudo from `system/secure-boot/`: `1-uki.sh`, reboot,
`2-sbctl.sh`, enable Secure Boot in firmware, boot (passphrase once),
`3-tpm.sh`, `4-cleanup.sh`.
