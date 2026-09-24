pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// Session state and ending the session like on a Mac:
//   keepAwake   "Computer wachhalten" (idle inhibitor in MenuBar.qml: no lock, screens stay on)
//   end(kind)   "logout" | "reboot" | "poweroff": every window is asked to close first (apps
//               with unsaved changes can ask to save). Apps still open after 10 s are listed,
//               with the choice to cancel or to go on anyway.
Singleton {
    id: root

    property bool keepAwake: false

    property string ending: ""        // kind of the running end, "" = none
    property int waited: 0            // half seconds
    readonly property var verb: ({ logout: "abmelden", reboot: "neu starten", poweroff: "ausschalten" })

    function end(kind) {
        if (ending !== "")
            return;
        ending = kind;
        waited = 0;
        if (Apps.windows.length === 0)
            return finish();
        Hyprland.dispatch("macos.close_all_windows()");
        poll.start();
    }

    function finish() {
        poll.stop();
        const kind = ending;
        ending = "";
        if (Confirm.open)
            Confirm.answer(false);
        if (kind === "logout")
            Quickshell.execDetached([Quickshell.shellPath("scripts/logout.sh")]);
        else if (kind === "reboot")
            Quickshell.execDetached(["systemctl", "reboot"]);
        else if (kind === "poweroff")
            Quickshell.execDetached(["systemctl", "poweroff"]);
    }

    function cancel() {
        poll.stop();
        ending = "";
    }

    Timer {
        id: poll
        interval: 500
        repeat: true
        onTriggered: {
            if (Apps.windows.length === 0)
                return root.finish();
            root.waited++;
            if (root.waited === 20) { // 10 s: some apps are still open
                const names = [...new Set(Apps.windows.map(w => Apps.name(Apps.keyForAppId(w.appId))))];
                const kind = root.ending;
                Confirm.ask(`Einige Apps haben sich noch nicht beendet: ${names.join(", ")}.`,
                    "Vielleicht gibt es ungesicherte Änderungen – du kannst sie jetzt speichern und die Apps schließen.",
                    `Trotzdem ${root.verb[kind]}`,
                    () => root.finish());
            } else if (root.waited > 20 && !Confirm.open) {
                root.cancel(); // "Abbrechen" in the dialog
            }
        }
    }
}
