"""The machine's health, watched by the session service (session.py): now and then it looks,
and when something is wrong it says so in a notification with a button, like the warnings
of macOS:

    disk almost full        less than 10 % or 10 GB free (critical below 3 %)
    a disk reports trouble  smartd's warnings (SMART) in the journal
    file system errors      btrfs error counters went up
    a service failed        systemd, system and session

Each warning comes at most once a day while it holds (~/.local/state/macos/health.json);
the button opens what helps (System Settings → Speicher, the disk utility, the report of
everything that went wrong: riptide-report).
"""

import json
import os
import subprocess
import time
from pathlib import Path

from gi.repository import Gio, GLib

from desktop_shell import paths

STATE = Path.home() / ".local/state/macos/health.json"
AGAIN_AFTER = 24 * 3600  # seconds until a warning that still holds comes again
SETTINGS = str(paths.SHELL / "scripts/system-settings.sh")


def run(argv):
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


class Health:
    def __init__(self):
        try:
            self.state = json.loads(STATE.read_text())
        except (OSError, ValueError):
            self.state = {}
        self.state.setdefault("shown", {})
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.actions = {}  # notification id → command of its button
        self.bus.signal_subscribe(None, "org.freedesktop.Notifications", "ActionInvoked",
                                  "/org/freedesktop/Notifications", None, Gio.DBusSignalFlags.NONE,
                                  self.on_action)

    def start(self):
        GLib.timeout_add_seconds(60, lambda: (self.check(), False)[1])
        GLib.timeout_add_seconds(15 * 60, lambda: (self.check(), True)[1])

    # ------------------------------------------------------------ checks

    def disk(self):
        found = []
        seen = set()
        for mount in ("/", "/home"):
            try:
                st = os.statvfs(mount)
            except OSError:
                continue
            if (st.f_fsid, st.f_blocks) in seen:
                continue  # the same file system (btrfs subvolumes)
            seen.add((st.f_fsid, st.f_blocks))
            free, total = st.f_bavail * st.f_frsize, st.f_blocks * st.f_frsize
            share = free / total if total else 1
            if share < 0.10 or free < 10 * 1024**3:
                found.append({
                    "key": f"disk:{mount}", "critical": share < 0.03,
                    "title": "Dein Speicher ist fast voll",
                    "text": f"Nur noch {free / 1024**3:.0f} GB frei ({share * 100:.0f} %). Lösche nicht mehr Benötigtes, "
                            "damit das System zuverlässig läuft.",
                    "button": "Speicher verwalten", "command": [SETTINGS, "storage"]})
        return found

    def smart(self):
        since = self.state.get("smart_since", "-1h")
        out = run(["journalctl", "--no-pager", "-o", "cat", "-p", "warning", "-u", "smartd", "--since", since])
        self.state["smart_since"] = time.strftime("%Y-%m-%d %H:%M:%S")
        lines = [l for l in out.splitlines() if l.strip() and not l.startswith("--")]
        if not lines:
            return []
        return [{"key": "smart", "critical": True, "title": "Eine Festplatte meldet Probleme",
                 "text": lines[-1][:200] + " – sichere wichtige Daten.",
                 "button": "Laufwerke öffnen", "command": ["gnome-disks"]}]

    def btrfs(self):
        errors = 0
        for stats in Path("/sys/fs/btrfs").glob("*/devinfo/*/error_stats"):
            try:
                errors += sum(int(line.split()[1]) for line in stats.read_text().splitlines() if line.strip())
            except (OSError, ValueError, IndexError):
                pass
        before = self.state.get("btrfs_errors", 0)
        self.state["btrfs_errors"] = errors
        if errors <= before:
            return []
        return [{"key": f"btrfs:{errors}", "critical": True, "title": "Fehler im Dateisystem",
                 "text": f"Das Dateisystem hat {errors - before} neue Fehler gezählt (Lesen, Schreiben oder "
                         "beschädigte Daten). Sichere wichtige Daten.",
                 "button": "Laufwerke öffnen", "command": ["gnome-disks"]}]

    def failed(self):
        found = []
        for scope, argv in (("System", ["systemctl", "--failed", "--no-legend", "--plain"]),
                            ("Sitzung", ["systemctl", "--user", "--failed", "--no-legend", "--plain"])):
            for line in run(argv).splitlines():
                unit = line.split()[0] if line.split() else ""
                if unit:
                    found.append({"key": f"failed:{unit}", "critical": False,
                                  "title": "Ein Dienst ist ausgefallen",
                                  "text": f"{unit} ({scope}) läuft nicht mehr.",
                                  "button": "Bericht öffnen", "command": ["sh", "-c", "riptide-report --quiet && "
                                              "xdg-open ~/.local/state/macos/reports/$(date +%F).md"]})
        return found

    # ------------------------------------------------------------ telling the user

    def check(self):
        try:
            warnings = self.disk() + self.smart() + self.btrfs() + self.failed()
        except Exception as e:  # a check must never take the service down
            print(f"health: {type(e).__name__}: {e}", flush=True)
            warnings = []
        now = time.time()
        holding = {w["key"] for w in warnings}
        # warnings that no longer hold may come again when they do
        self.state["shown"] = {k: t for k, t in self.state["shown"].items() if k in holding}
        for w in warnings:
            if now - self.state["shown"].get(w["key"], 0) >= AGAIN_AFTER:
                self.notify(w)
                self.state["shown"][w["key"]] = now
        self.save()

    def notify(self, w):
        hints = {"urgency": GLib.Variant("y", 2 if w["critical"] else 1)}
        try:
            reply = self.bus.call_sync(
                "org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications",
                "Notify", GLib.Variant("(susssasa{sv}i)", ("System", 0, "dialog-warning", w["title"], w["text"],
                                                           ["default", w["button"], "open", w["button"]], hints, 0)),
                GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, 5000, None)
            self.actions[reply.unpack()[0]] = w["command"]
        except GLib.Error as e:
            print(f"health: notify: {e.message}", flush=True)

    def on_action(self, _bus, _sender, _path, _interface, _signal, params):
        nid, _action = params.unpack()
        command = self.actions.pop(nid, None)
        if command:
            subprocess.Popen(command, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def save(self):
        STATE.parent.mkdir(parents=True, exist_ok=True)
        tmp = STATE.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.state, indent=1))
        tmp.replace(STATE)
