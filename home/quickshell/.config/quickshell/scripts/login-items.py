#!/usr/bin/env python3
"""Login items for System Settings → Anmeldeobjekte (like on a Mac).

    login-items.py list                 JSON: {"open": [...], "background": [...]}
    login-items.py add <desktop id>     open this app at login
    login-items.py remove <desktop id>  not any more
    login-items.py set <file> on|off    a background item on or off

"Beim Anmelden öffnen": apps chosen here – a copy of their start entry in
~/.config/autostart, marked X-Riptide-Login-Item (sandboxed apps keep their sandbox: the
copy starts them the same way the dock does).
"Im Hintergrund": what else starts at login without a window – system services from
/etc/xdg/autostart (off = a user entry of the same name with Hidden=true, the XDG way)
and apps that asked for it through the Background portal (<app>.riptide.desktop).
Systemd reads all this at login (xdg-autostart generator): changes apply from the next.
"""

import configparser
import json
import os
import re
import sys
from pathlib import Path

HOME = Path.home()
USER = HOME / ".config/autostart"
SYSTEM = Path("/etc/xdg/autostart")
APP_DIRS = [HOME / ".local/share/applications", Path("/usr/local/share/applications"),
            Path("/usr/share/applications")]
MARK = "X-Riptide-Login-Item"
VALID = re.compile(r"^[A-Za-z0-9._-]+$")


def read(path):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.optionxform = str  # keys keep their case
    try:
        parser.read(path, encoding="utf-8")
    except (configparser.Error, OSError):
        return {}
    return dict(parser["Desktop Entry"]) if parser.has_section("Desktop Entry") else {}


def desktops():
    """What this session calls itself (OnlyShowIn/NotShowIn are checked against it)."""
    return [d for d in os.environ.get("XDG_CURRENT_DESKTOP", "").split(":") if d]


def applies(entry):
    """Would the autostart generator start this entry in our session?"""
    ours = set(desktops())
    only = [d for d in entry.get("OnlyShowIn", "").split(";") if d]
    never = [d for d in entry.get("NotShowIn", "").split(";") if d]
    if only and not ours & set(only):
        return False
    return not (never and ours & set(never))


def off(entry):
    return entry.get("Hidden", "").lower() == "true" or entry.get("X-GNOME-Autostart-enabled", "").lower() == "false"


def listing():
    opened, background = [], []
    user = {p.name: read(p) for p in sorted(USER.glob("*.desktop"))}
    for name, entry in user.items():
        if entry.get(MARK) == "true":
            opened.append({"id": name.removesuffix(".desktop"), "name": entry.get("Name", name)})
        elif not (SYSTEM / name).exists():  # an app's own entry (Background portal …)
            background.append({"file": name, "name": entry.get("Name", name), "comment": entry.get("Comment", ""),
                               "icon": entry.get("Icon", ""), "enabled": not off(entry), "kind": "app"})
    for path in sorted(SYSTEM.glob("*.desktop")):
        entry = read(path)
        # (X-systemd-skip: it runs as a systemd service of its own, not from here)
        if not entry or not applies(entry) or off(entry) or entry.get("X-systemd-skip", "").lower() == "true":
            continue
        override = user.get(path.name)
        background.append({"file": path.name, "name": entry.get("Name", path.name), "comment": entry.get("Comment", ""),
                           "icon": entry.get("Icon", ""), "enabled": not (override and off(override)), "kind": "system"})
    return {"open": opened, "background": background}


def app_entry(app):
    for folder in APP_DIRS:
        path = folder / f"{app}.desktop"
        if path.is_file():
            return path
    return None


def add(app):
    source = app_entry(app)
    if not source:
        sys.exit(f"unknown app: {app}")
    lines = source.read_text(encoding="utf-8").splitlines()
    out, in_main = [], False
    for line in lines:
        if line.startswith("["):
            if in_main:
                out.append(f"{MARK}=true")
            in_main = line.strip() == "[Desktop Entry]"
            if not in_main:
                break  # actions etc. are not needed to start it
        elif in_main and re.match(r"^(Hidden|X-GNOME-Autostart-enabled|OnlyShowIn|NotShowIn|" + MARK + r")\s*=", line):
            continue
        out.append(line)
    if in_main:
        out.append(f"{MARK}=true")
    USER.mkdir(parents=True, exist_ok=True)
    (USER / f"{app}.desktop").write_text("\n".join(out) + "\n", encoding="utf-8")


def remove(app):
    path = USER / f"{app}.desktop"
    if path.is_file() and read(path).get(MARK) == "true":
        path.unlink()


def set_state(name, on):
    user = USER / name
    if (SYSTEM / name).exists():
        # a system entry: switched off by a user entry of the same name
        if on:
            if user.is_file() and read(user).get("Hidden", "").lower() == "true":
                user.unlink()
        else:
            USER.mkdir(parents=True, exist_ok=True)
            user.write_text(f"[Desktop Entry]\nType=Application\nName={read(SYSTEM / name).get('Name', name)}\n"
                            "Hidden=true\n", encoding="utf-8")
    elif user.is_file():
        text = re.sub(r"(?m)^Hidden\s*=.*\n?", "", user.read_text(encoding="utf-8"))
        if not on:
            text = text.replace("[Desktop Entry]\n", "[Desktop Entry]\nHidden=true\n", 1)
        user.write_text(text, encoding="utf-8")


def main():
    args = sys.argv[1:]
    if args == ["list"]:
        print(json.dumps(listing(), ensure_ascii=False))
    elif len(args) == 2 and args[0] in ("add", "remove") and VALID.match(args[1]):
        (add if args[0] == "add" else remove)(args[1])
    elif len(args) == 3 and args[0] == "set" and VALID.match(args[1]) and args[1].endswith(".desktop") and args[2] in ("on", "off"):
        set_state(args[1], args[2] == "on")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
