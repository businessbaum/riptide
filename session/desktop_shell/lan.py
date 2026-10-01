"""The local network per app, like "Lokales Netzwerk" on a Mac: a sandboxed app that may
use the internet reaches devices at home (printers, TVs, the router's pages, anything
found by mDNS/SSDP) only with the permission "local-network".

Without it, riptide-helper (root; polkit asks no password, it only restricts the user's
own apps) puts nftables rules on the app's systemd scope before the app runs
(Sandbox.guard): private addresses are refused, multicast dropped, DNS stays open. The
kernel logs the first blocked tries ("riptide-lan <scope>: …"); an app that was never asked
is asked then ("„Discord“ möchte Geräte in deinem lokalen Netzwerk finden …"). A decision
applies at once: the rules go (or come) for the app's running scopes.
Until the installed helper knows this (system/setup-os.sh), the kind stays unoffered.
"""

import os
import re
import subprocess
from pathlib import Path

from gi.repository import Gio, GLib

from desktop_shell import sandbox

HELPER = "/usr/local/sbin/riptide-helper"
KIND = "local-network"
LOGGED = re.compile(r"riptide-lan (app-sandbox-[A-Za-z0-9_.]+-\d+\.scope): ")


def supported():
    """The installed helper can do it (after system/setup-os.sh)"""
    try:
        return "riptide_lan" in Path(HELPER).read_text()
    except OSError:
        return False


def helper(action, unit):
    try:
        p = subprocess.run(["pkexec", HELPER, "network", action, unit], capture_output=True, text=True, timeout=15)
        if p.returncode != 0:
            print(f"lan: {action} {unit}: {(p.stderr or p.stdout).strip()}", flush=True)
        return p.returncode == 0
    except (OSError, subprocess.TimeoutExpired) as e:
        print(f"lan: {action} {unit}: {e}", flush=True)
        return False


class LocalNetwork:
    def __init__(self, session):
        self.session = session
        self.enforced = supported()
        self.units = {}      # scope → app: running sandboxes that may use the internet
        self.blocked = set()  # scopes with rules

    def start(self):
        if not self.enforced:
            return
        self.adopt()
        try:
            self.proc = Gio.Subprocess.new(["journalctl", "--dmesg", "--follow", "--lines=0", "--output=cat",
                                            "--grep=riptide-lan "], Gio.SubprocessFlags.STDOUT_PIPE)
        except GLib.Error as e:
            print(f"lan: journalctl: {e.message}", flush=True)
            return
        self.lines = Gio.DataInputStream.new(self.proc.get_stdout_pipe())
        self.read_next()

    # ------------------------------------------------------------ apps start and end

    def adopt(self):
        """Sandboxes that run already (the service restarted): the same rules as at a start"""
        for app, instance, folder in sandbox.instances():
            if not app or not sandbox.running(folder) or self.session.state(app, "network") != "yes":
                continue
            unit = f"app-sandbox-{re.sub(r'[^A-Za-z0-9_.]', '_', app)}-{instance}.scope"
            if Path(f"/sys/fs/cgroup/user.slice/user-{os.getuid()}.slice/user@{os.getuid()}.service/app.slice/"
                    f"app-graphical.slice/{unit}").is_dir():
                self.guard(app, unit)

    def guard(self, app, unit):
        """Before the app runs (its scope exists, bwrap still waits)"""
        self.units[unit] = app
        if self.enforced and self.session.state(app, KIND) != "yes" and helper("block", unit):
            self.blocked.add(unit)

    def ended(self, unit):
        self.units.pop(unit, None)
        if unit in self.blocked:
            self.blocked.discard(unit)
            GLib.idle_add(lambda: (helper("forget", unit), False)[1])

    def states_changed(self):
        """A decision changed: the running scopes follow at once"""
        for unit, app in list(self.units.items()):
            allowed = self.session.state(app, KIND) == "yes"
            if allowed and unit in self.blocked and helper("allow", unit):
                self.blocked.discard(unit)
            elif not allowed and unit not in self.blocked and helper("block", unit):
                self.blocked.add(unit)

    # ------------------------------------------------------------ blocked tries

    def read_next(self):
        self.lines.read_line_async(GLib.PRIORITY_DEFAULT, None, self.on_line)

    def on_line(self, stream, result):
        try:
            line, _ = stream.read_line_finish_utf8(result)
        except GLib.Error as e:
            print(f"lan: {e.message}", flush=True)
            return
        if line is None:
            return
        m = LOGGED.search(line)
        app = self.units.get(m.group(1)) if m else None
        if app and self.session.state(app, KIND) == "ask":
            self.session.request(app, KIND)
        self.read_next()
