pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Hyprland's own questions in the look of the system (stand-in: ~/.local/bin/hyprland-dialog):
//   an app does not respond → "„Discord“ reagiert nicht" – Warten / Sofort beenden
//   an app wants to capture the screen or see the pointer (ecosystem:enforce_permissions)
// They show as our dialog (Confirm.qml). The answer goes back as the button label Hyprland
// gave (in its language) through $XDG_RUNTIME_DIR/riptide/dialog-<pid of the stand-in>.
// Anything else is left to the original dialog.
Singleton {
    id: root

    readonly property string dir: Quickshell.env("XDG_RUNTIME_DIR") + "/riptide"

    // open questions: pid of the stand-in → { key, appClass, anr }
    property var pending: ({})
    // apps with an open "reagiert nicht" question ("Sofort beenden" marks them)
    readonly property var notResponding: Object.values(pending).filter(p => p.anr).map(p => p.appClass)

    IpcHandler {
        target: "hyprdialog"

        // "yes" when the shell asks, "no" to leave it to the original dialog
        function ask(pid: string, title: string, text: string, buttons: string): string {
            if (!/^\d+$/.test(pid))
                return "no";
            const labels = buttons.split(";").filter(l => l !== "");
            const anr = text.match(/^(?:Eine Anwendung|An application) (.*) - (\S*) (?:reagiert nicht|is not responding)/);
            if (anr && labels.length >= 2) {
                root.askNotResponding(pid, anr[1], anr[2], labels);
                return "yes";
            }
            const app = text.match(/<b>(.*?)<\/b>/);
            if (/^(Berechtigungsanfrage|Permission request)$/.test(title) && app && labels.length >= 2) {
                root.permission(pid, app[1], text, labels);
                return "yes";
            }
            return "no";
        }
    }

    function remember(pid, info) {
        pending = Object.assign({}, pending, { [pid]: info });
    }
    function forget(pid) {
        const rest = Object.assign({}, pending);
        delete rest[pid];
        pending = rest;
    }
    function reply(pid, label) {
        forget(pid);
        Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" > \"$2.tmp\" && mv \"$2.tmp\" \"$2\"", "sh",
            label, dir + "/dialog-" + pid]);
    }

    // Hyprland pings every window; one that misses five pings in a row (~7 s) is hanging
    function askNotResponding(pid, title, appClass, labels) {
        const entry = Apps.entryForAppId(appClass);
        const key = "hyprdialog:" + pid;
        remember(pid, { key, appClass, anr: true });
        Confirm.request({
            key,
            app: entry ? Apps.plainId(entry.id) : appClass,
            title: `„${entry?.name ?? (title || appClass)}“ reagiert nicht`,
            text: "Du kannst warten, bis die App wieder reagiert, oder sie sofort beenden. "
                + "Nicht gesicherte Änderungen gehen dabei verloren.",
            button: "Sofort beenden",
            cancel: "Warten",
            action: () => {
                reply(pid, labels[0]); // Terminate / Beenden
                ForceQuit.quit([appClass]);
            },
            cancelled: () => reply(pid, labels[1]) // Wait / Warten
        });
    }

    function permission(pid, app, text, labels) {
        const deny = labels.find(l => /^(Deny|Verweigern)$/.test(l)) ?? labels[0];
        const allow = labels.find(l => /^(Allow|Erlauben)$/.test(l)) ?? labels.find(l => l !== deny);
        const name = app.split("/").pop();
        const what = /screen|Bildschirm/i.test(text) ? "deinen Bildschirm aufnehmen"
            : /cursor|Maus|Zeiger/i.test(text) ? "sehen, wo dein Mauszeiger ist"
            : "eine Berechtigung, die das System nicht kennt";
        const key = "hyprdialog:" + pid;
        remember(pid, { key, appClass: name, anr: false });
        Confirm.request({
            key,
            app: name,
            title: `„${name}“ möchte ${what}`,
            text: "Die Erlaubnis gilt, bis das Programm beendet wird.",
            button: "Erlauben",
            cancel: "Ablehnen",
            action: () => reply(pid, allow),
            cancelled: () => reply(pid, deny)
        });
    }

    // A question settled by itself (the app responds again): Hyprland killed the stand-in
    Timer {
        running: Object.keys(root.pending).length > 0
        interval: 1000
        repeat: true
        onTriggered: {
            alive.command = ["sh", "-c", "for p; do [ -d /proc/$p ] || echo $p; done", "sh"].concat(Object.keys(root.pending));
            alive.running = true;
        }
    }
    Process {
        id: alive
        stdout: SplitParser {
            onRead: pid => {
                const q = root.pending[pid];
                if (!q)
                    return;
                Confirm.withdraw(q.key);
                root.forget(pid);
                Quickshell.execDetached(["rm", "-f", root.dir + "/dialog-" + pid]);
            }
        }
    }
}
