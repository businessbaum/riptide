"""App permissions, kept in the system's permission store.

The store is org.freedesktop.impl.portal.PermissionStore – the one Flatpak and the
portals use – so every part of the system reads the same decisions: the sandbox
(app-sandbox), PipeWire (microphone, speakers), the portals (camera, screen) and System
Settings. A permission is "yes", "no" or not decided yet ("ask": the app asks on first
use; until then it does not get it).

    app-permissions kinds                        every kind of permission (JSON)
    app-permissions get <app>                    {kind: yes|no|ask} of one app (JSON)
    app-permissions list                         every app with a decision (JSON)
    app-permissions set <app> <kind> <yes|no|ask>
    app-permissions watch-sound                  one line of JSON per request of the sound
                                                 system ({"app", "kind"}), for the shell
"""

import json
import subprocess
import sys
import time

from gi.repository import Gio, GLib

BUS_NAME = "org.freedesktop.impl.portal.PermissionStore"
OBJECT = "/org/freedesktop/impl/portal/PermissionStore"
INTERFACE = "org.freedesktop.impl.portal.PermissionStore"

# Our own table for everything the portals have no table for
TABLE = "org.riptide.sandbox"

# Every kind of permission:
#   key, where it is stored (table, id), label, what it allows, the question
#   ("„App“ möchte …"), how the app gets asked (prompt: on first use, portal: through the
#   portal's dialog, switch: only in System Settings) and when a change applies (live, or
#   restart: the next time the app starts); glyph (Symbols Nerd Font) and tile colour
#   for System Settings.
def _kind(key, where, label, description, question, how, applies, glyph, colour):
    return {"key": key, "table": where[0], "id": where[1], "label": label, "description": description,
            "question": question, "how": how, "applies": applies, "glyph": glyph, "colour": colour}


KINDS = [
    _kind("microphone", ("devices", "microphone"), "Mikrofon", "Ton aufnehmen",
          "auf das Mikrofon zugreifen", "prompt", "live", "\U000f036c", "#ff9f0a"),
    _kind("speakers", ("devices", "speakers"), "Lautsprecher", "Ton abspielen",
          "Ton über Lautsprecher und Kopfhörer abspielen", "prompt", "live", "\U000f04c3", "#ff375f"),
    _kind("camera", ("devices", "camera"), "Kamera", "Bilder der Kamera sehen",
          "auf die Kamera zugreifen", "portal", "live", "\U000f0100", "#30d158"),
    _kind("screen", (TABLE, "screen"), "Bildschirmaufnahme", "Den Bildschirm oder Fenster sehen und teilen",
          "deinen Bildschirm sehen", "portal", "live", "\U000f0379", "#bf5af2"),
    _kind("network", (TABLE, "network"), "Internet", "Verbindungen ins Internet",
          "eine Verbindung ins Internet herstellen", "prompt", "restart", "\U000f01e7", "#0a84ff"),
    _kind("local-network", (TABLE, "local-network"), "Lokales Netzwerk", "Geräte im eigenen Netzwerk finden und erreichen",
          "Geräte in deinem lokalen Netzwerk finden und sich mit ihnen verbinden", "prompt", "restart", "\U000f0317", "#0a84ff"),
    _kind("desktop", (TABLE, "files-desktop"), "Schreibtisch", "Dateien im Ordner Schreibtisch",
          "auf Dateien im Ordner „Schreibtisch“ zugreifen", "switch", "restart", "\U000f01c4", "#0a84ff"),
    _kind("documents", (TABLE, "files-documents"), "Dokumente", "Dateien im Ordner Dokumente",
          "auf Dateien im Ordner „Dokumente“ zugreifen", "switch", "restart", "\U000f0219", "#0a84ff"),
    _kind("downloads", (TABLE, "files-downloads"), "Downloads", "Dateien im Ordner Downloads",
          "auf Dateien im Ordner „Downloads“ zugreifen", "switch", "restart", "\U000f01da", "#0a84ff"),
    _kind("pictures", (TABLE, "files-pictures"), "Bilder", "Dateien im Ordner Bilder",
          "auf Dateien im Ordner „Bilder“ zugreifen", "switch", "restart", "\U000f02e9", "#0a84ff"),
    _kind("music", (TABLE, "files-music"), "Musik", "Dateien im Ordner Musik",
          "auf Dateien im Ordner „Musik“ zugreifen", "switch", "restart", "\U000f075a", "#0a84ff"),
    _kind("videos", (TABLE, "files-videos"), "Videos", "Dateien im Ordner Videos",
          "auf Dateien im Ordner „Videos“ zugreifen", "switch", "restart", "\U000f0567", "#0a84ff"),
    _kind("removable", (TABLE, "files-removable"), "Wechseldatenträger", "USB-Sticks und externe Festplatten",
          "auf USB-Sticks und externe Festplatten zugreifen", "switch", "restart", "\U000f02ca", "#8e8e93"),
    _kind("home", (TABLE, "files-home"), "Ganzer Benutzerordner", "Alle deine Dateien",
          "auf alle deine Dateien zugreifen", "switch", "restart", "\U000f02dc", "#8e8e93"),
    _kind("bluetooth", (TABLE, "bluetooth"), "Bluetooth", "Bluetooth-Geräte finden und benutzen",
          "Bluetooth verwenden", "prompt", "restart", "\U000f00af", "#0a84ff"),
    _kind("usb", (TABLE, "usb"), "USB- und Eingabegeräte", "Controller, Sicherheitsschlüssel, andere USB-Geräte",
          "auf USB- und Eingabegeräte zugreifen", "switch", "restart", "\U000f0553", "#8e8e93"),
    _kind("secrets", (TABLE, "secrets"), "Passwörter", "Anmeldedaten im Schlüsselbund speichern und lesen",
          "auf deine gespeicherten Passwörter zugreifen", "prompt", "restart", "\U000f0306", "#8e8e93"),
    _kind("notifications", ("notifications", "notification"), "Mitteilungen", "Mitteilungen schicken",
          "dir Mitteilungen senden", "prompt", "live", "\U000f009a", "#ff3b30"),
    _kind("background", ("background", "background"), "Hintergrund", "Weiterlaufen ohne Fenster und bei der Anmeldung starten",
          "im Hintergrund weiterlaufen", "portal", "live", "\U000f0150", "#8e8e93"),
]
BY_KEY = {k["key"]: k for k in KINDS}
STATES = ("yes", "no", "ask")


