pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Session state and ending the session like on a Mac:
//   keepAwake   "Computer wachhalten" (idle inhibitor in MenuBar.qml: no lock, screens stay on)
//   ask(kind)   the question of the Apple menu, with "Beim nächsten Anmelden alle Fenster
//               wieder öffnen" (Energie → Anmelden remembers the choice)
//   end(kind)   "logout" | "reboot" | "poweroff": every window is asked to close first (apps
//               with unsaved changes can ask to save). Apps still open after 10 s are listed,
//               with the choice to cancel or to go on anyway.
//   sleep()     "Ruhezustand": hypridle locks the screen first
// The apps open at the end come back at the next login (once per session, after the
// login items).
Singleton {
    id: root

    property bool keepAwake: false

    property string ending: ""        // kind of the running end, "" = none
    property int waited: 0            // half seconds
    readonly property var verb: ({ logout: "abmelden", reboot: "neu starten", poweroff: "ausschalten" })

    readonly property var question: ({
        logout: ["Möchtest du dich wirklich abmelden?", "Alle Programme werden beendet.", "Abmelden"],
        reboot: ["Möchtest du den Computer jetzt neu starten?", "", "Neustart"],
        poweroff: ["Möchtest du den Computer jetzt ausschalten?", "", "Ausschalten"]
    })
    function ask(kind, text) {
        const [title, detail, button] = question[kind];
        Confirm.request({
            title, button,
            text: text ?? detail,
            option: { text: "Beim nächsten Anmelden alle Fenster wieder öffnen", checked: Config.settings.session?.reopen !== false },
            action: reopen => {
                Config.updateSettings(s => {
                    s.session = s.session ?? {};
                    s.session.reopen = reopen;
                });
                end(kind);
            }
        });
    }

    function sleep() {
        Quickshell.execDetached(["systemctl", "suspend"]);
    }

    readonly property string reopenFile: Quickshell.env("HOME") + "/.local/state/macos/reopen.json"
    function rememberApps() {
        const ids = [...new Set(Apps.windows.map(w => Apps.keyForAppId(w.appId)))]
            .filter(k => Apps.entryById(k)).map(k => Apps.plainId(k));
        console.info("reopen: remembering", ids.join(", "));
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" > \"$2\"", "sh", JSON.stringify(ids), reopenFile]);
    }

    function end(kind) {
        if (ending !== "")
            return;
        ending = kind;
        if (Config.settings.session?.reopen !== false)
            rememberApps();
        else
            Quickshell.execDetached(["rm", "-f", reopenFile]);
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
        if (kind === "logout") {
            // for greetd's login screen: a logout, not a crash – the next session starts
            // locked again, as at boot (/usr/local/lib/riptide/greeter/start)
            const marker = `/var/lib/riptide/greeter/users/${Quickshell.env("USER")}/logged-out`;
            Quickshell.execDetached(["sh", "-c", 'date +%s > "$1" 2>/dev/null; exec "$2"', "sh", marker,
                Quickshell.shellPath("scripts/logout.sh")]);
        }
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

    // A new session: the apps of the last one open again – once (not when the shell
    // restarts), and only apps that are not open yet (login items open themselves).
    // At boot only after the password (the session starts locked, Lock.qml).
    Process {
        running: Lock.loggedIn
        command: ["sh", "-c", "m=\"$XDG_RUNTIME_DIR/riptide/reopened-$HYPRLAND_INSTANCE_SIGNATURE\"; [ -e \"$m\" ] && exit 0; "
            + "mkdir -p \"${m%/*}\" && touch \"$m\"; f=\"$1\"; [ -f \"$f\" ] || exit 0; "
            + "[ $(( $(date +%s) - $(stat -c %Y \"$f\") )) -lt 604800 ] && cat \"$f\"; rm -f \"$f\"", "sh", root.reopenFile]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    reopen.ids = JSON.parse(text);
                    console.info("reopen: after login", reopen.ids.join(", "));
                    reopen.start();
                } catch (e) {}
            }
        }
    }
    // (tried every 2 s for up to 30 s: right after login the list of apps may not be read yet)
    Timer {
        id: reopen
        property var ids: []
        property int attempts: 0
        interval: 2000
        repeat: true
        onTriggered: {
            attempts++;
            const left = [];
            for (const id of ids) {
                const entry = Apps.entryById(id);
                if (!entry) {
                    left.push(id);
                    continue;
                }
                if (Apps.windowsOf(entry.id).length === 0 && !Apps.isStarting(entry.id)) {
                    console.info("reopen: opening", id);
                    Apps.launch(entry);
                }
            }
            ids = left;
            if (ids.length === 0 || attempts >= 15) {
                if (ids.length > 0)
                    console.warn("reopen: not found:", ids.join(", "));
                stop();
            }
        }
    }
}
