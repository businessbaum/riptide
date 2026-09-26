"""Software updates, looked for by the session service (session.py) in the background, like
the macOS Softwareupdate: 5 minutes after login, then every 6 hours, and again after
packages changed:

    system packages   checkupdates (pacman-contrib: a copy of the package lists, no root)
    Flatpak apps      flatpak remote-ls --updates

and whether what runs is older than what is installed:

    reboot    the kernel or the NVIDIA driver were updated (the running ones are old)
    relogin   Hyprland was updated (the running compositor is old; our plugin is rebuilt
              at the next login, hypr/modules/autostart.lua)

All of it in ~/.local/state/macos/updates.json (the App Store shows it); the shell gets
{"event": "updates", "count": n, "reboot": bool, "relogin": bool} for the dock badge of
the App Store. New updates and a needed restart are told once in a notification.
Nothing here needs root: installing stays in the App Store (riptide-helper).
"""

import json
import os
import re
import subprocess
import time
from pathlib import Path

from gi.repository import Gio, GLib

STATE = Path.home() / ".local/state/macos/updates.json"
SCRIPTS = Path.home() / ".config/quickshell/scripts"
EVERY = 6 * 3600
NOTIFY_AGAIN = 12 * 3600  # new updates are told at most this often


def run(argv):
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=20).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def needs():
    """{"reboot": bool, "relogin": bool, "why": [...]} – what an update left waiting"""
    why = []
    kernel = os.uname().release
    if not Path(f"/usr/lib/modules/{kernel}").is_dir():
        why.append("kernel")
    loaded = Path("/sys/module/nvidia/version")
    if loaded.is_file() and "kernel" not in why:
        installed = run(["modinfo", "-F", "version", "nvidia"])
        if installed and installed != loaded.read_text().strip():
            why.append("nvidia")
    relogin = False
    try:
        tag = json.loads(run(["hyprctl", "version", "-j"]) or "{}").get("tag", "")
        pkg = run(["pacman", "-Q", "hyprland"]).split()
        if tag and len(pkg) == 2 and tag.lstrip("v").split("-")[0] != pkg[1].split("-")[0]:
            relogin = True
    except ValueError:
        pass
    return {"reboot": bool(why), "relogin": relogin and not why, "why": why}


