"""Start a desktop app in its sandbox (docs/os-plan.md, "App permissions").

    app-sandbox <desktop-id> [file or URL …]   start the app
    app-sandbox --run <desktop-id> <cmd …>     run this command as the app (desktop entries)
    app-sandbox --print <desktop-id>           show the sandbox command instead
    app-sandbox --shell <desktop-id> [cmd …]   a shell (or command) in the app's sandbox (testing)
    app-sandbox --sync                         make every app start in its sandbox (see sync())

What the app sees:
  /usr, /etc (read-only), its GPU, a private /tmp and /dev without other devices
  home folder: only its own data folders, a container for everything else
      (~/.local/share/macos/sandbox/<app>/home) and the folders it may use
  Wayland: its own socket in a security context (wl-security-context) – no screen
      capture, no clipboard in the background, no input injection
  D-Bus: filtered (xdg-dbus-proxy): portals always; notifications, passwords,
      Bluetooth only with permission
  Sound: PipeWire unless microphone and speakers are both denied; WirePlumber decides
      per device and asks (macos/app-permissions.lua)
  Network: none without permission; with no decision yet the launcher asks first
  /.flatpak-info names the app, so portals and PipeWire know who is asking.

System apps (sandbox.json → system_apps) start without a sandbox.
"""

import configparser
import fcntl
import fnmatch
import json
import os
import re
import secrets
import shlex
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

from desktop_shell import permissions

HOME = Path.home()
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
HELPERS = HOME / ".local/lib/macos-sandbox"
CONTAINERS = HOME / ".local/share/macos/sandbox"
PROFILES = HOME / ".config/macos/sandbox.json"
ENTRY_DIRS = [Path("/usr/local/share/applications"), Path("/usr/share/applications"),
              HOME / ".local/share/applications"]

# The desktop's look, read-only in every sandbox
LOOK = [".config/gtk-3.0", ".config/gtk-4.0", ".gtkrc-2.0", ".config/fontconfig", ".local/share/fonts",
        ".config/qt5ct", ".config/qt6ct", ".config/Kvantum", ".local/share/icons", ".icons",
        ".config/user-dirs.dirs", ".config/user-dirs.locale",
        # default apps: read-only, so an app knows whether it is the default (Thunderbird)
        ".config/mimeapps.list"]

# Environment the app keeps; everything else is dropped (no SSH agent, no Hyprland socket …)
KEEP_ENV = re.compile(r"^(PATH|LANG|LANGUAGE|LC_.*|TZ|USER|LOGNAME|HOME|SHELL|TERM|XDG_CURRENT_DESKTOP|"
                      r"XDG_SESSION_TYPE|XDG_SESSION_DESKTOP|XDG_DATA_DIRS|XDG_CONFIG_DIRS|XCURSOR_.*|"
                      r"QT_.*|GTK_THEME|GDK_BACKEND|MOZ_.*|ELECTRON_OZONE_PLATFORM_HINT|NVD_BACKEND|"
                      r"LIBVA_DRIVER_NAME|__GLX_VENDOR_LIBRARY_NAME|GBM_BACKEND|__GL_.*)$")


def fail(message):
    print(f"app-sandbox: {message}", file=sys.stderr)
    subprocess.run(["notify-send", "-a", "System", "-i", "dialog-warning", "App konnte nicht starten", message])
    sys.exit(1)


# ---------------------------------------------------------------- desktop entry

def find_entry(app):
    """The app's own desktop file (not our override of it)."""
    for folder in ENTRY_DIRS:
        path = folder / f"{app}.desktop"
        if path.is_file():
            entry = read_entry(path)
            if entry.get("X-Sandbox-Override") != "true":
                return entry
    fail(f"„{app}“ ist keine installierte App.")


def read_entry(path):
    parser = configparser.RawConfigParser(strict=False, interpolation=None)
    parser.optionxform = str
    parser.read(path, encoding="utf-8")
    return dict(parser["Desktop Entry"]) if parser.has_section("Desktop Entry") else {}


def exec_argv(entry, args):
    """Exec= line as argv with its field codes filled in (Desktop Entry Specification)."""
    words = shlex.split(entry.get("Exec", ""))
    argv = []
    for word in words:
        if word in ("%f", "%u"):
            argv += args[:1]
        elif word in ("%F", "%U"):
            argv += args
        elif word == "%i":
            argv += ["--icon", entry["Icon"]] if entry.get("Icon") else []
        elif word == "%c":
            argv.append(entry.get("Name", ""))
        elif word in ("%k", "%d", "%D", "%n", "%N", "%v", "%m"):
            continue
        else:
            argv.append(word.replace("%%", "%"))
    if not argv:
        fail("Die App hat keinen Startbefehl.")
    return argv


