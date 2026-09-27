#!/usr/bin/env python3
"""What the app menu's "Über „App“" shows (AppInfoWindow.qml), as JSON:
where the app comes from (package, version, size, website) and whether it runs in a
sandbox. Only reads: the start entry, pacman's database, flatpak.
    app-info.py <desktop id>"""
import configparser
import json
import os
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
MARK = "X-Sandbox-Override"


def entry_file(app):
    dirs = [Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share"))]
    dirs += [Path(d) for d in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":") if d]
    for d in dirs:
        path = d / "applications" / f"{app}.desktop"
        if path.exists():
            return path
    return None


def read_entry(path):
    parser = configparser.RawConfigParser(strict=False, interpolation=None)
    parser.optionxform = str
    try:
        parser.read(path, encoding="utf-8")
    except (OSError, configparser.Error):
        return {}
    return dict(parser["Desktop Entry"]) if parser.has_section("Desktop Entry") else {}


def run(*args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=10,
                              env={**os.environ, "LC_ALL": "C"}).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def fields(text):
    out = {}
    for line in text.splitlines():
        key, sep, value = line.partition(":")
        key = key.strip()
        # "Key: value" (flatpak indents its keys, pacman pads them)
        if sep and key and (" " not in key or key == "Installed Size"):
            out[key] = value.strip().replace("\u00a0", " ")
    return out


def main():
    app = sys.argv[1] if len(sys.argv) > 1 else ""
    info = {"package": "", "version": "", "size": "", "url": "", "source": "", "sandbox": "none", "comment": ""}
    path = entry_file(app)
    if not path:
        print(json.dumps(info))
        return
    entry = read_entry(path)
    info["comment"] = entry.get("Comment[de]") or entry.get("Comment", "")
    source = path
    if entry.get(MARK) == "true":
        info["sandbox"] = "riptide"
        source = Path(entry.get("X-Sandbox-Source", path))

    if "flatpak" in str(path.resolve()) or "flatpak run" in entry.get("Exec", ""):
        info.update(source="flatpak", sandbox="flatpak", package=app)
        f = fields(run("flatpak", "info", app))
        info["version"] = f.get("Version", "")
        info["size"] = f.get("Installed Size", "")
        info["url"] = "https://flathub.org/apps/" + app
    elif path.is_symlink() and "dotfiles" in str(path.resolve()):
        info["source"] = "riptide"  # our own apps (System Settings, App Store …)
    else:
        owner = run("pacman", "-Qo", str(source.resolve())).split(" is owned by ")
        if len(owner) == 2:
            package = owner[1].split()[0]
            f = fields(run("pacman", "-Qi", package))
            info.update(source="pacman", package=package, version=f.get("Version", ""),
                        size=f.get("Installed Size", ""), url=f.get("URL", ""))
            if not info["comment"]:
                info["comment"] = f.get("Description", "")
    print(json.dumps(info, ensure_ascii=False))


main()
