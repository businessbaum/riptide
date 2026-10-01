pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Runs the root helper /usr/local/sbin/riptide-helper through pkexec (our password
// dialog asks once, then polkit remembers it for a few minutes). Shared by the App Store
// and System Settings (Apps, Speicher). One operation at a time.
//   run("install" | "remove" | "upgrade" | "clean-cache", pkgs, displayName)
Singleton {
    id: root

    property var busy: null          // { action, pkgs, name } while running
    property var log: []             // output lines of the running operation
    property string lastError: ""

    // 0…1 once pacman installs ("(2/5) installing …"), -1 while that is unknown (downloading)
    readonly property real progress: {
        for (let i = log.length - 1; i >= 0; i--) {
            const m = /^\((\d+)\/(\d+)\) (installing|upgrading|removing|reinstalling)/.exec(log[i]);
            if (m)
                return Number(m[1]) / Number(m[2]);
        }
        return -1;
    }
    signal finished(string action, bool ok)

    function run(action, pkgs, name) {
        if (busy)
            return;
        busy = { action: action, pkgs: pkgs, name: name };
        log = [];
        lastError = "";
        helper.command = ["pkexec", "/usr/local/sbin/riptide-helper", "packages", action].concat(pkgs);
        helper.running = true;
    }

    Process {
        id: helper
        stdout: SplitParser {
            onRead: line => root.log = root.log.concat([line]).slice(-200)
        }
        stderr: SplitParser {
            onRead: line => {
                root.log = root.log.concat([line]).slice(-200);
                if (line.includes("failed retrieving file") || line.includes("404"))
                    root.lastError = "Die Paketliste ist veraltet – bitte zuerst im App Store unter „Updates“ alles aktualisieren.";
                else if (line.startsWith("FEHLER:") || line.startsWith("error:"))
                    root.lastError = line.replace(/^FEHLER: /, "");
            }
        }
        onExited: (code, status) => {
            const b = root.busy;
            root.busy = null;
            const ok = code === 0;
            if (ok) {
                const done = { install: "wurde installiert", remove: "wurde entfernt",
                               upgrade: "ist auf dem neuesten Stand", "clean-cache": "wurde aufgeräumt" }[b.action];
                Notify.send(b.name, done, false);
            } else if (code === 126 || code === 127) {
                root.lastError = "Abgebrochen."; // closed the password dialog
            } else {
                Notify.send(b.name, root.lastError || "Das hat nicht geklappt.", true);
            }
            root.finished(b.action, ok);
        }
    }
}
