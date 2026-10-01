#!/usr/bin/env python3
"""The idle behaviour (hypridle) from System Settings → Energie: writes
~/.local/state/macos/hypridle.conf from settings.json "energy" (minutes, 0 = never):

    lock          lock the screen            (default 10)
    display_off   turn the screens off       (default 12)
    sleep         go to sleep (suspend)      (default 0: never)

hypridle.service runs this before it starts (drop-in hypridle.service.d/riptide.conf) and
reads the file; System Settings runs it and restarts hypridle after a change.
Videos and calls keep the screen on (their idle inhibitors); "Computer wachhalten" in the
control centre inhibits all of it.
"""

import json
from pathlib import Path

SETTINGS = Path.home() / ".config/macos/settings.json"
OUT = Path.home() / ".local/state/macos/hypridle.conf"
DEFAULTS = {"lock": 10, "display_off": 12, "sleep": 0}


def minutes(energy, key):
    try:
        return max(0, int(energy.get(key, DEFAULTS[key])))
    except (TypeError, ValueError):
        return DEFAULTS[key]


def main():
    try:
        energy = json.loads(SETTINGS.read_text()).get("energy", {})
    except (OSError, ValueError):
        energy = {}
    lock, off, sleep = (minutes(energy, k) for k in ("lock", "display_off", "sleep"))

    parts = ["""# Written by ~/.config/quickshell/scripts/hypridle-config.py from System Settings → Energie.
# Changes here are lost: change the settings instead.

general {
    lock_cmd = qs ipc call lock now || pidof hyprlock || hyprlock
    before_sleep_cmd = loginctl lock-session
    after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({ action = "on" })'
    ignore_dbus_inhibit = false   # videos and calls keep the screen on
}
"""]
    if lock:
        parts.append(f"""
listener {{
    timeout = {lock * 60}
    on-timeout = loginctl lock-session
}}
""")
    if off:
        parts.append(f"""
listener {{
    timeout = {off * 60}
    on-timeout = hyprctl dispatch 'hl.dsp.dpms({{ action = "off" }})'
    on-resume = hyprctl dispatch 'hl.dsp.dpms({{ action = "on" }})'
}}
""")
    if sleep:
        parts.append(f"""
listener {{
    timeout = {sleep * 60}
    on-timeout = systemctl suspend
}}
""")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    tmp = OUT.with_suffix(".tmp")
    tmp.write_text("".join(parts))
    tmp.replace(OUT)


if __name__ == "__main__":
    main()
