"""riptide-session: the services of the desktop session, in one process
(docs/os-plan.md, "Architecture"). Runs as the systemd user service riptide-session.

It owns
  app permissions   the system's permission store; tells the shell what changed and
                    what an app asks for, answers come back from the shell
  app sandboxes     starts every app (app-sandbox hands it the start), asks first when
                    needed (internet), cleans up after the app has ended
  start entries     keeps every app starting in its sandbox (sandbox.sync), also apps
                    that are installed later
  sound requests    a sandboxed app wants a microphone, output or camera it has no
                    decision for (WirePlumber, macos/app-permissions.lua)
  D-Bus of apps     what sandboxed apps ask for on D-Bus (their proxy's dbus.log): screen
                    sharing requests (who is asking), and tries without permission
                    (passwords, Bluetooth), which the user is then asked about
  screen sharing    the portal's picker (riptide-share-picker) asks here: permission
                    "screen" first, then the shell shows our dialog
  portal backend    org.freedesktop.impl.portal.desktop.riptide: the portal's questions
                    (Access: camera, background, …) in our dialog, and autostart for
                    apps (Background), which then start in their sandbox
  health, crashes   warnings about the machine (health.py); apps that crashed (crashes.py)
  updates           looks for updates in the background (updates.py)
  local network     per app, with nftables through riptide-helper (lan.py)
  drives            external drives: mounted by themselves, ejected on request (drives.py)

The shell, System Settings and the command line tools talk to it through one Unix
socket, $XDG_RUNTIME_DIR/riptide/session.sock (only this user can open it; sandboxes
never see it), one JSON object per line:

  → {"id": 1, "call": "hello", "role": "shell"}          role: shell | settings | tool
  ← {"id": 1, "result": {"kinds": [...], "states": {...}}}
  ← {"event": "permissions", "states": {app: {kind: state}}}      to everyone
  ← {"event": "streams", "streams": {node id: app}}               to the shell: whose sound
  ← {"event": "request", "app": "discord", "kind": "microphone"}  to the shell
  ← {"event": "updates", "count": 3, "reboot": false, "relogin": false}  to the shell
  ← {"event": "session-ask", "what": "reboot"}  to the shell: ask, then restart/log out
  ← {"event": "drives", "drives": [...], "added": id}  to the shell: external drives

  ← {"event": "share", "pick": 3, "app": "discord", "windows": [...]}   to the shell
  ← {"event": "access", "pick": 4, "app": "discord", "title": …, "text": …, "grant": …, "deny": …}

  calls  hello, permissions.set {app, kind, state}, permissions.request {app, kind},
         apps.launch {app, args, run}, apps.sync,
         screen.pick {windows} (the picker), screen.picked {pick, selection} (the shell),
         access.answered {pick, granted} (the shell),
         updates.check, drives.eject {id},
         status (who is connected, what is open – for troubleshooting)
"""

import json
import os
import re
import subprocess
import sys
import time
import traceback
from pathlib import Path

from gi.repository import Gio, GLib

from desktop_shell import crashes, drives, health, lan, permissions, sandbox, updates

SOCKET = sandbox.SERVICE_SOCKET
HOME = Path.home()
ANSWER_TIMEOUT = 300  # seconds a start waits for an answer; none counts as no
RUNTIME = sandbox.RUNTIME

# D-Bus names an app may only talk to with permission: a try without it asks
DENIED_NAMES = {"org.freedesktop.secrets": "secrets", "org.bluez": "bluetooth"}
LOG_CALL = re.compile(r"^C\d+: -> (\S+) call (\S+)")
SCREEN_CALL = re.compile(r"^org\.freedesktop\.portal\.(ScreenCast|RemoteDesktop)\.(CreateSession|SelectSources|Start)$")
LOG_LIMIT = 256 * 1024  # dbus.log is emptied beyond this


def log(message):
    print(message, file=sys.stderr, flush=True)


