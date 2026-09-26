pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Software updates as the session service found them in the background (updates.py):
// how many wait (badge on the App Store in the dock) and whether a restart or a new login
// is needed. Its notification's "Neu starten …" / "Abmelden …" comes back here: asked
// once more like from the Apple menu (also from the App Store: qs ipc call session ask reboot).
Singleton {
    id: root

    property int count: 0
    property bool reboot: false
    property bool relogin: false

    Connections {
        target: Riptide
        function onEvent(message) {
            if (message.event === "updates") {
                root.count = message.count;
                root.reboot = message.reboot;
                root.relogin = message.relogin;
            } else if (message.event === "session-ask") {
                root.askSession(message.what);
            }
        }
    }

    function askSession(what) {
        if (what === "reboot")
            Confirm.ask("Möchtest du den Computer jetzt neu starten?", "Damit werden die Updates wirksam.",
                "Neustart", () => Session.end("reboot"));
        else if (what === "logout")
            Confirm.ask("Möchtest du dich jetzt abmelden?", "Alle Programme werden beendet. "
                + "Nach der Anmeldung läuft die neue Version von Hyprland.", "Abmelden", () => Session.end("logout"));
    }

    // The App Store's "Neu starten …": the shell ends the session (the App Store would
    // close itself on the way)
    IpcHandler {
        target: "session"
        function ask(what: string): void {
            root.askSession(what);
        }
    }
}
