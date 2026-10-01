#!/usr/bin/env python3
"""How safe this computer is set up, for System Settings → Datenschutz & Sicherheit:
disk encryption, Secure Boot, the firewall and what it lets in, remote login (SSH), the
newest snapshot. JSON, read without root; changes go through riptide-helper.
"""

import json
import re
import subprocess
from pathlib import Path


def run(*argv):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=10)
        return p.returncode, p.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return 1, ""


def encryption():
    """Is the root file system on an encrypted device (LUKS)?"""
    _, source = run("findmnt", "-no", "SOURCE", "/")
    device = re.sub(r"\[.*\]$", "", source)
    _, types = run("lsblk", "-sno", "TYPE", device)  # the device and what it sits on
    return "crypt" in types.split()


def secure_boot():
    for f in Path("/sys/firmware/efi/efivars").glob("SecureBoot-*"):
        try:
            return f.read_bytes()[-1] == 1
        except OSError:
            return None
    return None  # no UEFI


def firewall():
    """What the firewall lets in – from its zone file: asking firewalld itself would want the
    administrator's password (polkit: config.info). riptide-helper changes the running
    and the saved rules together, so the file tells both."""
    _, state = run("systemctl", "is-active", "firewalld.service")
    zone = "public"
    try:
        m = re.search(r"^DefaultZone=(\S+)", Path("/etc/firewalld/firewalld.conf").read_text(), re.M)
        zone = m.group(1) if m else zone
    except OSError:
        pass
    services = []
    for folder in ("/etc/firewalld/zones", "/usr/lib/firewalld/zones"):
        try:
            services = re.findall(r'<service name="([^"]+)"', (Path(folder) / f"{zone}.xml").read_text())
            break
        except OSError:
            continue
    return {"running": state == "active", "zone": zone, "services": services}


def remote_login():
    _, enabled = run("systemctl", "is-enabled", "sshd.service")
    _, active = run("systemctl", "is-active", "sshd.service")
    return {"enabled": enabled == "enabled", "active": active == "active"}


def snapshot():
    """The newest snapshot of the system (snapper; needs ALLOW_USERS, setup-os.sh)"""
    code, out = run("snapper", "--csvout", "-c", "root", "list", "--columns", "number,date,description",
                    "--disable-used-space")
    if code != 0:
        return {"allowed": False}
    rows = [r.split(",", 2) for r in out.splitlines()[1:] if r and not r.startswith("0,")]
    if not rows:
        return {"allowed": True, "date": "", "description": ""}
    number, date, description = rows[-1] + [""] * (3 - len(rows[-1]))
    return {"allowed": True, "date": date, "description": description}


print(json.dumps({
    "encryption": encryption(),
    "secureBoot": secure_boot(),
    "firewall": firewall(),
    "remoteLogin": remote_login(),
    "snapshot": snapshot(),
}, ensure_ascii=False))
