#!/usr/bin/env python3
"""The boot menu and its Notfallmodus entry – for system/setup-os.sh.

    limine-edit.py <limine.conf> <output> uki|linux

Windows is the default entry (2026-10-12): `default_entry` names the first top-level
entry whose title contains "windows"; nothing is changed when there is none.
Global options: the menu shows for 3 s (2026-09-28: choose the system right there –
a hidden menu could not be reached), no editor. Adds "/Notfallmodus (Textanmeldung)":
  uki    (the kernel images of Secure Boot stage 1 exist): chainloads
         /EFI/Linux/arch-linux-recovery.efi, the LTS kernel image with its own command line –
         also replacing an older kernel+initramfs copy
  linux  (kernel + initramfs only): a copy of the LTS entry (else the first Linux entry) whose
         command line ends at the text login: systemd.unit=multi-user.target, without "quiet"
Prints what it did; writes <output> in any case."""
import re
import sys

TITLE = "/Notfallmodus (Textanmeldung)"


def set_option(lines, key, value):
    for i, line in enumerate(lines):
        if re.match(rf"\s*{key}\s*:", line):
            lines[i] = f"{key}: {value}"
            return
    lines.append(f"{key}: {value}")


def main():
    path, out, mode = sys.argv[1:4]
    lines = open(path, encoding="utf-8").read().split("\n")
    first = next((i for i, l in enumerate(lines) if re.match(r"^/[^/]", l)), len(lines))
    head, blocks = lines[:first], []
    for line in lines[first:]:
        if re.match(r"^/[^/]", line):
            blocks.append([line])
        else:
            blocks[-1].append(line)

    while head and head[-1].strip() == "":
        head.pop()
    set_option(head, "timeout", "3")
    set_option(head, "quiet", "no")
    # no editing entries at the boot menu: the TPM unlocks the disk by itself, so e.g.
    # "init=/bin/sh" added there would be a way in without any password (with Secure Boot
    # and a sealed config Limine switches it off anyway)
    set_option(head, "editor_enabled", "no")
    win = next((b[0][1:] for b in blocks if "windows" in b[0].lower()), None)
    if win:
        set_option(head, "default_entry", re.sub(r"([/\\#])", r"\\\1", win))
        set_option(head, "remember_last_entry", "no") # else the last booted system would win
        print(f"  Standard: {win}")
    else:
        print("  Standard: kein Windows-Eintrag gefunden – unverändert")
    head.append("")

    old = [b for b in blocks if b[0].startswith("/Notfallmodus")]
    if mode == "uki" and old and not any("arch-linux-recovery.efi" in l for l in old[0]):
        blocks.remove(old[0]) # the kernel+initramfs copy: now its own image
        old = []
    if old:
        print("  Notfallmodus: schon vorhanden")
    elif mode == "uki":
        blocks.append([TITLE, "    protocol: efi", "    path: boot():/EFI/Linux/arch-linux-recovery.efi", ""])
        print("  Notfallmodus: eigenes Kernel-Image (LTS)")
    else:
        linux = [b for b in blocks if any(re.match(r"\s*protocol:\s*linux\s*$", l) for l in b)]
        pick = next((b for b in linux if any("vmlinuz-linux-lts" in l for l in b)), linux[0] if linux else None)
        if pick is None:
            print("  Notfallmodus: kein Linux-Eintrag gefunden – nicht angelegt")
        else:
            copy = [TITLE]
            for line in pick[1:]:
                if re.match(r"^//", line):
                    break  # sub-entries stay with the original
                m = re.match(r"(\s*(?:kernel_)?cmdline\s*:\s*)(.*)$", line)
                if m:
                    args = [a for a in m.group(2).split() if a != "quiet" and not a.startswith("systemd.unit=")]
                    line = m.group(1) + " ".join(args + ["systemd.unit=multi-user.target"])
                copy.append(line)
            while copy[-1].strip() == "":
                copy.pop()
            blocks.append(copy + [""])
            print(f"  Notfallmodus: Kopie von „{pick[0][1:]}“ bis zur Textanmeldung")

    for b in blocks[:-1]:
        if b[-1].strip() != "":
            b.append("")
    text = "\n".join(head + [l for b in blocks for l in b]).rstrip("\n") + "\n"
    open(out, "w", encoding="utf-8").write(text)


main()
