#!/usr/bin/env python3
"""Installed apps for System Settings → Apps (JSON on stdout).

    apps-info.py                             every app with launcher: source, package, size,
                                             whether it may be removed
    apps-info.py leftovers <desktop-id> <package> <name>
                                             folders with the app's personal data in the
                                             home folder (for removing it completely)
"""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
ENV = dict(os.environ, LC_ALL="C")

# Part of the system, never removed here (the same list the root helper checks)
def protected_patterns():
    try:
        lines = Path("/usr/local/share/riptide/protected-packages").read_text().splitlines()
    except OSError:
        lines = []
    patterns = [l.strip() for l in lines if l.strip() and not l.startswith("#")]
    return re.compile("^(" + "|".join(patterns) + ")$") if patterns else re.compile("(?!)")


PROTECTED = protected_patterns()

# Folders of our own desktop – never offered as "leftovers"
OWN = {"macos", "hypr", "quickshell", "desktop-theme", "appstore", "uwsm", "systemd", "gtk-3.0", "gtk-4.0",
       "qt5ct", "qt6ct", "kitty", "applications", "icons", "fonts", "trash", "pulse", "dconf"}

UNITS = {"B": 1, "KiB": 1024, "MiB": 1024 ** 2, "GiB": 1024 ** 3}


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True, env=ENV).stdout


def du(path):
    out = run("du", "-sb", str(path)).split("\t", 1)[0]
    return int(out) if out.isdigit() else 0


def apps():
    result = []

    # pacman: packages that ship a launcher
    owners = {}
    for line in run("pacman", "-Ql").splitlines():
        pkg, _, path = line.partition(" ")
        if path.startswith("/usr/share/applications/") and path.endswith(".desktop") and "/" not in path[24:]:
            owners[Path(path).name] = pkg
    explicit = set(run("pacman", "-Qqe").split())
    info = {}
    if owners:
        name = None
        for line in run("pacman", "-Qi", *sorted(set(owners.values()))).splitlines():
            key, _, value = line.partition(":")
            key, value = key.strip(), value.strip()
            if key == "Name":
                name = value
                info[name] = {"size": 0, "requiredBy": []}
            elif key == "Installed Size" and name:
                number, unit = value.split()
                info[name]["size"] = int(float(number) * UNITS.get(unit, 1))
            elif key == "Required By" and name and value != "None":
                info[name]["requiredBy"] = value.split()
    for desktop, pkg in owners.items():
        result.append({
            "desktop": desktop, "source": "pacman", "pkg": pkg,
            "size": info.get(pkg, {}).get("size", 0),
            "explicit": pkg in explicit,
            "requiredBy": info.get(pkg, {}).get("requiredBy", []),
            "protected": bool(PROTECTED.match(pkg)),
        })

    # Apps from their maker's release archive (archive_apps.py: Zen …)
    try:
        archives = json.loads((Path(__file__).resolve().parents[1] / "data/archive-apps.json").read_text())
    except (OSError, ValueError):
        archives = {}
    for app_id, spec in archives.items():
        folder = HOME / ".local/share/macos/apps" / app_id
        if not app_id.startswith("_") and (folder / ".riptide-release").is_file():
            result.append({
                "desktop": app_id + ".desktop", "source": "archive", "pkg": spec.get("repo", app_id),
                "size": du(folder), "explicit": True, "requiredBy": [], "protected": False,
            })

    # Our own apps (dotfiles)
    for path in (HOME / ".local/share/applications").glob("org.riptide.*.desktop"):
        result.append({"desktop": path.name, "source": "own", "pkg": "", "size": 0,
                       "explicit": False, "requiredBy": [], "protected": True})
    return result


def leftovers(desktop_id, pkg, name):
    """Existing folders named after the app in the usual places of the home folder."""
    base = desktop_id.removesuffix(".desktop")
    names = {n.lower() for n in (pkg, base, name, name.replace(" ", ""), name.replace(" ", "-")) if n}
    names -= OWN
    places = [HOME / ".config", HOME / ".local/share", HOME / ".local/state", HOME / ".cache", HOME]
    found = []
    for place in places:
        if not place.is_dir():
            continue
        for entry in place.iterdir():
            candidate = entry.name.lower().lstrip(".") if place == HOME else entry.name.lower()
            if place == HOME and not entry.name.startswith("."):
                continue  # in the home folder itself only hidden folders like ~/.thunderbird
            if candidate in names and entry.is_dir():
                found.append(entry)
    own_files = set(run("pacman", "-Qlq", pkg).split()) if pkg and "." not in pkg else set()

    def shared(path):
        """Named like another program on this computer (e.g. ~/.claude of Claude Code)?"""
        name = path.name.lstrip(".").lower()
        other = shutil.which(name)
        return bool(other) and other not in own_files

    return [{"path": str(p), "size": du(p), "shared": shared(p)} for p in sorted(set(found))]


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "leftovers":
        args = sys.argv[2:] + ["", "", ""]
        print(json.dumps(leftovers(args[0], args[1], args[2])))
    else:
        print(json.dumps(apps()))
