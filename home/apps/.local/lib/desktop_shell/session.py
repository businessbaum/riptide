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

The shell, System Settings and the command line tools talk to it through one Unix
socket, $XDG_RUNTIME_DIR/riptide/session.sock (only this user can open it; sandboxes
never see it), one JSON object per line:

  → {"id": 1, "call": "hello", "role": "shell"}          role: shell | settings | tool
  ← {"id": 1, "result": {"kinds": [...], "states": {...}}}
  ← {"event": "permissions", "states": {app: {kind: state}}}      to everyone
  ← {"event": "request", "app": "discord", "kind": "microphone"}  to the shell

  calls  hello, permissions.set {app, kind, state}, permissions.request {app, kind},
         apps.launch {app, args, run}, apps.sync
"""

import json
import os
import subprocess
import sys
import traceback
from pathlib import Path

from gi.repository import Gio, GLib

from desktop_shell import permissions, sandbox

SOCKET = sandbox.SERVICE_SOCKET
HOME = Path.home()
ANSWER_TIMEOUT = 300  # seconds a start waits for an answer; none counts as no


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
        self.sandboxes = {}  # pid of a sandbox → (app, instance)
        self.timers = {}

    # ------------------------------------------------------------ start

    def start(self):
        sandbox.gc()
        self.refresh_states()
        self.watch_store()
        self.watch_sound()
        self.watch_apps()
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
                if client.role == "shell":
                    for app, kind in sorted(self.asked):  # questions still open (shell restarted)
                        client.send({"event": "request", "app": app, "kind": kind})
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
            else:
                client.reply(msg_id, error=f"unknown call {call}")
        except sandbox.SandboxError as e:
            client.reply(msg_id, error=str(e))
        except Exception as e:  # never let one call take the service down
            log(traceback.format_exc())
            client.reply(msg_id, error=f"{type(e).__name__}: {e}")

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

        def on_output(source, condition):
            if condition & GLib.IOCondition.IN:
                line = source.readline()
                if line:
                    for app, kind in requests.feed(line):
                        self.request(app, kind)
                    return True
            return False

        GLib.io_add_watch(channel, GLib.PRIORITY_DEFAULT, GLib.IOCondition.IN | GLib.IOCondition.HUP, on_output)

        def on_exit(child, _status):
            GLib.spawn_close_pid(child)
            GLib.timeout_add_seconds(3, lambda: self.watch_sound() and False)  # PipeWire restarted

        GLib.child_watch_add(GLib.PRIORITY_DEFAULT, pid, on_exit)

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
                process = box.start(box.argv)
                self.sandboxes[process.pid] = (app, box.instance)
                GLib.child_watch_add(GLib.PRIORITY_DEFAULT, process.pid, self.on_sandbox_ended)
                for helper in box.children:
                    GLib.child_watch_add(GLib.PRIORITY_DEFAULT, helper, lambda pid, _s: GLib.spawn_close_pid(pid))
                client.reply(msg_id, {"sandbox": True, "pid": process.pid})
            except sandbox.SandboxError as e:
                client.reply(msg_id, error=str(e))
            except Exception as e:
                log(traceback.format_exc())
                client.reply(msg_id, error=f"{type(e).__name__}: {e}")

        if states["network"] == "ask":
            self.wait_for(app, "network", go)  # asked before the first start
        else:
            go(states["network"])

    def spawn_system(self, argv):
        process = subprocess.Popen(["systemd-run", "--user", "--scope", "--quiet", "--collect",
                                    "--slice=app-graphical.slice", *argv], start_new_session=True)
        GLib.child_watch_add(GLib.PRIORITY_DEFAULT, process.pid, lambda pid, _s: GLib.spawn_close_pid(pid))

    def on_sandbox_ended(self, pid, _status):
        GLib.spawn_close_pid(pid)
        app, instance = self.sandboxes.pop(pid, (None, None))
        if app:
            sandbox.cleanup(app, instance)

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


def main():
    GLib.set_prgname("riptide-session")
    service = Service()
    service.start()
    loop = GLib.MainLoop()
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, 15, lambda: (loop.quit(), False)[1])
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, 2, lambda: (loop.quit(), False)[1])
    loop.run()
    SOCKET.unlink(missing_ok=True)