# ---------------------------------------------------------------- profiles

def load_profiles():
    try:
        return json.loads(PROFILES.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def is_system_app(app, profiles):
    return any(fnmatch.fnmatchcase(app, pattern) for pattern in profiles.get("system_apps", []))


def data_folders(app, argv, profile):
    """The app's own folders (and files) in the home folder: from its profile, else folders named
    after it in ~/.config, ~/.local/share, ~/.local/state and ~/.cache. A name that is
    also another program (e.g. `claude`) is only used when the profile lists it."""
    folders = [Path(p).expanduser() for p in profile.get("data", []) if Path(p).expanduser().exists()]
    names = {app.lower(), app.rsplit(".", 1)[-1].lower(), Path(argv[0]).name.lower()}
    for name in sorted(names):
        other = shutil.which(name)
        if other and Path(other).resolve() != Path(shutil.which(argv[0]) or argv[0]).resolve():
            continue
        for place in (".config", ".local/share", ".local/state", ".cache"):
            base = HOME / place
            if base.is_dir():
                folders += [d for d in base.iterdir() if d.name.lower() == name and d.is_dir()]
    return sorted(set(folders))


def user_dirs():
    """XDG user folders (Schreibtisch, Dokumente, …) as real paths."""
    found = {}
    try:
        for line in (HOME / ".config/user-dirs.dirs").read_text(encoding="utf-8").splitlines():
            m = re.match(r'^XDG_(\w+)_DIR="(.*)"$', line.strip())
            if m:
                found[m.group(1)] = Path(m.group(2).replace("$HOME", str(HOME)))
    except OSError:
        pass
    return found


# ---------------------------------------------------------------- the sandbox

class Sandbox:
    def __init__(self, app, argv, profile, states):
        self.app = app                            # desktop id (files, profile, the user)
        self.id = permissions.store_key(app)      # id for portals, PipeWire, D-Bus
        self.argv = argv + profile.get("args", [])
        self.profile = profile
        self.states = states  # {kind: "yes" | "no" | "ask"}
        self.allowed = {kind: state == "yes" for kind, state in states.items()}
        self.instance = str(secrets.randbelow(2 ** 31))
        self.dir = RUNTIME / "macos-sandbox" / f"{app}-{self.instance}"
        self.tmp = RUNTIME / "macos-sandbox" / app / "tmp"  # shared by the app's windows
        self.container = CONTAINERS / app / "home"
        self.instance_dir = RUNTIME / ".flatpak" / self.instance
        self.children = []
        self.data = []  # fds bwrap reads (--ro-bind-data), closed once it started
        self.hold = []  # fds that keep the helpers alive while the app runs
        self.ref = None  # the instance's .ref, locked while the app runs

    # -------- helpers outside the sandbox

    def flatpak_info(self):
        shared = ["ipc"] + (["network"] if self.allowed["network"] else [])
        sockets = ["wayland"] + (["pulseaudio"] if self.sound() else [])
        return (f"[Application]\nname={self.id}\nruntime=runtime/org.riptide.Host/x86_64/host\n\n"
                f"[Instance]\ninstance-id={self.instance}\ninstance-path={self.container.parent}\n"
                f"app-path=/usr\nbranch=host\narch=x86_64\nflatpak-version=1.18.3\n"
                f"session-bus-proxy=true\nsystem-bus-proxy=true\n\n"
                f"[Context]\nshared={';'.join(shared)};\nsockets={';'.join(sockets)};\n")

    def data_fd(self, text):
        """A pipe with `text` for bwrap's --ro-bind-data."""
        r, w = os.pipe()
        os.write(w, text.encode())
        os.close(w)
        self.data.append(r)
        return r

    def start_wayland(self):
        socket = self.dir / "wayland-0"
        helper = subprocess.Popen([HELPERS / "wl-security-context", socket, self.id, self.instance],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        if helper.stdout.readline().strip() != "ready":
            fail("Der abgesicherte Bildschirmzugang konnte nicht eingerichtet werden.")
        self.children.append(helper)
        return socket

    def start_dbus(self):
        """xdg-dbus-proxy for the session and system bus, itself in a small sandbox with
        the app's /.flatpak-info, so the portals see the app's identity behind it."""
        session, system = self.dir / "bus", self.dir / "system_bus"
        # its own bus name, if its id can be one (needs a dot: "discord" cannot)
        own = [f"--own={self.id}", f"--own={self.id}.*"]
        rules = ["--filter", *own,
                 "--talk=org.freedesktop.portal.*", "--call=org.freedesktop.portal.*=*",
                 "--broadcast=org.freedesktop.portal.*=@/org/freedesktop/portal/*",
                 # menu bar icon: exact names only (StatusNotifierItem-<pid>-<n>, pids inside
                 # the sandbox are small), never a whole namespace: owning org.kde.* or
                 # org.freedesktop.* would let an app pose as a system service
                 "--talk=org.kde.StatusNotifierWatcher", "--talk=org.freedesktop.StatusNotifierWatcher",
                 *[f"--own={ns}.StatusNotifierItem-{pid}-{n}" for ns in ("org.kde", "org.freedesktop")
                   for pid in range(1, 40) for n in range(1, 4)],
                 # media controls (now playing, media keys)
                 "--own=org.mpris.MediaPlayer2.*"]
        rules += [f"--own={name}" for name in self.profile.get("dbus_own", [])]
        rules += [f"--talk={name}" for name in self.profile.get("dbus_own", [])]
        if self.allowed["notifications"]:
            rules.append("--talk=org.freedesktop.Notifications")
        if self.allowed["secrets"]:
            rules.append("--talk=org.freedesktop.secrets")
        system_rules = ["--filter"] + (["--talk=org.bluez"] if self.allowed["bluetooth"] else [])

        ready_r, ready_w = os.pipe()
        info = self.data_fd(self.flatpak_info())
        args = [f"unix:path={RUNTIME}/bus", str(session), *rules,
                "unix:path=/run/dbus/system_bus_socket", str(system), *system_rules]
        proxy = subprocess.Popen(
            ["bwrap", "--ro-bind", "/usr", "/usr", "--symlink", "usr/lib", "/lib", "--symlink", "usr/lib", "/lib64",
             "--symlink", "usr/bin", "/bin", "--ro-bind", "/etc", "/etc",
             "--bind", str(RUNTIME), str(RUNTIME), "--ro-bind", "/run/dbus", "/run/dbus",
             "--ro-bind-data", str(info), "/.flatpak-info", "--die-with-parent", "--unshare-pid",
             "--", "xdg-dbus-proxy", f"--fd={ready_w}", *args],
            pass_fds=(info, ready_w))
        os.close(ready_w)
        self.close_data()
        if os.read(ready_r, 1) != b"x":
            fail("Der D-Bus-Filter konnte nicht gestartet werden.")
        self.hold.append(ready_r)  # the proxy stops when this closes
        self.children.append(proxy)
        return session, system

    def sound(self):
        return self.states["microphone"] != "no" or self.states["speakers"] != "no"

    # -------- bwrap

    def bwrap_args(self, wayland, bus, system_bus):
        a = ["bwrap", "--unshare-pid", "--unshare-ipc", "--unshare-cgroup-try", "--die-with-parent",
             "--new-session", "--cap-drop", "ALL"]
        if not self.allowed["network"]:
            a.append("--unshare-net")

        # system
        a += ["--ro-bind", "/usr", "/usr", "--symlink", "usr/bin", "/bin", "--symlink", "usr/bin", "/sbin",
              "--symlink", "usr/lib", "/lib", "--symlink", "usr/lib", "/lib64",
              "--ro-bind", "/etc", "/etc", "--ro-bind-try", "/opt", "/opt",
              "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/var", "--tmpfs", "/run",
              "--ro-bind-try", "/var/cache/fontconfig", "/var/cache/fontconfig",
              "--bind", str(self.tmp), "/tmp", "--tmpfs", "/var/tmp",
              # links and mail addresses open through the portal, never inside the sandbox
              "--ro-bind-try", "/usr/lib/flatpak-xdg-utils/xdg-open", "/usr/bin/xdg-open",
              "--ro-bind-try", "/usr/lib/flatpak-xdg-utils/xdg-email", "/usr/bin/xdg-email"]
        # (module: the NVIDIA driver reads its parameters there, else apps fall back to the
        # onboard GPU and fail to hand frames to the compositor)
        for sys_dir in ("block", "bus", "class", "dev", "devices", "module"):
            a += ["--ro-bind-try", f"/sys/{sys_dir}", f"/sys/{sys_dir}"]

        # devices: the GPU always, the rest only with permission (never /dev/snd: sound
        # goes through PipeWire, which asks)
        a += ["--dev-bind-try", "/dev/dri", "/dev/dri"]
        for node in sorted(Path("/dev").glob("nvidia*")):
            a += ["--dev-bind", str(node), str(node)]
        if self.allowed["usb"]:
            for node in sorted(Path("/dev").glob("hidraw*")):
                a += ["--dev-bind", str(node), str(node)]
            a += ["--dev-bind-try", "/dev/input", "/dev/input", "--dev-bind-try", "/dev/bus/usb", "/dev/bus/usb"]
        if self.allowed["camera"]:
            for node in sorted(Path("/dev").glob("video*")):
                a += ["--dev-bind", str(node), str(node)]
        for node in self.profile.get("devices", []):  # what the app is known to need
            a += ["--dev-bind-try", node, node]

        # home folder: all of it with permission, else the app's container with its own
        # folders, the look and the folders it may use
        if self.allowed["home"]:
            a += ["--bind", str(HOME), str(HOME)]
        else:
            a += ["--bind", str(self.container), str(HOME)]
            for folder in data_folders(self.app, self.argv, self.profile):
                a += ["--bind", str(folder), str(folder)]
            for rel in LOOK:
                a += ["--ro-bind-try", str(HOME / rel), str(HOME / rel)]
            dirs = user_dirs()
            for kind, xdg in (("desktop", "DESKTOP"), ("documents", "DOCUMENTS"), ("downloads", "DOWNLOAD"),
                              ("pictures", "PICTURES"), ("music", "MUSIC"), ("videos", "VIDEOS")):
                if self.allowed[kind] and xdg in dirs:
                    a += ["--bind-try", str(dirs[xdg]), str(dirs[xdg])]
        if self.allowed["removable"]:
            a += ["--bind-try", f"/run/media/{os.environ.get('USER', '')}", f"/run/media/{os.environ.get('USER', '')}"]

        # runtime folder: Wayland, D-Bus, sound, documents chosen in file dialogs
        a += ["--tmpfs", str(RUNTIME), "--chmod", "0700", str(RUNTIME),
              "--bind", str(wayland), str(RUNTIME / "wayland-0"),
              "--bind", str(bus), str(RUNTIME / "bus"),
              "--bind", str(system_bus), "/run/dbus/system_bus_socket",
              "--bind-try", str(RUNTIME / "doc/by-app" / self.id), str(RUNTIME / "doc")]
        if self.sound():
            a += ["--bind", str(RUNTIME / "pipewire-0"), str(RUNTIME / "pipewire-0"),
                  "--bind", str(RUNTIME / "pulse/native"), str(RUNTIME / "pulse/native")]

        a += ["--ro-bind-data", str(self.data_fd(self.flatpak_info())), "/.flatpak-info"]

        # environment
        a.append("--clearenv")
        for name, value in os.environ.items():
            if KEEP_ENV.match(name):
                a += ["--setenv", name, value]
        a += ["--setenv", "XDG_RUNTIME_DIR", str(RUNTIME), "--setenv", "WAYLAND_DISPLAY", "wayland-0",
              "--setenv", "DBUS_SESSION_BUS_ADDRESS", f"unix:path={RUNTIME}/bus",
              "--setenv", "GTK_USE_PORTAL", "1", "--setenv", "NO_AT_BRIDGE", "1", "--setenv", "GTK_A11Y", "none",
              "--setenv", "FLATPAK_ID", self.id, "--chdir", str(HOME)]
        return a

    # -------- run

    def prepare(self):
        for d in (self.dir, self.tmp, self.container):
            d.mkdir(parents=True, exist_ok=True, mode=0o700)

    def run(self, command, dry=False):
        self.prepare()
        try:
            wayland = self.start_wayland()
            bus, system_bus = self.start_dbus()
            # bwrap tells where the sandbox is (--info-fd) and waits (--block-fd) until the
            # portals can find that out, like Flatpak does: they check a caller against
            # $XDG_RUNTIME_DIR/.flatpak/<instance>/bwrapinfo.json
            info_r, info_w = os.pipe()
            block_r, block_w = os.pipe()
            argv = self.bwrap_args(wayland, bus, system_bus) + [
                "--info-fd", str(info_w), "--block-fd", str(block_r), "--", *command]
            if dry:
                print(shlex.join(argv))
                return 0
            app = subprocess.Popen(argv, pass_fds=self.data + [info_w, block_r])
            os.close(info_w)
            os.close(block_r)
            self.close_data()
            with os.fdopen(info_r, "rb") as f:
                bwrap_info = f.read()
            # the same layout as a Flatpak instance: the portal reads every instance (e.g. for
            # background apps) and crashes on an incomplete one. `.ref` stays read-locked
            # while the app runs; that is how "running" is recognised.
            self.instance_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
            (self.instance_dir / "bwrapinfo.json").write_bytes(bwrap_info)
            (self.instance_dir / "info").write_text(self.flatpak_info())
            (self.instance_dir / "pid").write_text(str(app.pid))
            self.ref = open(self.instance_dir / ".ref", "a+")  # a read lock needs read access
            fcntl.lockf(self.ref, fcntl.LOCK_SH | fcntl.LOCK_NB)
            os.write(block_w, b"x")
            os.close(block_w)
            signal.signal(signal.SIGTERM, lambda *_: app.terminate())
            signal.signal(signal.SIGINT, lambda *_: app.terminate())
            return app.wait()
        finally:
            self.stop()

    def close_data(self):
        for fd in self.data:
            os.close(fd)
        self.data = []

    def stop(self):
        self.close_data()
        if self.ref:
            self.ref.close()
            self.ref = None
        for fd in self.hold:
            os.close(fd)
        self.hold = []
        for child in self.children:
            if child.stdin:
                child.stdin.close()
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
        shutil.rmtree(self.dir, ignore_errors=True)
        shutil.rmtree(self.instance_dir, ignore_errors=True)


def ask(app, kind, timeout=300):
    """Have the shell ask (Privacy.qml) and wait for the answer; no answer counts as no."""
    subprocess.run(["qs", "ipc", "call", "privacy", "request", app, kind], capture_output=True)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        state = permissions.get(app)[kind]
        if state != "ask":
            return state
        time.sleep(0.4)
    return "no"


# ---------------------------------------------------------------- files handed to the app

def forward_files(app_id, args):
    """Files and folders passed to the app (a double click in the file manager, "open
    with", an attachment) are given to it through the document portal – just these, like
    Flatpak does – and it gets their path inside its sandbox. Other arguments stay."""
    from urllib.parse import unquote, urlparse

    from gi.repository import Gio, GLib

    result = []
    bus = None
    for arg in args:
        uri = arg.startswith("file://")
        path = Path(unquote(urlparse(arg).path)) if uri else Path(arg)
        if not path.is_absolute() or not path.exists():
            result.append(arg)
            continue
        try:
            bus = bus or Gio.bus_get_sync(Gio.BusType.SESSION, None)
            fd = os.open(path, os.O_PATH | os.O_CLOEXEC)
            fds = Gio.UnixFDList.new_from_array([fd])
            # flags: 1 reuse an existing document, 8 the path is a folder
            flags = 1 | (8 if path.is_dir() else 0)
            reply, _ = bus.call_with_unix_fd_list_sync(
                "org.freedesktop.portal.Documents", "/org/freedesktop/portal/documents",
                "org.freedesktop.portal.Documents", "AddFull",
                GLib.Variant("(ahusas)", ([0], flags, app_id, ["read", "write"])),
                GLib.VariantType("(asa{sv})"), Gio.DBusCallFlags.NONE, 5000, fds, None)
            doc_id = reply.unpack()[0][0]
            inside = RUNTIME / "doc" / doc_id / path.name
            result.append(f"file://{inside}" if uri else str(inside))
        except (OSError, GLib.Error) as e:
            print(f"app-sandbox: {path} could not be handed to the app: {e}", file=sys.stderr)
            result.append(arg)
    return result


# ---------------------------------------------------------------- every app sandboxed

OVERRIDES = HOME / ".local/share/applications"
DBUS_OVERRIDES = HOME / ".local/share/dbus-1/services"
MARK = "X-Sandbox-Override"


def sync():
    """Make every app start in its sandbox, however it is started: dock, Spotlight,
    Launchpad, a file or link opened by another app, D-Bus activation. For each app in
    /usr/share/applications (not system apps, not hidden helpers, not terminal programs)
    an override with the same id goes to ~/.local/share/applications, whose Exec lines run
    `app-sandbox --run`; D-Bus activatable apps also get a service override. Overrides of
    apps that are gone or became system apps are removed. Runs at login and whenever apps
    are installed or removed (app-sandbox-sync.path)."""
    profiles = load_profiles()
    me = HOME / ".local/bin/app-sandbox"
    wanted = {}
    for folder in (Path("/usr/share/applications"), Path("/usr/local/share/applications")):
        for source in sorted(folder.glob("*.desktop")):
            app = source.stem
            entry = read_entry(source)
            if (entry.get("Type") != "Application" or entry.get("NoDisplay") == "true"
                    or entry.get("Hidden") == "true" or entry.get("Terminal") == "true"
                    or is_system_app(app, profiles) or "flatpak run" in entry.get("Exec", "")
                    or app in wanted or own_entry(OVERRIDES / source.name)):
                continue
            wanted[app] = source

    OVERRIDES.mkdir(parents=True, exist_ok=True)
    DBUS_OVERRIDES.mkdir(parents=True, exist_ok=True)
    for app, source in wanted.items():
        lines, dbus = [], False
        for line in source.read_text(encoding="utf-8").splitlines():
            if line.startswith("Exec="):
                line = f"Exec={me} --run {app} {line[5:]}"
            elif line.startswith("DBusActivatable="):
                dbus = line.strip() == "DBusActivatable=true"
                continue  # launchers must use Exec (sandboxed), not D-Bus
            lines.append(line)
            if line.strip() == "[Desktop Entry]":
                lines += [f"{MARK}=true", f"X-Sandbox-Source={source}"]
        text = (f"# Made by app-sandbox --sync: starts {app} in its sandbox. Do not edit.\n"
                + "\n".join(lines) + "\n")
        write_if_changed(OVERRIDES / source.name, text)
        service = Path("/usr/share/dbus-1/services") / f"{app}.service"
        if dbus and service.is_file():
            exec_line = next((l[5:] for l in service.read_text(encoding="utf-8").splitlines()
                              if l.startswith("Exec=")), None)
            if exec_line:
                write_if_changed(DBUS_OVERRIDES / service.name,
                                 f"# Made by app-sandbox --sync ({MARK}): starts {app} in its sandbox.\n"
                                 f"[D-BUS Service]\nName={app}\nExec={me} --run {app} {exec_line}\n")

    # remove overrides of apps that are gone or are system apps now
    for path in OVERRIDES.glob("*.desktop"):
        if not path.is_symlink() and path.stem not in wanted and read_entry(path).get(MARK) == "true":
            path.unlink()
    for path in DBUS_OVERRIDES.glob("*.service"):
        if path.stem not in wanted and MARK in path.read_text(encoding="utf-8").split("\n", 1)[0]:
            path.unlink()
    subprocess.run(["update-desktop-database", str(OVERRIDES)], capture_output=True)


def own_entry(path):
    """A start entry of our own (dotfiles, e.g. hiding a helper app) is never replaced."""
    return path.is_symlink() or (path.exists() and read_entry(path).get(MARK) != "true")


def write_if_changed(path, text):
    if path.is_symlink():
        return
    if not path.exists() or path.read_text(encoding="utf-8") != text:
        tmp = path.with_name(f".{path.name}.tmp")
        tmp.write_text(text, encoding="utf-8")
        tmp.replace(path)


def main():
    args = sys.argv[1:]
    if args == ["--sync"]:
        return sync()
    mode = "start"
    if args and args[0] in ("--print", "--shell", "--run"):
        mode, args = args[0][2:], args[1:]
    if not args or (mode == "run" and len(args) < 2):
        sys.exit(__doc__)
    app, rest = args[0].removesuffix(".desktop"), args[1:]
    profiles = load_profiles()
    launching = mode in ("start", "run")
    if launching and not is_system_app(app, profiles):
        first = 1 if mode == "run" else 0  # (with --run the first word is the program)
        rest = rest[:first] + forward_files(permissions.store_key(app), rest[first:])
    if mode == "run":
        argv = rest  # a desktop entry's command, field codes already filled in
    else:
        argv = exec_argv(find_entry(app), [] if mode == "shell" else rest)
    if is_system_app(app, profiles) and launching:
        os.execvp(argv[0], argv)

    states = permissions.get(app)
    if states["network"] == "ask" and launching:
        states["network"] = ask(app, "network")
    sandbox = Sandbox(app, argv, profiles.get("apps", {}).get(app, {}), states)
    command = (rest or ["bash"]) if mode == "shell" else sandbox.argv
    sys.exit(sandbox.run(command, dry=(mode == "print")))