class Updates:
    def __init__(self, on_change):
        self.on_change = on_change  # called with the event for the shell
        try:
            self.state = json.loads(STATE.read_text())
        except (OSError, ValueError):
            self.state = {}
        self.state.setdefault("packages", [])
        self.state.setdefault("flatpaks", [])
        self.state.setdefault("told", [])
        self.checking = False
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.actions = {}  # notification id → what its button does
        self.bus.signal_subscribe(None, "org.freedesktop.Notifications", "ActionInvoked",
                                  "/org/freedesktop/Notifications", None, Gio.DBusSignalFlags.NONE,
                                  self.on_action)

    def start(self):
        self.state.update(needs())
        GLib.timeout_add_seconds(300, lambda: (self.check(), False)[1])
        GLib.timeout_add_seconds(EVERY, lambda: (self.check(), True)[1])
        # packages installed or removed (the App Store, pacman in a terminal)
        self.pending = None
        self.monitor = Gio.File.new_for_path("/var/lib/pacman/local").monitor_directory(Gio.FileMonitorFlags.NONE, None)
        self.monitor.connect("changed", self.on_packages_changed)

    def event(self):
        return {"event": "updates", "count": len(self.state["packages"]) + len(self.state["flatpaks"]),
                "reboot": self.state.get("reboot", False), "relogin": self.state.get("relogin", False)}

    def on_packages_changed(self, *_):
        # pacman writes many files: once it is quiet for 20 s
        if self.pending:
            GLib.source_remove(self.pending)
        self.pending = GLib.timeout_add_seconds(20, self.after_packages_changed)

    def after_packages_changed(self):
        self.pending = None
        self.check()
        return False

    # ------------------------------------------------------------ looking

    def check(self):
        if self.checking:
            return
        self.checking = True
        self.spawn(["checkupdates", "--nocolor"], self.got_packages)

    def spawn(self, argv, done):
        try:
            proc = Gio.Subprocess.new(argv, Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE)
        except GLib.Error:
            done(None)
            return
        def finished(p, result):
            try:
                _ok, out, _err = p.communicate_utf8_finish(result)
            except GLib.Error:
                out = None
            # checkupdates: 0 = updates, 2 = none, 1 = failed (offline)
            done(None if p.get_exit_status() not in (0, 2) else (out or ""))
        proc.communicate_utf8_async(None, None, finished)

    def got_packages(self, out):
        if out is not None:
            # "firefox 150.0-1 -> 151.0-1"
            self.state["packages"] = [{"pkg": m[0], "from": m[1], "to": m[2]}
                                      for m in re.findall(r"^(\S+) (\S+) -> (\S+)$", out, re.M)]
        if run(["which", "flatpak"]):
            self.spawn(["flatpak", "remote-ls", "--updates", "--columns=application,version"], self.got_flatpaks)
        else:
            self.got_flatpaks("")

    def got_flatpaks(self, out):
        if out is not None:
            self.state["flatpaks"] = [{"app": line.split("\t")[0], "to": (line.split("\t") + [""])[1]}
                                      for line in out.splitlines() if line.strip()]
        self.checking = False
        self.state["checked"] = time.time()
        self.state.update(needs())
        self.save()
        self.on_change(self.event())
        self.tell()

    # ------------------------------------------------------------ telling

    def tell(self):
        now = time.time()
        found = [f"{p['pkg']}@{p['to']}" for p in self.state["packages"]] + \
                [f"{f['app']}@{f['to']}" for f in self.state["flatpaks"]]
        new = [k for k in found if k not in self.state["told"]]
        if new and now - self.state.get("told_at", 0) >= NOTIFY_AGAIN:
            n = len(found)
            self.notify("Softwareupdates verfügbar",
                        f"{n} Update{'s' if n != 1 else ''} für dein System. Vor der Installation wird "
                        "automatisch ein Snapshot angelegt.",
                        "Anzeigen", "show")
            self.state["told"] = found
            self.state["told_at"] = now
        waiting = "reboot" if self.state.get("reboot") else "relogin" if self.state.get("relogin") else ""
        if waiting and self.state.get("told_waiting") != waiting:
            if waiting == "reboot":
                self.notify("Neustart erforderlich", "Einige Updates werden erst nach einem Neustart wirksam.",
                            "Neu starten …", "reboot")
            else:
                self.notify("Neu anmelden erforderlich",
                            "Hyprland wurde aktualisiert. Melde dich ab und wieder an, damit die neue Version läuft.",
                            "Abmelden …", "logout")
        self.state["told_waiting"] = waiting
        self.save()

    def notify(self, title, text, button, action):
        try:
            reply = self.bus.call_sync(
                "org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications",
                "Notify", GLib.Variant("(susssasa{sv}i)", ("System", 0, "", title, text,
                                                           ["default", button, action, button], {}, 0)),
                GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, 5000, None)
            self.actions[reply.unpack()[0]] = action
        except GLib.Error as e:
            print(f"updates: notify: {e.message}", flush=True)

    def on_action(self, _bus, _sender, _path, _interface, _signal, params):
        nid, _key = params.unpack()
        action = self.actions.pop(nid, None)
        if action == "show":
            subprocess.Popen([str(SCRIPTS / "app-store.sh"), "updates"], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        elif action in ("reboot", "logout"):
            self.on_change({"event": "session-ask", "what": action})  # the shell asks first

    def save(self):
        STATE.parent.mkdir(parents=True, exist_ok=True)
        tmp = STATE.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.state, indent=1))
        tmp.replace(STATE)
