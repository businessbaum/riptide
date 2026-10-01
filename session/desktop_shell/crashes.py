"""Apps that crash, watched by the session service (session.py): when an app ends with a
crash (systemd-coredump writes it down), a notification says so, like the macOS dialog
"„Discord“ wurde unerwartet beendet", with "Erneut öffnen".

Which app it was comes from the systemd scope the crashed process ran in:
    app-sandbox-<app>-<n>.scope     started through our sandbox
    app-<launcher>-<app>-<hex>.scope  started from the dock/Launchpad (uwsm app)
Only when the whole app is gone (its scope ended): a crashed helper process of an app that
keeps running (a browser's GPU process) is not worth a notice. The shell itself (qs) and
anything outside an app scope (Hyprland, services) are left to riptide-report.
"""

import json
import re
import subprocess
from pathlib import Path

from gi.repository import Gio, GLib

from desktop_shell import sandbox

COREDUMP = "fc2e22bc6ee647b6b90729ab34a250b1"  # MESSAGE_ID of systemd-coredump's message
SCOPE = re.compile(r"^app-(?:sandbox-(?P<sandboxed>.+)-\d+|[^-]+-(?P<launched>.+)-[0-9a-f]{8})\.scope$")
NOT_APPS = {"qs"}  # the shell: it restarts by itself (riptide-shell.service)
ICON_BASES = [Path.home() / ".local/share/icons", Path("/usr/share/icons")]
ICON_SIZES = ["scalable", "512x512", "256x256", "128x128", "96x96", "64x64", "48x48"]


def app_of(unit):
    """The app's desktop id from its scope's name, or None"""
    m = SCOPE.match(unit or "")
    if not m:
        return None
    app = next(v for v in m.groupdict().values() if v)
    app = re.sub(r"\\x([0-9a-f]{2})", lambda x: chr(int(x.group(1), 16)), app)  # systemd escapes "-" as \x2d
    return None if app in NOT_APPS else app


def icon_path(name):
    """A file for an icon name (the notification shows a file, not a name the shell would
    take for an app)"""
    if not name or name.startswith("/"):
        return name or ""
    for base in ICON_BASES:
        for size in ICON_SIZES:
            for ext in ("svg", "png"):
                path = base / "hicolor" / size / "apps" / f"{name}.{ext}"
                if path.is_file():
                    return str(path)
    for ext in ("svg", "png"):
        path = Path("/usr/share/pixmaps") / f"{name}.{ext}"
        if path.is_file():
            return str(path)
    return ""


def entry_of(app):
    flatpak = [Path.home() / ".local/share/flatpak/exports/share/applications",
               Path("/var/lib/flatpak/exports/share/applications")]
    for folder in sandbox.ENTRY_DIRS + flatpak:
        path = folder / f"{app}.desktop"
        if path.is_file():
            return sandbox.read_entry(path)
    return {}


class Crashes:
    def __init__(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.actions = {}  # notification id → app to open again
        self.bus.signal_subscribe(None, "org.freedesktop.Notifications", "ActionInvoked",
                                  "/org/freedesktop/Notifications", None, Gio.DBusSignalFlags.NONE,
                                  self.on_action)

    def start(self):
        try:
            proc = Gio.Subprocess.new(["journalctl", "--follow", "--lines=0", "--output=json",
                                       f"MESSAGE_ID={COREDUMP}"], Gio.SubprocessFlags.STDOUT_PIPE)
        except GLib.Error as e:
            print(f"crashes: journalctl: {e.message}", flush=True)
            return
        self.proc = proc
        self.lines = Gio.DataInputStream.new(proc.get_stdout_pipe())
        self.read_next()

    def read_next(self):
        self.lines.read_line_async(GLib.PRIORITY_DEFAULT, None, self.on_line)

    def on_line(self, stream, result):
        try:
            line, _ = stream.read_line_finish_utf8(result)
        except GLib.Error as e:
            print(f"crashes: {e.message}", flush=True)
            return
        if line is None:
            print("crashes: journalctl ended", flush=True)
            return
        try:
            self.crashed(json.loads(line))
        except Exception as e:  # one odd entry must not end the watch
            print(f"crashes: {type(e).__name__}: {e}", flush=True)
        self.read_next()

    def crashed(self, record):
        unit = record.get("COREDUMP_USER_UNIT", "")
        app = app_of(unit)
        what = f"{record.get('COREDUMP_COMM', '?')} ({record.get('COREDUMP_SIGNAL_NAME', '?')}) in {unit or '?'}"
        print(f"crashes: {what}", flush=True)
        if not app:
            return
        # the whole app gone? (its scope ends a moment after its last process)
        GLib.timeout_add(1500, lambda: (self.tell(app, unit), False)[1])

    def tell(self, app, unit):
        state = subprocess.run(["systemctl", "--user", "show", "-P", "ActiveState", unit],
                               capture_output=True, text=True).stdout.strip()
        if state == "active":
            print(f"crashes: {app} keeps running – no notice", flush=True)
            return
        entry = entry_of(app)
        if not entry or entry.get("NoDisplay", "").lower() == "true":
            print(f"crashes: {app} is no app of the launcher – no notice", flush=True)
            return
        name = entry.get("Name[de]") or entry.get("Name") or app
        try:
            reply = self.bus.call_sync(
                "org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications",
                "Notify", GLib.Variant("(susssasa{sv}i)", (
                    "System", 0, icon_path(entry.get("Icon", "")),
                    f"„{name}“ wurde unerwartet beendet",
                    "Du kannst die App erneut öffnen. Was schiefging, steht im Fehlerbericht.",
                    ["default", "Erneut öffnen", "reopen", "Erneut öffnen"], {}, 0)),
                GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, 5000, None)
            self.actions[reply.unpack()[0]] = app
        except GLib.Error as e:
            print(f"crashes: notify: {e.message}", flush=True)

    def on_action(self, _bus, _sender, _path, _interface, _signal, params):
        nid, _action = params.unpack()
        app = self.actions.pop(nid, None)
        if app:
            subprocess.Popen(["uwsm", "app", "--", f"{app}.desktop"], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
