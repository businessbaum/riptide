"""Start a desktop app in its sandbox (docs/os-plan.md, "App permissions").

    app-sandbox <desktop-id> [file or URL …]   start the app
    app-sandbox --print <desktop-id>           show the sandbox command instead
    app-sandbox --shell <desktop-id> [cmd …]   a shell (or command) in the app's sandbox (testing)

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
        ".config/user-dirs.dirs", ".config/user-dirs.locale"]

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
    """The app's own folders in the home folder: from its profile, else folders named
    after it in ~/.config, ~/.local/share, ~/.local/state and ~/.cache. A name that is
    also another program (e.g. `claude`) is only used when the profile lists it."""
    folders = [Path(p).expanduser() for p in profile.get("data", []) if Path(p).expanduser().is_dir()]
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
        self.app = app
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

    # -------- helpers outside the sandbox

    def flatpak_info(self):
        shared = ["ipc"] + (["network"] if self.allowed["network"] else [])
        sockets = ["wayland"] + (["pulseaudio"] if self.sound() else [])
        return (f"[Application]\nname={self.app}\nruntime=runtime/org.riptide.Host/x86_64/host\n\n"
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
        helper = subprocess.Popen([HELPERS / "wl-security-context", socket, self.app, self.instance],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        if helper.stdout.readline().strip() != "ready":
            fail("Der abgesicherte Bildschirmzugang konnte nicht eingerichtet werden.")
        self.children.append(helper)
        return socket

    def start_dbus(self):
        """xdg-dbus-proxy for the session and system bus, itself in a small sandbox with
        the app's /.flatpak-info, so the portals see the app's identity behind it."""
        session, system = self.dir / "bus", self.dir / "system_bus"
        rules = ["--filter", f"--own={self.app}", f"--own={self.app}.*",
                 "--talk=org.freedesktop.portal.*", "--call=org.freedesktop.portal.*=*",
                 "--broadcast=org.freedesktop.portal.*=@/org/freedesktop/portal/*",
                 # menu bar icon and media controls
                 "--talk=org.kde.StatusNotifierWatcher", "--own=org.kde.*", "--own=org.mpris.MediaPlayer2.*"]
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
        for sys_dir in ("block", "bus", "class", "dev", "devices"):
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
              "--bind-try", str(RUNTIME / "doc/by-app" / self.app), str(RUNTIME / "doc")]
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
              "--setenv", "FLATPAK_ID", self.app, "--chdir", str(HOME)]
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
            self.instance_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
            (self.instance_dir / "bwrapinfo.json").write_bytes(bwrap_info)
            (self.instance_dir / "info").write_text(self.flatpak_info())
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


def main():
    args = sys.argv[1:]
    mode = "run"
    if args and args[0] in ("--print", "--shell"):
        mode, args = args[0][2:], args[1:]
    if not args:
        sys.exit(__doc__)
    app, rest = args[0].removesuffix(".desktop"), args[1:]

    entry = find_entry(app)
    argv = exec_argv(entry, [] if mode == "shell" else rest)
    profiles = load_profiles()
    if is_system_app(app, profiles) and mode == "run":
        os.execvp(argv[0], argv)

    states = permissions.get(app)
    if states["network"] == "ask" and mode == "run":
        states["network"] = ask(app, "network")
    sandbox = Sandbox(app, argv, profiles.get("apps", {}).get(app, {}), states)
    command = (rest or ["bash"]) if mode == "shell" else sandbox.argv
    sys.exit(sandbox.run(command, dry=(mode == "print")))
