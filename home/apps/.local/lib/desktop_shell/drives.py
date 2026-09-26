"""External drives, watched by the session service (session.py) through UDisks2, like on a
Mac: a USB stick or disk that is plugged in is mounted by itself (udisks lets the active
user mount removable drives without a password) and shows in Finder; the shell tells it
in a banner and keeps an eject symbol in the menu bar while one is mounted.

Only external drives count: removable, or connected by USB/FireWire/SD – never the
computer's own disks (the Windows partition), which stay as they are.

  ← {"event": "drives", "drives": [{id, name, mount, size, fs}], "added": id|null}
  → drives.eject {id}    unmount all its file systems and power it off; error text if busy
"""

import re
import subprocess

from gi.repository import Gio, GLib

UDISKS = "org.freedesktop.UDisks2"
BLOCK = UDISKS + ".Block"
FS = UDISKS + ".Filesystem"
DRIVE = UDISKS + ".Drive"
NO_QUESTIONS = {"auth.no_user_interaction": GLib.Variant("b", True)}


def prop(proxy, name, default=None):
    v = proxy.get_cached_property(name) if proxy else None
    return v.unpack() if v is not None else default


def text(value):
    """'ay' comes back as bytes (NUL at the end)"""
    if isinstance(value, (bytes, bytearray)):
        return bytes(value).rstrip(b"\0").decode(errors="replace")
    if isinstance(value, list):
        return bytes(value).rstrip(b"\0").decode(errors="replace")
    return value or ""


class Drives:
    def __init__(self, on_change):
        self.on_change = on_change  # called with the event for the shell
        self.known = set()          # block objects already seen mounted (for "added")
        self.manager = None

    def start(self):
        try:
            self.manager = Gio.DBusObjectManagerClient.new_for_bus_sync(
                Gio.BusType.SYSTEM, Gio.DBusObjectManagerClientFlags.NONE, UDISKS, "/org/freedesktop/UDisks2",
                None, None, None)
        except GLib.Error as e:
            print(f"drives: {e.message}", flush=True)
            return
        for sig in ("object-added", "object-removed", "interface-added", "interface-removed"):
            self.manager.connect(sig, lambda *_: self.later())
        self.manager.connect("interface-proxy-properties-changed", lambda *_: self.later())
        # drives already there at login: mounted if not yet, but no banner
        self.known = {d["id"] for d in self.drives()}
        self.mount_new()
        self.pending = None

    def later(self):
        if getattr(self, "pending", None):
            GLib.source_remove(self.pending)
        self.pending = GLib.timeout_add(400, self.changed)

    def changed(self):
        self.pending = None
        self.mount_new()
        drives = self.drives()
        added = next((d["id"] for d in drives if d["id"] not in self.known), None)
        self.known = {d["id"] for d in drives}
        self.on_change({"event": "drives", "drives": drives, "added": added})
        return False

    def event(self):
        return {"event": "drives", "drives": self.drives(), "added": None}

    # ------------------------------------------------------------ what is plugged in

    def external(self, obj):
        block = obj.get_interface(BLOCK)
        if not block or prop(block, "HintSystem", True) or prop(block, "HintIgnore", False):
            return None
        drive_path = prop(block, "Drive", "/")
        drive_obj = self.manager.get_object(drive_path) if drive_path != "/" else None
        drive = drive_obj.get_interface(DRIVE) if drive_obj else None
        if not drive:
            return None
        if not (prop(drive, "Removable", False) or prop(drive, "ConnectionBus", "") in ("usb", "sdio", "ieee1394")):
            return None
        return block, drive

    def filesystems(self):
        """[(object, block, drive, fs)] of external file systems"""
        found = []
        for obj in self.manager.get_objects() if self.manager else []:
            fs = obj.get_interface(FS)
            ext = self.external(obj) if fs else None
            if ext:
                found.append((obj, ext[0], ext[1], fs))
        return found

    def drives(self):
        found = []
        for obj, block, drive, fs in self.filesystems():
            mounts = [text(m) for m in prop(fs, "MountPoints", [])]
            if not mounts:
                continue
            label = prop(block, "IdLabel", "")
            model = " ".join(x for x in (prop(drive, "Vendor", "").strip(), prop(drive, "Model", "").strip()) if x)
            found.append({"id": obj.get_object_path(), "name": label or model or "Externes Laufwerk",
                          "mount": mounts[0], "size": prop(block, "Size", 0), "fs": prop(block, "IdType", ""),
                          "drive": prop(block, "Drive", ""), "uuid": prop(block, "IdUUID", ""),
                          "device": text(prop(block, "PreferredDevice", b"")) or text(prop(block, "Device", b""))})
        return found

    def mount_new(self):
        for obj, block, drive, fs in self.filesystems():
            if prop(fs, "MountPoints", []) or prop(block, "IdUsage", "") != "filesystem":
                continue
            fs.call("Mount", GLib.Variant("(a{sv})", (NO_QUESTIONS,)), Gio.DBusCallFlags.NONE, 30000, None,
                    self.mounted, obj.get_object_path())

    def mounted(self, proxy, result, path):
        try:
            proxy.call_finish(result)
        except GLib.Error as e:
            print(f"drives: mount {path}: {e.message}", flush=True)

    # ------------------------------------------------------------ ejecting

    def eject(self, object_path, done):
        """Unmount every file system of the drive, then power it off. done(error or None)"""
        target = next(((o, b, d, f) for o, b, d, f in self.filesystems() if o.get_object_path() == object_path), None)
        if not target:
            done("Das Laufwerk ist nicht mehr da.")
            return
        drive_path = prop(target[1], "Drive", "")
        parts = [(o, f) for o, b, d, f in self.filesystems() if prop(b, "Drive", "") == drive_path]
        for o, f in parts:
            if not prop(f, "MountPoints", []):
                continue
            try:
                f.call_sync("Unmount", GLib.Variant("(a{sv})", (NO_QUESTIONS,)), Gio.DBusCallFlags.NONE, 30000, None)
            except GLib.Error as e:
                done(self.busy_text(o, e))
                return
        drive = target[2]
        try:
            if prop(drive, "CanPowerOff", False):
                drive.call_sync("PowerOff", GLib.Variant("(a{sv})", (NO_QUESTIONS,)), Gio.DBusCallFlags.NONE, 30000, None)
            elif prop(drive, "Ejectable", False):
                drive.call_sync("Eject", GLib.Variant("(a{sv})", (NO_QUESTIONS,)), Gio.DBusCallFlags.NONE, 30000, None)
        except GLib.Error as e:
            print(f"drives: power off: {e.message}", flush=True)  # unmounted: safe to pull anyway
        done(None)

    def busy_text(self, obj, error):
        if "busy" not in error.message.lower() and "target is busy" not in error.message:
            return "Nicht ausgeworfen: " + re.sub(r"^GDBus\.Error:[^ ]+ ", "", error.message)
        # which programs still use it
        mount = next((text(m) for m in prop(obj.get_interface(FS), "MountPoints", [])), "")
        names = set()
        if mount:
            out = subprocess.run(["fuser", "-vm", mount], capture_output=True, text=True).stderr
            names = {m for m in re.findall(r"^\s*\S+\s+\d+\s+\S+\s+(\S+)$", out, re.M) if m != "kernel"}
        return "Das Laufwerk wird noch benutzt" + (f" von: {', '.join(sorted(names))}" if names else "") + \
               ". Schließe die Dateien darauf und versuche es noch einmal."
