"""The trash empties itself, like on a Mac ("Papierkorb automatisch leeren", System
Settings → Speicher; settings.json storage.empty_trash_after_30_days): what has been in
the trash for more than 30 days is deleted. The session service runs it shortly after
login and then once a day. Only the home folder's trash (the XDG trash spec:
files/ and info/<name>.trashinfo with its DeletionDate).
"""

import json
import shutil
from datetime import datetime, timedelta
from pathlib import Path

from gi.repository import GLib

TRASH = Path.home() / ".local/share/Trash"
SETTINGS = Path.home() / ".config/macos/settings.json"
DAYS = 30


def enabled():
    try:
        return json.loads(SETTINGS.read_text()).get("storage", {}).get("empty_trash_after_30_days", False) is True
    except (OSError, ValueError):
        return False


def empty_old(now=None):
    """Delete what was trashed more than 30 days ago; returns how many items went"""
    limit = (now or datetime.now()) - timedelta(days=DAYS)
    gone = 0
    for info in (TRASH / "info").glob("*.trashinfo"):
        try:
            date = next(l.split("=", 1)[1].strip() for l in info.read_text().splitlines() if l.startswith("DeletionDate="))
            if datetime.fromisoformat(date) > limit:
                continue
        except (OSError, ValueError, StopIteration):
            continue
        item = TRASH / "files" / info.name.removesuffix(".trashinfo")
        try:
            if item.is_dir() and not item.is_symlink():
                shutil.rmtree(item)
            elif item.exists() or item.is_symlink():
                item.unlink()
            info.unlink()
            gone += 1
        except OSError as e:
            print(f"trash: {item.name}: {e}", flush=True)
    return gone


def check():
    if enabled():
        gone = empty_old()
        if gone:
            print(f"trash: {gone} old item(s) deleted", flush=True)
    return True


def start():
    GLib.timeout_add_seconds(120, lambda: (check(), False)[1])
    GLib.timeout_add_seconds(24 * 3600, check)