class Client:
    """One connection to the socket."""

    def __init__(self, service, connection):
        self.service = service
        self.connection = connection
        self.role = "tool"
        self.input = Gio.DataInputStream.new(connection.get_input_stream())
        self.output = connection.get_output_stream()
        self.open = True
        self.read()

    def read(self):
        self.input.read_line_async(GLib.PRIORITY_DEFAULT, None, self.on_line)

    def on_line(self, stream, result):
        try:
            line, _length = stream.read_line_finish_utf8(result)
        except GLib.Error:
            line = None
        if line is None:
            self.service.drop(self)
            return
        try:
            message = json.loads(line) if line.strip() else None
        except ValueError:
            message = None
        if isinstance(message, dict):
            self.service.handle(self, message)
        if self.open:
            self.read()

    def send(self, message):
        if not self.open:
            return
        try:
            self.output.write_all((json.dumps(message, ensure_ascii=False) + "\n").encode(), None)
        except GLib.Error:
            self.service.drop(self)

    def reply(self, msg_id, result=None, error=None):
        self.send({"id": msg_id, "error": error} if error else {"id": msg_id, "result": result})


class Service:
    def __init__(self):
        self.clients = []
        self.kinds = [{k: v for k, v in kind.items() if k not in ("table", "id")}
                      for kind in permissions.KINDS if kind["enforced"]]
        self.states = {}
        self.asked = set()   # (app, kind) the shell asks about right now
        self.waiters = []    # [(app, kind, callback, timeout source)] starts waiting for an answer
        self.sandboxes = {}  # pid of a sandbox → (app, instance, unit)
        self.lan = lan.LocalNetwork(self)  # "Lokales Netzwerk" per app
        self.first_starts = {}  # app → [(client, msg id)] of starts joining its first start
        self.sound = None  # permissions.SoundRequests: also which app each sound stream is
        self.timers = {}
        self.logs = {}       # dbus.log path → {"offset", "app", "dest"}
        self.screen_requests = []  # [(time, app)] apps that asked the portal to share the screen
        self.picks = {}      # number → open share dialog (see screen_pick)
        self.accesses = {}   # number → open portal question (see access)
        self.next_pick = 1

    # ------------------------------------------------------------ start

    def start(self):
        sandbox.gc()
        self.refresh_states()
        self.watch_store()
        self.watch_sound()
        self.watch_apps()
        self.watch_proxy_logs()
        self.portal = PortalBackend(self)
        self.health = health.Health()  # disk full, disk trouble, file system errors, failed services
        self.health.start()
        self.crashes = crashes.Crashes()  # "„X“ wurde unerwartet beendet" – Erneut öffnen
        self.crashes.start()
        self.updates = updates.Updates(lambda event: self.broadcast(event, role="shell"))  # like Softwareupdate
        self.updates.start()
        self.lan.start()
        self.drives = drives.Drives(self.on_drives)  # USB sticks, disks
        self.drives.start()
        GLib.timeout_add_seconds(300, lambda: (sandbox.gc(), True)[1])
        GLib.idle_add(self.sync)
        self.listen()
        log("riptide-session ready")

    def listen(self):
        SOCKET.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(SOCKET.parent, 0o700)
        SOCKET.unlink(missing_ok=True)
        self.server = Gio.SocketService()
        self.server.add_address(Gio.UnixSocketAddress.new(str(SOCKET)), Gio.SocketType.STREAM,
                                Gio.SocketProtocol.DEFAULT, None)
        os.chmod(SOCKET, 0o600)
        self.server.connect("incoming", self.on_incoming)
        self.server.start()

    def on_incoming(self, _server, connection, _source):
        self.clients.append(Client(self, connection))
        return False

    def drop(self, client):
        client.open = False
        if client in self.clients:
            self.clients.remove(client)
        for pick, entry in list(self.picks.items()):
            if entry["picker"] is client:  # the portal gave up waiting
                self.end_pick(pick, None)

    def later(self, name, seconds, callback):
        """Run callback once, `seconds` after the last call with this name."""
        if name in self.timers:
            GLib.source_remove(self.timers[name])

        def run():
            del self.timers[name]
            callback()
            return False
        self.timers[name] = GLib.timeout_add(int(seconds * 1000), run)

    # ------------------------------------------------------------ calls

    def handle(self, client, message):
        msg_id, call = message.get("id"), message.get("call")
        try:
            if call == "hello":
                client.role = message.get("role", "tool")
                client.reply(msg_id, {"kinds": self.kinds, "states": self.states})
                if client.role == "shell":  # what is still open (the shell restarted)
                    for app, kind in sorted(self.asked):
                        client.send({"event": "request", "app": app, "kind": kind})
                    for pick, entry in sorted(self.picks.items()):
                        client.send(entry["event"])
                    for pick, entry in sorted(self.accesses.items()):
                        client.send(entry["event"])
                    client.send({"event": "streams", "streams": self.stream_apps()})
                    client.send(self.updates.event())
                    client.send(self.drives.event())
            elif call == "drives.eject":
                self.drives.eject(message["id"], lambda error: client.reply(msg_id, {"error": error}))
            elif call == "updates.check":  # look now (the App Store's "Nach Updates suchen")
                self.updates.check()
                client.reply(msg_id, True)
            elif call == "permissions.set":
                permissions.set_state(message["app"], message["kind"], message["state"])
                client.reply(msg_id, True)  # the store's signal brings the new states to all
            elif call == "permissions.request":
                self.request(message["app"], message["kind"])
                client.reply(msg_id, True)
            elif call == "apps.launch":
                self.launch(client, msg_id, message["app"], message.get("args", []), message.get("run", False))
            elif call == "apps.sync":
                self.sync()
                client.reply(msg_id, True)
            elif call == "status":  # for troubleshooting
                client.reply(msg_id, {"clients": [c.role for c in self.clients], "asked": sorted(self.asked),
                                      "picks": sorted(self.picks), "sandboxes": list(self.sandboxes.values())})
            elif call == "screen.pick":
                self.screen_pick(client, msg_id, message.get("windows", []))
            elif call == "access.answered":
                self.access_answered(message["pick"], bool(message.get("granted")))
                client.reply(msg_id, True)
            elif call == "screen.picked":
                self.screen_picked(message["pick"], message.get("selection"))
                client.reply(msg_id, True)
            else:
                client.reply(msg_id, error=f"unknown call {call}")
        except sandbox.SandboxError as e:
            client.reply(msg_id, error=str(e))
        except Exception as e:  # never let one call take the service down
            log(traceback.format_exc())
            client.reply(msg_id, error=f"{type(e).__name__}: {e}")

    def on_drives(self, event):
        self.broadcast(event, role="shell")
        # Time Machine's disk plugged in: back up if due (riptide-backup.service decides)
        added = next((d for d in event["drives"] if d["id"] == event.get("added")), None)
        try:
            volume = json.loads((HOME / ".config/macos/settings.json").read_text()).get("timemachine", {}).get("volume") or {}
        except (OSError, ValueError):
            volume = {}
        if added and volume.get("uuid") and added.get("uuid") == volume["uuid"]:
            subprocess.Popen(["systemctl", "--user", "start", "--no-block", "riptide-backup.service"])

    def broadcast(self, message, role=None):
        for client in list(self.clients):
            if role is None or client.role == role:
                client.send(message)

    # ------------------------------------------------------------ permissions

    def state(self, app, kind):
        return self.states.get(app, {}).get(kind, "ask")

    def refresh_states(self):
        states = permissions.list_all()
        changed = states != self.states
        self.states = states
        for key in [k for k in self.asked if self.state(*k) != "ask"]:
            self.asked.discard(key)
        for waiter in [w for w in self.waiters if self.state(w[0], w[1]) != "ask"]:
            self.finish_wait(waiter, self.state(waiter[0], waiter[1]))
        if changed:
            self.broadcast({"event": "permissions", "states": states})
            if hasattr(self, "lan"):
                self.lan.states_changed()

    def watch_store(self):
        # (any sender: matching the store's well-known name does not deliver; a fake signal
        # could only make us read the real store again)
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.bus.signal_subscribe(None, permissions.INTERFACE, "Changed", permissions.OBJECT,
                                  None, Gio.DBusSignalFlags.NONE,
                                  lambda *_: self.later("states", 0.2, self.refresh_states))

    def request(self, app, kind):
        """Have the shell ask the user, once at a time per app and kind."""
        if self.state(app, kind) != "ask" or (app, kind) in self.asked:
            return
        self.asked.add((app, kind))
        self.broadcast({"event": "request", "app": app, "kind": kind}, role="shell")

    def wait_for(self, app, kind, callback):
        """Ask, and call back with the answer (or "no" after ANSWER_TIMEOUT)."""
        waiter = [app, kind, callback, None]

        def timed_out():
            waiter[3] = None  # this source ends by returning False
            self.finish_wait(waiter, "no")
            return False
        waiter[3] = GLib.timeout_add_seconds(ANSWER_TIMEOUT, timed_out)
        self.waiters.append(waiter)
        self.request(app, kind)

    def finish_wait(self, waiter, state):
        if waiter not in self.waiters:
            return False
        self.waiters.remove(waiter)
        if waiter[3]:
            GLib.source_remove(waiter[3])
            waiter[3] = None
        waiter[2](state)
        return False

    # ------------------------------------------------------------ sound requests

    def watch_sound(self):
        requests = permissions.SoundRequests()
        try:
            pid, _stdin, stdout, _stderr = GLib.spawn_async(
                permissions.SoundRequests.COMMAND,
                flags=GLib.SpawnFlags.SEARCH_PATH | GLib.SpawnFlags.DO_NOT_REAP_CHILD,
                standard_output=True)
        except GLib.Error as e:
            log(f"sound requests: {e.message}")
            GLib.timeout_add_seconds(5, lambda: self.watch_sound() and False)
            return
        channel = GLib.IOChannel.unix_new(stdout)
        channel.set_close_on_unref(True)

        self.sound = requests

        def on_output(source, condition):
            if condition & GLib.IOCondition.IN:
                line = source.readline()
                if line:
                    for app, kind in requests.feed(line):
                        self.request(app, kind)
                    if requests.streams_changed:
                        requests.streams_changed = False
                        self.broadcast({"event": "streams", "streams": self.stream_apps()}, role="shell")
                    return True
            return False

        GLib.io_add_watch(channel, GLib.PRIORITY_DEFAULT, GLib.IOCondition.IN | GLib.IOCondition.HUP, on_output)

        def on_exit(child, _status):
            GLib.spawn_close_pid(child)
            GLib.timeout_add_seconds(3, lambda: self.watch_sound() and False)  # PipeWire restarted

        GLib.child_watch_add(GLib.PRIORITY_DEFAULT, pid, on_exit)

    def stream_apps(self):
        """{node id (as text, for JSON): app} – which app a sound stream belongs to."""
        return {str(node): app for node, app in (self.sound.streams() if self.sound else {}).items()}

    # ------------------------------------------------------------ apps

    def launch(self, client, msg_id, app, args, run):
        system, argv, profile, states = sandbox.prepare_launch(app, args, run)
        if system:
            self.spawn_system(argv)
            client.reply(msg_id, {"sandbox": False})
            return

        def go(network):
            try:
                states["network"] = network
                box = sandbox.Sandbox(app, argv, profile, states)
                if network == "yes":  # the local network needs its own permission (lan.py)
                    box.guard = lambda unit: self.lan.guard(app, unit)
                process = box.start(box.argv)
                self.sandboxes[process.pid] = (app, box.instance, box.unit)
                GLib.child_watch_add(GLib.PRIORITY_DEFAULT, process.pid, self.on_sandbox_ended)
                for helper in box.children:
                    GLib.child_watch_add(GLib.PRIORITY_DEFAULT, helper, lambda pid, _s: GLib.spawn_close_pid(pid))
                client.reply(msg_id, {"sandbox": True, "pid": process.pid})
            except sandbox.SandboxError as e:
                client.reply(msg_id, error=str(e))
            except Exception as e:
                log(traceback.format_exc())
                client.reply(msg_id, error=f"{type(e).__name__}: {e}")

        if states["network"] != "ask":
            go(states["network"])
            return
        # The first start waits for "Internet?" – more starts meanwhile (dock, Spotlight)
        # must not each start the app once the answer comes: they join that one start
        if app in self.first_starts:
            self.first_starts[app].append((client, msg_id))
            return
        self.first_starts[app] = []

        def answered(network):
            go(network)
            for later_client, later_id in self.first_starts.pop(app, []):
                later_client.reply(later_id, {"sandbox": True})
        self.wait_for(app, "network", answered)

    def spawn_system(self, argv):
        process = subprocess.Popen(["systemd-run", "--user", "--scope", "--quiet", "--collect",
                                    "--slice=app-graphical.slice", *argv], start_new_session=True)
        GLib.child_watch_add(GLib.PRIORITY_DEFAULT, process.pid, lambda pid, _s: GLib.spawn_close_pid(pid))

    def on_sandbox_ended(self, pid, _status):
        GLib.spawn_close_pid(pid)
        app, instance, unit = self.sandboxes.pop(pid, (None, None, None))
        if app:
            sandbox.cleanup(app, instance)
            self.lan.ended(f"{unit}.scope")

    # ------------------------------------------------------------ D-Bus of sandboxed apps

    def watch_proxy_logs(self):
        # logs of apps that were already running are read from their end on
        for file in (RUNTIME / "macos-sandbox").glob("*-*/dbus.log"):
            self.logs[str(file)] = {"offset": file.stat().st_size, "app": file.parent.name.rsplit("-", 1)[0], "dest": None}
        GLib.timeout_add(500, self.read_proxy_logs)

    def read_proxy_logs(self):
        try:
            present = set()
            for file in (RUNTIME / "macos-sandbox").glob("*-*/dbus.log"):
                path = str(file)
                present.add(path)
                entry = self.logs.setdefault(path, {"offset": 0, "app": file.parent.name.rsplit("-", 1)[0], "dest": None})
                size = file.stat().st_size
                if size < entry["offset"]:
                    entry["offset"] = 0
                if size == entry["offset"]:
                    continue
                with open(file, "rb") as f:
                    f.seek(entry["offset"])
                    data = f.read()
                entry["offset"] += len(data)
                for line in data.decode(errors="replace").splitlines():
                    self.on_proxy_line(entry, line)
                if entry["offset"] > LOG_LIMIT:
                    os.truncate(file, 0)
                    entry["offset"] = 0
            for path in set(self.logs) - present:
                del self.logs[path]
        except Exception:
            log(traceback.format_exc())
        return True

    def on_proxy_line(self, entry, line):
        m = LOG_CALL.match(line)
        if m:
            entry["dest"] = m.group(1)
            if SCREEN_CALL.match(m.group(2)):
                now = time.monotonic()
                self.screen_requests = [r for r in self.screen_requests if now - r[0] < 60] + [(now, entry["app"])]
        elif line.startswith("*HIDDEN*") and entry["dest"] in DENIED_NAMES:
            self.request(entry["app"], DENIED_NAMES[entry["dest"]])  # asks only if undecided

    # ------------------------------------------------------------ screen sharing

    def screen_pick(self, picker, msg_id, windows):
        """The portal's picker asks what to share. The asking app is the one that called the
        ScreenCast portal last (its proxy log); unknown for apps without a sandbox."""
        self.read_proxy_logs()  # the portal starts the picker right after the app's call
        now = time.monotonic()
        recent = [app for t, app in self.screen_requests if now - t < 60]
        app = recent[-1] if recent else ""

        def show():
            pick = self.next_pick
            self.next_pick += 1
            event = {"event": "share", "pick": pick, "app": app, "windows": windows}
            # (the portal waits for its picker and handles nothing else meanwhile: an
            # unanswered dialog must not block it for long)
            timeout = GLib.timeout_add_seconds(120, lambda: self.pick_timed_out(pick))
            self.picks[pick] = {"picker": picker, "msg": msg_id, "event": event, "timeout": timeout}
            self.broadcast(event, role="shell")

        if not app:
            show()
        elif self.state(app, "screen") == "yes":
            show()
        elif self.state(app, "screen") == "no":
            picker.reply(msg_id, {"selection": None})
        else:
            self.wait_for(app, "screen", lambda state: show() if state == "yes" else picker.reply(msg_id, {"selection": None}))

    def screen_picked(self, pick, selection):
        self.end_pick(pick, selection)

    def pick_timed_out(self, pick):
        if pick in self.picks:
            self.picks[pick]["timeout"] = None  # this source ends by returning False
            self.end_pick(pick, None)
        return False

    def end_pick(self, pick, selection):
        entry = self.picks.pop(pick, None)
        if entry is None:
            return False
        if entry["timeout"]:
            GLib.source_remove(entry["timeout"])
        entry["picker"].reply(entry["msg"], {"selection": selection})
        self.broadcast({"event": "share-cancelled", "pick": pick}, role="shell")
        return False

    # ------------------------------------------------------------ questions of the portal

    def access(self, app, title, text, grant, deny, done):
        """Show one of the portal's questions in our dialog; done(granted)."""
        pick = self.next_pick
        self.next_pick += 1
        event = {"event": "access", "pick": pick, "app": app, "title": title, "text": text,
                 "grant": grant, "deny": deny}
        self.accesses[pick] = {"done": done, "event": event}
        if not any(c.role == "shell" for c in self.clients):
            self.access_answered(pick, False)
            return
        self.broadcast(event, role="shell")

    def access_answered(self, pick, granted):
        entry = self.accesses.pop(pick, None)
        if entry:
            entry["done"](granted)

    # ------------------------------------------------------------ start entries

    def watch_apps(self):
        self.monitors = []
        for path in ("/usr/share/applications", "/usr/share/dbus-1/services"):
            monitor = Gio.File.new_for_path(path).monitor_directory(Gio.FileMonitorFlags.NONE, None)
            monitor.connect("changed", lambda *_: self.later("sync", 3, self.sync))
            self.monitors.append(monitor)
        profiles = sandbox.PROFILES.resolve()
        monitor = Gio.File.new_for_path(str(profiles)).monitor_file(Gio.FileMonitorFlags.NONE, None)
        monitor.connect("changed", lambda *_: self.later("sync", 1, self.sync))
        self.monitors.append(monitor)

    def sync(self):
        try:
            sandbox.sync()
        except Exception:
            log(traceback.format_exc())
        return False


