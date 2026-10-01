#!/usr/bin/env python3
"""What System Settings → Allgemein shows about time, the computer's name and language,
as JSON. Read without root; the page changes things with timedatectl, hostnamectl and
localectl (systemd asks for the password through our polkit dialog).

    general.py            everything below
    general.py zones      the time zones only (a long list, loaded when searched):
                          [[zone, "UTC+2"], …]
"""

import json
import subprocess
import sys
from datetime import datetime
from zoneinfo import ZoneInfo


def run(*argv):
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def pairs(text):
    return dict(line.split("=", 1) for line in text.splitlines() if "=" in line)


def offset(moment):
    """UTC+2, UTC−3:30, UTC"""
    minutes = int(moment.utcoffset().total_seconds() // 60)
    if minutes == 0:
        return "UTC"
    sign = "+" if minutes > 0 else "\u2212"
    h, m = divmod(abs(minutes), 60)
    return f"UTC{sign}{h}" + (f":{m:02d}" if m else "")


def zones():
    found = []
    for zone in run("timedatectl", "list-timezones").split():
        try:
            found.append([zone, offset(datetime.now(ZoneInfo(zone)))])
        except (KeyError, ValueError, OSError):
            pass
    return found


def locale_conf():
    try:
        with open("/etc/locale.conf") as f:
            return {k: v.strip('"') for k, v in pairs(f.read()).items()}
    except OSError:
        return {}


def main():
    if sys.argv[1:] == ["zones"]:
        print(json.dumps(zones()))
        return
    time = pairs(run("timedatectl", "show"))
    sync = pairs(run("timedatectl", "show-timesync"))
    try:
        host = json.loads(run("hostnamectl", "--json=short") or "{}")
    except ValueError:
        host = {}
    # generated locales, as de_DE.UTF-8 (what locale.conf takes)
    available = sorted({l.replace(".utf8", ".UTF-8") for l in run("locale", "-a").split() if l.endswith(".utf8")
                        and "_" in l})
    print(json.dumps({
        "timezone": time.get("Timezone", ""),
        "offset": offset(datetime.now().astimezone()),
        "ntp": time.get("NTP") == "yes",
        "canNtp": time.get("CanNTP") == "yes",
        "synced": time.get("NTPSynchronized") == "yes",
        "localRtc": time.get("LocalRTC") == "yes",
        "server": sync.get("ServerName", ""),
        "hostname": host.get("StaticHostname") or host.get("Hostname") or "",
        "prettyName": host.get("PrettyHostname") or "",
        # other devices find it as <hostname>.local while Avahi runs
        "mdns": run("systemctl", "is-active", "avahi-daemon.service").strip() == "active",
        "locale": locale_conf(),
        "locales": available,
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
