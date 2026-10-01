"""Start a desktop app in its sandbox (docs/os-plan.md, "App permissions").

    app-sandbox <desktop-id> [file or URL …]   start the app
    app-sandbox --run <desktop-id> <cmd …>     run this command as the app (desktop entries)
    app-sandbox --print <desktop-id>           show the sandbox command instead
    app-sandbox --shell <desktop-id> [cmd …]   a shell (or command) in the app's sandbox (testing)
    app-sandbox --sync                         make every app start in its sandbox (see sync())

Starting is done by the session service (riptide-session, session.py): this command only
hands it the start and returns at once. The service asks first if needed, starts the
sandbox in its own systemd scope and cleans up after it. Nothing of ours keeps running
per app: the helpers end with the sandbox.

What the app sees:
  /usr, /etc (read-only), its GPU, a private /tmp and /dev without other devices
  home folder: only its own data folders, a container for everything else
      (~/.local/share/macos/sandbox/<app>/home) and the folders it may use
  Wayland: its own socket in a security context (wl-security-context) – no screen
      capture, no clipboard in the background, no input injection
  D-Bus: filtered (xdg-dbus-proxy): portals, notifications (the server asks), menu bar
      icon and media controls; passwords and Bluetooth only with permission
  Sound: PipeWire unless microphone and speakers are both denied; WirePlumber decides
      per device and asks (macos/app-permissions.lua)
  Network: none without permission; with no decision yet the service asks first
  Files it is given (double click, "open with") come through the document portal.
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
import subprocess
import sys
import time
from pathlib import Path

from desktop_shell import login_items, paths, permissions

HOME = Path.home()
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
HELPERS = paths.SANDBOX
# our flatpak-spawn, bound over the real one in every sandbox (see that file)
FLATPAK_SPAWN = Path(__file__).resolve().parent / "flatpak-spawn"
CONTAINERS = HOME / ".local/share/macos/sandbox"
PROFILES = paths.DATA / "sandbox.json"
# start entries of apps that are no packages – from release archives (archive_apps.py)
# and web apps (WhatsApp, in git): not on the desktop's own search path – only their
# sandboxed overrides are (sync)
ARCHIVE_ENTRIES = HOME / ".local/share/macos/apps/entries"
ENTRY_DIRS = [Path("/usr/local/share/applications"), Path("/usr/share/applications"), ARCHIVE_ENTRIES,
              HOME / ".local/share/applications"]

# The desktop's look, read-only in every sandbox
LOOK = [".config/gtk-3.0", ".config/gtk-4.0", ".gtkrc-2.0", ".config/fontconfig", ".local/share/fonts",
        ".config/qt5ct", ".config/qt6ct", ".config/Kvantum", ".local/share/icons", ".icons",
        ".config/user-dirs.dirs", ".config/user-dirs.locale"]

# Links and files opened from a sandbox. The default apps live outside it (zen.desktop is
# our sandbox of Zen), so an app that asked GIO for "the browser" found none there and
# started whatever program knows the scheme – Chromium, inside Thunderbird's sandbox with
# Thunderbird's rights. In every sandbox every link and file type points to this entry
# instead: xdg-open, the portal's, so the desktop opens it in its default app, in that
# app's own sandbox (which app: our portal backend, session.py – no question asked).
LINK_SCHEMES = ("http", "https", "mailto")
FORWARDER = "riptide-open.desktop"

# The portals an app may use: the desktop portal (files, screen, camera, links …), the
# document portal (files it was given) and the input method portals
PORTALS = ("org.freedesktop.portal.Desktop", "org.freedesktop.portal.Documents",
           "org.freedesktop.portal.IBus", "org.freedesktop.portal.Fcitx")

# Environment the app keeps; everything else is dropped (no SSH agent, no Hyprland socket …)
KEEP_ENV = re.compile(r"^(PATH|LANG|LANGUAGE|LC_.*|TZ|USER|LOGNAME|HOME|SHELL|TERM|XDG_CURRENT_DESKTOP|"
                      r"XDG_SESSION_TYPE|XDG_SESSION_DESKTOP|XDG_DATA_DIRS|XDG_CONFIG_DIRS|XCURSOR_.*|"
                      r"QT_.*|GTK_THEME|GDK_BACKEND|MOZ_.*|ELECTRON_OZONE_PLATFORM_HINT|NVD_BACKEND|"
                      r"LIBVA_DRIVER_NAME|__GLX_VENDOR_LIBRARY_NAME|GBM_BACKEND|__GL_.*)$")


class SandboxError(Exception):
    """Something the user should hear about ("App konnte nicht starten")."""


def fail(message):
    raise SandboxError(message)


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


def sandbox_defaults(app):
    """The default apps as a sandboxed app sees them (mimeapps.list, read-only, so it knows
    whether it is the default) and the entry that hands its links and files out: every
    type an installed app opens. What the desktop gives to this app stays its own, and so
    do the schemes it handles itself (Thunderbird asks whether it is the one for mailto)."""
    parser = configparser.RawConfigParser(strict=False, interpolation=None)
    parser.optionxform = str
    try:
        parser.read(HOME / ".config/mimeapps.list", encoding="utf-8")
    except (OSError, configparser.Error):
        pass
    defaults = dict(parser["Default Applications"]) if parser.has_section("Default Applications") else {}
    kinds = {f"x-scheme-handler/{s}" for s in LINK_SCHEMES} | set(defaults)
    own = {k for k, v in defaults.items() if v.split(";")[0] == f"{app}.desktop"}
    for folder in ENTRY_DIRS:
        for path in folder.glob("*.desktop") if folder.is_dir() else []:
            types = {m for m in read_entry(path).get("MimeType", "").split(";") if m}
            kinds |= types
            if path.stem == app:
                own |= {m for m in types if m.startswith("x-scheme-handler/")}
    kinds -= own
    for kind in kinds:
        defaults[kind] = FORWARDER
    mimeapps = "[Default Applications]\n" + "".join(f"{k}={v}\n" for k, v in sorted(defaults.items()))
    entry = ("[Desktop Entry]\nType=Application\nName=Standard-App\nNoDisplay=true\nExec=xdg-open %u\n"
             f"MimeType={';'.join(sorted(kinds))};\n")
    return mimeapps, entry


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
    if profile.get("data_auto") is False:
        return sorted(set(folders))  # (WhatsApp runs chromium: not the browser's ~/.config/chromium)
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


def app_name(app):
    """The name the user knows an app by (its start entry), else its id."""
    for folder in ENTRY_DIRS:
        path = folder / f"{app}.desktop"
        if path.is_file():
            entry = read_entry(path)
            return entry.get("Name[de]") or entry.get("Name") or app
    return app


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
        # extra start arguments right after the program: before a "--" that ends the options
        self.argv = argv[:1] + profile.get("args", []) + argv[1:]
        self.profile = profile
        self.states = states  # {kind: "yes" | "no" | "ask"}
        self.allowed = {kind: state == "yes" for kind, state in states.items()}
        self.instance = str(secrets.randbelow(2 ** 31))
        self.dir = RUNTIME / "macos-sandbox" / f"{app}-{self.instance}"
        self.tmp = RUNTIME / "macos-sandbox" / app / "tmp"  # shared by the app's windows
        self.container = CONTAINERS / app / "home"
        self.instance_dir = RUNTIME / ".flatpak" / self.instance
        self.unit = f"app-sandbox-{re.sub(r'[^A-Za-z0-9_.]', '_', app)}-{self.instance}"
        self.guard = None  # called with the scope's name right before the app runs
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

    def start_wayland(self, life):
        """The Wayland socket in a security context; the helper ends when `life` (the
        write end of the sandbox's lifetime pipe) has no reader any more."""
        socket = self.dir / "wayland-0"
        helper = subprocess.Popen([HELPERS / "wl-security-context", socket, self.id, self.instance],
                                  stdin=life, stdout=subprocess.PIPE, text=True, start_new_session=True)
        ready = helper.stdout.readline().strip() == "ready"
        helper.stdout.close()
        self.children.append(helper.pid)
        if not ready:
            raise SandboxError("Der abgesicherte Bildschirmzugang konnte nicht eingerichtet werden.")
        return socket

    def start_dbus(self, life_w, life_r):
        """xdg-dbus-proxy for the session and system bus, itself in a small sandbox with
        the app's /.flatpak-info, so the portals see the app's identity behind it. It
        writes one byte to `life_w` when ready and ends when that pipe has no reader."""
        session, system = self.dir / "bus", self.dir / "system_bus"
        rules = ["--filter", f"--own={self.id}", f"--own={self.id}.*",
                 # the portals by name, not org.freedesktop.portal.*: that includes the
                 # Flatpak portal, which starts programs outside the sandbox (and cannot
                 # for our apps, they are no real Flatpaks; flatpak-spawn is our own here)
                 *[f"--talk={name}" for name in PORTALS],
                 *[f"--broadcast={name}=@/org/freedesktop/portal/*" for name in PORTALS],
                 # menu bar icon: exact names only (StatusNotifierItem-<pid>-<n>), never a whole
                 # namespace: owning org.kde.* or org.freedesktop.* would let an app pose as a
                 # system service. The app's main process registers it, and inside the sandbox
                 # that is pid 2 (bwrap is 1), so pids 2–9 are plenty. (Every name costs two
                 # checks on each new D-Bus connection: 1–39 made one ~4x slower.)
                 "--talk=org.kde.StatusNotifierWatcher", "--talk=org.freedesktop.StatusNotifierWatcher",
                 *[f"--own={ns}.StatusNotifierItem-{pid}-{n}" for ns in ("org.kde", "org.freedesktop")
                   for pid in range(2, 10) for n in range(1, 4)],
                 # media controls (now playing, media keys)
                 "--own=org.mpris.MediaPlayer2.*",
                 # notifications: the notification server itself asks and decides
                 "--talk=org.freedesktop.Notifications"]
        rules += [f"--own={name}" for name in self.profile.get("dbus_own", [])]
        rules += [f"--talk={name}" for name in self.profile.get("dbus_own", [])]
        if self.allowed["secrets"]:
            rules.append("--talk=org.freedesktop.secrets")
        system_rules = ["--filter"] + (["--talk=org.bluez"] if self.allowed["bluetooth"] else [])

        info = self.data_fd(self.flatpak_info())
        # --log: every call goes to dbus.log; the session service reads it to see what the
        # app asks for (screen sharing) and what it tried without permission (passwords,
        # Bluetooth), and keeps the file small
        args = [f"unix:path={RUNTIME}/bus", str(session), "--log", *rules,
                "unix:path=/run/dbus/system_bus_socket", str(system), "--log", *system_rules]
        log = open(self.dir / "dbus.log", "ab")
        proxy = subprocess.Popen(
            ["bwrap", "--ro-bind", "/usr", "/usr", "--symlink", "usr/lib", "/lib", "--symlink", "usr/lib", "/lib64",
             "--symlink", "usr/bin", "/bin", "--ro-bind", "/etc", "/etc",
             "--bind", str(RUNTIME), str(RUNTIME), "--ro-bind", "/run/dbus", "/run/dbus",
             "--ro-bind-data", str(info), "/.flatpak-info", "--unshare-pid",
             # (line-buffered: the service must see a call the moment it happens)
             "--", "stdbuf", "-oL", "-eL", "xdg-dbus-proxy", f"--fd={life_w}", *args],
            pass_fds=(info, life_w), start_new_session=True, stdout=log, stderr=log)
        log.close()
        self.close_data()
        self.children.append(proxy.pid)
        if os.read(life_r, 1) != b"x":
            raise SandboxError("Der D-Bus-Filter konnte nicht gestartet werden.")
        return session, system

    def sound(self):
        return self.states["microphone"] != "no" or self.states["speakers"] != "no"

    # -------- bwrap

    def bwrap_args(self, wayland, bus, system_bus):
        # (no --die-with-parent: the app must outlive whoever started it)
        a = ["bwrap", "--unshare-pid", "--unshare-ipc", "--unshare-cgroup-try",
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
              "--ro-bind-try", "/usr/lib/flatpak-xdg-utils/xdg-email", "/usr/bin/xdg-email",
              # helpers of the app (glycin's image loaders) start inside its sandbox, not
              # through the Flatpak portal, which cannot start anything for our apps
              "--ro-bind", str(FLATPAK_SPAWN), "/usr/lib/flatpak-xdg-utils/flatpak-spawn"]
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
        # the default apps, links and files handed out (sandbox_defaults)
        mimeapps, forwarder = sandbox_defaults(self.app)
        a += ["--ro-bind-data", str(self.data_fd(mimeapps)), str(HOME / ".config/mimeapps.list")]
        # folders it may only read: its program when it does not live in /usr (an app from a
        # release archive, archive_apps.py – it cannot change itself)
        for folder in self.profile.get("ro", []):
            path = Path(folder).expanduser()
            a += ["--ro-bind-try", str(path), str(path)]

        # runtime folder: Wayland, D-Bus, sound, documents chosen in file dialogs
        a += ["--tmpfs", str(RUNTIME), "--chmod", "0700", str(RUNTIME),
              "--bind", str(wayland), str(RUNTIME / "wayland-0"),
              "--bind", str(bus), str(RUNTIME / "bus"),
              "--bind", str(system_bus), "/run/dbus/system_bus_socket",
              "--bind-try", str(RUNTIME / "doc/by-app" / self.id), str(RUNTIME / "doc"),
              # the entry that hands links and files out (sandbox_defaults), on its own data path
              "--ro-bind-data", str(self.data_fd(forwarder)), str(RUNTIME / "riptide/applications" / FORWARDER)]
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
              "--setenv", "FLATPAK_ID", self.id,
              "--setenv", "XDG_DATA_DIRS", f"{RUNTIME}/riptide:" + (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"),
              # Electron/Chromium name their notifications after it (desktop-entry), else
              # they arrive without any sender and cannot be told apart
              "--setenv", "CHROME_DESKTOP", f"{self.app}.desktop", "--chdir", str(HOME)]
        for name, value in self.profile.get("env", {}).items():  # what the app is known to need
            a += ["--setenv", name, str(value)]
        return a

    # -------- start

    def prepare(self):
        for d in (self.dir, self.tmp, self.container, self.instance_dir):
            d.mkdir(parents=True, exist_ok=True, mode=0o700)
        (self.instance_dir / ".ref").touch()
        (self.instance_dir / "info").write_text(self.flatpak_info())

    def start(self, command, dry=False):
        """Start the app in its sandbox and return its process at once. Nothing has to
        keep running for it: the helpers end with the sandbox (they hold the write end of
        a pipe whose only reader is bwrap, --sync-fd), bwrap keeps the instance marked as
        running itself (--lock-file on .ref), and cleanup() removes what is left after it
        ended (the session service, or gc() at its next start)."""
        self.prepare()
        life_r, life_w = os.pipe()
        try:
            wayland = self.start_wayland(life_w)
            bus, system_bus = self.start_dbus(life_w, life_r)
            os.close(life_w)
            life_w = None
            # bwrap tells where the sandbox is (--info-fd) and waits (--block-fd) until the
            # portals can find that out, like Flatpak does: they check a caller against
            # $XDG_RUNTIME_DIR/.flatpak/<instance>/bwrapinfo.json
            info_r, info_w = os.pipe()
            block_r, block_w = os.pipe()
            argv = self.bwrap_args(wayland, bus, system_bus) + [
                "--ro-bind", str(self.instance_dir / ".ref"), "/run/.ref", "--lock-file", "/run/.ref",
                "--sync-fd", str(life_r), "--info-fd", str(info_w), "--block-fd", str(block_r),
                "--", *command]
            if dry:
                print(shlex.join(argv))
                return None
            # its own systemd scope next to the other apps (not inside the service)
            # (Delegate: so the helpers can be moved into it, join_scope)
            scope = ["systemd-run", "--user", "--scope", "--quiet", "--collect", "--slice=app-graphical.slice",
                     "--property=Delegate=yes", f"--unit={self.unit}"]
            app = subprocess.Popen(scope + argv, pass_fds=self.data + [info_w, block_r, life_r],
                                   start_new_session=True)
            for fd in (info_w, block_r, life_r):
                os.close(fd)
            life_r = None
            self.close_data()
            with os.fdopen(info_r, "rb") as f:
                bwrap_info = f.read()
            (self.instance_dir / "bwrapinfo.json").write_bytes(bwrap_info)
            (self.instance_dir / "pid").write_text(str(app.pid))
            self.join_scope()
            # (the scope exists, the app has not started: e.g. its local network rules, lan.py)
            if self.guard:
                try:
                    self.guard(f"{self.unit}.scope")
                except Exception as e:  # a failed guard must not keep the app from starting
                    print(f"app-sandbox: guard: {type(e).__name__}: {e}", file=sys.stderr)
            os.write(block_w, b"x")
            os.close(block_w)
            return app
        except BaseException:
            self.close_data()
            cleanup(self.app, self.instance)
            raise
        finally:
            for fd in (life_r, life_w):
                if fd is not None:
                    os.close(fd)

    def join_scope(self):
        """Move the helpers into the app's scope: all its processes together, and they
        outlive whoever started them (a restart of the session service)."""
        from gi.repository import Gio, GLib

        pids = []
        for pid in self.children:
            pids += [pid, *descendants(pid)]
        try:
            Gio.bus_get_sync(Gio.BusType.SESSION, None).call_sync(
                "org.freedesktop.systemd1", "/org/freedesktop/systemd1", "org.freedesktop.systemd1.Manager",
                "AttachProcessesToUnit", GLib.Variant("(ssau)", (f"{self.unit}.scope", "", pids)),
                None, Gio.DBusCallFlags.NONE, 5000, None)
        except GLib.Error as e:
            print(f"app-sandbox: helpers stay outside the app's scope: {e.message}", file=sys.stderr)

    def close_data(self):
        for fd in self.data:
            os.close(fd)
        self.data = []


def descendants(pid):
    """Child processes of pid, and theirs."""
    found = []
    for task in Path(f"/proc/{pid}/task").glob("*"):
        try:
            children = (task / "children").read_text().split()
        except OSError:
            continue
        for child in map(int, children):
            found += [child, *descendants(child)]
    return found


def cleanup(app, instance):
    """Remove what a sandbox leaves behind once it has ended."""
    shutil.rmtree(RUNTIME / "macos-sandbox" / f"{app}-{instance}", ignore_errors=True)
    shutil.rmtree(RUNTIME / ".flatpak" / instance, ignore_errors=True)


def running(instance_dir):
    """Is the sandbox of this instance still running? (bwrap holds a lock on .ref)"""
    try:
        with open(instance_dir / ".ref", "a+") as ref:
            fcntl.lockf(ref, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return False
    except BlockingIOError:
        return True
    except OSError:
        return False


def instances():
    """[(app, instance, instance_dir)] of our sandboxes (running or ended)."""
    found = []
    for folder in (RUNTIME / ".flatpak").glob("*"):
        try:
            info = (folder / "info").read_text()
        except OSError:
            continue
        if "runtime=runtime/org.riptide.Host/" in info:
            app = next((d.name.rsplit("-", 1)[0] for d in (RUNTIME / "macos-sandbox").glob(f"*-{folder.name}")), None)
            found.append((app, folder.name, folder))
    return found


def gc():
    """Clean up after sandboxes that have ended (e.g. while the service was not running)."""
    for app, instance, folder in instances():
        if not running(folder):
            if app:
                cleanup(app, instance)
            else:
                shutil.rmtree(folder, ignore_errors=True)


def prepare_launch(app, args, run):
    """What starting `app` means: (system app?, command, profile, permissions). With `run`
    the args are a desktop entry's command, else files or links for the app. Files are
    handed over through the document portal (forward_files)."""
    profiles = load_profiles()
    system = is_system_app(app, profiles)
    first = 1 if run else 0  # (with run the first word is the program)
    if not system:
        args = args[:first] + forward_files(permissions.store_key(app), args[first:])
    argv = args if run else exec_argv(find_entry(app), args)
    if not argv:
        fail("Die App hat keinen Startbefehl.")
    return system, argv, profiles.get("apps", {}).get(app, {}), permissions.get(app)


SERVICE_SOCKET = RUNTIME / "riptide" / "session.sock"


def call_service(message, timeout=360):
    """One call to the session service (riptide-session); starts it when it is not running."""
    import socket

    for attempt in range(2):
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            sock.connect(str(SERVICE_SOCKET))
            break
        except OSError:
            sock.close()
            if attempt:
                fail("Der Systemdienst riptide-session läuft nicht.")
            subprocess.run(["systemctl", "--user", "start", "riptide-session.service"], capture_output=True)
            for _ in range(50):
                if SERVICE_SOCKET.exists():
                    break
                time.sleep(0.1)
    with sock:
        sock.settimeout(timeout)
        sock.sendall((json.dumps({"id": 1, **message}) + "\n").encode())
        data = b""
        while not data.endswith(b"\n"):
            chunk = sock.recv(65536)
            if not chunk:
                break
            data += chunk
    try:
        reply = json.loads(data)
    except ValueError:
        fail("Keine Antwort vom Systemdienst.")
    if "error" in reply:
        fail(reply["error"])
    return reply.get("result")


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
    me = paths.BIN / "app-sandbox"
    wanted = {}
    for folder in (Path("/usr/share/applications"), Path("/usr/local/share/applications"), ARCHIVE_ENTRIES):
        for source in sorted(folder.glob("*.desktop")):
            app = source.stem
            entry = read_entry(source)
            if (entry.get("Type") != "Application" or entry.get("NoDisplay") == "true"
                    or entry.get("Hidden") == "true" or entry.get("Terminal") == "true"
                    or is_system_app(app, profiles)
                    or app in wanted or own_entry(OVERRIDES / source.name)):
                continue
            wanted[app] = source

    # Entries that are only a part of another app (e.g. the settings of Tor Browser's
    # launcher): hidden from Launchpad and Spotlight, run in that app's sandbox, and offered
    # as an action in its menu instead – one app, like on a Mac
    parts = find_parts(wanted, profiles)  # part → (main app, name)
    actions = {}  # main app → [(action id, name, command)]
    for part, (main, name) in sorted(parts.items()):
        listed = actions.setdefault(main, [])
        listed.append((f"Part{len(listed)}", name, read_entry(wanted[part])["Exec"]))

    OVERRIDES.mkdir(parents=True, exist_ok=True)
    DBUS_OVERRIDES.mkdir(parents=True, exist_ok=True)
    for app, source in wanted.items():
        box = parts[app][0] if app in parts else app
        lines, dbus = [], False
        for line in source.read_text(encoding="utf-8").splitlines():
            if line.startswith("Exec="):
                line = f"Exec={me} --run {box} {line[5:]}"
            elif line.startswith("DBusActivatable="):
                dbus = line.strip() == "DBusActivatable=true"
                continue  # launchers must use Exec (sandboxed), not D-Bus
            elif line.startswith(("NoDisplay=", "Actions=")) and (app in parts or app in actions):
                if line.startswith("Actions=") and app in actions:
                    line = line.rstrip(";") + ";" + ";".join(a[0] for a in actions[app]) + ";"
                elif line.startswith("NoDisplay="):
                    continue
            lines.append(line)
            if line.strip() == "[Desktop Entry]":
                lines += [f"{MARK}=true", f"X-Sandbox-Source={source}"]
                if app in parts:
                    lines.append("NoDisplay=true")
        if app in actions:
            if not any(l.startswith("Actions=") for l in lines):
                i = lines.index("[Desktop Entry]") + 1
                lines.insert(i, "Actions=" + ";".join(a[0] for a in actions[app]) + ";")
            for action_id, name, command in actions[app]:
                lines += ["", f"[Desktop Action {action_id}]", f"Name={name}", f"Exec={me} --run {app} {command}"]
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
                                 f"[D-BUS Service]\nName={app}\nExec={me} --run {box} {exec_line}\n")

    # remove overrides of apps that are gone or are system apps now
    for path in OVERRIDES.glob("*.desktop"):
        if not path.is_symlink() and path.stem not in wanted and read_entry(path).get(MARK) == "true":
            path.unlink()
    for path in DBUS_OVERRIDES.glob("*.service"):
        if path.stem not in wanted and MARK in path.read_text(encoding="utf-8").split("\n", 1)[0]:
            path.unlink()
    subprocess.run(["update-desktop-database", str(OVERRIDES)], capture_output=True)
    # login items are copies of these entries: brought up to date with them
    login_items.refresh([OVERRIDES, Path("/usr/local/share/applications"), Path("/usr/share/applications")])


def find_parts(wanted, profiles):
    """Which start entries are only a part of another app, found by themselves: entries of
    the same package that run the same program are one app (Tor Browser and "Tor Browser
    Launcher Settings" both run torbrowser-launcher). The one with the plainest command is
    the app, the others become its parts. Tools of one package with programs of their own
    (avahi's bssh and bvnc) stay apps of their own. Safe for the sandbox: a part is the same
    program, so it gets no more than the app already has. sandbox.json can still say
    otherwise: "part_of" {entry: {app?, name?}} (a German name, or a part not found), and
    "separate" [entries] that must stay apps of their own."""
    owners = {}
    try:
        out = subprocess.run(["pacman", "-Qo", *map(str, wanted.values())],
                             capture_output=True, text=True, timeout=30,
                             env={**os.environ, "LC_ALL": "C"}).stdout
        for line in out.splitlines():
            path, found, rest = line.partition(" is owned by ")
            if found:
                owners[Path(path).stem] = rest.split()[0]
    except (OSError, subprocess.SubprocessError):
        pass

    def program(entry):
        try:
            words = [w for w in shlex.split(entry.get("Exec", "")) if not w.startswith("%")]
        except ValueError:
            return None, 0
        while words and (words[0] == "env" or "=" in words[0]):
            words = words[1:]  # env FOO=1 program …
        return (os.path.basename(words[0]), len(words)) if words else (None, 0)

    separate = set(profiles.get("separate", []))
    groups = {}
    for app, source in wanted.items():
        name, size = program(read_entry(source))
        if name and app in owners and app not in separate:
            groups.setdefault((owners[app], name), []).append((size, len(app), app))
    parts = {}
    for members in groups.values():
        if len(members) > 1:
            main = min(members)[2]
            for _size, _length, app in members:
                if app != main:
                    parts[app] = main
    for app, spec in profiles.get("part_of", {}).items():
        if app in wanted and spec.get("app", parts.get(app)) in wanted:
            parts[app] = spec.get("app", parts.get(app))

    named = {}
    for app, main in parts.items():
        if main in parts:
            continue  # a part of a part: leave both alone
        entry = read_entry(wanted[app])
        name = (profiles.get("part_of", {}).get(app, {}).get("name")
                or entry.get("Name[de]") or entry.get("Name") or app)
        if entry.get("Exec"):
            named[app] = (main, name)
    return named


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
    try:
        if args == ["--sync"]:
            return sync()
        mode = "start"
        if args and args[0] in ("--print", "--shell", "--run"):
            mode, args = args[0][2:], args[1:]
        if not args or (mode == "run" and len(args) < 2):
            sys.exit(__doc__)
        app, rest = args[0].removesuffix(".desktop"), args[1:]

        if mode in ("start", "run"):
            # the session service starts it (asks first if needed, cleans up afterwards)
            call_service({"call": "apps.launch", "app": app, "args": rest, "run": mode == "run"})
            return

        # --print, --shell: here, for testing
        system, argv, profile, states = prepare_launch(app, [], False)
        box = Sandbox(app, argv, profile, states)
        if mode == "print":
            box.start(box.argv, dry=True)
            return
        app_process = box.start(rest or ["bash"])
        code = app_process.wait()
        cleanup(app, box.instance)
        sys.exit(code)
    except SandboxError as e:
        print(f"app-sandbox: {e}", file=sys.stderr)
        subprocess.run(["notify-send", "-a", "System", "-i", "dialog-warning", "App konnte nicht starten", str(e)])
        sys.exit(1)