PORTAL_XML = """
<node>
  <interface name="org.freedesktop.impl.portal.Access">
    <method name="AccessDialog">
      <arg type="o" name="handle" direction="in"/>
      <arg type="s" name="app_id" direction="in"/>
      <arg type="s" name="parent_window" direction="in"/>
      <arg type="s" name="title" direction="in"/>
      <arg type="s" name="subtitle" direction="in"/>
      <arg type="s" name="body" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="u" name="response" direction="out"/>
      <arg type="a{sv}" name="results" direction="out"/>
    </method>
  </interface>
  <interface name="org.freedesktop.impl.portal.Background">
    <method name="GetAppState">
      <arg type="a{sv}" name="apps" direction="out"/>
    </method>
    <method name="NotifyBackground">
      <arg type="o" name="handle" direction="in"/>
      <arg type="s" name="app_id" direction="in"/>
      <arg type="s" name="name" direction="in"/>
      <arg type="u" name="response" direction="out"/>
      <arg type="a{sv}" name="results" direction="out"/>
    </method>
    <method name="EnableAutostart">
      <arg type="s" name="app_id" direction="in"/>
      <arg type="b" name="enable" direction="in"/>
      <arg type="as" name="commandline" direction="in"/>
      <arg type="u" name="flags" direction="in"/>
      <arg type="b" name="result" direction="out"/>
    </method>
    <signal name="RunningApplicationsChanged"/>
  </interface>
</node>
"""
AUTOSTART = HOME / ".config/autostart"