def _bus():
    return Gio.bus_get_sync(Gio.BusType.SESSION, None)


def _call(method, args, reply=None):
    return _bus().call_sync(BUS_NAME, OBJECT, INTERFACE, method, args,
                            GLib.VariantType(reply) if reply else None,
                            Gio.DBusCallFlags.NONE, 5000, None)


def _lookup(table, entry):
    """{app: [values]} of one entry; empty if nothing was decided yet."""
    try:
        permissions, _data = _call("Lookup", GLib.Variant("(ss)", (table, entry)), "(a{sas}v)").unpack()
        return permissions
    except GLib.Error as e:
        if "NotFound" in e.message or "not found" in e.message.lower():
            return {}
        raise


def get(app):
    """{kind: "yes" | "no" | "ask"} for one app."""
    cache = {}
    result = {}
    for k in KINDS:
        where = (k["table"], k["id"])
        if where not in cache:
            cache[where] = _lookup(*where)
        values = cache[where].get(app, [])
        result[k["key"]] = values[0] if values and values[0] in ("yes", "no") else "ask"
    return result


def list_all():
    """{app: {kind: state}} for every app with at least one decision."""
    apps = set()
    seen = set()
    for k in KINDS:
        if (k["table"], k["id"]) not in seen:
            seen.add((k["table"], k["id"]))
            apps |= set(_lookup(k["table"], k["id"]))
    return {app: get(app) for app in sorted(apps)}


def set_state(app, key, state):
    if key not in BY_KEY or state not in STATES:
        raise ValueError(f"unknown permission or state: {key} {state}")
    table, entry = BY_KEY[key]["table"], BY_KEY[key]["id"]
    if state == "ask":
        try:
            _call("DeletePermission", GLib.Variant("(sss)", (table, entry, app)))
        except GLib.Error as e:
            if "NotFound" not in e.message and "not found" not in e.message.lower():
                raise
    else:
        _call("SetPermission", GLib.Variant("(sbssas)", (table, True, entry, app, [state])))


def watch_sound():
    """Requests of WirePlumber (macos/app-permissions.lua): a sandboxed app wants a device
    it has no decision for. They come through the PipeWire metadata "macos-permissions";
    `pw-dump --monitor` follows it also when WirePlumber restarts and creates it anew.
    Requests older than ten minutes are left out (the app has most likely given up)."""
    # line-buffered: through a pipe pw-dump would keep the end of an update back
    dump = subprocess.Popen(["stdbuf", "-oL", "pw-dump", "--monitor", "--no-colors"], stdout=subprocess.PIPE, text=True)
    buffer = ""
    seen = set()
    for line in dump.stdout:
        buffer += line
        if line.rstrip() != "]":
            continue  # every update is an array whose "]" stands alone on the last line
        try:
            objects = json.loads(buffer)
        except ValueError:
            continue
        buffer = ""
        for obj in objects if isinstance(objects, list) else []:
            if obj.get("type") != "PipeWire:Interface:Metadata":
                continue
            if (obj.get("props") or {}).get("metadata.name") != "macos-permissions":
                continue
            for item in obj.get("metadata") or []:
                value = item.get("value")
                if not str(item.get("key", "")).startswith("request:") or not isinstance(value, dict):
                    continue
                key = (obj.get("id"), item["key"], value.get("time"))
                if key in seen or not value.get("app") or value.get("kind") not in BY_KEY:
                    continue
                seen.add(key)
                if time.time() - value.get("time", 0) > 600:
                    continue
                print(json.dumps({"app": value["app"], "kind": value["kind"]}), flush=True)
    sys.exit(dump.wait())


def main():
    args = sys.argv[1:]
    if args == ["kinds"]:
        print(json.dumps([{k: v for k, v in kind.items() if k not in ("table", "id")} for kind in KINDS],
                         ensure_ascii=False))
    elif len(args) == 2 and args[0] == "get":
        print(json.dumps(get(args[1])))
    elif args == ["list"]:
        print(json.dumps(list_all()))
    elif len(args) == 4 and args[0] == "set":
        set_state(args[1], args[2], args[3])
    elif args == ["watch-sound"]:
        watch_sound()
    else:
        sys.exit(__doc__)
