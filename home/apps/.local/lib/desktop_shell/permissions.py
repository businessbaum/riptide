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
"""

import json
import sys

from gi.repository import Gio, GLib

BUS_NAME = "org.freedesktop.impl.portal.PermissionStore"
OBJECT = "/org/freedesktop/impl/portal/PermissionStore"
INTERFACE = "org.freedesktop.impl.portal.PermissionStore"

# Our own table for everything the portals have no table for
TABLE = "org.riptide.sandbox"

# key, (table, id), German label, what it allows, how the app gets asked
KINDS = [
    ("microphone", ("devices", "microphone"), "Mikrofon", "Ton aufnehmen", "prompt"),
    ("speakers", ("devices", "speakers"), "Lautsprecher", "Ton abspielen", "prompt"),
    ("camera", ("devices", "camera"), "Kamera", "Bilder der Kamera sehen", "portal"),
    ("screen", (TABLE, "screen"), "Bildschirmaufnahme", "Den Bildschirm oder Fenster sehen und teilen", "portal"),
    ("network", (TABLE, "network"), "Internet", "Verbindungen ins Internet", "prompt"),
    ("local-network", (TABLE, "local-network"), "Lokales Netzwerk", "Geräte im eigenen Netzwerk finden und erreichen", "prompt"),
    ("desktop", (TABLE, "files-desktop"), "Schreibtisch", "Dateien im Ordner Schreibtisch", "switch"),
    ("documents", (TABLE, "files-documents"), "Dokumente", "Dateien im Ordner Dokumente", "switch"),
    ("downloads", (TABLE, "files-downloads"), "Downloads", "Dateien im Ordner Downloads", "switch"),
    ("pictures", (TABLE, "files-pictures"), "Bilder", "Dateien im Ordner Bilder", "switch"),
    ("music", (TABLE, "files-music"), "Musik", "Dateien im Ordner Musik", "switch"),
    ("videos", (TABLE, "files-videos"), "Videos", "Dateien im Ordner Videos", "switch"),
    ("removable", (TABLE, "files-removable"), "Wechseldatenträger", "USB-Sticks und externe Festplatten", "switch"),
    ("home", (TABLE, "files-home"), "Ganzer Benutzerordner", "Alle deine Dateien", "switch"),
    ("bluetooth", (TABLE, "bluetooth"), "Bluetooth", "Bluetooth-Geräte finden und benutzen", "switch"),
    ("usb", (TABLE, "usb"), "USB- und Eingabegeräte", "Controller, Sicherheitsschlüssel, andere USB-Geräte", "switch"),
    ("secrets", (TABLE, "secrets"), "Passwörter", "Anmeldedaten im Schlüsselbund speichern und lesen", "switch"),
    ("notifications", ("notifications", "notification"), "Mitteilungen", "Mitteilungen schicken", "prompt"),
    ("background", ("background", "background"), "Hintergrund", "Weiterlaufen ohne Fenster und bei der Anmeldung starten", "portal"),
]
BY_KEY = {k[0]: k for k in KINDS}
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
    for key, (table, entry), *_ in KINDS:
        if (table, entry) not in cache:
            cache[(table, entry)] = _lookup(table, entry)
        values = cache[(table, entry)].get(app, [])
        result[key] = values[0] if values and values[0] in ("yes", "no") else "ask"
    return result


def list_all():
    """{app: {kind: state}} for every app with at least one decision."""
    apps = set()
    seen = set()
    for _key, (table, entry), *_ in KINDS:
        if (table, entry) not in seen:
            seen.add((table, entry))
            apps |= set(_lookup(table, entry))
    return {app: get(app) for app in sorted(apps)}


def set_state(app, key, state):
    if key not in BY_KEY or state not in STATES:
        raise ValueError(f"unknown permission or state: {key} {state}")
    _key, (table, entry), *_ = BY_KEY[key]
    if state == "ask":
        try:
            _call("DeletePermission", GLib.Variant("(sss)", (table, entry, app)))
        except GLib.Error as e:
            if "NotFound" not in e.message and "not found" not in e.message.lower():
                raise
    else:
        _call("SetPermission", GLib.Variant("(sbssas)", (table, True, entry, app, [state])))


def main():
    args = sys.argv[1:]
    if args == ["kinds"]:
        print(json.dumps([{"key": k, "label": label, "description": text, "ask": how}
                          for k, _entry, label, text, how in KINDS], ensure_ascii=False))
    elif len(args) == 2 and args[0] == "get":
        print(json.dumps(get(args[1])))
    elif args == ["list"]:
        print(json.dumps(list_all()))
    elif len(args) == 4 and args[0] == "set":
        set_state(args[1], args[2], args[3])
    else:
        sys.exit(__doc__)