class PortalBackend:
    """Our backend of xdg-desktop-portal (registered by riptide.portal and
    xdg-desktop-portal/hyprland-portals.conf): the questions the portal asks – camera,
    running in the background, … – come to our dialog instead of GTK's, and apps that
    want to start at login get an autostart entry that starts them in their sandbox."""

    NAME = "org.freedesktop.impl.portal.desktop.riptide"
    PATH = "/org/freedesktop/portal/desktop"

    def __init__(self, service):
        self.service = service
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        info = Gio.DBusNodeInfo.new_for_xml(PORTAL_XML)
        for interface in info.interfaces:
            self.bus.register_object(self.PATH, interface, self.on_call, None, None)
        Gio.bus_own_name_on_connection(self.bus, self.NAME, Gio.BusNameOwnerFlags.NONE, None, None)

    def on_call(self, _bus, _sender, _path, interface, method, params, invocation):
        try:
            if method == "AccessDialog":
                _handle, app_id, _parent, title, subtitle, body, options = params.unpack()
                app = permissions.desktop_id(app_id)
                # the portal names the app by its id; the user knows its name
                name = sandbox.app_name(app)
                text = "\n\n".join(t for t in (subtitle, body) if t).replace(app_id, name)

                def done(granted):
                    invocation.return_value(GLib.Variant("(ua{sv})", (0 if granted else 1, {})))
                self.service.access(app, title.replace(app_id, name), text,
                                    options.get("grant_label") or "Erlauben", options.get("deny_label") or "Nicht erlauben", done)
            elif method == "GetAppState":
                invocation.return_value(GLib.Variant("(a{sv})", ({},)))
            elif method == "NotifyBackground":
                # the permission "background" was already decided by the portal: allow this time
                invocation.return_value(GLib.Variant("(ua{sv})", (0, {"result": GLib.Variant("u", 2)})))
            elif method == "EnableAutostart":
                app_id, enable, commandline, _flags = params.unpack()
                invocation.return_value(GLib.Variant("(b)", (self.autostart(permissions.desktop_id(app_id), enable, commandline),)))
            else:
                invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)
        except Exception as e:
            log(traceback.format_exc())
            invocation.return_dbus_error("org.freedesktop.DBus.Error.Failed", str(e))

    def autostart(self, app, enable, commandline):
        """~/.config/autostart/<app>.desktop: starts the app in its sandbox at login."""
        path = AUTOSTART / f"{app}.riptide.desktop"
        if not enable:
            path.unlink(missing_ok=True)
            return True
        if not commandline or not re.fullmatch(r"[A-Za-z0-9_.+-]+", app):
            return False
        import shlex
        me = HOME / ".local/bin/app-sandbox"
        AUTOSTART.mkdir(parents=True, exist_ok=True)
        path.write_text("[Desktop Entry]\nType=Application\n"
                        f"Name={sandbox.app_name(app)}\n"
                        f"Exec={me} --run {app} {shlex.join(commandline)}\n"
                        "X-Riptide-Autostart=true\n", encoding="utf-8")
        return True


def main():
    GLib.set_prgname("riptide-session")
    service = Service()
    service.start()
    loop = GLib.MainLoop()
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, 15, lambda: (loop.quit(), False)[1])
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, 2, lambda: (loop.quit(), False)[1])
    loop.run()
    SOCKET.unlink(missing_ok=True)
